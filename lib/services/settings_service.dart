import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme variants supported by the app.
enum AppThemeVariant { light, dark, amoled }

/// Selectable brand accent colors.
class AccentOption {
  const AccentOption(this.name, this.color);
  final String name;
  final Color color;
}

const List<AccentOption> kAccentOptions = [
  AccentOption('MX Pink', Color(0xFFFF005B)),
  AccentOption('Ocean Blue', Color(0xFF2D95E5)),
  AccentOption('Emerald', Color(0xFF1DB954)),
  AccentOption('Violet', Color(0xFF7C4DFF)),
  AccentOption('Amber', Color(0xFFFFA000)),
  AccentOption('Crimson', Color(0xFFE53935)),
];

/// Central, persistent application settings. Loaded once at startup and exposed
/// through an [InheritedNotifier] so any screen can read/update it reactively.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;

  // Theme
  AppThemeVariant _themeVariant = AppThemeVariant.light;
  int _accentValue = kAccentOptions.first.color.toARGB32();

  // Player
  double _defaultSpeed = 1.0;
  bool _resumePlayback = true;
  bool _autoPlayNext = true;
  String _resizeMode = 'fit'; // fit | fill | crop

  // Subtitles
  bool _subtitlesEnabled = true;
  double _subtitleFontSize = 18;

  // Transfer
  bool _transferConfirmReceive = true;

  // Privacy
  bool _useFingerprint = false;

  // Notifications
  bool _notifyTransfers = true;

  // Storage
  int _recycleBinRetentionDays = 30;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _themeVariant =
        AppThemeVariant.values[prefs.getInt('themeVariant') ?? 0];
    _accentValue = prefs.getInt('accentValue') ?? _accentValue;
    _defaultSpeed = prefs.getDouble('defaultSpeed') ?? 1.0;
    _resumePlayback = prefs.getBool('resumePlayback') ?? true;
    _autoPlayNext = prefs.getBool('autoPlayNext') ?? true;
    _resizeMode = prefs.getString('resizeMode') ?? 'fit';
    _subtitlesEnabled = prefs.getBool('subtitlesEnabled') ?? true;
    _subtitleFontSize = prefs.getDouble('subtitleFontSize') ?? 18;
    _transferConfirmReceive = prefs.getBool('transferConfirmReceive') ?? true;
    _useFingerprint = prefs.getBool('useFingerprint') ?? false;
    _notifyTransfers = prefs.getBool('notifyTransfers') ?? true;
    _recycleBinRetentionDays = prefs.getInt('recycleBinRetentionDays') ?? 30;
    notifyListeners();
  }

  // --- Theme getters ---
  AppThemeVariant get themeVariant => _themeVariant;
  ThemeMode get themeMode =>
      _themeVariant == AppThemeVariant.light ? ThemeMode.light : ThemeMode.dark;
  bool get isAmoled => _themeVariant == AppThemeVariant.amoled;
  Color get accent => Color(_accentValue);

  // --- Player getters ---
  double get defaultSpeed => _defaultSpeed;
  bool get resumePlayback => _resumePlayback;
  bool get autoPlayNext => _autoPlayNext;
  String get resizeMode => _resizeMode;

  // --- Subtitle getters ---
  bool get subtitlesEnabled => _subtitlesEnabled;
  double get subtitleFontSize => _subtitleFontSize;

  // --- Transfer / privacy / notification getters ---
  bool get transferConfirmReceive => _transferConfirmReceive;
  bool get useFingerprint => _useFingerprint;
  bool get notifyTransfers => _notifyTransfers;
  int get recycleBinRetentionDays => _recycleBinRetentionDays;

  // --- Setters (persist + notify) ---
  Future<void> setThemeVariant(AppThemeVariant value) async {
    _themeVariant = value;
    await _prefs?.setInt('themeVariant', value.index);
    notifyListeners();
  }

  Future<void> setAccent(Color color) async {
    _accentValue = color.toARGB32();
    await _prefs?.setInt('accentValue', _accentValue);
    notifyListeners();
  }

  Future<void> setDefaultSpeed(double value) async {
    _defaultSpeed = value;
    await _prefs?.setDouble('defaultSpeed', value);
    notifyListeners();
  }

  Future<void> setResumePlayback(bool value) async {
    _resumePlayback = value;
    await _prefs?.setBool('resumePlayback', value);
    notifyListeners();
  }

  Future<void> setAutoPlayNext(bool value) async {
    _autoPlayNext = value;
    await _prefs?.setBool('autoPlayNext', value);
    notifyListeners();
  }

  Future<void> setResizeMode(String value) async {
    _resizeMode = value;
    await _prefs?.setString('resizeMode', value);
    notifyListeners();
  }

  Future<void> setSubtitlesEnabled(bool value) async {
    _subtitlesEnabled = value;
    await _prefs?.setBool('subtitlesEnabled', value);
    notifyListeners();
  }

  Future<void> setSubtitleFontSize(double value) async {
    _subtitleFontSize = value;
    await _prefs?.setDouble('subtitleFontSize', value);
    notifyListeners();
  }

  Future<void> setTransferConfirmReceive(bool value) async {
    _transferConfirmReceive = value;
    await _prefs?.setBool('transferConfirmReceive', value);
    notifyListeners();
  }

  Future<void> setUseFingerprint(bool value) async {
    _useFingerprint = value;
    await _prefs?.setBool('useFingerprint', value);
    notifyListeners();
  }

  Future<void> setNotifyTransfers(bool value) async {
    _notifyTransfers = value;
    await _prefs?.setBool('notifyTransfers', value);
    notifyListeners();
  }

  Future<void> setRecycleBinRetentionDays(int value) async {
    _recycleBinRetentionDays = value;
    await _prefs?.setInt('recycleBinRetentionDays', value);
    notifyListeners();
  }
}

/// Exposes [AppSettings] down the widget tree and rebuilds dependents on change.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    return scope?.notifier ?? AppSettings.instance;
  }
}
