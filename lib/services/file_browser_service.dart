import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/file_entry.dart';
import 'android_storage_service.dart';

class FileBrowserService {
  static const String internalPath = '/storage/emulated/0';
  static List<String>? _sdRootsCache;
  static List<Map<String, Object?>>? _videoFolderRowsCache;
  static final Map<String, List<FileEntry>> _directoryCache = {};

  Future<bool> requestAccess() async {
    final storage = await Permission.storage.request();
    final videos = await Permission.videos.request();
    final audio = await Permission.audio.request();
    final manage = await Permission.manageExternalStorage.request();
    return storage.isGranted ||
        videos.isGranted ||
        audio.isGranted ||
        manage.isGranted;
  }

  Future<List<String>> sdCardRoots() async {
    final cached = _sdRootsCache;
    if (cached != null) return cached;

    final roots = <String>{};
    roots.addAll(await _nativeSdCardRoots());
    roots.addAll(await _storageDirectoryCandidates());

    final envStorage = Platform.environment['SECONDARY_STORAGE'];
    if (envStorage != null && envStorage.trim().isNotEmpty) {
      for (final path in envStorage.split(':')) {
        final dir = Directory(path);
        if (await _canOpenDirectory(dir)) roots.add(dir.path);
      }
    }

    roots.addAll(await _mountFileCandidates());

    final result = roots.toList()..sort();
    _sdRootsCache = result;
    return result;
  }

