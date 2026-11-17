import 'dart:io';

class AudioItem {
  const AudioItem({
    required this.id,
    required this.title,
    required this.file,
    required this.duration,
    required this.modifiedAt,
    this.sizeBytes = 0,
    this.artist,
    this.album,
    this.folder,
  });

  final String id;
  final String title;
  final File file;
  final Duration duration;
  final DateTime modifiedAt;
  final int sizeBytes;
  final String? artist;
  final String? album;
  final String? folder;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'path': file.path,
      'duration': duration.inMilliseconds,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'sizeBytes': sizeBytes,
      'artist': artist,
      'album': album,
      'folder': folder,
    };
  }

  static AudioItem? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null) return null;
    return AudioItem(
      id: json['id'] as String? ?? path,
      title: json['title'] as String? ?? _fileNameWithoutExtension(path),
      file: File(path),
      duration: Duration(milliseconds: json['duration'] as int? ?? 0),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        json['modifiedAt'] as int? ?? 0,
      ),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      folder: json['folder'] as String?,
    );
  }

  AudioItem copyWith({
    String? id,
    String? title,
    File? file,
    Duration? duration,
    DateTime? modifiedAt,
    int? sizeBytes,
    String? artist,
    String? album,
    String? folder,
  }) {
    return AudioItem(
      id: id ?? this.id,
      title: title ?? this.title,
      file: file ?? this.file,
      duration: duration ?? this.duration,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      folder: folder ?? this.folder,
    );
  }

  static String _fileNameWithoutExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}
