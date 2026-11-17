import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ─── C Types & Structs ────────────────────────────────────────────────────────
final DynamicLibrary _coreGraphics = Platform.isMacOS
    ? DynamicLibrary.open('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
    : DynamicLibrary.process();

base class CGPoint extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

base class CGSize extends Struct {
  @Double()
  external double width;

  @Double()
  external double height;
}

base class CGRect extends Struct {
  external CGPoint origin;
  external CGSize size;
}

// ─── Constants ──────────────────────────────────────────────────────────────
const int kCGEventLeftMouseDown = 1;
const int kCGEventLeftMouseUp = 2;
const int kCGEventRightMouseDown = 3;
const int kCGEventRightMouseUp = 4;
const int kCGEventMouseMoved = 5;
const int kCGEventLeftMouseDragged = 6;
const int kCGEventRightMouseDragged = 7;
const int kCGEventScrollWheel = 22;

const int kCGMouseButtonLeft = 0;
const int kCGMouseButtonRight = 1;
const int kCGMouseButtonCenter = 2;

const int kCGSessionEventTap = 1;
const int kCGHIDEventTap = 0;

// ─── Function Signatures ────────────────────────────────────────────────────

typedef CGEventCreateMouseEventC = Pointer Function(
    Pointer source, Uint32 mouseType, CGPoint mouseCursorPosition, Uint32 mouseButton);
typedef CGEventCreateMouseEventDart = Pointer Function(
    Pointer source, int mouseType, CGPoint mouseCursorPosition, int mouseButton);

typedef CGEventCreateScrollWheelEventC = Pointer Function(
    Pointer source, Uint32 units, Uint32 wheelCount, Int32 wheel1);
typedef CGEventCreateScrollWheelEventDart = Pointer Function(
    Pointer source, int units, int wheelCount, int wheel1);

typedef CGEventPostC = Void Function(Uint32 tap, Pointer event);
typedef CGEventPostDart = void Function(int tap, Pointer event);

typedef CGEventGetLocationC = CGPoint Function(Pointer event);
typedef CGEventGetLocationDart = CGPoint Function(Pointer event);

typedef CGEventCreateC = Pointer Function(Pointer source);
typedef CGEventCreateDart = Pointer Function(Pointer source);

typedef CGMainDisplayIDC = Uint32 Function();
typedef CGMainDisplayIDDart = int Function();

typedef CGDisplayPixelsC = IntPtr Function(Uint32 display);
typedef CGDisplayPixelsDart = int Function(int display);

typedef CGGetActiveDisplayListC = Int32 Function(
    Uint32 maxDisplays, Pointer<Uint32> activeDisplays, Pointer<Uint32> displayCount);
typedef CGGetActiveDisplayListDart = int Function(
    int maxDisplays, Pointer<Uint32> activeDisplays, Pointer<Uint32> displayCount);

typedef CGDisplayBoundsC = CGRect Function(Uint32 display);
typedef CGDisplayBoundsDart = CGRect Function(int display);

typedef CFReleaseC = Void Function(Pointer arg);
typedef CFReleaseDart = void Function(Pointer arg);

// Non-variadic scroll constructor (macOS 10.13+) so a horizontal wheel can be
// passed safely through FFI on arm64.
typedef CGEventCreateScrollWheelEvent2C = Pointer Function(
    Pointer source, Uint32 units, Uint32 wheelCount, Int32 wheel1, Int32 wheel2, Int32 wheel3);
typedef CGEventCreateScrollWheelEvent2Dart = Pointer Function(
    Pointer source, int units, int wheelCount, int wheel1, int wheel2, int wheel3);

typedef CGEventSetIntegerValueFieldC = Void Function(Pointer event, Uint32 field, Int64 value);
typedef CGEventSetIntegerValueFieldDart = void Function(Pointer event, int field, int value);

const int kCGMouseEventClickState = 1;
const int kCGScrollWheelEventIsContinuous = 88;

// NX media key codes (IOKit/hidsystem/ev_keymap.h).
const int kNXKeySoundUp = 0;
const int kNXKeySoundDown = 1;
const int kNXKeyMute = 7;
const int kNXKeyPlay = 16;
const int kNXKeyNext = 17;
const int kNXKeyPrevious = 18;

// ─── Bound Functions ────────────────────────────────────────────────────────
final CGEventCreateMouseEventDart _cgEventCreateMouseEvent = _coreGraphics
    .lookupFunction<CGEventCreateMouseEventC, CGEventCreateMouseEventDart>(
        'CGEventCreateMouseEvent');

final CGEventCreateScrollWheelEventDart _cgEventCreateScrollWheelEvent =
    _coreGraphics.lookupFunction<CGEventCreateScrollWheelEventC,
        CGEventCreateScrollWheelEventDart>('CGEventCreateScrollWheelEvent');

final CGEventPostDart _cgEventPost =
    _coreGraphics.lookupFunction<CGEventPostC, CGEventPostDart>('CGEventPost');

final CGEventGetLocationDart _cgEventGetLocation = _coreGraphics
    .lookupFunction<CGEventGetLocationC, CGEventGetLocationDart>(
        'CGEventGetLocation');

final CGEventCreateDart _cgEventCreate = _coreGraphics
    .lookupFunction<CGEventCreateC, CGEventCreateDart>('CGEventCreate');

final CGMainDisplayIDDart _cgMainDisplayID = _coreGraphics
    .lookupFunction<CGMainDisplayIDC, CGMainDisplayIDDart>('CGMainDisplayID');

final CGDisplayPixelsDart _cgDisplayPixelsWide = _coreGraphics
    .lookupFunction<CGDisplayPixelsC, CGDisplayPixelsDart>(
        'CGDisplayPixelsWide');

final CGDisplayPixelsDart _cgDisplayPixelsHigh = _coreGraphics
    .lookupFunction<CGDisplayPixelsC, CGDisplayPixelsDart>(
        'CGDisplayPixelsHigh');

final CGGetActiveDisplayListDart _cgGetActiveDisplayList = _coreGraphics
    .lookupFunction<CGGetActiveDisplayListC, CGGetActiveDisplayListDart>(
        'CGGetActiveDisplayList');

final CGDisplayBoundsDart _cgDisplayBounds = _coreGraphics
    .lookupFunction<CGDisplayBoundsC, CGDisplayBoundsDart>('CGDisplayBounds');

final DynamicLibrary _coreFoundation = Platform.isMacOS
    ? DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    : DynamicLibrary.process();

final CFReleaseDart _cfRelease =
    _coreFoundation.lookupFunction<CFReleaseC, CFReleaseDart>('CFRelease');

final CGEventCreateScrollWheelEvent2Dart _cgEventCreateScrollWheelEvent2 =
    _coreGraphics.lookupFunction<CGEventCreateScrollWheelEvent2C,
        CGEventCreateScrollWheelEvent2Dart>('CGEventCreateScrollWheelEvent2');

final CGEventSetIntegerValueFieldDart _cgEventSetIntegerValueField = _coreGraphics
    .lookupFunction<CGEventSetIntegerValueFieldC, CGEventSetIntegerValueFieldDart>(
        'CGEventSetIntegerValueField');

// Keyboard events posted at the HID level reach the login window too, which
// AppleScript keystrokes cannot (used to type the unlock password).
typedef CGEventCreateKeyboardEventC = Pointer Function(Pointer source, Uint16 keycode, Bool keyDown);
typedef CGEventCreateKeyboardEventDart = Pointer Function(Pointer source, int keycode, bool keyDown);
typedef CGEventKeyboardSetUnicodeStringC = Void Function(Pointer event, UnsignedLong length, Pointer<Uint16> chars);
typedef CGEventKeyboardSetUnicodeStringDart = void Function(Pointer event, int length, Pointer<Uint16> chars);

final CGEventCreateKeyboardEventDart _cgEventCreateKeyboardEvent = _coreGraphics
    .lookupFunction<CGEventCreateKeyboardEventC, CGEventCreateKeyboardEventDart>(
        'CGEventCreateKeyboardEvent');
final CGEventKeyboardSetUnicodeStringDart _cgEventKeyboardSetUnicodeString = _coreGraphics
    .lookupFunction<CGEventKeyboardSetUnicodeStringC, CGEventKeyboardSetUnicodeStringDart>(
        'CGEventKeyboardSetUnicodeString');

// ─── Objective-C runtime (NSEvent system-defined media keys) ─────────────────
typedef _ObjcLookupC = Pointer Function(Pointer<Utf8> name);
typedef _ObjcLookupDart = Pointer Function(Pointer<Utf8> name);
typedef _MsgSendPtrC = Pointer Function(Pointer receiver, Pointer selector);
typedef _MsgSendPtrDart = Pointer Function(Pointer receiver, Pointer selector);
// +[NSEvent otherEventWithType:location:modifierFlags:timestamp:windowNumber:
//          context:subtype:data1:data2:]
typedef _MsgSendOtherEventC = Pointer Function(Pointer receiver, Pointer selector,
    Uint64 type, CGPoint location, Uint64 flags, Double timestamp, Int64 windowNumber,
    Pointer context, Int16 subtype, Int64 data1, Int64 data2);
typedef _MsgSendOtherEventDart = Pointer Function(Pointer receiver, Pointer selector,
    int type, CGPoint location, int flags, double timestamp, int windowNumber,
    Pointer context, int subtype, int data1, int data2);

final DynamicLibrary _objc = Platform.isMacOS
    ? DynamicLibrary.open('/usr/lib/libobjc.A.dylib')
    : DynamicLibrary.process();
final _ObjcLookupDart _objcGetClass =
    _objc.lookupFunction<_ObjcLookupC, _ObjcLookupDart>('objc_getClass');
final _ObjcLookupDart _selRegisterName =
    _objc.lookupFunction<_ObjcLookupC, _ObjcLookupDart>('sel_registerName');
final _MsgSendPtrDart _msgSendPtr =
    _objc.lookupFunction<_MsgSendPtrC, _MsgSendPtrDart>('objc_msgSend');
final _MsgSendOtherEventDart _msgSendOtherEvent =
    _objc.lookupFunction<_MsgSendOtherEventC, _MsgSendOtherEventDart>('objc_msgSend');

Pointer _objcName(String name, _ObjcLookupDart lookup) {
  final cName = name.toNativeUtf8();
  try {
    return lookup(cName);
  } finally {
    calloc.free(cName);
  }
}

// ─── Internal State ─────────────────────────────────────────────────────────
bool _isLeftButtonDown = false;
double _scrollRemainderX = 0;
double _scrollRemainderY = 0;
DateTime _lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);
double _lastClickX = -1000;
double _lastClickY = -1000;
int _clickCount = 0;
bool _lastClickRight = false;

