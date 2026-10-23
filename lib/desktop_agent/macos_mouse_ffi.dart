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

// CGEventRef CGEventCreateMouseEvent(CGEventSourceRef source, CGEventType mouseType, CGPoint mouseCursorPosition, CGMouseButton mouseButton);
typedef CGEventCreateMouseEventC = Pointer Function(
    Pointer source, Uint32 mouseType, CGPoint mouseCursorPosition, Uint32 mouseButton);
typedef CGEventCreateMouseEventDart = Pointer Function(
    Pointer source, int mouseType, CGPoint mouseCursorPosition, int mouseButton);

// CGEventRef CGEventCreateScrollWheelEvent(CGEventSourceRef source, CGScrollEventUnit units, uint32_t wheelCount, int32_t wheel1, ...);
typedef CGEventCreateScrollWheelEventC = Pointer Function(
    Pointer source, Uint32 units, Uint32 wheelCount, Int32 wheel1);
typedef CGEventCreateScrollWheelEventDart = Pointer Function(
    Pointer source, int units, int wheelCount, int wheel1);

// void CGEventPost(CGEventTapLocation tap, CGEventRef event);
typedef CGEventPostC = Void Function(Uint32 tap, Pointer event);
typedef CGEventPostDart = void Function(int tap, Pointer event);

// CGPoint CGEventGetLocation(CGEventRef event);
typedef CGEventGetLocationC = CGPoint Function(Pointer event);
typedef CGEventGetLocationDart = CGPoint Function(Pointer event);

// CGEventRef CGEventCreate(CGEventSourceRef source);
typedef CGEventCreateC = Pointer Function(Pointer source);
typedef CGEventCreateDart = Pointer Function(Pointer source);

typedef CFReleaseC = Void Function(Pointer arg);
typedef CFReleaseDart = void Function(Pointer arg);

// ─── Bound Functions ────────────────────────────────────────────────────────
final CGEventCreateMouseEventDart _cgEventCreateMouseEvent =
    _coreGraphics.lookupFunction<CGEventCreateMouseEventC, CGEventCreateMouseEventDart>('CGEventCreateMouseEvent');

final CGEventCreateScrollWheelEventDart _cgEventCreateScrollWheelEvent =
    _coreGraphics.lookupFunction<CGEventCreateScrollWheelEventC, CGEventCreateScrollWheelEventDart>('CGEventCreateScrollWheelEvent');

final CGEventPostDart _cgEventPost =
    _coreGraphics.lookupFunction<CGEventPostC, CGEventPostDart>('CGEventPost');

final CGEventGetLocationDart _cgEventGetLocation =
    _coreGraphics.lookupFunction<CGEventGetLocationC, CGEventGetLocationDart>('CGEventGetLocation');

final CGEventCreateDart _cgEventCreate =
    _coreGraphics.lookupFunction<CGEventCreateC, CGEventCreateDart>('CGEventCreate');

final DynamicLibrary _coreFoundation = Platform.isMacOS
    ? DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    : DynamicLibrary.process();

final CFReleaseDart _cfRelease =
    _coreFoundation.lookupFunction<CFReleaseC, CFReleaseDart>('CFRelease');

// ─── Internal State ─────────────────────────────────────────────────────────
bool _isLeftButtonDown = false;

// ─── Public API ─────────────────────────────────────────────────────────────
class MacOSMouseController {
  
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

  static void moveBy(double dx, double dy) {
    if (!Platform.isMacOS) return;
    
    final currentPos = _getCurrentMousePosition();
    
    final newPosPtr = calloc<CGPoint>();
    newPosPtr.ref.x = currentPos.x + dx;
    newPosPtr.ref.y = currentPos.y + dy;

    if (_isLeftButtonDown) {
      _postMouseEvent(kCGEventLeftMouseDragged, kCGMouseButtonLeft, newPosPtr.ref);
    } else {
      _postMouseEvent(kCGEventMouseMoved, kCGMouseButtonLeft, newPosPtr.ref);
    }
    
    calloc.free(newPosPtr);
  }

