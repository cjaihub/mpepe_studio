import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/settings_provider.dart';

class ThemeNotifier extends Notifier<ThemeMode> {
  static const _themePrefKeyStr = 'theme_mode_pref_str';

  @override
  ThemeMode build() {
    _loadTheme();
    // The account's choice (user_settings/{uid}.appearance.themeMode) wins
    // over this device's cached one, so the theme follows the account.
    ref.listen<String?>(
      settingsProvider.select((s) => (s.value?['appearance'] as Map?)?['themeMode'] as String?),
      (_, mode) {
        if (mode == null) return;
        final next = _parse(mode);
        if (next == state) return;
        state = next;
        _cache(next);
      },
    );
    return ThemeMode.system; // Default until loaded
  }

  static ThemeMode _parse(String mode) => switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> _cache(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKeyStr, mode.name);
  }

  Future<void> _save(ThemeMode mode) async {
    await _cache(mode);
    await ref.read(settingsProvider.notifier).updateSetting('appearance', 'themeMode', mode.name);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    
    // First check the new string key
    final modeStr = prefs.getString(_themePrefKeyStr);
    if (modeStr != null) {
      if (modeStr == 'light') {
        state = ThemeMode.light;
      } else if (modeStr == 'dark') {
        state = ThemeMode.dark;
      } else {
        state = ThemeMode.system;
      }
      return;
    }
    
    // Fallback to legacy bool key if it exists
    final isDark = prefs.getBool('theme_mode_pref');
    if (isDark != null) {
      state = isDark ? ThemeMode.dark : ThemeMode.light;
      return;
    }
    
    // Default to system
    state = ThemeMode.system; 
  }

  Future<void> toggleTheme() async {
    // If it's system, toggle to the opposite of what's currently being shown, 
    // or just toggle between light and dark
    final newMode = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    state = newMode;
    await _save(newMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _save(mode);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(() {
  return ThemeNotifier();
});