/// Serialises `osascript` volume writes and keeps only the newest value.
bool _volumeWriteInFlight = false;
int? _pendingVolume;

// ─── Public API ─────────────────────────────────────────────────────────────
class MacOSMouseController {
  static bool get isLeftButtonDown => _isLeftButtonDown;

  static CGPoint _getCurrentMousePosition() {
    final event = _cgEventCreate(nullptr);
    if (event == nullptr) {
      final fallback = calloc<CGPoint>();
      fallback.ref.x = 0;
      fallback.ref.y = 0;
      final pt = fallback.ref;
      calloc.free(fallback);
      return pt;
    }
    final loc = _cgEventGetLocation(event);
    _cfRelease(event);
    return loc;
  }

  static ({double x, double y}) getCursorPosition() {
    if (!Platform.isMacOS) return (x: 0.0, y: 0.0);
    final pos = _getCurrentMousePosition();
    return (x: pos.x, y: pos.y);
  }

  static int selectedDisplayIndex = 0;

  static ({int width, int height}) getMainDisplayBounds() {
    if (!Platform.isMacOS) return (width: 1920, height: 1080);
    try {
      final id = _cgMainDisplayID();
      final w = _cgDisplayPixelsWide(id);
      final h = _cgDisplayPixelsHigh(id);
      if (w > 0 && h > 0) return (width: w, height: h);
    } catch (_) {}
    return (width: 1920, height: 1080);
  }