  static void leftClickDown() {
    if (!Platform.isMacOS) return;
    _isLeftButtonDown = true;
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, _getCurrentMousePosition());
  }

  static void leftClickUp() {
    if (!Platform.isMacOS) return;
    _isLeftButtonDown = false;
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, _getCurrentMousePosition());
  }

  static void click() {
    if (!Platform.isMacOS) return;
    final pos = _getCurrentMousePosition();
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, pos);
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, pos);
  }

  static void rightClick() {
    if (!Platform.isMacOS) return;
    final pos = _getCurrentMousePosition();
    _postMouseEvent(kCGEventRightMouseDown, kCGMouseButtonRight, pos);
    _postMouseEvent(kCGEventRightMouseUp, kCGMouseButtonRight, pos);
  }

  static void doubleClick() {
    if (!Platform.isMacOS) return;
    final pos = _getCurrentMousePosition();
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, pos);
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, pos);
    _postMouseEvent(kCGEventLeftMouseDown, kCGMouseButtonLeft, pos);
    _postMouseEvent(kCGEventLeftMouseUp, kCGMouseButtonLeft, pos);
  }

  static void scroll(double dy) {
    if (!Platform.isMacOS) return;
    final int units = 1; // 0 = lines, 1 = pixels
    final int wheelCount = 1;
    final int wheel1 = (dy * 2).round(); // scale up scroll speed

    final event = _cgEventCreateScrollWheelEvent(nullptr, units, wheelCount, wheel1);
    if (event != nullptr) {
      _cgEventPost(kCGHIDEventTap, event);
      _cfRelease(event);
    }
  }

  static void _postMouseEvent(int eventType, int mouseButton, CGPoint position) {
    final event = _cgEventCreateMouseEvent(nullptr, eventType, position, mouseButton);
    if (event != nullptr) {
      _cgEventPost(kCGHIDEventTap, event);
      _cfRelease(event);
    }
  }

  static Future<void> tapKey(String key) async {
    if (!Platform.isMacOS) return;
    try {
      final lower = key.toLowerCase().trim();
      if (lower == 'enter' || lower == 'return') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 36']);
      } else if (lower == 'tab') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 48']);
      } else if (lower == 'space') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 49']);
      } else if (lower == 'esc' || lower == 'escape') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 53']);
      } else if (lower == 'backspace' || lower == 'delete') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 51']);
      } else if (lower == 'left') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 123']);
      } else if (lower == 'right') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 124']);
      } else if (lower == 'down') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 125']);
      } else if (lower == 'up') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 126']);
      } else if (lower == 'cmd' || lower == 'command' || lower == 'win') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 55']);
      } else if (lower == 'shift') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 56']);
      } else if (lower == 'alt' || lower == 'option') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 58']);
      } else if (lower == 'ctrl' || lower == 'control') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to key code 59']);
      } else {
        final sanitized = key.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
        await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "$sanitized"']);
      }
    } catch (_) {}
  }

  static Future<void> sendHotkey(String combo) async {
    if (!Platform.isMacOS) return;
    try {
      final lower = combo.toLowerCase().trim();
      if (lower == 'copy' || lower == 'cmd+c' || lower == 'ctrl+c') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "c" using command down']);
      } else if (lower == 'paste' || lower == 'cmd+v' || lower == 'ctrl+v') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "v" using command down']);
      } else if (lower == 'cmd+a' || lower == 'ctrl+a') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "a" using command down']);
      } else if (lower == 'cmd+z' || lower == 'ctrl+z') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "z" using command down']);
      } else if (lower == 'cmd+s' || lower == 'ctrl+s') {
        await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "s" using command down']);
      } else {
        await tapKey(combo);
      }
    } catch (_) {}
  }

  static Future<void> typeString(String text) async {
    if (!Platform.isMacOS || text.isEmpty) return;
    try {
      final sanitized = text.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
      await Process.run('osascript', ['-e', 'tell application "System Events" to keystroke "$sanitized"']);
    } catch (_) {}
  }

  static Future<void> wakeAndUnlock(String passkey) async {
    if (!Platform.isMacOS) return;
    try {
      await Process.run('caffeinate', ['-u', '-t', '2']);
      if (passkey.isNotEmpty) {
        final sanitized = passkey.replaceAll('"', '\\"').replaceAll('\\', '\\\\');
        await Process.run('osascript', [
          '-e', 'tell application "System Events" to keystroke "$sanitized"',
          '-e', 'tell application "System Events" to key code 36',
        ]);
      }
    } catch (_) {}
  }
}
