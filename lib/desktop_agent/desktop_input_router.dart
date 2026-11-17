import 'dart:async';
import 'dart:io';

import 'macos_mouse_ffi.dart';
import 'windows_automation_ffi.dart';

/// Unified desktop OS automation interface routing identically across macOS and Windows.
class DesktopInputRouter {
  DesktopInputRouter._();

  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  static ({double x, double y}) getCursorPosition() {
    if (Platform.isMacOS) return MacOSMouseController.getCursorPosition();
    if (Platform.isWindows) return WindowsDesktopController.getCursorPosition();
    return (x: 0, y: 0);
  }

  static ({int width, int height}) getMainDisplayBounds() {
    if (Platform.isMacOS) {
      final b = MacOSMouseController.getMainDisplayBounds();
      return (width: b.width.toInt(), height: b.height.toInt());
    }
    if (Platform.isWindows) return WindowsDesktopController.getMainDisplayBounds();
    return (width: 1920, height: 1080);
  }

  static Future<String?> getActiveAppName() async {
    if (Platform.isMacOS) return MacOSMouseController.getActiveAppName();
    if (Platform.isWindows) return WindowsDesktopController.getActiveAppName();
    return 'Desktop';
  }

  static void moveTo(double x, double y) {
    if (Platform.isMacOS) MacOSMouseController.moveTo(x, y);
    if (Platform.isWindows) WindowsDesktopController.moveTo(x, y);
  }

  static void moveBy(double dx, double dy) {
    if (Platform.isMacOS) MacOSMouseController.moveBy(dx, dy);
    if (Platform.isWindows) WindowsDesktopController.moveBy(dx, dy);
  }

  static Future<void> clickAt(double x, double y, {bool right = false, bool doubleClick = false}) async {
    if (Platform.isMacOS) {
      MacOSMouseController.clickAt(x, y, right: right, doubleClick: doubleClick);
      return;
    }
    if (Platform.isWindows) {
      await WindowsDesktopController.clickAt(x, y, right: right, doubleClick: doubleClick);
    }
  }

  static Future<void> clickCurrent() async {
    if (Platform.isMacOS) {
      MacOSMouseController.click();
    } else if (Platform.isWindows) {
      await WindowsDesktopController.clickCurrent();
    }
  }

  static Future<void> doubleClickCurrent() async {
    if (Platform.isMacOS) {
      MacOSMouseController.doubleClick();
    } else if (Platform.isWindows) {
      await WindowsDesktopController.doubleClickCurrent();
    }
  }

  static Future<void> rightClickCurrent() async {
    if (Platform.isMacOS) {
      MacOSMouseController.rightClick();
    } else if (Platform.isWindows) {
      await WindowsDesktopController.rightClickCurrent();
    }
  }

  static Future<void> dragTo(double x, double y) async {
    if (Platform.isMacOS) {
      await MacOSMouseController.dragTo(x, y);
    } else if (Platform.isWindows) {
      final cur = WindowsDesktopController.getCursorPosition();
      await WindowsDesktopController.dragTo(cur.x, cur.y, x, y);
    }
  }

  static bool get isLeftButtonDown {
    if (Platform.isMacOS) return MacOSMouseController.isLeftButtonDown;
    if (Platform.isWindows) return WindowsDesktopController.isLeftButtonDown;
    return false;
  }

  static void leftClickDown() {
    if (Platform.isMacOS) MacOSMouseController.leftClickDown();
    if (Platform.isWindows) WindowsDesktopController.leftClickDown();
  }

  static void leftClickUp() {
    if (Platform.isMacOS) MacOSMouseController.leftClickUp();
    if (Platform.isWindows) WindowsDesktopController.leftClickUp();
  }

  static void scroll(double dy) {
    if (Platform.isMacOS) {
      MacOSMouseController.scroll(dy);
    } else if (Platform.isWindows) {
      WindowsDesktopController.scroll(dy.round());
    }
  }

  static void scrollPixels(double dx, double dy) {
    if (Platform.isMacOS) {
      MacOSMouseController.scrollPixels(dx, dy);
    } else if (Platform.isWindows) {
      WindowsDesktopController.scrollPixels(dx, dy);
    }
  }

  static Future<bool> isScreenLocked() async {
    if (Platform.isMacOS) return MacOSMouseController.isScreenLocked();
    if (Platform.isWindows) return WindowsDesktopController.isScreenLocked();
    return false;
  }

  static Future<void> wakeDisplay() async {
    if (Platform.isMacOS) return MacOSMouseController.wakeDisplay();
    if (Platform.isWindows) return WindowsDesktopController.wakeDisplay();
  }

  static Future<void> mediaKey(String key) async {
    if (Platform.isMacOS) return MacOSMouseController.mediaKey(key);
    if (Platform.isWindows) return WindowsDesktopController.mediaKey(key);
  }

  static Future<({int level, bool muted})?> getVolume() async {
    if (Platform.isMacOS) return MacOSMouseController.getVolume();
    return null;
  }

  static Future<void> setVolume(int level) async {
    if (Platform.isMacOS) return MacOSMouseController.setVolume(level);
  }

  static Future<void> setMuted(bool muted) async {
    if (Platform.isMacOS) return MacOSMouseController.setMuted(muted);
  }

  static Future<bool> unlockWithPassword(String password) async {
    if (Platform.isMacOS) return MacOSMouseController.unlockWithPassword(password);
    return false;
  }

  static Future<void> wakeAndUnlock(String passkey) async {
    if (Platform.isMacOS) return MacOSMouseController.wakeAndUnlock(passkey);
    if (Platform.isWindows) return WindowsDesktopController.wakeDisplay();
  }

  static Future<void> sendHotkey(String combo) async {
    if (Platform.isMacOS) {
      await MacOSMouseController.sendHotkey(combo);
    } else if (Platform.isWindows) {
      await WindowsDesktopController.sendHotkey(combo);
    }
  }

  static Future<void> tapKey(String key) async {
    if (Platform.isMacOS) {
      await MacOSMouseController.tapKey(key);
    } else if (Platform.isWindows) {
      await WindowsDesktopController.tapKey(key);
    }
  }

  static Future<void> typeString(String text) async {
    if (Platform.isMacOS) {
      await MacOSMouseController.typeString(text);
    } else if (Platform.isWindows) {
      await WindowsDesktopController.typeString(text);
    }
  }

  static Future<void> pasteTextInstant(String text, {bool pressEnter = false}) async {
    if (Platform.isMacOS) {
      await MacOSMouseController.pasteTextInstant(text, pressEnter: pressEnter);
    } else if (Platform.isWindows) {
      await WindowsDesktopController.pasteTextInstant(text, pressEnter: pressEnter);
    }
  }

  static Future<bool> writeClipboard(String text) async {
    if (Platform.isMacOS) return MacOSMouseController.writeClipboard(text);
    if (Platform.isWindows) {
      await WindowsDesktopController.writeClipboard(text);
      return true;
    }
    return false;
  }

  static Future<String> readClipboard() async {
    if (Platform.isMacOS) return MacOSMouseController.readClipboard();
    if (Platform.isWindows) return WindowsDesktopController.readClipboard();
    return '';
  }
}
