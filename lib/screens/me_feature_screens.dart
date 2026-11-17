import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/file_entry.dart';
import '../models/video_item.dart';
import '../services/biometric_service.dart';
import '../services/file_browser_service.dart';
import '../services/network_scan_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _FileActionBrowser(
      title: 'Downloads',
      roots: const ['/storage/emulated/0/Download'],
      emptyText: 'No downloaded files found',
    );
  }
}

class StatusSaverScreen extends StatelessWidget {
  const StatusSaverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _FileActionBrowser(
      title: 'Status Saver',
      roots: const [
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
        '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
        '/storage/emulated/0/WhatsApp/Media/.Statuses',
        '/storage/emulated/0/WhatsApp Business/Media/.Statuses',
      ],
      emptyText: 'No WhatsApp statuses found',
      saveMode: true,
    );
  }
}

class RecycleBinScreen extends StatelessWidget {
  const RecycleBinScreen({super.key});

  /// Deletes recycled files older than the user's retention window.
  Future<Directory> _prepareBin() async {
    final dir = await _appDir('Recycle Bin');
    final retention =
        Duration(days: AppSettings.instance.recycleBinRetentionDays);
    final cutoff = DateTime.now().subtract(retention);
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
    return dir;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: _prepareBin(),
      builder: (context, snapshot) {
        final dir = snapshot.data;
        if (dir == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return _FileActionBrowser(
          title: 'Recycle Bin',
          roots: [dir.path],
          emptyText: 'Recycle Bin is empty',
          recycleMode: true,
        );
      },
    );
  }
}

class PrivateFolderScreen extends StatefulWidget {
  const PrivateFolderScreen({super.key});

  @override
  State<PrivateFolderScreen> createState() => _PrivateFolderScreenState();
}

class _PrivateFolderScreenState extends State<PrivateFolderScreen> {
  final TextEditingController _pinController = TextEditingController();
  final BiometricService _biometric = BiometricService();
  bool _unlocked = false;
  String? _pin;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPin());
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _loadPin() async {
    final dir = await _appDir('Private');
    final file = File(p.join(dir.path, '.pin'));
    if (await file.exists()) {
      _pin = await file.readAsString();
    }
    if (mounted) setState(() {});
    await _tryBiometric();
  }

  Future<void> _tryBiometric() async {
    if (_pin == null || !mounted) return;
    final settings = AppSettings.instance;
    if (!settings.useFingerprint) return;
    if (!await _biometric.isAvailable()) return;
    final ok = await _biometric.authenticate('Unlock your Private Folder');
    if (ok && mounted) setState(() => _unlocked = true);
  }

  Future<void> _submit() async {
    final text = _pinController.text.trim();
    if (text.length < 4) return;
    if (_pin == null) {
      final dir = await _appDir('Private');
      await File(p.join(dir.path, '.pin')).writeAsString(text);
      _pin = text;
      setState(() => _unlocked = true);
    } else if (text == _pin) {
      setState(() => _unlocked = true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return FutureBuilder<Directory>(
        future: _appDir('Private'),
        builder: (context, snapshot) {
          final dir = snapshot.data;
          if (dir == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return _FileActionBrowser(
            title: 'Private Folder',
            roots: [dir.path],
            emptyText: 'No private files',
            allowImport: true,
            privateMode: true,
          );
        },
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Private Folder')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.lock_outline, size: 72),
          const SizedBox(height: 18),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _pin == null ? 'Create PIN' : 'Enter PIN',
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.lock_open),
            label: Text(_pin == null ? 'Create secure folder' : 'Unlock'),
          ),
          if (_pin != null && AppSettings.instance.useFingerprint) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _tryBiometric,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Unlock with fingerprint'),
            ),
          ],
        ],
      ),
    );
  }
}

class VideoPlaylistsScreen extends StatefulWidget {
  const VideoPlaylistsScreen({super.key});

  @override
  State<VideoPlaylistsScreen> createState() => _VideoPlaylistsScreenState();
}

