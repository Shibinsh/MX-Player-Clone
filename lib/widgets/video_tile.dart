import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/video_item.dart';
import '../services/thumbnail_service.dart';

class VideoTile extends StatefulWidget {
  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.enableThumbnail = true,
  });

  final VideoItem video;
  final VoidCallback onTap;
  final bool enableThumbnail;

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  static const ThumbnailService _thumbnailService = ThumbnailService();

  ImageProvider? _thumbnail;
  bool _thumbnailRequested = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableThumbnail) _scheduleThumbnailLoad();
  }

  @override
  void didUpdateWidget(covariant VideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.file.path != widget.video.file.path ||
        oldWidget.video.assetId != widget.video.assetId) {
      _thumbnail = null;
      _thumbnailRequested = false;
      if (widget.enableThumbnail) _scheduleThumbnailLoad();
    } else if (!oldWidget.enableThumbnail && widget.enableThumbnail) {
      _scheduleThumbnailLoad();
    }
  }

  void _scheduleThumbnailLoad() {
    if (!widget.enableThumbnail) return;
    if (_thumbnailRequested) return;
    _thumbnailRequested = true;
    unawaited(_loadThumbnail());
  }

  Future<void> _loadThumbnail() async {
    if (!mounted || !widget.enableThumbnail) {
      _thumbnailRequested = false;
      return;
    }
    var data = await _thumbnailService.load(widget.video.assetId);
    if (!mounted || !widget.enableThumbnail) {
      _thumbnailRequested = false;
      return;
    }
    data ??= await _thumbnailService.loadFile(widget.video.file.path);
    if (!mounted || !widget.enableThumbnail || data == null || data.isEmpty) {
      _thumbnailRequested = false;
      return;
    }
    final bytes = data;
    setState(() => _thumbnail = MemoryImage(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Row(
          children: [
            SizedBox(
              width: 132,
              height: 78,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_thumbnail == null)
                    const _ThumbnailFallback()
                  else
                    Image(
                      image: _thumbnail!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.low,
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _Pill(text: _formatDuration(widget.video.duration)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _Meta(
                            icon: Icons.sd_storage_outlined,
                            text: _formatSize(widget.video.sizeBytes)),
                        _Meta(
                            icon: Icons.movie_filter_outlined,
                            text: widget.video.extension.toUpperCase()),
                        if (widget.video.subtitleFile != null)
                          const _Meta(
                              icon: Icons.closed_caption_outlined, text: 'SRT'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var suffix = 0;
    while (size >= 1024 && suffix < suffixes.length - 1) {
      size /= 1024;
      suffix++;
    }
    return '${NumberFormat('0.#').format(size)} ${suffixes[suffix]}';
  }
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 34,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}