  /// Enumerates all connected macOS displays in CoreGraphics global coordinates.
  static List<({int index, int id, int x, int y, int width, int height, bool isPrimary})> getDisplays() {
    if (!Platform.isMacOS) {
      return const [
        (index: 0, id: 1, x: 0, y: 0, width: 1920, height: 1080, isPrimary: true),
      ];
    }
    try {
      const maxDisplays = 16;
      final idsPtr = calloc<Uint32>(maxDisplays);
      final countPtr = calloc<Uint32>();
      try {
        final err = _cgGetActiveDisplayList(maxDisplays, idsPtr, countPtr);
        final count = err == 0 ? countPtr.value.clamp(0, maxDisplays) : 0;
        if (count == 0) {
          final b = getMainDisplayBounds();
          return [
            (index: 0, id: _cgMainDisplayID(), x: 0, y: 0, width: b.width, height: b.height, isPrimary: true),
          ];
        }
        final mainId = _cgMainDisplayID();
        final out = <({int index, int id, int x, int y, int width, int height, bool isPrimary})>[];
        for (int i = 0; i < count; i++) {
          final did = idsPtr[i];
          final rect = _cgDisplayBounds(did);
          out.add((
            index: i,
            id: did,
            x: rect.origin.x.round(),
            y: rect.origin.y.round(),
            width: rect.size.width.round().clamp(1, 32768),
            height: rect.size.height.round().clamp(1, 32768),
            isPrimary: did == mainId,
          ));
        }
        return out;
      } finally {
        calloc.free(idsPtr);
        calloc.free(countPtr);
      }
    } catch (_) {
      final b = getMainDisplayBounds();
      return [
        (index: 0, id: 1, x: 0, y: 0, width: b.width, height: b.height, isPrimary: true),
      ];
    }
  }

