import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../models/audio_item.dart';
import '../services/media_service.dart';
import '../widgets/app_toast.dart';

enum _MusicView { tracks, playlists, albums, artists, folders }

enum _MusicSort { date, size, time }

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> with WidgetsBindingObserver {
  final MediaService _mediaService = MediaService();
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  final ValueNotifier<AudioItem?> _playingNotifier =
      ValueNotifier<AudioItem?>(null);
  List<AudioItem> _tracks = const [];
  final Set<String> _favorites = {};
  final Set<String> _selected = {};
  bool _loading = true;
  bool _refreshing = false;
  String _query = '';
  AudioItem? _playing;
  String? _loadedAudioPath;
  int _playRequestId = 0;
  _MusicView _view = _MusicView.tracks;
  _MusicSort _sort = _MusicSort.date;
  bool _repeatOne = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCachedAudio();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _playingNotifier.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _player.stop();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAudioAfterStartup());
    }
  }

  Future<void> _play(AudioItem audio) async {
    final requestId = ++_playRequestId;
    final previousPlaying = _playing ?? _playingNotifier.value;
    final previousLoadedPath = _loadedAudioPath;
    _playingNotifier.value = audio;
    setState(() => _playing = audio);

    if (_loadedAudioPath != audio.file.path) {
      try {
        await _player.setFilePath(audio.file.path);
        _loadedAudioPath = audio.file.path;
      } catch (_) {
        if (!mounted || requestId != _playRequestId) return;
        _loadedAudioPath = previousLoadedPath;
        final restored = previousPlaying ?? audio;
        _playingNotifier.value = restored;
        setState(() => _playing = restored);
        return;
      }
    }

    unawaited(_player.play());
  }

  Future<void> _loadCachedAudio() async {
    final cached = await _mediaService.loadAudio();
    if (!mounted) return;
    setState(() {
      _tracks = cached;
      _loading = false;
    });
    unawaited(_refreshAudioAfterStartup());
  }

  Future<void> _refreshAudioAfterStartup() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final existing = await _mediaService.removeDeletedAudioAsync(_tracks);
      if (mounted && existing.length != _tracks.length) {
        setState(() => _tracks = existing);
      }

      final fresh = await _mediaService.refreshAudio();
      if (!mounted) return;
      final existingFresh = await _mediaService.removeDeletedAudioAsync(fresh);
      if (!mounted) return;
      setState(() => _tracks = existingFresh);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      setState(() {
        _loading = true;
        _selected.clear();
      });
      await _mediaService.clearAudioCache();
      final fresh = await _mediaService.refreshAudio();
      if (!mounted) return;
      final existingFresh = await _mediaService.removeDeletedAudioAsync(fresh);
      if (!mounted) return;
      setState(() {
        _tracks = existingFresh;
        _loading = false;
      });
      showWorkableMessage(context, 'Music library refreshed');
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleCurrent() async {
    if (_playing == null && _playingNotifier.value == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      unawaited(_player.play());
    }
    if (mounted) setState(() {});
  }

  Future<void> _closePlayer() async {
    _playRequestId++;
    await _player.stop();
    _loadedAudioPath = null;
    _playingNotifier.value = null;
    if (mounted) {
      setState(() => _playing = null);
    }
  }

  Future<void> _toggleRepeat() async {
    _repeatOne = !_repeatOne;
    await _player.setLoopMode(_repeatOne ? LoopMode.one : LoopMode.off);
    if (mounted) setState(() {});
  }

  void _toggleFavorite(AudioItem track) {
    setState(() {
      if (!_favorites.add(track.id)) {
        _favorites.remove(track.id);
      }
    });
    showWorkableMessage(
      context,
      _favorites.contains(track.id) ? 'Added to favourites' : 'Removed',
    );
  }

  Future<void> _skip(int offset) async {
    final current = _playing ?? _playingNotifier.value;
    if (current == null || _tracks.isEmpty) return;
    final index = _tracks.indexWhere((track) => track.id == current.id);
    if (index < 0) return;
    final next = (index + offset).clamp(0, _tracks.length - 1);
    if (next != index) await _play(_tracks[next]);
  }

  List<AudioItem> _filter(List<AudioItem> audios) {
    final query = _searchKey(_query);
    if (query.isEmpty) return audios;
    return audios
        .where((audio) => _searchKey([
              audio.title,
              audio.artist,
              audio.album,
              audio.folder,
              audio.file.path,
            ].whereType<String>().join(' '))
                .contains(query))
        .toList();
  }

  List<AudioItem> _sorted(List<AudioItem> audios) {
    final sorted = [...audios];
    sorted.sort((a, b) {
      return switch (_sort) {
        _MusicSort.date => b.modifiedAt.compareTo(a.modifiedAt),
        _MusicSort.size => b.sizeBytes.compareTo(a.sizeBytes),
        _MusicSort.time => b.duration.compareTo(a.duration),
      };
    });
    return sorted;
  }

  bool get _selectionMode => _selected.isNotEmpty;

  void _toggleSelect(AudioItem track) {
    setState(() {
      if (!_selected.add(track.id)) {
        _selected.remove(track.id);
      }
    });
  }

  void _selectAll(List<AudioItem> tracks) {
    setState(() {
      if (_selected.length == tracks.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(tracks.map((track) => track.id));
      }
    });
  }

  List<AudioItem> _selectedTracks() {
    return _tracks.where((track) => _selected.contains(track.id)).toList();
  }

  Future<void> _shareSelected() async {
    final files =
        _selectedTracks().map((track) => XFile(track.file.path)).toList();
    if (files.isEmpty) {
      showWorkableMessage(context, 'Select songs to share');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: files));
  }

  Future<void> _copyOrMoveSelected({required bool move}) async {
    final target = await FilePicker.getDirectoryPath();
    if (target == null) return;
    final selected = _selectedTracks();
    for (final track in selected) {
      try {
        final targetPath = p.join(target, p.basename(track.file.path));
        await track.file.copy(targetPath);
        if (move) await track.file.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    _selected.clear();
    if (move) {
      final fresh = await _mediaService.refreshAudio();
      if (!mounted) return;
      setState(() => _tracks = fresh);
    } else {
      setState(() {});
    }
    showWorkableMessage(context, move ? 'Songs moved' : 'Songs copied');
  }

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text('Delete $count selected song(s).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final track in _selectedTracks()) {
      try {
        await track.file.delete();
      } catch (_) {}
    }
    final fresh = await _mediaService.refreshAudio();
    if (!mounted) return;
    setState(() {
      _tracks = fresh;
      _selected.clear();
    });
  }

  void _showTrackMenu(AudioItem track) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Play'),
              onTap: () {
                Navigator.pop(context);
                _play(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Select'),
              onTap: () {
                Navigator.pop(context);
                _toggleSelect(track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(context);
                await SharePlus.instance.share(
                  ShareParams(files: [XFile(track.file.path)]),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              subtitle: Text(track.file.path,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  String _searchKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[_\-\.\(\)\[\]]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Map<String, List<AudioItem>> _groupBy(
    List<AudioItem> audios,
    String Function(AudioItem audio) keyFor,
  ) {
    final groups = <String, List<AudioItem>>{};
    for (final audio in audios) {
      final key = keyFor(audio).trim();
      final name = key.isEmpty ? 'Unknown' : key;
      groups.putIfAbsent(name, () => <AudioItem>[]).add(audio);
    }
    return Map.fromEntries(
      groups.entries.toList()
        ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
  }

  List<_LibraryGroupData> _groupsFor(List<AudioItem> tracks) {
    return switch (_view) {
      _MusicView.playlists => [
          _LibraryGroupData(
            title: 'All songs',
            subtitle: '${tracks.length} song(s)',
            icon: Icons.queue_music,
            tracks: tracks,
          ),
          _LibraryGroupData(
            title: 'Recently added',
            subtitle: '${tracks.take(30).length} song(s)',
            icon: Icons.new_releases_outlined,
            tracks: tracks.take(30).toList(),
          ),
          ..._groupBy(tracks, (audio) => audio.folder ?? 'Unknown folder')
              .entries
              .map(
                (entry) => _LibraryGroupData(
                  title: entry.key,
                  subtitle: '${entry.value.length} song(s)',
                  icon: Icons.playlist_play,
                  tracks: entry.value,
                ),
              ),
        ],
      _MusicView.albums => _groupBy(
          tracks,
          (audio) => audio.album ?? 'Unknown album',
        )
            .entries
            .map(
              (entry) => _LibraryGroupData(
                title: entry.key,
                subtitle: '${entry.value.length} song(s)',
                icon: Icons.album,
                tracks: entry.value,
              ),
            )
            .toList(),
      _MusicView.artists => _groupBy(
          tracks,
          (audio) => audio.artist ?? 'Unknown artist',
        )
            .entries
            .map(
              (entry) => _LibraryGroupData(
                title: entry.key,
                subtitle: '${entry.value.length} song(s)',
                icon: Icons.person,
                tracks: entry.value,
              ),
            )
            .toList(),
      _MusicView.folders => _groupBy(
          tracks,
          (audio) => audio.folder ?? 'Unknown folder',
        )
            .entries
            .map(
              (entry) => _LibraryGroupData(
                title: entry.key,
                subtitle: '${entry.value.length} song(s)',
                icon: Icons.folder,
                tracks: entry.value,
              ),
            )
            .toList(),
      _MusicView.tracks => const [],
    };
  }

  void _openPlayer() {
    final track = _playing ?? _playingNotifier.value;
    if (track == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NowPlayingSheet(
        initialTrack: track,
        playingNotifier: _playingNotifier,
        player: _player,
        favorites: _favorites,
        repeatOne: _repeatOne,
        onToggle: _toggleCurrent,
        onClose: _closePlayer,
        onRepeat: _toggleRepeat,
        onFavorite: _toggleFavorite,
        onPrevious: () => _skip(-1),
        onNext: () => _skip(1),
        onQueue: () => _openGroup(
          _LibraryGroupData(
            title: 'Now playing queue',
            subtitle: '${_tracks.length} song(s)',
            icon: Icons.queue_music,
            tracks: _tracks,
          ),
        ),
      ),
    );
  }

  void _openGroup(_LibraryGroupData group) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                child: Row(
                  children: [
                    _GroupIcon(icon: group.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(group.subtitle),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _TrackList(
                  controller: controller,
                  tracks: group.tracks,
                  playing: _playing,
                  player: _player,
                  selected: const {},
                  selectionMode: false,
                  bottomPadding: 24,
                  onPlay: (track) {
                    Navigator.of(context).pop();
                    _play(track);
                  },
                  onSelect: (_) {},
                  onMore: (track) =>
                      showWorkableMessage(context, track.file.path),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _sorted(_filter(_tracks));
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0E1117) : null,
      appBar: AppBar(
        title: Text(_selectionMode ? '${_selected.length} selected' : 'Music'),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _selectAll(tracks),
                ),
                IconButton(
                  tooltip: 'Share',
                  icon: const Icon(Icons.share),
                  onPressed: _shareSelected,
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copyOrMoveSelected(move: false),
                ),
                IconButton(
                  tooltip: 'Move',
                  icon: const Icon(Icons.drive_file_move),
                  onPressed: () => _copyOrMoveSelected(move: true),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteSelected,
                ),
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
              ]
            : [
                const ThemeToggleButton(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed:
                      _loading ? null : () => unawaited(_manualRefresh()),
                ),
              ],
      ),
      body: _loading && _tracks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _MusicTabs(
                  selected: _view,
                  onChanged: (view) => setState(() => _view = view),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF1F4F8),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _controller.clear();
                                        setState(() => _query = '');
                                      },
                                    ),
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search songs',
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (value) =>
                                setState(() => _query = value),
                            onSubmitted: (_) {
                              if (tracks.isNotEmpty) _play(tracks.first);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed:
                            tracks.isEmpty ? null : () => _play(tracks.first),
                        icon: const Icon(Icons.shuffle, size: 18),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 4),
                      PopupMenuButton<_MusicSort>(
                        tooltip: 'Sort by',
                        icon: const Icon(Icons.more_vert, size: 22),
                        onSelected: (sort) => setState(() => _sort = sort),
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: _MusicSort.date,
                            child: _SortItem(
                              selected: _sort == _MusicSort.date,
                              icon: Icons.calendar_month,
                              label: 'Date',
                            ),
                          ),
                          PopupMenuItem(
                            value: _MusicSort.size,
                            child: _SortItem(
                              selected: _sort == _MusicSort.size,
                              icon: Icons.sd_storage,
                              label: 'Size',
                            ),
                          ),
                          PopupMenuItem(
                            value: _MusicSort.time,
                            child: _SortItem(
                              selected: _sort == _MusicSort.time,
                              icon: Icons.timer,
                              label: 'Time',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: tracks.isEmpty
                      ? const Center(child: Text('No audio files found'))
                      : _view == _MusicView.tracks
                          ? _TrackList(
                              tracks: tracks,
                              playing: _playing,
                              player: _player,
                              selected: _selected,
                              selectionMode: _selectionMode,
                              bottomPadding: _playing == null ? 18 : 112,
                              onPlay: (track) {
                                if (_selectionMode) {
                                  _toggleSelect(track);
                                } else {
                                  _play(track);
                                }
                              },
                              onSelect: _toggleSelect,
                              onMore: _showTrackMenu,
                            )
                          : _GroupList(
                              groups: _groupsFor(tracks),
                              bottomPadding: _playing == null ? 18 : 112,
                              onPlayGroup: (group) {
                                if (group.tracks.isNotEmpty) {
                                  _play(group.tracks.first);
                                }
                              },
                              onOpenGroup: (group) => _openGroup(group),
                            ),
                ),
                if (_playing != null || _playingNotifier.value != null)
                  StreamBuilder<PlayerState>(
                    stream: _player.playerStateStream,
                    builder: (context, snapshot) {
                      final track = _playing ?? _playingNotifier.value;
                      if (track == null) return const SizedBox.shrink();
                      return _MiniPlayer(
                        track: track,
                        player: _player,
                        onTap: _openPlayer,
                        onToggle: _toggleCurrent,
                        onClose: _closePlayer,
                        onPrevious: () => _skip(-1),
                        onNext: () => _skip(1),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _MusicTabs extends StatelessWidget {
  const _MusicTabs({required this.selected, required this.onChanged});

  final _MusicView selected;
  final ValueChanged<_MusicView> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (_MusicView.tracks, 'Tracks'),
      (_MusicView.playlists, 'Playlists'),
      (_MusicView.albums, 'Albums'),
      (_MusicView.artists, 'Artists'),
      (_MusicView.folders, 'Folders'),
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final active = tab.$1 == selected;
          return ChoiceChip(
            selected: active,
            label: Text(tab.$2),
            onSelected: (_) => onChanged(tab.$1),
            selectedColor: const Color(0xFFFF005B),
            labelStyle: TextStyle(
              color: active ? Colors.white : const Color(0xFF3D4652),
              fontWeight: FontWeight.w800,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color:
                    active ? const Color(0xFFFF005B) : const Color(0xFFD9E0EA),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SortItem extends StatelessWidget {
  const _SortItem({
    required this.selected,
    required this.icon,
    required this.label,
  });

  final bool selected;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (selected) const Icon(Icons.check, size: 18),
      ],
    );
  }
}

class _LibraryGroupData {
  const _LibraryGroupData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tracks,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<AudioItem> tracks;
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.playing,
    required this.player,
    required this.selected,
    required this.selectionMode,
    required this.bottomPadding,
    required this.onPlay,
    required this.onSelect,
    required this.onMore,
    this.controller,
  });

  final List<AudioItem> tracks;
  final AudioItem? playing;
  final AudioPlayer player;
  final Set<String> selected;
  final bool selectionMode;
  final double bottomPadding;
  final ValueChanged<AudioItem> onPlay;
  final ValueChanged<AudioItem> onSelect;
  final ValueChanged<AudioItem> onMore;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final active = track.id == playing?.id;
        return _TrackTile(
          track: track,
          active: active,
          playing: active && player.playing,
          selected: selected.contains(track.id),
          selectionMode: selectionMode,
          onTap: () => onPlay(track),
          onLongPress: () => onSelect(track),
          onMore: () => onMore(track),
        );
      },
    );
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.bottomPadding,
    required this.onPlayGroup,
    required this.onOpenGroup,
  });

  final List<_LibraryGroupData> groups;
  final double bottomPadding;
  final ValueChanged<_LibraryGroupData> onPlayGroup;
  final ValueChanged<_LibraryGroupData> onOpenGroup;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const Center(child: Text('Nothing found'));
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          leading: _GroupIcon(icon: group.icon),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(group.subtitle),
          trailing: IconButton(
            tooltip: 'Play',
            icon: const Icon(Icons.play_circle_fill),
            color: const Color(0xFFFF005B),
            onPressed: () => onPlayGroup(group),
          ),
          onTap: () => onOpenGroup(group),
        );
      },
    );
  }
}

class _GroupIcon extends StatelessWidget {
  const _GroupIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: const Color(0xFF2D95E5), size: 28),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.active,
    required this.playing,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final AudioItem track;
  final bool active;
  final bool playing;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: const Color(0xFFFFEDF4),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: selectionMode
          ? Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? const Color(0xFFFF005B) : null,
              size: 30,
            )
          : _MusicArt(active: active),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
          color: active ? const Color(0xFFFF005B) : null,
        ),
      ),
      subtitle: Text(
        _trackSubtitle(track),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon:
            Icon(playing && !selectionMode ? Icons.equalizer : Icons.more_vert),
        color: active ? const Color(0xFFFF005B) : null,
        onPressed: onMore,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String _trackSubtitle(AudioItem track) {
    final parts = [
      track.artist,
      track.album,
    ].where((item) => item != null && item.trim().isNotEmpty).cast<String>();
    final text = parts.join(' - ');
    return text.isEmpty ? 'Finding artist...' : text;
  }
}

