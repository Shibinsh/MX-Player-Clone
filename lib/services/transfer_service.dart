import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'transfer_history_service.dart';

enum TransferMode { send, receive }

enum TransferStatus { starting, running, completed, failed, canceled }

class TransferItem {
  const TransferItem({
    required this.id,
    required this.name,
    required this.bytes,
    required this.totalBytes,
    required this.speedBytesPerSecond,
    required this.status,
    this.error,
  });

  final String id;
  final String name;
  final int bytes;
  final int totalBytes;
  final double speedBytesPerSecond;
  final TransferStatus status;
  final String? error;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (bytes / totalBytes).clamp(0, 1).toDouble();
  }
}

class PublishedFile {
  const PublishedFile({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final String path;
  final int sizeBytes;
}

class TransferSnapshot {
  const TransferSnapshot({
    required this.running,
    required this.mode,
    required this.url,
    required this.files,
    required this.items,
    this.error,
  });

  final bool running;
  final TransferMode? mode;
  final String? url;
  final List<PublishedFile> files;
  final List<TransferItem> items;
  final String? error;
}

class TransferService extends ChangeNotifier {
  HttpServer? _server;
  TransferMode? _mode;
  String? _url;
  String? _error;
  final List<PublishedFile> _files = [];
  final Map<String, TransferItem> _items = {};
  final Map<String, IOSink> _activeUploads = {};
  final TransferHistoryService _history = TransferHistoryService();
  VoidCallback? onHistoryChanged;

  TransferSnapshot get snapshot => TransferSnapshot(
        running: _server != null,
        mode: _mode,
        url: _url,
        files: List.unmodifiable(_files),
        items: List.unmodifiable(_items.values),
        error: _error,
      );

  Future<void> startSend() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final files = <PublishedFile>[];
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final stat = await file.stat();
      files.add(
        PublishedFile(
          id: _idFor(path),
          name: picked.name,
          path: path,
          sizeBytes: stat.size,
        ),
      );
    }
    if (files.isEmpty) {
      _setError('No readable files selected');
      return;
    }

    _files
      ..clear()
      ..addAll(files);
    await _start(TransferMode.send);
  }

  Future<void> startReceive() async {
    _files.clear();
    await _start(TransferMode.receive);
  }

  Future<void> stop() async {
    for (final sink in _activeUploads.values) {
      try {
        await sink.close();
      } catch (_) {}
    }
    _activeUploads.clear();
    await _server?.close(force: true);
    _server = null;
    _mode = null;
    _url = null;
    notifyListeners();
  }

  void cancel(String id) {
    final sink = _activeUploads.remove(id);
    unawaited(sink?.close());
    final item = _items[id];
    if (item == null) return;
    _items[id] = TransferItem(
      id: item.id,
      name: item.name,
      bytes: item.bytes,
      totalBytes: item.totalBytes,
      speedBytesPerSecond: 0,
      status: TransferStatus.canceled,
    );
    unawaited(_saveHistoryForItem(_items[id]!, direction: 'received'));
    notifyListeners();
  }