  Future<List<String>> _nativeSdCardRoots() async {
    try {
      return AndroidStorageService().removableStoragePaths().timeout(
            const Duration(seconds: 2),
            onTimeout: () => const [],
          );
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _storageDirectoryCandidates() async {
    final roots = <String>{};
    try {
      final directStorage = Directory('/storage');
      if (!await directStorage.exists()) return const [];
      await for (final entity in directStorage.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path).toLowerCase();
        if (name == 'emulated' || name == 'self' || name == '0') continue;
        final looksLikePublicVolume =
            RegExp(r'^[0-9a-f]{4}-[0-9a-f]{4}$', caseSensitive: false)
                .hasMatch(name);
        if (looksLikePublicVolume && await _canOpenDirectory(entity)) {
          roots.add(entity.path);
        }
      }
    } catch (_) {
      return const [];
    }
    return roots.toList()..sort();
  }

  Future<List<String>> _mountFileCandidates() async {
    try {
      final mounts = await File('/proc/mounts').readAsString();
      final regex = RegExp(r'/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}');
      final candidates = regex
          .allMatches(mounts)
          .map((match) => match.group(0)!)
          .toSet()
          .toList();
      final roots = <String>[];
      for (final path in candidates) {
        if (await _canOpenDirectory(Directory(path))) roots.add(path);
      }
      return roots;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> _canOpenDirectory(Directory directory) async {
    try {
      if (!await directory.exists()) return false;
      await directory.list(followLinks: false).take(1).drain<void>();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<FileEntry>> list(String directoryPath) async {
    final normalized = _normalizeDirectoryPath(directoryPath);
    final cached = _directoryCache[normalized];
    if (cached != null) return cached;

    final dir = Directory(directoryPath);
    if (!await dir.exists()) return const [];
    final entities = <FileSystemEntity>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        entities.add(entity);
      }
    } catch (_) {
      return const [];
    }

    final entries = <FileEntry>[];
    var nextIndex = 0;
    const workers = 8;
    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= entities.length) return;
        final entity = entities[index];
        try {
          final stat = await entity.stat();
          final isDir = entity is Directory;
          entries.add(
            FileEntry(
              name: p.basename(entity.path),
              path: entity.path,
              isDirectory: isDir,
              sizeBytes: isDir ? 0 : stat.size,
              modifiedAt: stat.modified,
            ),
          );
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(workers, (_) => worker()));
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _directoryCache[normalized] = entries;
    return entries;
  }

  void invalidateDirectory(String directoryPath) {
    _directoryCache.remove(_normalizeDirectoryPath(directoryPath));
  }

  Future<List<FileEntry>> videoFolders({
    required List<String> roots,
    required String prefix,
    bool cacheOnly = false,
  }) async {
    final cachedRows = await _cachedVideoFolderRows();
    if (cacheOnly) {
      return _videoFolderEntriesFromRows(cachedRows, roots, prefix);
    }

    final rows = await AndroidStorageService().videoFolders().timeout(
          const Duration(seconds: 1),
          onTimeout: () => cachedRows,
        );
    if (rows.isNotEmpty) await _writeVideoFolderRows(rows);
    if (rows.isNotEmpty) _videoFolderRowsCache = rows;
    return _videoFolderEntriesFromRows(
      rows.isEmpty ? cachedRows : rows,
      roots,
      prefix,
    );
  }

  List<FileEntry> _videoFolderEntriesFromRows(
    List<Map<String, Object?>> rows,
    List<String> roots,
    String prefix,
  ) {
    if (roots.isEmpty) return const [];

    final entriesByPath = <String, FileEntry>{};
    final normalizedRoots = roots.map(_normalizeDirectoryPath).toList();
    for (final row in rows) {
      final path = row['path'] as String?;
      if (path == null || path.isEmpty) continue;
      final normalizedPath = _normalizeDirectoryPath(path);
      if (normalizedRoots.any((root) => normalizedPath == root)) {
        continue;
      }
      if (!normalizedRoots.any((root) => _isInsideRoot(normalizedPath, root))) {
        continue;
      }
      final name = row['name'] as String? ?? p.basename(path);
      final modified = row['modifiedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(row['modifiedAt'] as int)
          : DateTime.now();
      entriesByPath[path] = FileEntry(
        name: prefix.isEmpty ? name : '$prefix / $name',
        path: path,
        isDirectory: true,
        sizeBytes: row['count'] is int ? row['count'] as int : 0,
        modifiedAt: modified,
      );
    }
    return entriesByPath.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  String _normalizeDirectoryPath(String path) {
    return p
        .normalize(path)
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
  }

  bool _isInsideRoot(String path, String root) {
    return path == root || path.startsWith('$root/');
  }

  Future<File> _videoFolderRowsCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'local_video_folders_cache.json'));
  }

  Future<List<Map<String, Object?>>> _readVideoFolderRows() async {
    try {
      final file = await _videoFolderRowsCacheFile();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, Object?>>> _cachedVideoFolderRows() async {
    final cached = _videoFolderRowsCache;
    if (cached != null) return cached;
    final rows = await _readVideoFolderRows();
    _videoFolderRowsCache = rows;
    return rows;
  }

  Future<void> _writeVideoFolderRows(List<Map<String, Object?>> rows) async {
    try {
      final file = await _videoFolderRowsCacheFile();
      await file.writeAsString(jsonEncode(rows));
    } catch (_) {}
  }

  Future<bool> directoryContainsVideo(String path, {int maxDepth = 1}) async {
    // Cap how deep we descend. Walking 5+ levels across every folder in
    // storage floods the event loop and causes ANRs, so keep it shallow.
    final depthLimit = maxDepth.clamp(1, 2);
    // A hard wall-clock deadline that the recursion itself checks. A plain
    // Future.timeout() would return early but leave the directory walk
    // running in the background, which is what previously hung the UI.
    final deadline = DateTime.now().add(
      Duration(milliseconds: depthLimit <= 1 ? 400 : 800),
    );
    return _directoryContainsVideo(Directory(path), 0, depthLimit, deadline);
  }

  Future<bool> _directoryContainsVideo(
    Directory directory,
    int depth,
    int maxDepth,
    DateTime deadline,
  ) async {
    if (depth > maxDepth || !await directory.exists()) return false;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        // Stop the moment we run past the deadline so the walk can't keep
        // churning through huge trees after the caller has moved on.
        if (DateTime.now().isAfter(deadline)) return false;
        if (entity is File) {
          final name = p.basename(entity.path).toLowerCase();
          if (_isVideoName(name)) return true;
        } else if (entity is Directory && depth < maxDepth) {
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (await _directoryContainsVideo(
              entity, depth + 1, maxDepth, deadline)) {
            return true;
          }
        }
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  bool _isVideoName(String name) {
    return name.endsWith('.mp4') ||
        name.endsWith('.mkv') ||
        name.endsWith('.avi') ||
        name.endsWith('.mov');
  }
}
