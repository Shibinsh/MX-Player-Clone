import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A named, ordered collection of video file paths.
class Playlist {
  Playlist({required this.id, required this.name, required this.paths});

  final String id;
  String name;
  List<String> paths;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'paths': paths};

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Playlist',
        paths: (json['paths'] as List?)?.whereType<String>().toList() ?? [],
      );
}

/// Persists playlists to a local JSON document. Acts as a lightweight local
/// database so playlists survive app restarts.
class PlaylistService {
  PlaylistService._();
  static final PlaylistService instance = PlaylistService._();

  List<Playlist>? _cache;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'playlists.json'));
  }

  Future<List<Playlist>> load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (!await file.exists()) return _cache = [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return _cache = [];
      _cache = decoded
          .whereType<Map>()
          .map((e) => Playlist.fromJson(Map<String, Object?>.from(e)))
          .toList();
    } catch (_) {
      _cache = [];
    }
    return _cache!;
  }

  Future<void> _persist() async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(_cache!.map((e) => e.toJson()).toList()),
    );
  }

  Future<Playlist> create(String name) async {
    await load();
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      paths: [],
    );
    _cache!.add(playlist);
    await _persist();
    return playlist;
  }

  Future<void> rename(String id, String name) async {
    await load();
    final playlist = _cache!.firstWhere((e) => e.id == id);
    playlist.name = name;
    await _persist();
  }

  Future<void> delete(String id) async {
    await load();
    _cache!.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> addPaths(String id, Iterable<String> paths) async {
    await load();
    final playlist = _cache!.firstWhere((e) => e.id == id);
    for (final path in paths) {
      if (!playlist.paths.contains(path)) playlist.paths.add(path);
    }
    await _persist();
  }

  Future<void> removePath(String id, String path) async {
    await load();
    final playlist = _cache!.firstWhere((e) => e.id == id);
    playlist.paths.remove(path);
    await _persist();
  }
}
