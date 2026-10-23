import 'package:flutter_riverpod/flutter_riverpod.dart';

class OneovaFocusModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void set(bool val) => state = val;
}

/// Global provider for Oneova Single-Tap Full-Screen Focus Mode.
///
/// When active (true), all ambient overlays (top tabs, stories strip, dock,
/// engagement buttons, captions, audio pill, and global bottom navigation)
/// smoothly fade away, providing an edge-to-edge immersive media focus mode.
/// A single tap toggles it on or off on any screen.
final oneovaFocusModeProvider = NotifierProvider<OneovaFocusModeNotifier, bool>(OneovaFocusModeNotifier.new);