  static ({int x, int y, int width, int height}) getActiveDisplayRect() {
    final list = getDisplays();
    if (list.isEmpty) return (x: 0, y: 0, width: 1920, height: 1080);
    final idx = selectedDisplayIndex.clamp(0, list.length - 1);
    final d = list[idx];
    return (x: d.x, y: d.y, width: d.width, height: d.height);
  }

  /// Union bounding box across all active macOS screens so mouse moves seamlessly across monitors.
  static ({double minX, double minY, double maxX, double maxY}) getVirtualDesktopBounds() {
    final list = getDisplays();
    if (list.isEmpty) {
      return (minX: 0, minY: 0, maxX: 1920, maxY: 1080);
    }
    double minX = list.first.x.toDouble();
    double minY = list.first.y.toDouble();
    double maxX = (list.first.x + list.first.width).toDouble();
    double maxY = (list.first.y + list.first.height).toDouble();
    for (final d in list.skip(1)) {
      if (d.x < minX) minX = d.x.toDouble();
      if (d.y < minY) minY = d.y.toDouble();
      if (d.x + d.width > maxX) maxX = (d.x + d.width).toDouble();
      if (d.y + d.height > maxY) maxY = (d.y + d.height).toDouble();
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  static void moveTo(double x, double y) {
    if (!Platform.isMacOS) return;
    final bounds = getVirtualDesktopBounds();
    final clampedX = x.clamp(bounds.minX, bounds.maxX - 1);
    final clampedY = y.clamp(bounds.minY, bounds.maxY - 1);

    final ptr = calloc<CGPoint>();
    ptr.ref.x = clampedX;
    ptr.ref.y = clampedY;
    if (_isLeftButtonDown) {
      _postMouseEvent(kCGEventLeftMouseDragged, kCGMouseButtonLeft, ptr.ref);
    } else {
      _postMouseEvent(kCGEventMouseMoved, kCGMouseButtonLeft, ptr.ref);
    }
    calloc.free(ptr);
  }

  static void moveBy(double dx, double dy) {
    if (!Platform.isMacOS) return;

    final currentPos = _getCurrentMousePosition();
    final bounds = getVirtualDesktopBounds();

    final newPosPtr = calloc<CGPoint>();
    newPosPtr.ref.x = (currentPos.x + dx).clamp(bounds.minX, bounds.maxX - 1);
    newPosPtr.ref.y = (currentPos.y + dy).clamp(bounds.minY, bounds.maxY - 1);

    if (_isLeftButtonDown) {
      _postMouseEvent(
          kCGEventLeftMouseDragged, kCGMouseButtonLeft, newPosPtr.ref);
    } else {
      _postMouseEvent(kCGEventMouseMoved, kCGMouseButtonLeft, newPosPtr.ref);
    }

    calloc.free(newPosPtr);
  }

  static void clickAt(
    double x,
    double y, {
    bool right = false,
    bool doubleClick = false,
  }) {
    if (!Platform.isMacOS) return;
    moveTo(x, y);
    if (right) {
      rightClick();
    } else if (doubleClick) {
      MacOSMouseController.doubleClick();
    } else {
      click();
    }
  }

  static Future<void> dragTo(double x, double y) async {
    if (!Platform.isMacOS) return;
    leftClickDown();
    await Future<void>.delayed(const Duration(milliseconds: 24));
    moveTo(x, y);
    await Future<void>.delayed(const Duration(milliseconds: 24));
    leftClickUp();
  }

  static void leftClickDown() {
    if (!Platform.isMacOS) return;
    _isLeftButtonDown = true;
    _postMouseEvent(
        kCGEventLeftMouseDown, kCGMouseButtonLeft, _getCurrentMousePosition(),
        clickState: 1);
  }

  static void leftClickUp() {
    if (!Platform.isMacOS) return;
    _isLeftButtonDown = false;
    _postMouseEvent(
        kCGEventLeftMouseUp, kCGMouseButtonLeft, _getCurrentMousePosition(),
        clickState: 1);
  }

  /// macOS only treats two clicks as a double-click when the events carry an
  /// increasing click state, so successive taps are counted here.
  static int _nextClickState(CGPoint pos, {required bool right}) {
    final now = DateTime.now();
    final near = (pos.x - _lastClickX).abs() < 6 && (pos.y - _lastClickY).abs() < 6;
    if (near &&
        right == _lastClickRight &&
        now.difference(_lastClickAt).inMilliseconds < 450) {
      _clickCount = (_clickCount % 3) + 1;
    } else {
      _clickCount = 1;
    }
    _lastClickAt = now;
    _lastClickX = pos.x;
    _lastClickY = pos.y;
    _lastClickRight = right;
    return _clickCount;
  }

  static void click() {
    if (!Platform.isMacOS) return;
    final pos = _getCurrentMousePosition();
    final clicks = _nextClickState(pos, right: false);
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, pos, clickState: clicks);
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, pos, clickState: clicks);
  }

