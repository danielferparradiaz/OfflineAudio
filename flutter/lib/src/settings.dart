import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App appearance settings (theme mode, accent "button" color and background),
/// persisted with `shared_preferences`. Mirrors the Angular bubble theme panel:
/// primary color + surface color + light/dark.
class SettingsController extends ChangeNotifier {
  static const _kThemeMode = 'settings.theme_mode';
  static const _kAccent = 'settings.accent_color';
  static const _kBackground = 'settings.background_color';

  ThemeMode _themeMode = ThemeMode.system;
  int _accent = 0xFF1DB954;
  int? _background;

  ThemeMode get themeMode => _themeMode;
  int get accent => _accent;

  /// Surface/background override; null means "use the theme default".
  int? get background => _background;

  bool get hasCustomBackground => _background != null;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString(_kThemeMode);
      _themeMode = switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      _accent = prefs.getInt(_kAccent) ?? 0xFF1DB954;
      _background = prefs.getInt(_kBackground);
    } catch (_) {
      // Keep defaults; never let persistence break startup.
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _persistKey(_kThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
    notifyListeners();
  }

  void setAccent(int color) {
    _accent = color;
    _persistKey(_kAccent, color);
    notifyListeners();
  }

  void setBackground(int? color) {
    _background = color;
    if (color == null) {
      _persistRemove(_kBackground);
    } else {
      _persistKey(_kBackground, color);
    }
    notifyListeners();
  }

  void _persistKey(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) {
      await prefs.setInt(key, value);
    } else {
      await prefs.setString(key, value.toString());
    }
  }

  void _persistRemove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

/// Provides the shared [SettingsController] and rebuilds dependents when the
/// appearance changes.
class SettingsScope extends InheritedNotifier<SettingsController> {
  const SettingsScope({super.key, required super.notifier, required super.child});

  static SettingsController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SettingsScope>();
    assert(scope != null, 'No SettingsScope found in context');
    return scope!.notifier!;
  }
}