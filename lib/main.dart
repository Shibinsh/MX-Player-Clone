import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'screens/home_screen.dart';
import 'services/settings_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Route video_player through the FFmpeg/libmpv-based backend for clean,
  // hardware-accelerated rendering across all formats (fixes banding/artifacts
  // seen with the default ExoPlayer texture path on some Android GPUs).
  fvp.registerWith(options: {
    'video.decoders': ['AMediaCodec', 'FFmpeg'],
  });
  unawaited(_clearStartupCaches());
  unawaited(AppSettings.instance.load());
  runApp(const MxPlayerCloneApp());
}

Future<void> _clearStartupCaches() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final marker = File(p.join(docs.path, 'cache_cleanup_2026_05_22.flag'));
    if (await marker.exists()) return;

    for (final name in [
      'video_folders_cache.json',
      'audio_cache.json',
      'local_video_folders_cache.json',
    ]) {
      final file = File(p.join(docs.path, name));
      if (await file.exists()) await file.delete();
    }

    final temp = await getTemporaryDirectory();
    final thumbnails = Directory(p.join(temp.path, 'video_thumbnails'));
    if (await thumbnails.exists()) {
      await thumbnails.delete(recursive: true);
    }
    await marker.writeAsString(DateTime.now().toIso8601String());
  } catch (_) {
    // Cache cleanup must never block app startup.
  }
}

class MxPlayerCloneApp extends StatefulWidget {
  const MxPlayerCloneApp({super.key});

  @override
  State<MxPlayerCloneApp> createState() => _MxPlayerCloneAppState();
}

class _MxPlayerCloneAppState extends State<MxPlayerCloneApp> {
  final AppSettings _settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() => setState(() {});

  void _toggleTheme() {
    _settings.setThemeVariant(
      _settings.themeMode == ThemeMode.dark
          ? AppThemeVariant.light
          : AppThemeVariant.dark,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: _settings,
      child: AppThemeController(
        themeMode: _settings.themeMode,
        onToggleTheme: _toggleTheme,
        child: MaterialApp(
          title: 'MX Player Clone',
          debugShowCheckedModeBanner: false,
          themeMode: _settings.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const HomeScreen(),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final amoled = dark && _settings.isAmoled;
    final accent = _settings.accent;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      surface: amoled
          ? Colors.black
          : dark
              ? const Color(0xFF121418)
              : Colors.white,
    );
    final appBarBackground = dark
        ? (amoled ? Colors.black : const Color(0xFF181B20))
        : colorScheme.primary;
    final appBarForeground =
        dark ? const Color(0xFFFFD7E3) : colorScheme.onPrimary;
    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: appBarBackground,
        foregroundColor: appBarForeground,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: appBarBackground,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.light,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        titleTextStyle: TextStyle(
          color: appBarForeground,
          fontSize: 23,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardTheme(
        color: dark
            ? (amoled ? const Color(0xFF0A0A0A) : const Color(0xFF1B1E24))
            : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark
            ? (amoled ? Colors.black : const Color(0xFF181B20))
            : colorScheme.surface,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color:
                selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          );
        }),
      ),
      useMaterial3: true,
    );
  }
}

class AppThemeController extends InheritedWidget {
  const AppThemeController({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
    required super.child,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  static AppThemeController of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppThemeController>()!;
  }

  @override
  bool updateShouldNotify(AppThemeController oldWidget) {
    return oldWidget.themeMode != themeMode;
  }
}

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppThemeController.of(context);
    final dark = controller.themeMode == ThemeMode.dark;
    return IconButton(
      tooltip: dark ? 'Light mode' : 'Dark mode',
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
      onPressed: controller.onToggleTheme,
    );
  }
}
