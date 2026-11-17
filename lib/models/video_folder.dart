import 'package:path/path.dart' as p;

import 'video_item.dart';

class VideoFolder {
  const VideoFolder({
    required this.name,
    required this.path,
    required this.videos,
  });

  final String name;
  final String path;
  final List<VideoItem> videos;

  int get count => videos.length;

  Duration get totalDuration {
    return videos.fold(Duration.zero, (total, video) => total + video.duration);
  }

  int get totalSizeBytes {
    return videos.fold(0, (total, video) => total + video.sizeBytes);
  }

  VideoItem? get coverVideo => videos.isEmpty ? null : videos.first;

  DateTime get latestModified {
    return videos.fold<DateTime>(
      DateTime.fromMillisecondsSinceEpoch(0),
      (latest, video) =>
          video.modifiedAt.isAfter(latest) ? video.modifiedAt : latest,
    );
  }

  static VideoFolder fromPath(String path, List<VideoItem> videos) {
    final name = p.basename(path).trim();
    return VideoFolder(
      name: name.isEmpty ? path : name,
      path: path,
      videos: videos,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'path': path,
      'videos': videos.map((video) => video.toJson()).toList(),
    };
  }

  static VideoFolder? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    final rawVideos = json['videos'];
    if (path == null || rawVideos is! List) return null;
    final videos = rawVideos
        .whereType<Map>()
        .map((item) => VideoItem.fromJson(Map<String, dynamic>.from(item)))
        .whereType<VideoItem>()
        .toList();
    if (videos.isEmpty) return null;
    return VideoFolder(
      name: json['name'] as String? ?? p.basename(path),
      path: path,
      videos: videos,
    );
  }
}
