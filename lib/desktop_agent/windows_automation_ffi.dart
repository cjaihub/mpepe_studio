import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

base class WinPoint extends Struct {
  @Int32()
  external int x;

  @Int32()
  external int y;
}

typedef SetCursorPosC = Int32 Function(Int32 x, Int32 y);
typedef SetCursorPosDart = int Function(int x, int y);

typedef GetCursorPosC = Int32 Function(Pointer<WinPoint> lpPoint);
typedef GetCursorPosDart = int Function(Pointer<WinPoint> lpPoint);

typedef MouseEventC = Void Function(
    Uint32 dwFlags, Uint32 dx, Uint32 dy, Uint32 dwData, IntPtr dwExtraInfo);
typedef MouseEventDart = void Function(
    int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);

typedef KeybdEventC = Void Function(
    Uint8 bVk, Uint8 bScan, Uint32 dwFlags, IntPtr dwExtraInfo);
typedef KeybdEventDart = void Function(
    int bVk, int bScan, int dwFlags, int dwExtraInfo);

typedef GetSystemMetricsC = Int32 Function(Int32 nIndex);
typedef GetSystemMetricsDart = int Function(int nIndex);

typedef GetForegroundWindowC = IntPtr Function();
typedef GetForegroundWindowDart = int Function();

typedef GetWindowTextWC = Int32 Function(
    IntPtr hWnd, Pointer<Utf16> lpString, Int32 nMaxCount);
typedef GetWindowTextWDart = int Function(
    int hWnd, Pointer<Utf16> lpString, int nMaxCount);

const int _mouseEventMove = 0x0001;
const int _mouseEventLeftDown = 0x0002;
const int _mouseEventLeftUp = 0x0004;
const int _mouseEventRightDown = 0x0008;
const int _mouseEventRightUp = 0x0010;
const int _mouseEventWheel = 0x0800;
const int _mouseEventHWheel = 0x1000;
const int _keyEventKeyUp = 0x0002;

/// Win32 FFI + PowerShell UI Automation controller giving Windows 1:1 parity
/// with macOS mouse, keyboard, window discovery, screen capture, and clipboard.
class WindowsDesktopController {
  WindowsDesktopController._();

  static DynamicLibrary? _user32;
  static DynamicLibrary get _u32 =>
      _user32 ??= DynamicLibrary.open('user32.dll');

  static bool _leftButtonDown = false;
  static bool get isLeftButtonDown => _leftButtonDown;

  static bool get isSupported => Platform.isWindows;

  static ({double x, double y}) getCursorPosition() {
    if (!isSupported) return (x: 0, y: 0);
    final fn = _u32.lookupFunction<GetCursorPosC, GetCursorPosDart>('GetCursorPos');
    final ptr = calloc<WinPoint>();
    try {
      fn(ptr);
      return (x: ptr.ref.x.toDouble(), y: ptr.ref.y.toDouble());
    } finally {
      calloc.free(ptr);
    }
  }

  static ({int width, int height}) getMainDisplayBounds() {
    if (!isSupported) return (width: 1920, height: 1080);
    final fn = _u32
        .lookupFunction<GetSystemMetricsC, GetSystemMetricsDart>('GetSystemMetrics');
    final w = fn(0); // SM_CXSCREEN
    final h = fn(1); // SM_CYSCREEN
    return (width: w > 0 ? w : 1920, height: h > 0 ? h : 1080);
  }

  static Future<String?> getActiveAppName() async {
    if (!isSupported) return null;
    try {
      final fgFn = _u32.lookupFunction<GetForegroundWindowC, GetForegroundWindowDart>(
          'GetForegroundWindow');
      final textFn = _u32
          .lookupFunction<GetWindowTextWC, GetWindowTextWDart>('GetWindowTextW');
      final hwnd = fgFn();
      if (hwnd == 0) return 'Desktop';
      final buf = calloc<Uint16>(256).cast<Utf16>();
      try {
        final len = textFn(hwnd, buf, 256);
        if (len <= 0) return 'Desktop';
        return buf.toDartString(length: len).trim();
      } finally {
        calloc.free(buf);
      }
    } catch (_) {
      return null;
    }
  }

