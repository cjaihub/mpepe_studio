import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends Notifier<ThemeMode> {
  static const _themePrefKeyStr = 'theme_mode_pref_str';

  @override
  ThemeMode build() {
    _loadTheme();
    return ThemeMode.system; // Default until loaded
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
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKeyStr, newMode.name);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePrefKeyStr, mode.name);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(() {
  return ThemeNotifier();
});
