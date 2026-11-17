import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../models/file_entry.dart';
import '../models/video_item.dart';
import '../services/file_browser_service.dart';
import '../services/thumbnail_service.dart';
import '../widgets/app_toast.dart';
import 'player_screen.dart';

class LocalScreen extends StatefulWidget {
  const LocalScreen({super.key, required this.onTabRequested});

  final ValueChanged<int> onTabRequested;

  @override
  State<LocalScreen> createState() => _LocalScreenState();
}

class _LocalScreenState extends State<LocalScreen> {
  static const ThumbnailService _thumbnailService = ThumbnailService();

  final FileBrowserService _service = FileBrowserService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selected = {};
  final List<String> _history = [];
  final Map<String, double> _scrollOffsets = {};

  String _currentPath = 'All Files';
  String _query = '';
  bool _gridMode = false;
  bool _searching = false;
  bool _loading = false;
  bool _allMode = true;
  bool _scrolling = false;
  List<FileEntry> _entries = const [];
  List<FileEntry> _allEntries = const [];
  List<String> _sdRoots = const [];
  Timer? _scrollStopTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _entries = const [];
      _allEntries = const [];
    });

    final cachedEntries = await _allFilesEntries(const [], cacheOnly: true);
    final showedCache = mounted && cachedEntries.isNotEmpty;
    if (showedCache) {
      setState(() => _setAllEntries(entries: cachedEntries));
    }

    unawaited(_refreshAllFilesInBackground(showedCache: showedCache));
  }

  Future<void> _refreshAllFilesInBackground({required bool showedCache}) async {
    try {
      await _service.requestAccess();
      if (showedCache) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      final roots = await _service.sdCardRoots();
      final entries = await _allFilesEntries(roots);
      if (!mounted) return;
      setState(() {
        _sdRoots = roots;
        _setAllEntries(entries: entries);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _setAllEntries({List<FileEntry>? entries}) {
    _entries = entries ?? _allEntries;
    _allEntries = _entries;
    _allMode = true;
    _currentPath = 'All Files';
    _loading = false;
  }

  String get _scrollKey => _allMode ? 'All Files' : p.normalize(_currentPath);

  void _saveScrollOffset() {
    if (!_scrollController.hasClients) return;
    _scrollOffsets[_scrollKey] = _scrollController.offset;
  }

  void _restoreScrollOffset() {
    final key = _scrollKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || key != _scrollKey) {
        return;
      }
      final position = _scrollController.position;
      final offset = (_scrollOffsets[key] ?? 0)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _scrollController.jumpTo(offset);
    });
  }

  Future<List<FileEntry>> _allFilesEntries(
    List<String> sdRoots, {
    bool cacheOnly = false,
  }) async {
    final entries = <FileEntry>[
      ...await _videoFolderEntries(
        roots: const [FileBrowserService.internalPath],
        prefix: 'Internal',
        cacheOnly: cacheOnly,
      ),
    ];
    if (sdRoots.isNotEmpty) {
      entries.addAll(
        await _videoFolderEntries(
          roots: sdRoots,
          prefix: 'SD Card',
          cacheOnly: cacheOnly,
        ),
      );
    }
    return _sortAndDedupeEntries(entries);
  }

  Future<List<FileEntry>> _videoFolderEntries({
    required List<String> roots,
    required String prefix,
    bool cacheOnly = false,
  }) async {
    final mediaStoreEntries = await _service.videoFolders(
      roots: roots,
      prefix: prefix,
      cacheOnly: cacheOnly,
    );
    if (mediaStoreEntries.isNotEmpty) {
      if (cacheOnly) return mediaStoreEntries;
      final rootVideos = await _directRootVideoEntries(
        roots: roots,
        prefix: prefix,
      );
      return _sortAndDedupeEntries([...mediaStoreEntries, ...rootVideos]);
    }
    final rootVideos = cacheOnly
        ? <FileEntry>[]
        : await _directRootVideoEntries(roots: roots, prefix: prefix);
    final rootFolders = cacheOnly
        ? <FileEntry>[]
        : await _rootFoldersContainingVideos(roots: roots, prefix: prefix);
    final fallback = <FileEntry>[];
    for (final root in roots) {
      final rawEntries = await _service.list(root);
      fallback.addAll(
        (await _filterVisibleEntries(rawEntries, mediaFoldersOnly: true)).map(
          (item) => FileEntry(
            name: '$prefix / ${item.name}',
            path: item.path,
            isDirectory: item.isDirectory,
            sizeBytes: item.sizeBytes,
            modifiedAt: item.modifiedAt,
          ),
        ),
      );
    }
    return _sortAndDedupeEntries([...rootFolders, ...fallback, ...rootVideos]);
  }

  Future<List<FileEntry>> _rootFoldersContainingVideos({
    required List<String> roots,
    required String prefix,
  }) async {
    final entries = <FileEntry>[];
    for (final root in roots) {
      final rawEntries = await _service.list(root);
      final folders = rawEntries
          .where((entry) => entry.isDirectory && !entry.name.startsWith('.'))
          .toList();
      // Check all candidate folders concurrently; doing this sequentially
      // (one awaited scan after another) is what made this screen crawl.
      final checks = await Future.wait(
        folders.map(
          (folder) =>
              _service.directoryContainsVideo(folder.path, maxDepth: 2),
        ),
      );
      for (var i = 0; i < folders.length; i++) {
        if (!checks[i]) continue;
        final folder = folders[i];
        entries.add(
          FileEntry(
            name: prefix.isEmpty ? folder.name : '$prefix / ${folder.name}',
            path: folder.path,
            isDirectory: true,
            sizeBytes: folder.sizeBytes,
            modifiedAt: folder.modifiedAt,
          ),
        );
      }
    }
    return entries;
  }

  Future<List<FileEntry>> _directRootVideoEntries({
    required List<String> roots,
    required String prefix,
  }) async {
    final entries = <FileEntry>[];
    for (final root in roots) {
      final rootEntries = await _service.list(root);
      for (final item in rootEntries) {
        if (!item.isVideo || item.isDirectory || item.name.startsWith('.')) {
          continue;
        }
        entries.add(
          FileEntry(
            name: prefix.isEmpty ? item.name : '$prefix / ${item.name}',
            path: item.path,
            isDirectory: false,
            sizeBytes: item.sizeBytes,
            modifiedAt: item.modifiedAt,
          ),
        );
      }
    }
    return entries;
  }

  List<FileEntry> _sortAndDedupeEntries(List<FileEntry> entries) {
    final byPath = <String, FileEntry>{};
    for (final entry in entries) {
      byPath[p.normalize(entry.path).toLowerCase()] = entry;
    }
    return byPath.values.toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  Future<List<String>> _loadSdRoots() async {
    final List<String> roots;
    try {
      roots = await _service.sdCardRoots();
    } catch (_) {
      return _sdRoots;
    }
    if (!mounted) return roots;
    setState(() {
      _sdRoots = roots;
    });
    return roots;
  }

  Future<void> _openPath(String path, {bool push = true}) async {
    _saveScrollOffset();
    setState(() {
      _loading = true;
      _selected.clear();
      if (push) _history.add(_currentPath);
      _currentPath = path;
      _allMode = false;
    });
    final isKnownSdRoot = _sdRoots.contains(path);
    final rawEntries = path == FileBrowserService.internalPath
        ? await _videoFolderEntries(
            roots: const [FileBrowserService.internalPath],
            prefix: '',
          )
        : isKnownSdRoot
            ? await _videoFolderEntries(roots: [path], prefix: '')
            : await _service.list(path);
    final visibleEntries =
        path == FileBrowserService.internalPath || isKnownSdRoot
            ? rawEntries
            : await _filterVisibleEntries(rawEntries);
    if (!mounted) return;
    setState(() {
      _entries = visibleEntries;
      _loading = false;
    });
    _restoreScrollOffset();
    _prewarmVisibleThumbnails(visibleEntries);
  }

  void _prewarmVisibleThumbnails(List<FileEntry> entries) {
    unawaited(
      _thumbnailService.prewarmFiles(
        entries
            .where((entry) => entry.isVideo && !entry.isDirectory)
            .map((entry) => entry.path),
        limit: 8,
      ),
    );
  }

  Future<List<FileEntry>> _filterVisibleEntries(
    List<FileEntry> entries, {
    bool mediaFoldersOnly = true,
  }) async {
    final visible = <FileEntry>[];
    final directoryCandidates = <FileEntry>[];
    for (final entry in entries) {
      if (entry.name.startsWith('.')) continue;
      if (entry.isVideo) {
        visible.add(entry);
        continue;
      }
      if (!entry.isDirectory) continue;
      if (!mediaFoldersOnly) {
        visible.add(entry);
      } else {
        directoryCandidates.add(entry);
      }
    }
    final checks = await Future.wait(
      directoryCandidates.map(
        (entry) => _service.directoryContainsVideo(entry.path, maxDepth: 2),
      ),
    );
    for (var i = 0; i < directoryCandidates.length; i++) {
      if (checks[i]) visible.add(directoryCandidates[i]);
    }
    return visible;
  }

  List<FileEntry> get _visibleEntries {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _entries;
    return _entries
        .where((entry) =>
            entry.name.toLowerCase().contains(query) ||
            entry.path.toLowerCase().contains(query))
        .toList();
  }

  bool get _selectionMode => _selected.isNotEmpty;

  Future<bool> handleBack() async {
    if (_selectionMode) {
      setState(() => _selected.clear());
      return false;
    }
    if (_history.isNotEmpty) {
      _saveScrollOffset();
      final previous = _history.removeLast();
      if (previous == 'All Files') {
        setState(() => _setAllEntries());
        _restoreScrollOffset();
      } else {
        await _openPath(previous, push: false);
      }
      return false;
    }
    return true;
  }

  void _toggleSelect(FileEntry entry) {
    setState(() {
      if (_selected.contains(entry.path)) {
        _selected.remove(entry.path);
      } else {
        _selected.add(entry.path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _visibleEntries.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_visibleEntries.map((entry) => entry.path));
      }
    });
  }

  Future<void> _shareSelected() async {
    final files = _selected
        .where((path) =>
            FileSystemEntity.typeSync(path) == FileSystemEntityType.file)
        .map(XFile.new)
        .toList();
    if (files.isEmpty) {
      showWorkableMessage(context, 'Select files to share');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: files));
  }

  Future<void> _copyOrMoveSelected({required bool move}) async {
    final target = await FilePicker.platform.getDirectoryPath();
    if (target == null) return;
    for (final path in _selected) {
      final type = FileSystemEntity.typeSync(path);
      final targetPath = p.join(target, p.basename(path));
      try {
        if (type == FileSystemEntityType.file) {
          await File(path).copy(targetPath);
          if (move) await File(path).delete();
        } else if (type == FileSystemEntityType.directory) {
          await _copyDirectory(Directory(path), Directory(targetPath));
          if (move) await Directory(path).delete(recursive: true);
        }
      } catch (_) {}
    }
    _selected.clear();
    _service.invalidateDirectory(_currentPath);
    await _openPath(_currentPath, push: false);
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final next = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(next));
      } else if (entity is File) {
        await entity.copy(next);
      }
    }
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected?'),
        content: Text('Delete ${_selected.length} selected item(s).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    for (final path in _selected) {
      try {
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.directory) {
          await Directory(path).delete(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          await File(path).delete();
        }
      } catch (_) {}
    }
    _selected.clear();
    _service.invalidateDirectory(_currentPath);
    await _openPath(_currentPath, push: false);
  }

  void _openEntry(FileEntry entry) {
    if (_selectionMode) {
      _toggleSelect(entry);
      return;
    }
    if (entry.isDirectory) {
      _openPath(entry.path);
      return;
    }
    if (entry.isVideo) {
      final videos = _entries
          .where((item) => item.isVideo && !item.isDirectory)
          .map(_videoFromEntry)
          .toList();
      final index = videos.indexWhere((video) => video.file.path == entry.path);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            playlist: videos,
            initialIndex: index < 0 ? 0 : index,
          ),
        ),
      );
      return;
    }
    if (entry.isAudio) {
      widget.onTabRequested(1);
      showWorkableMessage(context, 'Open Music tab to play audio');
      return;
    }
    showWorkableMessage(context, 'No preview available');
  }

  VideoItem _videoFromEntry(FileEntry entry) {
    return VideoItem(
      id: entry.path,
      assetId: '',
      title: p.basenameWithoutExtension(entry.path),
      file: File(entry.path),
      duration: Duration.zero,
      sizeBytes: entry.sizeBytes,
      modifiedAt: entry.modifiedAt,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification) {
      if (!_scrolling) setState(() => _scrolling = true);
      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _scrolling = false);
      });
    } else if (notification is ScrollEndNotification) {
      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _scrolling = false);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visibleEntries;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await handleBack();
        // Use the imperative pop(), not maybePop(): with canPop:false a
        // maybePop() would re-trigger this same callback instead of popping,
        // spinning into an infinite loop that freezes the screen.
        if (shouldPop && context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search current folder',
                  ),
                  onChanged: (value) => setState(() => _query = value),
                )
              : Text(
                  _selectionMode ? '${_selected.length} selected' : 'Folders'),
          actions: _selectionMode
              ? [
                  IconButton(
                      tooltip: 'Select all',
                      icon: const Icon(Icons.select_all),
                      onPressed: _selectAll),
                  IconButton(
                      tooltip: 'Share',
                      icon: const Icon(Icons.share),
                      onPressed: _shareSelected),
                  IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copyOrMoveSelected(move: false)),
                  IconButton(
                      tooltip: 'Move',
                      icon: const Icon(Icons.drive_file_move),
                      onPressed: () => _copyOrMoveSelected(move: true)),
                  IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete),
                      onPressed: _deleteSelected),
                ]
              : [
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
                    icon: Icon(
                        _gridMode ? Icons.view_list : Icons.grid_view_rounded),
                    onPressed: () => setState(() => _gridMode = !_gridMode),
                  ),
                ],
        ),
        body: Column(
          children: [
            _StorageButtons(
              currentPath: _currentPath,
              allMode: _allMode,
              onAll: () => setState(() {
                _saveScrollOffset();
                _history.clear();
                _selected.clear();
                _setAllEntries(entries: _allEntries);
                _restoreScrollOffset();
              }),
              onInternal: () =>
                  _openPath(FileBrowserService.internalPath, push: false),
              onSd: () async {
                if (_sdRoots.isEmpty) {
                  final roots = await _loadSdRoots();
                  if (!mounted) return;
                  if (roots.isEmpty) {
                    await _chooseSdCardRoot();
                  } else {
                    await _openPath(roots.first, push: false);
                  }
                } else {
                  await _openPath(_sdRoots.first, push: false);
                }
              },
            ),
            _PathBar(
                path: _currentPath,
                onBack: _history.isEmpty ? null : () => handleBack()),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : entries.isEmpty
                      ? const Center(child: Text('No files found'))
                      : _gridMode
                          ? _FileGrid(
                              controller: _scrollController,
                              entries: entries,
                              selected: _selected,
                              onTap: _openEntry,
                              onLongPress: _toggleSelect)
                          : NotificationListener<ScrollNotification>(
                              onNotification: _handleScrollNotification,
                              child: _FileList(
                                controller: _scrollController,
                                entries: entries,
                                selected: _selected,
                                enableThumbnails: !_scrolling,
                                onTap: _openEntry,
                                onLongPress: _toggleSelect,
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseSdCardRoot() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select SD Card root',
    );
    if (selected == null) {
      if (mounted) {
        showWorkableMessage(context, 'SD Card not found or permission denied');
      }
      return;
    }
    _sdRoots = [selected];
    await _openPath(selected, push: false);
  }
}

class _StorageButtons extends StatelessWidget {
  const _StorageButtons({
    required this.currentPath,
    required this.allMode,
    required this.onAll,
    required this.onInternal,
    required this.onSd,
  });

  final String currentPath;
  final bool allMode;
  final VoidCallback onAll;
  final VoidCallback onInternal;
  final VoidCallback onSd;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final internal =
        !allMode && currentPath.startsWith(FileBrowserService.internalPath);
    final sdCard = !allMode && !internal;
    ButtonStyle styleFor(bool selected) {
      return FilledButton.styleFrom(
        backgroundColor: selected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        foregroundColor:
            selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
        textStyle: const TextStyle(fontSize: 12),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onAll,
              icon: const Icon(Icons.folder_copy),
              label: const Text('All Files'),
              style: styleFor(allMode),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: onInternal,
              icon: const Icon(Icons.phone_android),
              label: const Text('Internal Storage'),
              style: styleFor(internal),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: onSd,
              icon: const Icon(Icons.sd_card),
              label: const Text('SD Card'),
              style: styleFor(sdCard),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathBar extends StatelessWidget {
  const _PathBar({required this.path, required this.onBack});

  final String path;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList(
      {required this.controller,
      required this.entries,
      required this.selected,
      required this.enableThumbnails,
      required this.onTap,
      required this.onLongPress});

  final ScrollController controller;
  final List<FileEntry> entries;
  final Set<String> selected;
  final bool enableThumbnails;
  final ValueChanged<FileEntry> onTap;
  final ValueChanged<FileEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: controller,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isSelected = selected.contains(entry.path);
        return ListTile(
          dense: true,
          selected: isSelected,
          leading: _EntryLeading(
            entry: entry,
            selected: isSelected,
            enableThumbnail: enableThumbnails,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(entry.isDirectory ? 'Folder' : _formatSize(entry.sizeBytes)),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: colorScheme.primary)
              : Text(
                  DateFormat('MMM d').format(entry.modifiedAt),
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
        );
      },
    );
  }
}

class _FileGrid extends StatelessWidget {
  const _FileGrid(
      {required this.controller,
      required this.entries,
      required this.selected,
      required this.onTap,
      required this.onLongPress});

  final ScrollController controller;
  final List<FileEntry> entries;
  final Set<String> selected;
  final ValueChanged<FileEntry> onTap;
  final ValueChanged<FileEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisExtent: 122),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final isSelected = selected.contains(entry.path);
        return InkWell(
          onTap: () => onTap(entry),
          onLongPress: () => onLongPress(entry),
          child: Card(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _EntryGridIcon(entry: entry),
                  const SizedBox(height: 8),
                  Text(entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EntryLeading extends StatelessWidget {
  const _EntryLeading({
    required this.entry,
    required this.selected,
    required this.enableThumbnail,
  });

  final FileEntry entry;
  final bool selected;
  final bool enableThumbnail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (entry.isVideo) {
      return SizedBox(
        width: 58,
        height: 42,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _FileVideoThumbnail(
            path: entry.path,
            enableThumbnail: enableThumbnail,
          ),
        ),
      );
    }
    return Icon(
      _iconFor(entry),
      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
    );
  }
}

class _EntryGridIcon extends StatelessWidget {
  const _EntryGridIcon({required this.entry});

  final FileEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (entry.isVideo) {
      return SizedBox(
        height: 48,
        width: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _FileVideoThumbnail(path: entry.path),
        ),
      );
    }
    return Icon(_iconFor(entry), size: 34, color: colorScheme.onSurfaceVariant);
  }
}

class _FileVideoThumbnail extends StatefulWidget {
  const _FileVideoThumbnail({
    required this.path,
    this.enableThumbnail = true,
  });

  final String path;
  final bool enableThumbnail;

  @override
  State<_FileVideoThumbnail> createState() => _FileVideoThumbnailState();
}

class _FileVideoThumbnailState extends State<_FileVideoThumbnail> {
  static const ThumbnailService _thumbnailService = ThumbnailService();

  ImageProvider? _thumbnail;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableThumbnail) _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant _FileVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _thumbnail = null;
      _requested = false;
      if (widget.enableThumbnail) _scheduleLoad();
    } else if (!oldWidget.enableThumbnail && widget.enableThumbnail) {
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    if (!widget.enableThumbnail) return;
    if (_requested) return;
    _requested = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted || !widget.enableThumbnail) {
      _requested = false;
      return;
    }
    final data = await _thumbnailService.loadFile(widget.path);
    if (!mounted || !widget.enableThumbnail || data == null || data.isEmpty) {
      _requested = false;
      return;
    }
    setState(() => _thumbnail = MemoryImage(data));
  }

  @override
  Widget build(BuildContext context) {
    final image = _thumbnail;
    if (image == null) {
      final colorScheme = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.movie_outlined,
            color: colorScheme.onSurfaceVariant,
            size: 24,
          ),
        ),
      );
    }
    return Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
  }
}

IconData _iconFor(FileEntry entry) {
  if (entry.isDirectory) return Icons.folder;
  if (entry.isVideo) return Icons.movie;
  if (entry.isAudio) return Icons.music_note;
  return Icons.insert_drive_file;
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
