import 'dart:io';

class VideoItem {
  const VideoItem({
    required this.id,
    required this.assetId,
    required this.title,
    required this.file,
    required this.duration,
    required this.sizeBytes,
    required this.modifiedAt,
    this.subtitleFile,
  });

  final String id;
  final String assetId;
  final String title;
  final File file;
  final Duration duration;
  final int sizeBytes;
  final DateTime modifiedAt;
  final File? subtitleFile;

  String get extension => file.path.split('.').last.toLowerCase();

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'title': title,
      'path': file.path,
      'duration': duration.inMilliseconds,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'subtitlePath': subtitleFile?.path,
    };
  }

  static VideoItem? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null || path.isEmpty) return null;
    final subtitlePath = json['subtitlePath'] as String?;
    return VideoItem(
      id: json['id'] as String? ?? path,
      assetId: json['assetId'] as String? ?? '',
      title: json['title'] as String? ?? fileNameWithoutExtension(path),
      file: File(path),
      duration: Duration(milliseconds: json['duration'] as int? ?? 0),
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
        json['modifiedAt'] as int? ?? 0,
      ),
      subtitleFile: subtitlePath == null ? null : File(subtitlePath),
    );
  }

  static String fileNameWithoutExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}
