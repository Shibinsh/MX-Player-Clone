import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/audio_item.dart';
import '../models/video_folder.dart';
import '../models/video_item.dart';
import 'android_storage_service.dart';

class MediaService {
  static const int maxAssetsPerBucket = 1000;
  static List<VideoFolder>? _folderCache;
  static List<AudioItem>? _audioCache;

  static const Set<String> supportedExtensions = {
    'mp4',
    'mkv',
    'avi',
    'mov',
  };

  Future<bool> requestAccess() async {
    final mediaPermission = await PhotoManager.requestPermissionExtend();

    if (mediaPermission.isAuth || mediaPermission.hasAccess) return true;

    final videos = await Permission.videos.request();
    if (videos.isGranted || videos.isLimited) return true;

    final storage = await Permission.storage.request();
    if (storage.isGranted || storage.isLimited) return true;

    final manageStorage = await Permission.manageExternalStorage.request();
    return manageStorage.isGranted || manageStorage.isLimited;
  }

  Future<bool> requestAudioAccess() async {
    final mediaPermission = await PhotoManager.requestPermissionExtend();
    if (mediaPermission.isAuth || mediaPermission.hasAccess) return true;

    final audio = await Permission.audio.request();
    if (audio.isGranted || audio.isLimited) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted || storage.isLimited;
  }