  static void moveTo(double x, double y) {
    if (!isSupported) return;
    final fn = _u32.lookupFunction<SetCursorPosC, SetCursorPosDart>('SetCursorPos');
    fn(x.round(), y.round());
  }

  static Future<void> clickAt(double x, double y, {bool right = false, bool doubleClick = false}) async {
    if (!isSupported) return;
    moveTo(x, y);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (doubleClick) {
      await clickCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await clickCurrent();
      return;
    }
    if (right) {
      await rightClickCurrent();
      return;
    }
    await clickCurrent();
  }

  static Future<void> clickCurrent() async {
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    me(_mouseEventLeftDown, 0, 0, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    me(_mouseEventLeftUp, 0, 0, 0, 0);
  }

  static Future<void> doubleClickCurrent() async {
    await clickCurrent();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await clickCurrent();
  }

  static Future<void> rightClickCurrent() async {
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    me(_mouseEventRightDown, 0, 0, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    me(_mouseEventRightUp, 0, 0, 0, 0);
  }

  static void moveBy(double dx, double dy) {
    final cur = getCursorPosition();
    moveTo(cur.x + dx, cur.y + dy);
  }

  static Future<void> tapKey(String key) async => sendHotkey(key);

  static Future<void> doubleClick(double x, double y) async {
    await clickAt(x, y);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await clickAt(x, y);
  }

  static Future<void> rightClick(double x, double y) async {
    if (!isSupported) return;
    moveTo(x, y);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    me(_mouseEventRightDown, 0, 0, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 22));
    me(_mouseEventRightUp, 0, 0, 0, 0);
  }

  static Future<void> dragTo(double sx, double sy, double ex, double ey) async {
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    moveTo(sx, sy);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    me(_mouseEventLeftDown, 0, 0, 0, 0);
    const steps = 14;
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      moveTo(sx + (ex - sx) * t, sy + (ey - sy) * t);
      await Future<void>.delayed(const Duration(milliseconds: 14));
    }
    me(_mouseEventLeftUp, 0, 0, 0, 0);
  }

  static void leftClickDown() {
    if (!isSupported) return;
    _leftButtonDown = true;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    me(_mouseEventLeftDown, 0, 0, 0, 0);
  }

  static void leftClickUp() {
    _leftButtonDown = false;
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    me(_mouseEventLeftUp, 0, 0, 0, 0);
  }

  static void scroll(int dy) {
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    // Win32 WHEEL_DELTA is 120 units per notch
    me(_mouseEventWheel, 0, 0, dy * 30, 0);
  }

  static void scrollPixels(double dx, double dy) {
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    if (dy.round() != 0) {
      me(_mouseEventWheel, 0, 0, (dy * 4).round(), 0);
    }
    if (dx.round() != 0) {
      me(_mouseEventHWheel, 0, 0, (dx * 4).round(), 0);
    }
  }

  static Future<void> mediaKey(String key) async {
    if (!isSupported) return;
    final vk = switch (key) {
      'play' || 'play_pause' => 0xB3, // VK_MEDIA_PLAY_PAUSE
      'next' => 0xB0, // VK_MEDIA_NEXT_TRACK
      'prev' || 'previous' => 0xB1, // VK_MEDIA_PREV_TRACK
      'mute' => 0xAD, // VK_VOLUME_MUTE
      'vol_down' || 'volume_down' => 0xAE, // VK_VOLUME_DOWN
      'vol_up' || 'volume_up' => 0xAF, // VK_VOLUME_UP
      _ => null,
    };
    if (vk == null) return;
    final ke = _u32.lookupFunction<KeybdEventC, KeybdEventDart>('keybd_event');
    ke(vk, 0, 0, 0);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    ke(vk, 0, _keyEventKeyUp, 0);
  }