class _VideoPlaylistsScreenState extends State<VideoPlaylistsScreen> {
  final PlaylistService _service = PlaylistService.instance;
  List<Playlist> _playlists = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final lists = await _service.load();
    if (!mounted) return;
    setState(() {
      _playlists = List.of(lists);
      _loading = false;
    });
  }

  Future<void> _createPlaylist() async {
    final name = await _promptName(context, 'New playlist', '');
    if (name == null || name.isEmpty) return;
    await _service.create(name);
    await _reload();
  }

  Future<void> _rename(Playlist playlist) async {
    final name = await _promptName(context, 'Rename playlist', playlist.name);
    if (name == null || name.isEmpty) return;
    await _service.rename(playlist.id, name);
    await _reload();
  }

  Future<void> _delete(Playlist playlist) async {
    await _service.delete(playlist.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Playlists')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createPlaylist,
        icon: const Icon(Icons.playlist_add),
        label: const Text('New playlist'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
              ? const Center(child: Text('Tap "New playlist" to get started'))
              : ListView.builder(
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    return ListTile(
                      leading: const Icon(Icons.queue_music, size: 32),
                      title: Text(playlist.name),
                      subtitle: Text('${playlist.paths.length} videos'),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PlaylistDetailScreen(playlistId: playlist.id),
                          ),
                        );
                        await _reload();
                      },
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'rename') _rename(playlist);
                          if (value == 'delete') _delete(playlist);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PlaylistService _service = PlaylistService.instance;
  Playlist? _playlist;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final lists = await _service.load();
    if (!mounted) return;
    Playlist? found;
    for (final item in lists) {
      if (item.id == widget.playlistId) {
        found = item;
        break;
      }
    }
    setState(() => _playlist = found);
  }

  Future<void> _addVideos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.video,
    );
    if (result == null) return;
    final paths = result.files.map((f) => f.path).whereType<String>();
    await _service.addPaths(widget.playlistId, paths);
    await _reload();
  }

  void _play(int index) {
    final playlist = _playlist;
    if (playlist == null) return;
    final videos = playlist.paths
        .map((path) => VideoItem(
              id: path,
              assetId: '',
              title: p.basenameWithoutExtension(path),
              file: File(path),
              duration: Duration.zero,
              sizeBytes: File(path).existsSync() ? File(path).lengthSync() : 0,
              modifiedAt: DateTime.now(),
            ))
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(playlist: videos, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist?.name ?? 'Playlist'),
        actions: [
          if (playlist != null && playlist.paths.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              icon: const Icon(Icons.play_circle_fill),
              onPressed: () => _play(0),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addVideos,
        child: const Icon(Icons.add),
      ),
      body: playlist == null
          ? const Center(child: CircularProgressIndicator())
          : playlist.paths.isEmpty
              ? const Center(child: Text('Add videos to this playlist'))
              : ListView.builder(
                  itemCount: playlist.paths.length,
                  itemBuilder: (context, index) {
                    final path = playlist.paths[index];
                    return ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(p.basename(path),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _play(index),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () async {
                          await _service.removePath(widget.playlistId, path);
                          await _reload();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

Future<String?> _promptName(
    BuildContext context, String title, String initial) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  return name;
}

class NetworkStreamScreen extends StatefulWidget {
  const NetworkStreamScreen({super.key});

  @override
  State<NetworkStreamScreen> createState() => _NetworkStreamScreenState();
}

class _NetworkStreamScreenState extends State<NetworkStreamScreen> {
  final TextEditingController _controller = TextEditingController();
  VideoPlayerController? _video;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final raw = _controller.text.trim();
    final uri = Uri.tryParse(raw);
    if (raw.isEmpty || uri == null || !uri.hasScheme || !uri.hasAuthority) {
      setState(() => _error = 'Enter a valid URL (http://, https:// or rtsp://)');
      return;
    }

    // Tear down any previous stream before starting a new one.
    final previous = _video;
    setState(() {
      _video = null;
      _loading = true;
      _error = null;
    });
    await previous?.dispose();

    final controller = VideoPlayerController.networkUrl(uri);
    try {
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _loading = false;
      });
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not play this stream.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      appBar: AppBar(title: const Text('Network Stream')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_loading,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Stream URL',
              hintText: 'https://example.com/video.mp4 or .m3u8',
            ),
            onSubmitted: (_) => _play(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _play,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_loading ? 'Connecting...' : 'Play stream'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          if (video != null && video.value.isInitialized)
            AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
        ],
      ),
    );
  }
}

class LocalNetworkScreen extends StatefulWidget {
  const LocalNetworkScreen({super.key});

  @override
  State<LocalNetworkScreen> createState() => _LocalNetworkScreenState();
}

class _LocalNetworkScreenState extends State<LocalNetworkScreen> {
  final NetworkScanService _service = NetworkScanService();
  final List<DiscoveredDevice> _devices = [];
  StreamSubscription<DiscoveredDevice>? _sub;
  bool _scanning = false;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _sub?.cancel();
    final ip = await _service.localIp();
    if (!mounted) return;
    setState(() {
      _devices.clear();
      _scanning = true;
      _localIp = ip;
    });
    _sub = _service.scan().listen(
      (device) {
        if (!mounted) return;
        setState(() => _devices.add(device));
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _openShare() async {
    final controller = TextEditingController(text: 'smb://');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open SMB / FTP share'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'smb://192.168.1.5 or ftp://192.168.1.5',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty) return;
    await _launch(url);
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No app can open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Network'),
        actions: [
          IconButton(
            tooltip: 'Open SMB/FTP',
            icon: const Icon(Icons.dns_outlined),
            onPressed: _openShare,
          ),
          IconButton(
            tooltip: 'Rescan',
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _startScan,
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.wifi),
            title: Text(_localIp == null
                ? 'Not connected to WiFi'
                : 'This device: $_localIp'),
            subtitle: Text(_scanning
                ? 'Scanning your WiFi network...'
                : '${_devices.length} device(s) found'),
            trailing: _scanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: _devices.isEmpty && !_scanning
                ? const Center(
                    child: Text('No shared devices found on this WiFi'))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      return ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(device.hostname ?? device.ip),
                        subtitle: Text(
                            '${device.ip} • ${device.serviceHint} • ports ${device.openPorts.join(', ')}'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () {
                          final scheme = device.openPorts.contains(21)
                              ? 'ftp'
                              : device.openPorts.contains(445) ||
                                      device.openPorts.contains(139)
                                  ? 'smb'
                                  : 'http';
                          _launch('$scheme://${device.ip}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CloudDriveScreen extends StatelessWidget {
  const CloudDriveScreen({super.key});

  Future<void> _importFromCloud(BuildContext context) async {
    // Cloud apps (Drive/Dropbox/OneDrive) register as document providers, so
    // the Android Storage Access Framework picker can browse and pull files
    // straight from them without per-provider OAuth setup.
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || !context.mounted) return;
    final count = result.files.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $count file(s) from cloud')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Drive')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync, size: 32),
              title: const Text('Import from cloud'),
              subtitle: const Text(
                  'Browse Google Drive, Dropbox, OneDrive and other installed cloud apps and pull files in.'),
              onTap: () => _importFromCloud(context),
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Providers'),
          _ProviderTile(
            name: 'Google Drive',
            icon: Icons.add_to_drive,
            color: Color(0xFF1FA463),
          ),
          _ProviderTile(
            name: 'Dropbox',
            icon: Icons.cloud,
            color: Color(0xFF0061FF),
          ),
          _ProviderTile(
            name: 'OneDrive',
            icon: Icons.cloud_circle,
            color: Color(0xFF0364B8),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Direct in-app sign-in and streaming for each provider requires '
              'official OAuth client IDs registered in their developer consoles. '
              'Until then, "Import from cloud" uses the Android system picker, '
              'which already lists every installed cloud app.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 30),
        title: Text(name),
        subtitle: const Text('Connect via system picker'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => FilePicker.platform.pickFiles(allowMultiple: true),
      ),
    );
  }
}

class AppThemeScreen extends StatelessWidget {
  const AppThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('App Theme')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader('Mode'),
          RadioGroup<AppThemeVariant>(
            groupValue: settings.themeVariant,
            onChanged: (value) {
              if (value != null) settings.setThemeVariant(value);
            },
            child: Column(
              children: [
                for (final entry in const [
                  (AppThemeVariant.light, Icons.light_mode, 'Light',
                      'Bright theme for daytime'),
                  (AppThemeVariant.dark, Icons.dark_mode, 'Dark',
                      'Dimmed surfaces for low light'),
                  (AppThemeVariant.amoled, Icons.contrast, 'AMOLED black',
                      'True black to save battery on OLED screens'),
                ])
                  RadioListTile<AppThemeVariant>(
                    value: entry.$1,
                    secondary: Icon(entry.$2),
                    title: Text(entry.$3),
                    subtitle: Text(entry.$4),
                  ),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('Accent color'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final option in kAccentOptions)
                  _AccentSwatch(
                    option: option,
                    selected: settings.accent.toARGB32() ==
                        option.color.toARGB32(),
                    onTap: () => settings.setAccent(option.color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: option.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Colors.transparent,
                width: 3,
              ),
            ),
            child: selected
                ? const Icon(Icons.check, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 6),
          Text(option.name, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Player'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Default playback speed'),
            subtitle: Text('${settings.defaultSpeed}x'),
            trailing: DropdownButton<double>(
              value: settings.defaultSpeed,
              underline: const SizedBox.shrink(),
              items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                  .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                  .toList(),
              onChanged: (v) {
                if (v != null) settings.setDefaultSpeed(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.aspect_ratio),
            title: const Text('Default resize mode'),
            subtitle: Text(_resizeLabel(settings.resizeMode)),
            trailing: DropdownButton<String>(
              value: settings.resizeMode,
              underline: const SizedBox.shrink(),
              items: const ['fit', 'fill', 'crop']
                  .map((m) =>
                      DropdownMenuItem(value: m, child: Text(_resizeLabel(m))))
                  .toList(),
              onChanged: (v) {
                if (v != null) settings.setResizeMode(v);
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.history_toggle_off),
            title: const Text('Resume playback'),
            subtitle: const Text('Continue videos from where you left off'),
            value: settings.resumePlayback,
            onChanged: settings.setResumePlayback,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next),
            title: const Text('Auto play next'),
            subtitle: const Text('Play the next video in a playlist/folder'),
            value: settings.autoPlayNext,
            onChanged: settings.setAutoPlayNext,
          ),
          const Divider(),
          const _SectionHeader('Subtitles'),
          SwitchListTile(
            secondary: const Icon(Icons.subtitles),
            title: const Text('Enable subtitles'),
            value: settings.subtitlesEnabled,
            onChanged: settings.setSubtitlesEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Subtitle text size'),
            subtitle: Slider(
              min: 12,
              max: 32,
              divisions: 10,
              label: settings.subtitleFontSize.round().toString(),
              value: settings.subtitleFontSize,
              onChanged: settings.subtitlesEnabled
                  ? settings.setSubtitleFontSize
                  : null,
            ),
          ),
          const Divider(),
          const _SectionHeader('Transfer'),
          SwitchListTile(
            secondary: const Icon(Icons.verified_user_outlined),
            title: const Text('Confirm before receiving'),
            subtitle: const Text('Ask before accepting incoming files'),
            value: settings.transferConfirmReceive,
            onChanged: settings.setTransferConfirmReceive,
          ),
          const Divider(),
          const _SectionHeader('Privacy'),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Use fingerprint for Private Folder'),
            subtitle: const Text('Unlock with biometrics when available'),
            value: settings.useFingerprint,
            onChanged: settings.setUseFingerprint,
          ),
          const Divider(),
          const _SectionHeader('Storage'),
          ListTile(
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Recycle Bin auto-cleanup'),
            subtitle: Text('Delete items after ${settings.recycleBinRetentionDays} days'),
            trailing: DropdownButton<int>(
              value: settings.recycleBinRetentionDays,
              underline: const SizedBox.shrink(),
              items: const [7, 14, 30, 60, 90]
                  .map((d) => DropdownMenuItem(value: d, child: Text('$d d')))
                  .toList(),
              onChanged: (v) {
                if (v != null) settings.setRecycleBinRetentionDays(v);
              },
            ),
          ),
          const Divider(),
          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Transfer notifications'),
            subtitle: const Text('Show progress while sending/receiving'),
            value: settings.notifyTransfers,
            onChanged: settings.setNotifyTransfers,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static String _resizeLabel(String mode) => switch (mode) {
        'fill' => 'Stretch to fill',
        'crop' => 'Crop to fill',
        _ => 'Fit to screen',
      };
}

class PopupPlayScreen extends StatelessWidget {
  const PopupPlayScreen({super.key});

  Future<void> _playInMiniWindow(BuildContext context) async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;
    final video = VideoItem(
      id: path,
      assetId: '',
      title: p.basenameWithoutExtension(path),
      file: File(path),
      duration: Duration.zero,
      sizeBytes: File(path).existsSync() ? File(path).lengthSync() : 0,
      modifiedAt: DateTime.now(),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(playlist: [video], initialIndex: 0),
      ),
    );
  }

  Future<void> _openOverlaySettings() async {
    // Send the user to the app's system settings, where "Display over other
    // apps" can be enabled for a floating window.
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Pop-up Play')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.picture_in_picture_alt,
              size: 64, color: Color(0xFFFF005B)),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Play a video'),
              subtitle: const Text(
                  'Opens the player; press Home to keep audio in the background.'),
              onTap: () => _playInMiniWindow(context),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: const Text('Allow floating window'),
              subtitle: const Text(
                  'Grant "Display over other apps" so video can float over other apps.'),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openOverlaySettings,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'A true system floating window over other apps needs a native '
              'Android overlay Service (SYSTEM_ALERT_WINDOW). The in-app player '
              'already supports fullscreen, gestures, zoom, rotation and '
              'background audio. The overlay Service is the remaining native step.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal')),
      body: ListView(
        children: [
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: 'MX Player Clone',
            applicationVersion: '1.0.0',
            applicationLegalese: 'For personal media playback and transfer.',
          ),
          const ListTile(
            title: Text('Privacy Policy'),
            subtitle: Text(
                'Files stay on your device unless you start local transfer.'),
          ),
          const ListTile(
            title: Text('Terms & Conditions'),
            subtitle: Text(
                'Use only with files and devices you are authorized to access.'),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Open-source licenses'),
            onTap: () => showLicensePage(context: context),
          ),
        ],
      ),
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<(String, String)> _faqs = [
    (
      'How do I transfer files to my PC?',
      'Open File Transfer, tap SEND, then open the shown web address in any '
          'browser on a PC connected to the same WiFi or hotspot.'
    ),
    (
      'How do I seek or change brightness/volume?',
      'In the player, double tap the left/right edge to seek. Swipe up/down on '
          'the left for brightness and on the right for volume.'
    ),
    (
      'Where do private files go?',
      'Private Folder moves files into the app\'s sandboxed private storage, '
          'protected by your PIN (and fingerprint if enabled in Settings).'
    ),
    (
      'Can I recover deleted files?',
      'Yes. Deleted files go to the Recycle Bin and can be restored until '
          'auto-cleanup removes them after the period set in Settings.'
    ),
  ];

  Future<void> _email(BuildContext context, String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@mxplayerclone.app',
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        children: [
          const _SectionHeader('Frequently asked questions'),
          for (final faq in _faqs)
            ExpansionTile(
              leading: const Icon(Icons.help_outline),
              title: Text(faq.$1),
              childrenPadding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [Align(
                alignment: Alignment.centerLeft,
                child: Text(faq.$2),
              )],
            ),
          const Divider(),
          const _SectionHeader('Get in touch'),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Contact support'),
            subtitle: const Text('Email our support team'),
            onTap: () => _email(context, 'MX Player Clone support'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a bug'),
            subtitle: const Text('Tell us what went wrong'),
            onTap: () => _email(context, 'MX Player Clone bug report'),
          ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('Send feedback'),
            subtitle: const Text('Share ideas and suggestions'),
            onTap: () => SharePlus.instance.share(
              ShareParams(text: 'MX Player Clone feedback: '),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _FileActionBrowser extends StatefulWidget {
  const _FileActionBrowser({
    required this.title,
    required this.roots,
    required this.emptyText,
    this.saveMode = false,
    this.recycleMode = false,
    this.allowImport = false,
    this.privateMode = false,
  });

  final String title;
  final List<String> roots;
  final String emptyText;
  final bool saveMode;
  final bool recycleMode;
  final bool allowImport;
  final bool privateMode;

  @override
  State<_FileActionBrowser> createState() => _FileActionBrowserState();
}

class _FileActionBrowserState extends State<_FileActionBrowser> {
  final FileBrowserService _service = FileBrowserService();
  final TextEditingController _searchController = TextEditingController();
  List<FileEntry> _entries = const [];
  bool _loading = true;
  String _query = '';
  String _category = 'all'; // all | video | audio | docs
  String _sort = 'name'; // name | date | size

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = <FileEntry>[];
    for (final root in widget.roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      entries.addAll(await _service.list(root));
    }
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  List<FileEntry> get _visible {
    final query = _query.trim().toLowerCase();
    var list = _entries.where((entry) {
      if (query.isNotEmpty && !entry.name.toLowerCase().contains(query)) {
        return false;
      }
      switch (_category) {
        case 'video':
          return entry.isDirectory || entry.isVideo;
        case 'audio':
          return entry.isDirectory || entry.isAudio;
        case 'docs':
          return entry.isDirectory || (!entry.isVideo && !entry.isAudio);
        default:
          return true;
      }
    }).toList();
    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (_sort) {
        case 'date':
          return b.modifiedAt.compareTo(a.modifiedAt);
        case 'size':
          return b.sizeBytes.compareTo(a.sizeBytes);
        default:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });
    return list;
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final dir = Directory(widget.roots.first);
    if (!await dir.exists()) await dir.create(recursive: true);
    for (final picked in result.files) {
      final path = picked.path;
      if (path == null) continue;
      await File(path).copy(p.join(dir.path, picked.name));
    }
    await _load();
  }

  Future<void> _open(FileEntry entry) async {
    if (entry.isDirectory) return;
    if (entry.isVideo) {
      final videos = _visible
          .where((item) => item.isVideo && !item.isDirectory)
          .map((item) => VideoItem(
                id: item.path,
                assetId: '',
                title: p.basenameWithoutExtension(item.path),
                file: File(item.path),
                duration: Duration.zero,
                sizeBytes: item.sizeBytes,
                modifiedAt: item.modifiedAt,
              ))
          .toList();
      final index = videos.indexWhere((video) => video.file.path == entry.path);
      if (!mounted) return;
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
    await SharePlus.instance.share(ShareParams(files: [XFile(entry.path)]));
  }

  Future<void> _delete(FileEntry entry) async {
    final file = File(entry.path);
    if (widget.recycleMode) {
      await file.delete();
    } else {
      final bin = await _appDir('Recycle Bin');
      await file.rename(p.join(bin.path, p.basename(entry.path)));
    }
    await _load();
  }

  Future<void> _rename(FileEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await File(entry.path).rename(p.join(p.dirname(entry.path), name));
    await _load();
  }

  Future<void> _restore(FileEntry entry) async {
    // Move the file back out to a visible public folder (unhide).
    final target = Directory('/storage/emulated/0/Download/MX Restored');
    if (!await target.exists()) await target.create(recursive: true);
    await File(entry.path).rename(p.join(target.path, p.basename(entry.path)));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restored to Downloads/MX Restored')),
      );
    }
    await _load();
  }

  Future<void> _saveStatus(FileEntry entry) async {
    final target = Directory('/storage/emulated/0/Download/MX Status Saver');
    if (!await target.exists()) await target.create(recursive: true);
    await File(entry.path).copy(p.join(target.path, p.basename(entry.path)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to Downloads/MX Status Saver')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.allowImport)
            IconButton(
              tooltip: 'Import files',
              icon: const Icon(Icons.add),
              onPressed: _import,
            ),
          PopupMenuButton<String>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: 'name',
                  checked: _sort == 'name',
                  child: const Text('Name')),
              CheckedPopupMenuItem(
                  value: 'date',
                  checked: _sort == 'date',
                  child: const Text('Date modified')),
              CheckedPopupMenuItem(
                  value: 'size',
                  checked: _sort == 'size',
                  child: const Text('Size')),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (!widget.recycleMode && !widget.saveMode)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final cat in const [
                    ('all', 'All'),
                    ('video', 'Videos'),
                    ('audio', 'Music'),
                    ('docs', 'Documents'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat.$2),
                        selected: _category == cat.$1,
                        onSelected: (_) =>
                            setState(() => _category = cat.$1),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? Center(child: Text(widget.emptyText))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            leading: Icon(entry.isDirectory
                                ? Icons.folder
                                : entry.isVideo
                                    ? Icons.movie
                                    : Icons.insert_drive_file),
                            title: Text(entry.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${_formatSize(entry.sizeBytes)} - ${DateFormat('MMM d, yyyy').format(entry.modifiedAt)}',
                            ),
                            onTap: () => _open(entry),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'share') {
                                  SharePlus.instance.share(
                                    ShareParams(files: [XFile(entry.path)]),
                                  );
                                } else if (value == 'delete') {
                                  _delete(entry);
                                } else if (value == 'rename') {
                                  _rename(entry);
                                } else if (value == 'save') {
                                  _saveStatus(entry);
                                } else if (value == 'restore') {
                                  _restore(entry);
                                }
                              },
                              itemBuilder: (_) => [
                                if (widget.saveMode)
                                  const PopupMenuItem(
                                      value: 'save', child: Text('Save')),
                                if (widget.recycleMode || widget.privateMode)
                                  const PopupMenuItem(
                                      value: 'restore',
                                      child: Text('Restore / Unhide')),
                                const PopupMenuItem(
                                    value: 'share', child: Text('Share')),
                                const PopupMenuItem(
                                    value: 'rename', child: Text('Rename')),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(widget.recycleMode
                                      ? 'Delete permanently'
                                      : 'Move to Recycle Bin'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

Future<Directory> _appDir(String name) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, name));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
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
