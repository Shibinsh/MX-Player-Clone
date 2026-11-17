import 'package:flutter/material.dart';

import '../main.dart';
import 'local_screen.dart';
import 'me_feature_screens.dart';
import 'transfer_screen.dart';

class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Me'),
        actions: const [ThemeToggleButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolsGrid(),
          const SizedBox(height: 16),
          _ListCard(items: [
            _MenuItem(Icons.download_for_offline, 'Status Saver', badge: '5'),
          ]),
          const SizedBox(height: 16),
          _ListCard(items: [
            _MenuItem(Icons.checkroom_outlined, 'App Theme'),
            _MenuItem(Icons.settings_outlined, 'Settings'),
            _MenuItem(
                Icons.picture_in_picture_alt_outlined, 'Custom Pop-up Play'),
          ]),
          const SizedBox(height: 16),
          _ListCard(items: [
            _MenuItem(Icons.balance, 'Legal'),
            _MenuItem(Icons.help_outline, 'Help'),
          ]),
        ],
      ),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      _MenuItem(Icons.file_download_outlined, 'Downloads'),
      _MenuItem(Icons.mobile_screen_share, 'File Transfer'),
      _MenuItem(Icons.folder_special_outlined, 'Private Folder'),
      _MenuItem(Icons.playlist_add, 'Video Playlists'),
      _MenuItem(Icons.folder_copy_outlined, 'Media Manager'),
      _MenuItem(Icons.desktop_windows_outlined, 'Local Network', badge: 'NEW'),
      _MenuItem(Icons.public, 'Network Stream'),
      _MenuItem(Icons.cloud_queue, 'Cloud Drive'),
      _MenuItem(Icons.delete_outline, 'Recycle Bin'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8)),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3, mainAxisExtent: 88),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: () => _openMeDetail(context, item),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(item.icon, color: const Color(0xFF2D95E5), size: 30),
                    if (item.badge != null)
                      Positioned(
                          right: -24,
                          top: -2,
                          child: _Badge(text: item.badge!)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(item.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.items});
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              dense: true,
              leading: Icon(item.icon,
                  color: item.title == 'Status Saver'
                      ? const Color(0xFF20D66B)
                      : const Color(0xFF536071)),
              title: Text(item.title, style: const TextStyle(fontSize: 17)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.badge != null) _Badge(text: item.badge!),
                  const SizedBox(width: 10),
                  const Icon(Icons.chevron_right, color: Color(0xFF9AA6B5)),
                ],
              ),
              onTap: () => _openMeDetail(context, item),
            ),
        ],
      ),
    );
  }
}

void _openMeDetail(BuildContext context, _MenuItem item) {
  final Widget screen = switch (item.title) {
    'Downloads' => const DownloadsScreen(),
    'File Transfer' => const TransferScreen(),
    'Private Folder' => const PrivateFolderScreen(),
    'Video Playlists' => const VideoPlaylistsScreen(),
    'Media Manager' => LocalScreen(onTabRequested: (_) {}),
    'Local Network' => const LocalNetworkScreen(),
    'Network Stream' => const NetworkStreamScreen(),
    'Cloud Drive' => const CloudDriveScreen(),
    'Recycle Bin' => const RecycleBinScreen(),
    'Status Saver' => const StatusSaverScreen(),
    'App Theme' => const AppThemeScreen(),
    'Settings' => const AppSettingsScreen(),
    'Custom Pop-up Play' => const PopupPlayScreen(),
    'Legal' => const LegalScreen(),
    'Help' => const HelpScreen(),
    _ => const HelpScreen(),
  };
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
          color: const Color(0xFFFF2D63),
          borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.icon, this.title, {this.badge});
  final IconData icon;
  final String title;
  final String? badge;
}