  static Future<void> wakeDisplay() async {
    if (!isSupported) return;
    final me = _u32.lookupFunction<MouseEventC, MouseEventDart>('mouse_event');
    me(_mouseEventMove, 0, 0, 0, 0);
  }

  static Future<bool> isScreenLocked() async {
    if (!isSupported) return false;
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r"if (Get-Process -Name LogonUI -ErrorAction SilentlyContinue) { '1' } else { '0' }",
      ]);
      return res.stdout.toString().trim() == '1';
    } catch (_) {
      return false;
    }
  }

  static int? _vkForName(String token) {
    final k = token.trim().toLowerCase();
    return switch (k) {
      'ctrl' || 'control' || 'cmd' || 'command' || 'meta' => 0x11, // VK_CONTROL
      'win' || 'super' => 0x5B, // VK_LWIN
      'alt' || 'option' || 'opt' => 0x12, // VK_MENU
      'shift' => 0x10, // VK_SHIFT
      'enter' || 'return' => 0x0D,
      'space' => 0x20,
      'tab' => 0x09,
      'esc' || 'escape' => 0x1B,
      'backspace' || 'delete' => 0x08,
      'del' || 'forwarddelete' => 0x2E,
      'up' => 0x26,
      'down' => 0x28,
      'left' => 0x25,
      'right' => 0x27,
      'f1' => 0x70,
      'f2' => 0x71,
      'f3' => 0x72,
      'f4' => 0x73,
      'f5' => 0x74,
      'f6' => 0x75,
      'f7' => 0x76,
      'f8' => 0x77,
      'f9' => 0x78,
      'f10' => 0x79,
      'f11' => 0x7A,
      'f12' => 0x7B,
      _ => k.length == 1 ? k.toUpperCase().codeUnitAt(0) : null,
    };
  }

  static Future<void> sendHotkey(String combo) async {
    if (!isSupported || combo.trim().isEmpty) return;
    final parts = combo
        .split('+')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    final vks = <int>[];
    for (final p in parts) {
      final vk = _vkForName(p);
      if (vk != null) vks.add(vk);
    }
    if (vks.isEmpty) return;

    final ke = _u32.lookupFunction<KeybdEventC, KeybdEventDart>('keybd_event');
    for (final vk in vks) {
      ke(vk, 0, 0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (final vk in vks.reversed) {
      ke(vk, 0, _keyEventKeyUp, 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  static Future<void> writeClipboard(String text) async {
    if (!isSupported) return;
    final encoded = base64Encode(utf8.encode(text));
    await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r"$s = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" +
          encoded +
          r"')); Set-Clipboard -Value $s",
    ]);
  }

  static Future<String> readClipboard() async {
    if (!isSupported) return '';
    final res = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      'Get-Clipboard -Raw',
    ]);
    return res.stdout.toString();
  }

  static Future<void> pasteTextInstant(String text, {bool pressEnter = false}) async {
    if (!isSupported) return;
    await writeClipboard(text);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await sendHotkey('ctrl+v');
    if (pressEnter) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await sendHotkey('enter');
    }
  }

  static Future<void> typeString(String text) async => pasteTextInstant(text);

  static Future<String> listOpenWindows() async {
    if (!isSupported) return '';
    final res = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r"Get-Process | Where-Object { $_.MainWindowTitle -ne '' } | Select-Object ProcessName, MainWindowTitle | Format-Table -AutoSize | Out-String",
    ]);
    return res.stdout.toString().trim();
  }

  static Future<bool> captureScreenToFile(String path) async {
    if (!isSupported) return false;
    final safePath = path.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
\$bmp = New-Object System.Drawing.Bitmap(\$bounds.Width, \$bounds.Height)
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)
\$bmp.Save('$safePath', [System.Drawing.Imaging.ImageFormat]::Png)
\$g.Dispose()
\$bmp.Dispose()
''';
    final res = await Process.run('powershell', ['-NoProfile', '-Command', script]);
    return res.exitCode == 0;
  }
}
