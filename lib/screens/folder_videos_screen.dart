import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/thumbnail_service.dart';
import '../models/video_folder.dart';
import '../models/video_item.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';

class FolderVideosScreen extends StatefulWidget {
  const FolderVideosScreen({super.key, required this.folder});

  final VideoFolder folder;

  @override
  State<FolderVideosScreen> createState() => _FolderVideosScreenState();
}

class _FolderVideosScreenState extends State<FolderVideosScreen> {
  static const ThumbnailService _thumbnailService = ThumbnailService();

  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  bool _gridMode = false;
  String _query = '';
  String _prewarmedFolderKey = '';

  @override
  void initState() {
    super.initState();
    _prewarmFolderThumbnails();
  }

  @override
  void didUpdateWidget(covariant FolderVideosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.path != widget.folder.path ||
        oldWidget.folder.videos.length != widget.folder.videos.length) {
      _prewarmFolderThumbnails();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<VideoItem> get _videos {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.folder.videos;
    return widget.folder.videos.where((video) {
      return video.title.toLowerCase().contains(query) ||
          video.file.path.toLowerCase().contains(query);
    }).toList();
  }

  void _openVideo(int visibleIndex) {
    final video = _videos[visibleIndex];
    final originalIndex =
        widget.folder.videos.indexWhere((item) => item.id == video.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          playlist: widget.folder.videos,
          initialIndex: originalIndex < 0 ? 0 : originalIndex,
        ),
      ),
    );
  }

  void _prewarmFolderThumbnails() {
    final key = '${widget.folder.path}:${widget.folder.videos.length}';
    if (_prewarmedFolderKey == key) return;
    _prewarmedFolderKey = key;
    unawaited(
      _thumbnailService.prewarmFiles(
        widget.folder.videos.map((video) => video.file.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videos = _videos;
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search videos',
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(widget.folder.name),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            tooltip: _gridMode ? 'List view' : 'Grid view',
            icon: Icon(_gridMode ? Icons.view_list : Icons.grid_view_rounded),
            onPressed: () => setState(() => _gridMode = !_gridMode),
          ),
        ],
      ),
      body: videos.isEmpty
          ? const Center(child: Text('No videos found'))
          : _gridMode
              ? GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.45,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return InkWell(
                      onTap: () => _openVideo(index),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Expanded(
                                child: Center(
                                  child: Icon(Icons.movie_outlined, size: 44),
                                ),
                              ),
                              Text(
                                video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return VideoTile(
                      video: video,
                      onTap: () => _openVideo(index),
                    );
                  },
                ),
    );
  }
}
