import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

class ThumbnailService {
  const ThumbnailService();

  static const MethodChannel _channel =
      MethodChannel('mx_player_clone/storage');
  static final Map<String, Uint8List> _memoryCache = {};
  static final Map<String, Future<Uint8List?>> _pending = {};
  static int _nativeJobs = 0;
  static final List<void Function()> _nativeWaiters = [];
  static const int _maxNativeJobs = 1;

  Future<Uint8List?> load(String assetId) async {
    try {
      if (assetId.trim().isEmpty) return null;
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) return null;

      return asset.thumbnailDataWithSize(
        const ThumbnailSize(320, 180),
        quality: 60,
      );
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> loadFile(String path) async {
    final key = await _cacheKey(path);
    if (key == null) return null;
    final cached = _memoryCache[key];
    if (cached != null) return cached;
    final pending = _pending[key];
    if (pending != null) return pending;

    final future = _loadFileCached(path, key);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  Future<void> prewarmFiles(
    Iterable<String> paths, {
    int limit = 140,
  }) async {
    final uniquePaths = <String>{};
    for (final path in paths) {
      if (path.trim().isEmpty) continue;
      uniquePaths.add(path);
      if (uniquePaths.length >= limit) break;
    }

    const workers = 1;
    final iterator = uniquePaths.iterator;
    final tasks = List.generate(workers, (_) async {
      while (iterator.moveNext()) {
        await loadFile(iterator.current);
      }
    });
    await Future.wait(tasks);
  }

  Future<Uint8List?> _loadFileCached(String path, String key) async {
    final diskFile = await _thumbnailFile(key);
    try {
      if (await diskFile.exists()) {
        final bytes = await diskFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _remember(key, bytes);
          return bytes;
        }
      }
    } catch (_) {}

    try {
      await _enterNativeQueue();
      final data = await _channel.invokeMethod<Uint8List>(
        'videoThumbnail',
        {'path': path},
      );
      if (data == null || data.isEmpty) return null;
      _remember(key, data);
      try {
        await diskFile.writeAsBytes(data, flush: false);
      } catch (_) {}
      return data;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    } finally {
      _leaveNativeQueue();
    }
  }

  void _remember(String key, Uint8List bytes) {
    if (_memoryCache.length > 360) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[key] = bytes;
  }

  Future<String?> _cacheKey(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      return '${_stableHash(path)}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<File> _thumbnailFile(String key) async {
    final temp = await getTemporaryDirectory();
    final dir = Directory(p.join(temp.path, 'video_thumbnails'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, '$key.jpg'));
  }

  String _stableHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  Future<void> _enterNativeQueue() {
    if (_nativeJobs < _maxNativeJobs) {
      _nativeJobs++;
      return Future.value();
    }

    final completer = Completer<void>();
    _nativeWaiters.add(() {
      _nativeJobs++;
      completer.complete();
    });
    return completer.future;
  }

  void _leaveNativeQueue() {
    if (_nativeJobs > 0) _nativeJobs--;
    if (_nativeWaiters.isEmpty) return;
    final next = _nativeWaiters.removeAt(0);
    scheduleMicrotask(next);
  }
}
