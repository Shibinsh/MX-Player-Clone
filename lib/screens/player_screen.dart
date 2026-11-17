import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import '../models/subtitle_cue.dart';
import '../models/video_item.dart';
import '../services/subtitle_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    VideoItem? video,
    List<VideoItem>? playlist,
    this.initialIndex = 0,
  })  : playlist = playlist ?? const [],
        fallbackVideo = video;

  final List<VideoItem> playlist;
  final int initialIndex;
  final VideoItem? fallbackVideo;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  final VolumeController _volumeController = VolumeController.instance;
  final List<double> _speeds = const [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

  List<SubtitleCue> _subtitles = const [];
  Timer? _hideTimer;
  late List<VideoItem> _playlist;
  late int _currentIndex;
  bool _initialized = false;
  bool _controlsVisible = true;
  bool _controlsLocked = false;
  bool _subtitlesEnabled = true;
  bool _displayLandscape = true;
  BoxFit _videoFit = BoxFit.contain;
  String _activeSubtitle = '';
  String? _gestureLabel;
  double _brightness = 0.5;
  double _volume = 0.5;
  bool _isSeeking = false;
  double? _seekPreviewMillis;
  double? _dragSeekStartMillis;
  Offset _oneFingerDrag = Offset.zero;
  bool? _oneFingerHorizontal;
  double _pinchZoom = 1.0;
  double _pinchZoomStart = 1.0;
  bool _autoAdvancing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playlist = widget.playlist.isNotEmpty
        ? widget.playlist
        : widget.fallbackVideo == null
            ? const []
            : [widget.fallbackVideo!];
    _currentIndex = _playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _playlist.length - 1);
    _enterFullscreen();
    if (_playlist.isNotEmpty) {
      _initialize();
    }
  }

  VideoItem get _currentVideo => _playlist[_currentIndex];
  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < _playlist.length - 1;

  Future<void> _initialize() async {
    _subtitles = const [];
    _activeSubtitle = '';
    _initialized = false;
    _controller = VideoPlayerController.file(_currentVideo.file);
    await _controller.initialize();
    if (!mounted) return;
    _controller.addListener(_onTick);
    setState(() => _initialized = true);
    unawaited(_controller.play());
    unawaited(_applyNaturalOrientation());
    unawaited(_loadSubtitles());
    unawaited(_readSystemLevels());
    _resetHideTimer();
  }

  Future<void> _loadSubtitles() async {
    final subtitleFile = _currentVideo.subtitleFile;
    if (subtitleFile == null) return;
    _subtitles = await SubtitleService.loadSrt(subtitleFile);
  }

  Future<void> _readSystemLevels() async {
    try {
      _brightness = await ScreenBrightness.instance.application;
    } catch (_) {
      _brightness = 0.5;
    }
    try {
      _volume = await _volumeController.getVolume();
    } catch (_) {
      _volume = 0.5;
    }
  }

  void _onTick() {
    if (!_initialized) return;
    if (_controller.value.isCompleted) {
      unawaited(_autoPlayNextVideo());
      return;
    }
    if (_controlsVisible && !_isSeeking && mounted) {
      setState(() {});
    }
    if (!_subtitlesEnabled || _subtitles.isEmpty) {
      if (_activeSubtitle.isNotEmpty) setState(() => _activeSubtitle = '');
      return;
    }
    final position = _controller.value.position;
    final cue = _subtitles.cast<SubtitleCue?>().firstWhere(
          (item) => item!.contains(position),
          orElse: () => null,
        );
    final text = cue?.text ?? '';
    if (text != _activeSubtitle) setState(() => _activeSubtitle = text);
  }

  Future<void> _autoPlayNextVideo() async {
    if (_autoAdvancing || !_hasNext) return;
    _autoAdvancing = true;
    try {
      await _playAt(_currentIndex + 1);
    } finally {
      _autoAdvancing = false;
    }
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    if (_controlsLocked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _resetHideTimer();
  }

  Future<void> _togglePlay() async {
    if (_controlsLocked) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
      setState(() => _controlsVisible = true);
    } else {
      await _controller.play();
      _resetHideTimer();
    }
    setState(() {});
  }

  Future<void> _seekBy(Duration offset) async {
    if (_controlsLocked) return;
    final value = _controller.value;
    final next = value.position + offset;
    final clamped = next < Duration.zero
        ? Duration.zero
        : next > value.duration
            ? value.duration
            : next;
    await _seekTo(clamped);
    _showGesture(offset.isNegative ? '-10s' : '+10s');
  }

  void _startHorizontalSeek() {
    if (_controlsLocked) return;
    _hideTimer?.cancel();
    setState(() {
      _isSeeking = true;
      _controlsVisible = true;
      _dragSeekStartMillis = _sliderValue(_controller.value);
      _seekPreviewMillis = _dragSeekStartMillis;
    });
  }

  void _updateHorizontalSeek(double primaryDelta, double width) {
    if (_controlsLocked || !_isSeeking || _dragSeekStartMillis == null) return;
    final durationMs = _sliderMax(_controller.value);
    final deltaRatio = width <= 0 ? 0.0 : primaryDelta / width;
    final deltaMs = durationMs * deltaRatio;
    final next = ((_seekPreviewMillis ?? _dragSeekStartMillis!) + deltaMs)
        .clamp(0.0, durationMs)
        .toDouble();
    setState(() => _seekPreviewMillis = next);
    _showGesture(_format(Duration(milliseconds: next.round())));
  }

  Future<void> _endHorizontalSeek() async {
    if (!_isSeeking || _seekPreviewMillis == null) return;
    final target = Duration(milliseconds: _seekPreviewMillis!.round());
    await _seekTo(target);
    if (!mounted) return;
    setState(() {
      _isSeeking = false;
      _dragSeekStartMillis = null;
      _seekPreviewMillis = null;
    });
    _resetHideTimer();
  }

  Future<void> _seekTo(Duration target) async {
    final wasPlaying = _controller.value.isPlaying;
    await _controller.seekTo(target);
    if (wasPlaying && mounted && !_controller.value.isPlaying) {
      await _controller.play();
    }
  }

  Future<void> _handleVerticalDrag(
    Offset localPosition,
    double primaryDelta,
    double width,
  ) async {
    if (_controlsLocked) return;
    final isLeftSide = localPosition.dx < width / 2;
    final delta = -primaryDelta / 360;
    if (isLeftSide) {
      _brightness = (_brightness + delta).clamp(0.0, 1.0);
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(_brightness);
      _showGesture('Brightness ${(_brightness * 100).round()}%');
    } else {
      _volume = (_volume + delta).clamp(0.0, 1.0);
      await _volumeController.setVolume(_volume);
      _showGesture('Volume ${(_volume * 100).round()}%');
    }
  }

  void _showGesture(String label) {
    setState(() => _gestureLabel = label);
    Timer(const Duration(milliseconds: 700), () {
      if (mounted && _gestureLabel == label) {
        setState(() => _gestureLabel = null);
      }
    });
  }

  Future<void> _setSpeed(double speed) async {
    await _controller.setPlaybackSpeed(speed);
    if (mounted) Navigator.of(context).pop();
    setState(() {});
  }

  Future<void> _applyNaturalOrientation() async {
    _displayLandscape = _controller.value.aspectRatio >= 1;
    await _applyDisplayOrientation();
  }

  Future<void> _applyDisplayOrientation() async {
    if (_displayLandscape) {
      await _setLandscapeOrientation();
    } else {
      await _setPortraitOrientation();
    }
  }

  Future<void> _setLandscapeOrientation() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
    ]);
  }

  Future<void> _setPortraitOrientation() {
    return SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  Future<void> _rotateVideo() async {
    setState(() {
      _displayLandscape = !_displayLandscape;
      _controlsVisible = true;
    });
    await _applyDisplayOrientation();
    _resetHideTimer();
  }

  void _cycleZoom() {
    setState(() {
      _videoFit = switch (_videoFit) {
        BoxFit.contain => BoxFit.cover,
        BoxFit.cover => BoxFit.fill,
        _ => BoxFit.contain,
      };
    });
    _showGesture(switch (_videoFit) {
      BoxFit.contain => 'Fit',
      BoxFit.cover => 'Zoom',
      _ => 'Stretch',
    });
  }

  void _startScale(ScaleStartDetails details) {
    if (_controlsLocked) return;
    _oneFingerDrag = Offset.zero;
    _oneFingerHorizontal = null;
    _pinchZoomStart = _pinchZoom;
    _hideTimer?.cancel();
    if (details.pointerCount == 1) {
      _dragSeekStartMillis = _sliderValue(_controller.value);
    }
  }

  void _updateScale(ScaleUpdateDetails details) {
    if (_controlsLocked) return;
    if (details.pointerCount == 1) {
      _handleOneFingerScaleDrag(details);
      return;
    }
    final next = (_pinchZoomStart * details.scale).clamp(1.0, 4.0).toDouble();
    setState(() {
      _pinchZoom = next;
      _controlsVisible = true;
    });
    _showGesture('Zoom ${(next * 100).round()}%');
  }

  void _endScale(ScaleEndDetails details) {
    if (_oneFingerHorizontal == true) {
      unawaited(_endHorizontalSeek());
    } else {
      _isSeeking = false;
      _seekPreviewMillis = null;
      _dragSeekStartMillis = null;
    }
    _oneFingerDrag = Offset.zero;
    _oneFingerHorizontal = null;
    if (_pinchZoom <= 1.02) {
      setState(() => _pinchZoom = 1.0);
    }
    _resetHideTimer();
  }

  void _handleOneFingerScaleDrag(ScaleUpdateDetails details) {
    final delta = details.focalPointDelta;
    _oneFingerDrag += delta;
    _oneFingerHorizontal ??= _oneFingerDrag.distance < 8
        ? null
        : _oneFingerDrag.dx.abs() >= _oneFingerDrag.dy.abs();
    final horizontal = _oneFingerHorizontal;
    if (horizontal == null) return;
    if (horizontal) {
      if (!_isSeeking) _startHorizontalSeek();
      _updateHorizontalSeek(delta.dx, MediaQuery.sizeOf(context).width);
    } else {
      unawaited(_handleVerticalDrag(
        details.localFocalPoint,
        delta.dy,
        MediaQuery.sizeOf(context).width,
      ));
    }
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _playlist.length || index == _currentIndex) {
      return;
    }
    _hideTimer?.cancel();
    if (_initialized) {
      _controller.removeListener(_onTick);
      await _controller.pause();
      await _controller.dispose();
    }
    setState(() {
      _currentIndex = index;
      _initialized = false;
      _autoAdvancing = false;
      _controlsVisible = true;
      _controlsLocked = false;
      _isSeeking = false;
      _seekPreviewMillis = null;
      _pinchZoom = 1.0;
      _pinchZoomStart = 1.0;
      _displayLandscape = true;
      _videoFit = BoxFit.contain;
      _gestureLabel = null;
    });
    await _initialize();
  }

  Future<void> _nextVideo() => _playAt(_currentIndex + 1);

  Future<void> _previousVideo() => _playAt(_currentIndex - 1);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (_initialized) {
        _controller.pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    if (_initialized) {
      _controller.removeListener(_onTick);
    }
    _controller.dispose();
    ScreenBrightness.instance.resetApplicationScreenBrightness();
    _exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _initialized
          ? LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTapDown: (details) {
                    final left =
                        details.localPosition.dx < constraints.maxWidth / 2;
                    _seekBy(Duration(seconds: left ? -10 : 10));
                  },
                  onScaleStart: _startScale,
                  onScaleUpdate: _updateScale,
                  onScaleEnd: _endScale,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: _videoSurface()),
                      if (_activeSubtitle.isNotEmpty)
                        _SubtitleText(text: _activeSubtitle),
                      if (_gestureLabel != null)
                        _GestureLabel(text: _gestureLabel!),
                      if (_controlsVisible) _controlsOverlay(),
                      if (_controlsLocked)
                        _LockedButton(
                            onUnlock: () =>
                                setState(() => _controlsLocked = false)),
                    ],
                  ),
                );
              },
            )
          : Center(
              child: _playlist.isEmpty
                  ? const Text('No video selected',
                      style: TextStyle(color: Colors.white))
                  : const CircularProgressIndicator(),
            ),
    );
  }

  String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Widget _controlsOverlay() {
    final value = _controller.value;
    final durationMs = _sliderMax(value);
    final visiblePositionMs = _seekPreviewMillis ?? _sliderValue(value);
    // A flat translucent scrim instead of a gradient: a uniform colour never
    // produces 8-bit colour banding the way a smooth gradient does over video.
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    _currentVideo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: _controlsLocked ? 'Unlock' : 'Lock',
                  icon: Icon(_controlsLocked ? Icons.lock : Icons.lock_open),
                  onPressed: () => setState(() {
                    _controlsLocked = !_controlsLocked;
                    _controlsVisible = !_controlsLocked;
                  }),
                ),
                IconButton(
                  tooltip: 'Rotate',
                  icon: const Icon(Icons.screen_rotation),
                  onPressed: _rotateVideo,
                ),
                IconButton(
                  tooltip: 'Zoom',
                  icon: const Icon(Icons.zoom_out_map),
                  onPressed: _cycleZoom,
                ),
                IconButton(
                  tooltip: 'Subtitles',
                  icon: Icon(_subtitlesEnabled
                      ? Icons.closed_caption
                      : Icons.closed_caption_disabled),
                  onPressed: _subtitles.isEmpty
                      ? null
                      : () => setState(() {
                            _subtitlesEnabled = !_subtitlesEnabled;
                            if (!_subtitlesEnabled) _activeSubtitle = '';
                          }),
                ),
                IconButton(
                  tooltip: 'Speed',
                  icon: const Icon(Icons.speed),
                  onPressed: _showSpeedSheet,
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    iconSize: 34,
                    tooltip: 'Previous',
                    icon: const Icon(Icons.skip_previous),
                    onPressed: _hasPrevious ? _previousVideo : null,
                  ),
                  const SizedBox(width: 22),
                  IconButton.filled(
                    iconSize: 48,
                    tooltip: value.isPlaying ? 'Pause' : 'Play',
                    icon:
                        Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                    onPressed: _togglePlay,
                  ),
                  const SizedBox(width: 22),
                  IconButton.filledTonal(
                    iconSize: 34,
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next),
                    onPressed: _hasNext ? _nextVideo : null,
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Row(
                children: [
                  Text(
                    _format(
                      Duration(milliseconds: visiblePositionMs.round()),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: visiblePositionMs.clamp(0, durationMs).toDouble(),
                      max: durationMs,
                      onChangeStart: (next) {
                        _hideTimer?.cancel();
                        setState(() {
                          _isSeeking = true;
                          _seekPreviewMillis = next;
                        });
                      },
                      onChanged: (next) {
                        setState(() => _seekPreviewMillis = next);
                      },
                      onChangeEnd: (next) async {
                        final target = Duration(milliseconds: next.round());
                        await _seekTo(target);
                        if (!mounted) return;
                        setState(() {
                          _isSeeking = false;
                          _seekPreviewMillis = null;
                        });
                        _resetHideTimer();
                      },
                    ),
                  ),
                  Text(_format(value.duration)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    _resetHideTimer();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171A21),
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        maxWidth: MediaQuery.sizeOf(context).width,
      ),
      builder: (context) {
        final current = _controller.value.playbackSpeed;
        return Theme(
          data: Theme.of(context).copyWith(
            iconTheme: const IconThemeData(color: Colors.white),
            listTileTheme: const ListTileThemeData(
              iconColor: Colors.white,
              textColor: Colors.white,
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final speed in _speeds)
                  ListTile(
                    dense: true,
                    minVerticalPadding: 8,
                    leading: Icon(speed == current ? Icons.check : Icons.speed),
                    title: Text(
                      '${speed}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => _setSpeed(speed),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _videoSurface() {
    final size = _controller.value.size;
    final width = size.width <= 0 ? 1280.0 : size.width;
    final height = size.height <= 0 ? 720.0 : size.height;

    // Paint the video texture directly at its native resolution and let
    // FittedBox scale it on the GPU. Avoid wrapping it in a clip/transform
    // layer during normal playback — that forces Skia to composite the frame
    // through an offscreen buffer, which introduces colour banding/pixelation.
    Widget video = FittedBox(
      fit: _videoFit,
      child: SizedBox(
        width: width,
        height: height,
        child: VideoPlayer(_controller),
      ),
    );

    // Only introduce the extra clip + transform layer when actually zoomed in.
    if (_pinchZoom != 1.0) {
      video = ClipRect(
        child: Transform.scale(scale: _pinchZoom, child: video),
      );
    }

    return SizedBox.expand(child: video);
  }

  double _sliderMax(VideoPlayerValue value) {
    final millis = value.duration.inMilliseconds;
    return millis <= 0 ? 1 : millis.toDouble();
  }

  double _sliderValue(VideoPlayerValue value) {
    final max = _sliderMax(value);
    return value.position.inMilliseconds.toDouble().clamp(0, max).toDouble();
  }
}

class _SubtitleText extends StatelessWidget {
  const _SubtitleText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 28,
      right: 28,
      bottom: 78,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
    );
  }
}

class _GestureLabel extends StatelessWidget {
  const _GestureLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.34),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedButton extends StatelessWidget {
  const _LockedButton({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 18),
          child: IconButton.filled(
            tooltip: 'Unlock',
            iconSize: 34,
            onPressed: onUnlock,
            icon: const Icon(Icons.lock),
          ),
        ),
      ),
    );
  }
}