  static void rightClick() {
    if (!Platform.isMacOS) return;
    final pos = _getCurrentMousePosition();
    final clicks = _nextClickState(pos, right: true);
    _postMouseEvent(kCGEventRightMouseDown, kCGMouseButtonRight, pos, clickState: clicks);
    _postMouseEvent(kCGEventRightMouseUp, kCGMouseButtonRight, pos, clickState: clicks);
  }

  static void doubleClick() {
    if (!Platform.isMacOS) return;
    final pos = _getCurrentMousePosition();
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, pos, clickState: 1);
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, pos, clickState: 1);
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, pos, clickState: 2);
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, pos, clickState: 2);
    _lastClickAt = DateTime.now();
    _lastClickX = pos.x;
    _lastClickY = pos.y;
    _lastClickRight = false;
    _clickCount = 2;
  }

  static void scroll(double dy) {
    if (!Platform.isMacOS) return;
    const int units = 1; // 0 = lines, 1 = pixels
    const int wheelCount = 1;
    final int wheel1 = (dy * 2).round();

    final event =
        _cgEventCreateScrollWheelEvent(nullptr, units, wheelCount, wheel1);
    if (event != nullptr) {
      _cgEventPost(kCGHIDEventTap, event);
      _cfRelease(event);
    }
  }

  /// Smooth pixel scroll in both axes. Events are flagged continuous so apps
  /// treat them like trackpad scrolling; sub-pixel remainders carry over so
  /// slow momentum tails are not lost to rounding. Positive [dy] moves the
  /// content down (natural scrolling: the finger drags the page).
  static void scrollPixels(double dx, double dy) {
    if (!Platform.isMacOS) return;
    final totalX = dx + _scrollRemainderX;
    final totalY = dy + _scrollRemainderY;
    final wheelX = totalX.truncate();
    final wheelY = totalY.truncate();
    _scrollRemainderX = totalX - wheelX;
    _scrollRemainderY = totalY - wheelY;
    if (wheelX == 0 && wheelY == 0) return;
    final event = _cgEventCreateScrollWheelEvent2(nullptr, 1, 2, wheelY, wheelX, 0);
    if (event != nullptr) {
      _cgEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, 1);
      _cgEventPost(kCGHIDEventTap, event);
      _cfRelease(event);
    }
  }

  /// Posts a hardware-style media key (play, next, previous, volume, mute)
  /// as an NSEvent system-defined event, so it reaches whichever app owns
  /// Now Playing (Music, Spotify, a browser tab...).
  static Future<void> mediaKey(String key) async {
    if (!Platform.isMacOS) return;
    final code = switch (key) {
      'play' || 'play_pause' => kNXKeyPlay,
      'next' => kNXKeyNext,
      'prev' || 'previous' => kNXKeyPrevious,
      'mute' => kNXKeyMute,
      'vol_up' => kNXKeySoundUp,
      'vol_down' => kNXKeySoundDown,
      _ => -1,
    };
    if (code < 0) return;
    if (_postSystemMediaKey(code, down: true)) {
      _postSystemMediaKey(code, down: false);
      return;
    }
    await _mediaKeyViaScript(code);
  }

  static bool _postSystemMediaKey(int code, {required bool down}) {
    try {
      final cls = _objcName('NSEvent', _objcGetClass);
      if (cls == nullptr) return false;
      final sel = _objcName(
        'otherEventWithType:location:modifierFlags:timestamp:windowNumber:context:subtype:data1:data2:',
        _selRegisterName,
      );
      final cgSel = _objcName('CGEvent', _selRegisterName);
      final loc = calloc<CGPoint>();
      Pointer nsEvent;
      try {
        nsEvent = _msgSendOtherEvent(
          cls,
          sel,
          14, // NSEventTypeSystemDefined
          loc.ref,
          down ? 0xa00 : 0xb00,
          0,
          0,
          nullptr,
          8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
          (code << 16) | ((down ? 0xa : 0xb) << 8),
          -1,
        );
      } finally {
        calloc.free(loc);
      }
      if (nsEvent == nullptr) return false;
      final cgEvent = _msgSendPtr(nsEvent, cgSel);
      if (cgEvent == nullptr) return false;
      _cgEventPost(kCGHIDEventTap, cgEvent);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _mediaKeyViaScript(int code) async {
    final script = [
      'ObjC.import("Cocoa");',
      'function post(down) {',
      '  var e = \$.NSEvent.otherEventWithTypeLocationModifierFlagsTimestampWindowNumberContextSubtypeData1Data2(',
      '    14, \$.NSMakePoint(0, 0), down ? 0xa00 : 0xb00, 0, 0, null, 8,',
      '    ($code << 16) | ((down ? 0xa : 0xb) << 8), -1);',
      '  \$.CGEventPost(0, e.CGEvent);',
      '}',
      'post(true); post(false);',
    ].join('\n');
    try {
      await Process.run('osascript', ['-l', 'JavaScript', '-e', script]);
    } catch (_) {}
  }

  /// Current output volume (0-100) and mute state.
  static Future<({int level, bool muted})?> getVolume() async {
    if (!Platform.isMacOS) return null;
    try {
      final res = await Process.run('osascript', [
        '-e',
        'set s to get volume settings',
        '-e',
        'return ((output volume of s) as text) & "," & ((output muted of s) as text)',
      ]);
      if (res.exitCode != 0) return null;
      final parts = res.stdout.toString().trim().split(',');
      final level = int.tryParse(parts.first.trim());
      if (level == null) return null;
      final muted = parts.length > 1 && parts[1].trim() == 'true';
      return (level: level, muted: muted);
    } catch (_) {
      return null;
    }
  }

  /// Sets output volume. Rapid dial updates are coalesced: one write runs at
  /// a time and only the newest requested level is applied next.
  static Future<void> setVolume(int level) async {
    if (!Platform.isMacOS) return;
    _pendingVolume = level.clamp(0, 100);
    if (_volumeWriteInFlight) return;
    _volumeWriteInFlight = true;
    try {
      while (_pendingVolume != null) {
        final next = _pendingVolume!;
        _pendingVolume = null;
        try {
          await Process.run('osascript', [
            '-e',
            next == 0
                ? 'set volume output volume 0'
                : 'set volume output volume $next without output muted',
          ]);
        } catch (_) {}
      }
    } finally {
      _volumeWriteInFlight = false;
    }
  }

  static Future<void> setMuted(bool muted) async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('osascript', [
        '-e',
        muted ? 'set volume with output muted' : 'set volume without output muted',
      ]);
    } catch (_) {}
  }

  static void _postMouseEvent(
      int eventType, int mouseButton, CGPoint position, {int clickState = 0}) {
    final event =
        _cgEventCreateMouseEvent(nullptr, eventType, position, mouseButton);
    if (event != nullptr) {
      if (clickState > 0) {
        _cgEventSetIntegerValueField(event, kCGMouseEventClickState, clickState);
      }
      _cgEventPost(kCGHIDEventTap, event);
      _cfRelease(event);
    }
  }

  static Future<String> readClipboard() async {
    if (!Platform.isMacOS) return '';
    try {
      final res = await Process.run('pbpaste', const []);
      if (res.exitCode == 0) return res.stdout.toString();
    } catch (_) {}
    return '';
  }

  static Future<bool> writeClipboard(String text) async {
    if (!Platform.isMacOS) return false;
    try {
      final proc = await Process.start('pbcopy', const []);
      proc.stdin.add(utf8.encode(text));
      await proc.stdin.close();
      final code = await proc.exitCode;
      return code == 0;
    } catch (_) {
      return false;
    }
  }

  /// Wispr-Flow-style instant text injection into the focused macOS cursor!
  /// Copies UTF-8 text into `pbcopy`, fires `⌘V`, optionally hits Return, and
  /// restores the user's prior clipboard 280ms later.
  static Future<void> pasteTextInstant(
    String text, {
    bool restoreClipboard = true,
    bool pressEnter = false,
  }) async {
    if (!Platform.isMacOS || text.isEmpty) return;
    String? priorClipboard;
    if (restoreClipboard) {
      priorClipboard = await readClipboard();
    }
    final copied = await writeClipboard(text);
    if (!copied) {
      await typeString(text);
      if (pressEnter) await tapKey('enter');
      return;
    }
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to keystroke "v" using command down',
    ]);
    if (pressEnter) {
      await Future<void>.delayed(const Duration(milliseconds: 55));
      await tapKey('enter');
    }
    if (restoreClipboard && priorClipboard != null) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 280), () async {
          await writeClipboard(priorClipboard!);
        }),
      );
    }
  }

  /// macOS virtual key codes for keys that can't be typed as text.
  static const Map<String, int> _namedKeyCodes = {
    'f1': 122, 'f2': 120, 'f3': 99, 'f4': 118, 'f5': 96, 'f6': 97,
    'f7': 98, 'f8': 100, 'f9': 101, 'f10': 109, 'f11': 103, 'f12': 111,
    'home': 115, 'end': 119, 'pageup': 116, 'page_up': 116,
    'pagedown': 121, 'page_down': 121,
    'left': 123, 'right': 124, 'down': 125, 'up': 126,
    'escape': 53, 'esc': 53, 'forward_delete': 117,
  };

  static Future<void> tapKey(String key) async {
    if (!Platform.isMacOS) return;
    try {
      final lower = key.toLowerCase().trim();
      final named = _namedKeyCodes[lower];
      if (named != null && lower.startsWith(RegExp(r'f\d|home|end|page'))) {
        await Process.run('osascript',
            ['-e', 'tell application "System Events" to key code $named']);
        return;
      }
      if (lower == 'enter' || lower == 'return') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 36']);
      } else if (lower == 'tab') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 48']);
      } else if (lower == 'space') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 49']);
      } else if (lower == 'esc' || lower == 'escape') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 53']);
      } else if (lower == 'backspace' || lower == 'delete') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 51']);
      } else if (lower == 'forward_delete') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 117']);
      } else if (lower == 'left') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 123']);
      } else if (lower == 'right') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 124']);
      } else if (lower == 'down') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 125']);
      } else if (lower == 'up') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 126']);
      } else if (lower == 'cmd' || lower == 'command' || lower == 'win') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 55']);
      } else if (lower == 'shift') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 56']);
      } else if (lower == 'alt' || lower == 'option') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 58']);
      } else if (lower == 'ctrl' || lower == 'control') {
        await Process.run(
            'osascript', ['-e', 'tell application "System Events" to key code 59']);
      } else {
        final sanitized = key.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        await Process.run('osascript',
            ['-e', 'tell application "System Events" to keystroke "$sanitized"']);
      }
    } catch (_) {}
  }

  static Future<void> sendHotkey(String combo) async {
    if (!Platform.isMacOS) return;
    try {
      final lower = combo.toLowerCase().trim();
      if (lower == 'copy') {
        await Process.run('osascript', [
          '-e',
          'tell application "System Events" to keystroke "c" using command down'
        ]);
        return;
      } else if (lower == 'paste') {
        await Process.run('osascript', [
          '-e',
          'tell application "System Events" to keystroke "v" using command down'
        ]);
        return;
      }

      if (lower.contains('+')) {
        final parts = lower
            .split('+')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.length >= 2) {
          final keyPart = parts.last;
          final modifiers = <String>[];
          for (final mod in parts.sublist(0, parts.length - 1)) {
            if (mod == 'cmd' ||
                mod == 'command' ||
                mod == 'win' ||
                mod == 'meta') {
              modifiers.add('command down');
            } else if (mod == 'ctrl' || mod == 'control') {
              final hasExplicitCmd =
                  parts.any((p) => p == 'cmd' || p == 'command');
              if (!hasExplicitCmd &&
                  const {'c', 'v', 'x', 'z', 'a', 's'}.contains(keyPart)) {
                modifiers.add('command down');
              } else {
                modifiers.add('control down');
              }
            } else if (mod == 'alt' || mod == 'opt' || mod == 'option') {
              modifiers.add('option down');
            } else if (mod == 'shift') {
              modifiers.add('shift down');
            }
          }

          if (modifiers.isNotEmpty) {
            final usingClause = modifiers.length == 1
                ? modifiers.first
                : '{${modifiers.toSet().join(', ')}}';
            if (keyPart == 'space') {
              await Process.run('osascript', [
                '-e',
                'tell application "System Events" to key code 49 using $usingClause',
              ]);
              return;
            } else if (keyPart == 'tab') {
              await Process.run('osascript', [
                '-e',
                'tell application "System Events" to key code 48 using $usingClause',
              ]);
              return;
            } else if (keyPart == 'enter' || keyPart == 'return') {
              await Process.run('osascript', [
                '-e',
                'tell application "System Events" to key code 36 using $usingClause',
              ]);
              return;
            } else if (keyPart == 'delete' || keyPart == 'backspace') {
              await Process.run('osascript', [
                '-e',
                'tell application "System Events" to key code 51 using $usingClause',
              ]);
              return;
            } else if (_namedKeyCodes.containsKey(keyPart)) {
              // Arrows, F-keys, Home/End, Page Up/Down with modifiers (⌘←, ⇧F5…).
              await Process.run('osascript', [
                '-e',
                'tell application "System Events" to key code ${_namedKeyCodes[keyPart]} using $usingClause',
              ]);
              return;
            }
            final sanitized =
                keyPart.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
            await Process.run('osascript', [
              '-e',
              'tell application "System Events" to keystroke "$sanitized" using $usingClause',
            ]);
            return;
          }
        }
      }

      await tapKey(combo);
    } catch (_) {}
  }

  static Future<String?> getActiveAppName() async {
    if (!Platform.isMacOS) return null;
    try {
      final res = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get name of first application process whose frontmost is true',
      ]);
      if (res.exitCode == 0) {
        final out = (res.stdout as String).trim();
        if (out.isNotEmpty) return out;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> typeString(String text) async {
    if (!Platform.isMacOS || text.isEmpty) return;
    if (text.length > 16 || text.contains('\n')) {
      await pasteTextInstant(text);
      return;
    }
    try {
      final sanitized = text.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
      await Process.run('osascript',
          ['-e', 'tell application "System Events" to keystroke "$sanitized"']);
    } catch (_) {}
  }

  /// Wakes a sleeping display (the system itself is kept awake by the agent).
  static Future<void> wakeDisplay() async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('caffeinate', ['-u', '-t', '3']);
    } catch (_) {}
  }

  /// True while the login window / lock screen is up.
  static Future<bool> isScreenLocked() async {
    if (!Platform.isMacOS) return false;
    try {
      final res = await Process.run('ioreg', ['-n', 'Root', '-d1', '-k', 'IOConsoleUsers']);
      return res.stdout.toString().contains('"CGSSessionScreenIsLocked"=Yes');
    } catch (_) {
      return false;
    }
  }

  static void _postKey(int keycode, {String? char}) {
    for (final down in [true, false]) {
      final event = _cgEventCreateKeyboardEvent(nullptr, keycode, down);
      if (event == nullptr) continue;
      if (char != null) {
        final units = char.codeUnits;
        final buf = calloc<Uint16>(units.length);
        for (var i = 0; i < units.length; i++) {
          buf[i] = units[i];
        }
        _cgEventKeyboardSetUnicodeString(event, units.length, buf);
        calloc.free(buf);
      }
      _cgEventPost(kCGHIDEventTap, event);
      _cfRelease(event);
    }
  }

  /// Types [text] with HID-level unicode key events (works at the lock
  /// screen, unlike System Events keystrokes).
  static Future<void> typeUnicodeHid(String text) async {
    if (!Platform.isMacOS) return;
    for (final rune in text.runes) {
      _postKey(0, char: String.fromCharCode(rune));
      await Future<void>.delayed(const Duration(milliseconds: 18));
    }
  }

  /// Wakes the screen, types the login password and presses Return.
  /// Returns false when macOS has no display to wake or posting failed.
  /// The password is held only for the duration of this call.
  static Future<bool> unlockWithPassword(String password) async {
    if (!Platform.isMacOS || password.isEmpty) return false;
    try {
      await wakeDisplay();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      // A first key press reveals the password field on the lock screen.
      _postKey(56); // shift
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await typeUnicodeHid(password);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      _postKey(36); // return
      return true;
    } catch (_) {
      // Fall back to the AppleScript path.
      await wakeAndUnlock(password);
      return false;
    }
  }

  static Future<void> wakeAndUnlock(String passkey) async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('caffeinate', ['-u', '-t', '2']);
      if (passkey.isNotEmpty) {
        final sanitized =
            passkey.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
        await Process.run('osascript', [
          '-e',
          'tell application "System Events" to keystroke "$sanitized"',
          '-e',
          'tell application "System Events" to key code 36',
        ]);
      }
    } catch (_) {}
  }
}