class _MusicArt extends StatelessWidget {
  const _MusicArt({this.active = false});

  final bool active;

  @override
  Widget build(BuildContext context) {
    const size = 50.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF005B), Color(0xFF2D95E5)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFFFF005B).withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: const Icon(
        Icons.music_note,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.track,
    required this.player,
    required this.onTap,
    required this.onToggle,
    required this.onClose,
    required this.onPrevious,
    required this.onNext,
  });

  final AudioItem track;
  final AudioPlayer player;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF171A21),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const _MusicArt(active: true),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track.artist ?? 'Unknown artist',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onPrevious,
                        icon: const Icon(Icons.skip_previous),
                        color: Colors.white,
                      ),
                      IconButton.filled(
                        onPressed: onToggle,
                        icon: Icon(
                          player.playing ? Icons.pause : Icons.play_arrow,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFF005B),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: onNext,
                        icon: const Icon(Icons.skip_next),
                        color: Colors.white,
                      ),
                      IconButton(
                        tooltip: 'Close player',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                      ),
                    ],
                  ),
                  _AudioProgress(player: player, compact: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.initialTrack,
    required this.playingNotifier,
    required this.player,
    required this.favorites,
    required this.repeatOne,
    required this.onToggle,
    required this.onClose,
    required this.onRepeat,
    required this.onFavorite,
    required this.onPrevious,
    required this.onNext,
    required this.onQueue,
  });

  final AudioItem initialTrack;
  final ValueNotifier<AudioItem?> playingNotifier;
  final AudioPlayer player;
  final Set<String> favorites;
  final bool repeatOne;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final VoidCallback onRepeat;
  final ValueChanged<AudioItem> onFavorite;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onQueue;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  late AudioItem _track;

  @override
  void initState() {
    super.initState();
    _track = widget.playingNotifier.value ?? widget.initialTrack;
    widget.playingNotifier.addListener(_syncTrack);
  }

  @override
  void dispose() {
    widget.playingNotifier.removeListener(_syncTrack);
    super.dispose();
  }

  void _syncTrack() {
    final next = widget.playingNotifier.value;
    if (next == null || next.id == _track.id || !mounted) return;
    setState(() => _track = next);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 1,
      child: AnimatedBuilder(
        animation: widget.playingNotifier,
        builder: (context, _) {
          final currentTrack = widget.playingNotifier.value ?? _track;
          final favourite = widget.favorites.contains(currentTrack.id);
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF111827),
                  Color(0xFF1F2937),
                  Color(0xFF0B1220),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.keyboard_arrow_down),
                          color: Colors.white,
                          iconSize: 34,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close music',
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onClose();
                          },
                          icon: const Icon(Icons.close),
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _AlbumArt(track: currentTrack, player: widget.player),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentTrack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => widget.onFavorite(currentTrack),
                          icon: Icon(favourite
                              ? Icons.star_rounded
                              : Icons.star_border_rounded),
                          color: Colors.white,
                          iconSize: 40,
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        currentTrack.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _AudioProgress(player: widget.player),
                    const SizedBox(height: 24),
                    StreamBuilder<PlayerState>(
                      stream: widget.player.playerStateStream,
                      builder: (context, snapshot) {
                        final playing = widget.player.playing;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: widget.onRepeat,
                              iconSize: 38,
                              color: widget.repeatOne
                                  ? const Color(0xFFFFE082)
                                  : Colors.white,
                              icon: Icon(
                                widget.repeatOne
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                              ),
                            ),
                            IconButton(
                              onPressed: widget.onPrevious,
                              iconSize: 42,
                              color: Colors.white,
                              icon: const Icon(Icons.skip_previous),
                            ),
                            IconButton.filled(
                              onPressed: widget.onToggle,
                              iconSize: 50,
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.22),
                                foregroundColor: Colors.white,
                                fixedSize: const Size(92, 92),
                              ),
                              icon: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                            IconButton(
                              onPressed: widget.onNext,
                              iconSize: 42,
                              color: Colors.white,
                              icon: const Icon(Icons.skip_next),
                            ),
                            IconButton(
                              onPressed: widget.onQueue,
                              iconSize: 38,
                              color: Colors.white,
                              icon: const Icon(Icons.queue_music),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.track, required this.player});

  final AudioItem track;
  final AudioPlayer player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, snapshot) {
        final playing = player.playing;
        return Container(
          width: 280,
          height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEF4444), Color(0xFF111827)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.36),
                blurRadius: 36,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 10,
                    ),
                  ),
                ),
                for (final size in const [214.0, 154.0, 94.0])
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                Container(
                  width: 74,
                  height: 74,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Icon(
                    playing ? Icons.graphic_eq : Icons.music_note,
                    color: const Color(0xFF111827),
                    size: 34,
                  ),
                ),
                Positioned(
                  left: 34,
                  right: 34,
                  bottom: 34,
                  child: Text(
                    track.album ?? track.folder ?? 'Local music',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CassetteArt extends StatefulWidget {
  const _CassetteArt({required this.playing});

  final bool playing;

  @override
  State<_CassetteArt> createState() => _CassetteArtState();
}

class _CassetteArtState extends State<_CassetteArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _CassetteArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 270,
      child: Center(
        child: Container(
          width: 330,
          height: 220,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 28,
                right: 28,
                top: 24,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'MUSIC TAPE',
                      style: TextStyle(
                        color: Color(0xFF245CA8),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 44,
                right: 44,
                top: 98,
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E4F9B).withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(36),
                  ),
                ),
              ),
              Positioned(
                left: 66,
                top: 94,
                child: _TapeReel(animation: _controller),
              ),
              Positioned(
                right: 66,
                top: 94,
                child: _TapeReel(animation: _controller),
              ),
              Positioned(
                left: 126,
                right: 126,
                bottom: 22,
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.64),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TapeReel extends StatelessWidget {
  const _TapeReel({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Transform.rotate(
          angle: animation.value * 6.28318530718,
          child: child,
        );
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFF245CA8),
                shape: BoxShape.circle,
              ),
            ),
            for (var i = 0; i < 6; i++)
              Transform.rotate(
                angle: i * 1.0471975512,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 7,
                    height: 22,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF245CA8).withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AudioProgress extends StatefulWidget {
  const _AudioProgress({required this.player, this.compact = false});

  final AudioPlayer player;
  final bool compact;

  @override
  State<_AudioProgress> createState() => _AudioProgressState();
}

class _AudioProgressState extends State<_AudioProgress> {
  double? _dragValue;

  Future<void> _seekTo(double next) async {
    final wasPlaying = widget.player.playing;
    try {
      await widget.player.seek(Duration(milliseconds: next.round()));
    } catch (_) {}
    if (wasPlaying && !widget.player.playing) {
      unawaited(widget.player.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = widget.player.duration ?? Duration.zero;
        final max = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final value =
            _dragValue ?? position.inMilliseconds.clamp(0, max).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: widget.compact ? 2 : 4,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: widget.compact ? 0 : 7,
                ),
              ),
              child: Slider(
                value: value,
                max: max,
                activeColor: const Color(0xFFFF005B),
                inactiveColor: Colors.white24,
                onChanged: (next) {
                  setState(() => _dragValue = next);
                },
                onChangeEnd: (next) {
                  setState(() => _dragValue = null);
                  unawaited(_seekTo(next));
                },
              ),
            ),
            if (!widget.compact)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_format(position), style: _timeStyle),
                    Text(_format(duration), style: _timeStyle),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  TextStyle get _timeStyle => TextStyle(
        color: Colors.white.withValues(alpha: 0.62),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );

  String _format(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return duration.inHours > 0
        ? '${duration.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}