  Future<List<VideoFolder>> loadFolders() async {
    if (_folderCache != null) return _folderCache!;
    final cached = await _readFoldersCache();
    if (cached.isNotEmpty) {
      _folderCache = cached;
      return cached;
    }

    final videos = await loadVideos();
    final byFolder = <String, List<VideoItem>>{};

    for (final video in videos) {
      final folderPath = p.normalize(video.file.parent.path);
      byFolder.putIfAbsent(folderPath, () => <VideoItem>[]).add(video);
    }

    final folders = byFolder.entries
        .map((entry) => VideoFolder.fromPath(entry.key, entry.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _folderCache = folders;
    await _writeFoldersCache(folders);
    return folders;
  }

  Future<List<VideoFolder>> refreshFolders() async {
    _folderCache = null;
    final cacheFile = await _foldersCacheFile();
    if (await cacheFile.exists()) {
      await cacheFile.delete();
    }
    PhotoManager.clearFileCache();
    return loadFolders();
  }

  Future<List<VideoItem>> loadVideos() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.updateDate, asc: false),
        ],
      ),
    );

    final videosByPath = <String, VideoItem>{};
    for (final path in paths) {
      final count = await path.assetCountAsync;
      final end = count > maxAssetsPerBucket ? maxAssetsPerBucket : count;
      final assets = await path.getAssetListRange(start: 0, end: end);
      for (final asset in assets) {
        final video = await _videoFromAsset(asset);
        if (video != null) {
          final key = p.normalize(video.file.absolute.path).toLowerCase();
          videosByPath.putIfAbsent(key, () => video);
        }
      }
    }

    final videos = videosByPath.values.toList();
    videos.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return videos;
  }

  Future<List<AudioItem>> loadAudio() async {
    if (_audioCache != null) return _audioCache!;

    final cached = await _readAudioCache();
    if (cached.isNotEmpty) {
      _audioCache = cached;
      return cached;
    }

    return refreshAudio();
  }

  Future<List<AudioItem>> refreshAudio() async {
    final hasAccess = await requestAudioAccess();
    if (!hasAccess) return _audioCache ?? const [];

    final audiosByPath = <String, AudioItem>{};

    final rows = await AndroidStorageService().audioFiles();
    for (final row in rows) {
      final audio = _audioFromRow(row);
      if (audio == null) continue;
      final key = p.normalize(audio.file.absolute.path).toLowerCase();
      audiosByPath.putIfAbsent(key, () => audio);
    }

    if (audiosByPath.isEmpty) {
      await _collectAudioFromDirectory(
          Directory('/storage/emulated/0'), audiosByPath, 0);
    }

    final audios = audiosByPath.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    _audioCache = audios;
    await _writeAudioCache(audios);
    return audios;
  }

  List<AudioItem> removeDeletedAudio(List<AudioItem> audios) {
    return audios;
  }

  Future<void> _collectAudioFromDirectory(
    Directory directory,
    Map<String, AudioItem> audiosByPath,
    int depth,
  ) async {
    if (depth > 4 || !await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        if (entity is Directory) {
          final name = p.basename(entity.path).toLowerCase();
          if (name.startsWith('.') || name == 'android') continue;
          await _collectAudioFromDirectory(entity, audiosByPath, depth + 1);
        } else if (entity is File) {
          final lower = entity.path.toLowerCase();
          final isAudio = lower.endsWith('.mp3') ||
              lower.endsWith('.m4a') ||
              lower.endsWith('.aac') ||
              lower.endsWith('.wav') ||
              lower.endsWith('.ogg') ||
              lower.endsWith('.flac');
          if (!isAudio) continue;
          final stat = await entity.stat();
          final key = p.normalize(entity.absolute.path).toLowerCase();
          audiosByPath.putIfAbsent(
            key,
            () => AudioItem(
              id: entity.path,
              title: p.basenameWithoutExtension(entity.path),
              file: entity,
              duration: Duration.zero,
              modifiedAt: stat.modified,
              sizeBytes: stat.size,
              artist: null,
              album: null,
              folder: p.basename(entity.parent.path),
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }
  }

  Future<VideoItem?> _videoFromAsset(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null) return null;

      final extension =
          p.extension(file.path).replaceFirst('.', '').toLowerCase();
      if (!supportedExtensions.contains(extension)) return null;

      final stat = await file.stat();
      final subtitle = await _findSubtitleFor(file);
      return VideoItem(
        id: asset.id,
        assetId: asset.id,
        title: _titleFor(asset, file),
        file: file,
        duration: Duration(seconds: asset.duration),
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
        subtitleFile: subtitle,
      );
    } catch (_) {
      return null;
    }
  }

  AudioItem? _audioFromRow(Map<String, Object?> row) {
    final path = row['path'] as String?;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    final title = (row['title'] as String?)?.trim();
    return AudioItem(
      id: row['id'] as String? ?? path,
      title: title == null || title.isEmpty
          ? p.basenameWithoutExtension(path)
          : title,
      file: file,
      duration: Duration(milliseconds: row['duration'] as int? ?? 0),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        row['modifiedAt'] as int? ?? 0,
      ),
      sizeBytes: row['sizeBytes'] as int? ?? 0,
      artist: _cleanUnknown(row['artist'] as String?),
      album: _cleanUnknown(row['album'] as String?),
      folder: _cleanUnknown(row['folder'] as String?) ??
          p.basename(p.dirname(path)),
    );
  }

  String? _cleanUnknown(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower == 'unknown' || lower == '<unknown>') return null;
    return text;
  }

  Future<File?> _findSubtitleFor(File videoFile) async {
    final dir = videoFile.parent;
    final basename = p.basenameWithoutExtension(videoFile.path);
    final subtitle = File(p.join(dir.path, '$basename.srt'));
    return await subtitle.exists() ? subtitle : null;
  }

  String _titleFor(AssetEntity asset, File file) {
    final title = asset.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    return p.basenameWithoutExtension(file.path);
  }

  Future<File> _foldersCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'video_folders_cache.json'));
  }

  Future<File> _audioCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'audio_cache.json'));
  }

  Future<List<VideoFolder>> _readFoldersCache() async {
    try {
      final file = await _foldersCacheFile();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => VideoFolder.fromJson(Map<String, dynamic>.from(item)))
          .whereType<VideoFolder>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeFoldersCache(List<VideoFolder> folders) async {
    try {
      final file = await _foldersCacheFile();
      await file.writeAsString(
          jsonEncode(folders.map((folder) => folder.toJson()).toList()));
    } catch (_) {
      // Cache failures should never block playback.
    }
  }

  Future<List<AudioItem>> _readAudioCache() async {
    try {
      final file = await _audioCacheFile();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => AudioItem.fromJson(Map<String, dynamic>.from(item)))
          .whereType<AudioItem>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearAudioCache() async {
    _audioCache = null;
    try {
      final file = await _audioCacheFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<List<AudioItem>> removeDeletedAudioAsync(
      List<AudioItem> audios) async {
    final existing = <AudioItem>[];
    for (final audio in audios) {
      try {
        if (await audio.file.exists()) existing.add(audio);
      } catch (_) {}
    }
    if (existing.length != audios.length) {
      _audioCache = existing;
      unawaited(_writeAudioCache(existing));
    }
    return existing;
  }

  Future<void> _writeAudioCache(List<AudioItem> audios) async {
    try {
      final file = await _audioCacheFile();
      await file.writeAsString(
        jsonEncode(audios.map((audio) => audio.toJson()).toList()),
      );
    } catch (_) {
      // Cache failures should not block the UI.
    }
  }
}
