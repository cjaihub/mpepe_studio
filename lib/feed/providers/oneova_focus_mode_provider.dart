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

class OneovaBottomNavVisibleNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setVisible(bool visible) {
    if (state != visible) {
      state = visible;
    }
  }
}

/// Global provider for Oneova bottom navigation bar visibility.
///
/// Tracks whether the bottom navigation is currently mounted and visible on-screen,
/// allowing full-bleed feed overlays to drop down and eliminate bottom dead space.
/// Reels: the bottom nav stays hidden while a reel plays and slides back
/// when the viewer taps to pause (or the feed is empty). Approved by the user
/// on 2026-11-14.
final reelsNavPeekProvider = NotifierProvider<OneovaFocusModeNotifier, bool>(OneovaFocusModeNotifier.new);

final oneovaBottomNavVisibleProvider =
    NotifierProvider<OneovaBottomNavVisibleNotifier, bool>(OneovaBottomNavVisibleNotifier.new);