  Future<void> _start(TransferMode mode) async {
    await stop();
    _error = null;
    _mode = mode;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _url = 'http://${await _localIp()}:8080';
      _server!.listen(
        (request) => unawaited(_handle(request)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Transfer server error: $error');
          _setError(error.toString());
        },
      );
    } catch (error) {
      _server = null;
      _url = null;
      _setError('Could not start transfer server: $error');
    }
    notifyListeners();
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/' || path == '/index.html') {
        await _sendHtml(request);
      } else if (path == '/api/files') {
        await _sendJson(
          request,
          _files
              .map((file) => {
                    'id': file.id,
                    'name': file.name,
                    'size': file.sizeBytes,
                  })
              .toList(),
        );
      } else if (path == '/download') {
        await _download(request);
      } else if (path == '/upload' && request.method == 'PUT') {
        await _upload(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (error, stackTrace) {
      debugPrint('Transfer request failed: $error\n$stackTrace');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _download(HttpRequest request) async {
    final id = request.uri.queryParameters['id'];
    final published = _files.where((file) => file.id == id).firstOrNull;
    if (published == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final file = File(published.path);
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final total = published.sizeBytes;
    var start = 0;
    var end = total - 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.startsWith('bytes=')) {
      final parts = range.substring(6).split('-');
      start = int.tryParse(parts.first) ?? 0;
      if (parts.length > 1 && parts[1].isNotEmpty) {
        end = int.tryParse(parts[1]) ?? end;
      }
      start = start.clamp(0, total - 1);
      end = end.clamp(start, total - 1);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$total',
      );
    }

    final length = end - start + 1;
    request.response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentLengthHeader, length)
      ..set(
        HttpHeaders.contentDisposition,
        'attachment; filename="${_sanitizeHeader(published.name)}"',
      )
      ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream');

    final itemId = 'download-${published.id}';
    final watch = Stopwatch()..start();
    var sent = 0;
    final remoteIp = _remoteIp(request);
    final remoteDevice = _remoteDevice(request);
    _upsertItem(
        itemId, published.name, sent, length, 0, TransferStatus.running);
    await for (final chunk in file.openRead(start, end + 1)) {
      sent += chunk.length;
      request.response.add(chunk);
      if (watch.elapsedMilliseconds > 250) {
        _upsertItem(
          itemId,
          published.name,
          sent,
          length,
          sent / (watch.elapsedMilliseconds / 1000),
          TransferStatus.running,
        );
      }
    }
    await request.response.close();
    _upsertItem(
        itemId, published.name, length, length, 0, TransferStatus.completed);
    unawaited(
      _saveHistory(
        fileName: published.name,
        filePath: published.path,
        fileSize: published.sizeBytes,
        direction: 'sent',
        status: 'completed',
        remoteDevice: remoteDevice,
        remoteIp: remoteIp,
        speedBytesPerSecond:
            sent / ((watch.elapsedMilliseconds.clamp(1, 1 << 31)) / 1000),
        duration: watch.elapsed,
      ),
    );
  }

  Future<void> _upload(HttpRequest request) async {
    final rawName = utf8
        .decode(
          base64Url.decode(request.headers.value('x-file-name') ?? ''),
          allowMalformed: true,
        )
        .trim();
    final fileName = rawName.isEmpty ? 'upload.bin' : p.basename(rawName);
    final total = request.contentLength < 0 ? 0 : request.contentLength;
    final dir = await _receivedDirectory();
    final target = File(p.join(dir.path, _uniqueName(dir, fileName)));
    final id = 'upload-${DateTime.now().microsecondsSinceEpoch}';
    final sink = target.openWrite();
    _activeUploads[id] = sink;
    final remoteIp = _remoteIp(request);
    final remoteDevice = _remoteDevice(request);

    final watch = Stopwatch()..start();
    var received = 0;
    try {
      _upsertItem(id, fileName, received, total, 0, TransferStatus.running);
      await for (final chunk in request) {
        received += chunk.length;
        sink.add(chunk);
        if (watch.elapsedMilliseconds > 250) {
          _upsertItem(
            id,
            fileName,
            received,
            total,
            received / (watch.elapsedMilliseconds / 1000),
            TransferStatus.running,
          );
        }
      }
      await sink.close();
      _activeUploads.remove(id);
      _upsertItem(id, fileName, received, total, 0, TransferStatus.completed);
      unawaited(
        _saveHistory(
          fileName: fileName,
          filePath: target.path,
          fileSize: received,
          direction: 'received',
          status: 'completed',
          remoteDevice: remoteDevice,
          remoteIp: remoteIp,
          speedBytesPerSecond:
              received / ((watch.elapsedMilliseconds.clamp(1, 1 << 31)) / 1000),
          duration: watch.elapsed,
        ),
      );
      await _sendJson(request, {'ok': true, 'path': target.path});
    } catch (error) {
      _activeUploads.remove(id);
      try {
        await sink.close();
      } catch (_) {}
      _upsertItem(
        id,
        fileName,
        received,
        total,
        0,
        TransferStatus.failed,
        error: error.toString(),
      );
      unawaited(
        _saveHistory(
          fileName: fileName,
          filePath: target.path,
          fileSize: received,
          direction: 'received',
          status: 'failed',
          remoteDevice: remoteDevice,
          remoteIp: remoteIp,
          speedBytesPerSecond: 0,
          duration: watch.elapsed,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<void> _sendHtml(HttpRequest request) async {
    final files = _files
        .map(
          (file) =>
              '<li><a href="/download?id=${Uri.encodeQueryComponent(file.id)}">${htmlEscape.convert(file.name)}</a><span>${_formatBytes(file.sizeBytes)}</span></li>',
        )
        .join();
    final html = '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MX Transfer</title>
<style>
body{margin:0;font-family:Arial,sans-serif;background:#111318;color:#f3f3f3}
main{max-width:860px;margin:0 auto;padding:24px}
h1{margin:0 0 10px}
.drop{border:2px dashed #ff4d82;border-radius:10px;padding:34px;text-align:center;background:#1b1e26;margin:22px 0}
.drop.drag{background:#2a1d28}
li{display:flex;justify-content:space-between;gap:18px;padding:14px;border-bottom:1px solid #2b303b}
a{color:#ff6f9f;text-decoration:none;font-weight:700}
.bar{height:8px;background:#333844;border-radius:99px;overflow:hidden;margin-top:8px}
.bar>i{display:block;height:100%;width:0;background:#ff005b}
.item{margin:12px 0;padding:12px;background:#1b1e26;border-radius:8px}
</style>
</head>
<body>
<main>
<h1>MX Transfer</h1>
<p>Connected to ${_mode == TransferMode.send ? 'phone file sharing' : 'phone receiver'}.</p>
<section><h2>Download from phone</h2><ul>$files</ul></section>
<section><h2>Upload to phone</h2><div id="drop" class="drop">Drop files here or click to upload<input id="picker" type="file" multiple hidden></div><div id="progress"></div></section>
</main>
<script>
const drop=document.getElementById('drop'), picker=document.getElementById('picker'), progress=document.getElementById('progress');
drop.onclick=()=>picker.click();
drop.ondragover=e=>{e.preventDefault();drop.classList.add('drag')};
drop.ondragleave=()=>drop.classList.remove('drag');
drop.ondrop=e=>{e.preventDefault();drop.classList.remove('drag');upload(e.dataTransfer.files)};
picker.onchange=()=>upload(picker.files);
function b64url(s){return btoa(unescape(encodeURIComponent(s))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','')}
function upload(files){[...files].forEach(file=>{
 const item=document.createElement('div'); item.className='item'; item.innerHTML='<b>'+file.name+'</b><div class="bar"><i></i></div><small>0%</small>'; progress.prepend(item);
 const fill=item.querySelector('i'), small=item.querySelector('small'), xhr=new XMLHttpRequest(), start=Date.now();
 xhr.open('PUT','/upload'); xhr.setRequestHeader('x-file-name',b64url(file.name));
 xhr.upload.onprogress=e=>{if(e.lengthComputable){const pct=Math.round(e.loaded*100/e.total), secs=(Date.now()-start)/1000, speed=e.loaded/secs;fill.style.width=pct+'%';small.textContent=pct+'% - '+fmt(speed)+'/s'}};
 xhr.onload=()=>{small.textContent=xhr.status<300?'Complete':'Failed'; if(xhr.status<300) fill.style.width='100%'};
 xhr.onerror=()=>small.textContent='Connection failed';
 xhr.send(file);
})}
function fmt(n){if(!isFinite(n))return '0 B'; const u=['B','KB','MB','GB']; let i=0; while(n>1024&&i<u.length-1){n/=1024;i++} return n.toFixed(1)+' '+u[i]}
</script>
</body>
</html>
''';
    request.response.headers.contentType = ContentType.html;
    request.response.write(html);
    await request.response.close();
  }

  Future<void> _sendJson(HttpRequest request, Object data) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  Future<String> _localIp() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.address.startsWith('169.254.')) return address.address;
      }
    }
    return '127.0.0.1';
  }

  Future<Directory> _receivedDirectory() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'MX Transfer'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _uniqueName(Directory dir, String fileName) {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = fileName;
    var index = 1;
    while (File(p.join(dir.path, candidate)).existsSync()) {
      candidate = '$base ($index)$ext';
      index++;
    }
    return candidate;
  }

  void _upsertItem(
    String id,
    String name,
    int bytes,
    int totalBytes,
    double speed,
    TransferStatus status, {
    String? error,
  }) {
    _items[id] = TransferItem(
      id: id,
      name: name,
      bytes: bytes,
      totalBytes: totalBytes,
      speedBytesPerSecond: speed,
      status: status,
      error: error,
    );
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    debugPrint('Transfer error: $error');
    notifyListeners();
  }

  String _idFor(String value) => base64Url.encode(utf8.encode(value));

  String _sanitizeHeader(String value) => value.replaceAll('"', "'");

  String _remoteIp(HttpRequest request) {
    return request.connectionInfo?.remoteAddress.address ?? 'unknown';
  }

  String _remoteDevice(HttpRequest request) {
    final explicit = request.headers.value('x-device-name')?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final userAgent = request.headers.value(HttpHeaders.userAgentHeader) ?? '';
    if (userAgent.contains('Windows')) return 'Windows PC';
    if (userAgent.contains('Macintosh')) return 'Mac';
    if (userAgent.contains('Android')) return 'Android device';
    if (userAgent.contains('Linux')) return 'Linux PC';
    return 'Browser device';
  }

  Future<void> _saveHistoryForItem(
    TransferItem item, {
    required String direction,
  }) {
    return _saveHistory(
      fileName: item.name,
      filePath: '',
      fileSize: item.bytes,
      direction: direction,
      status: 'canceled',
      remoteDevice: 'Remote device',
      remoteIp: 'unknown',
      speedBytesPerSecond: item.speedBytesPerSecond,
      duration: Duration.zero,
    );
  }

  Future<void> _saveHistory({
    required String fileName,
    required String filePath,
    required int fileSize,
    required String direction,
    required String status,
    required String remoteDevice,
    required String remoteIp,
    required double speedBytesPerSecond,
    required Duration duration,
    String? error,
  }) async {
    try {
      final localDevice = Platform.localHostname;
      await _history.insert(
        TransferHistoryDraft(
          fileName: fileName,
          filePath: filePath,
          fileSize: fileSize,
          senderDevice: direction == 'sent' ? localDevice : remoteDevice,
          receiverDevice: direction == 'sent' ? remoteDevice : localDevice,
          remoteDevice: remoteDevice,
          remoteIp: remoteIp,
          direction: direction,
          status: status,
          speedBytesPerSecond: speedBytesPerSecond,
          duration: duration,
          createdAt: DateTime.now(),
          error: error,
        ),
      );
      onHistoryChanged?.call();
    } catch (error) {
      debugPrint('Failed to save transfer history: $error');
    }
  }
}

String _formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
}
