import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../geometry/studio_geometry.dart';

/// What a pop-out shows: a person (by uid) or the table.
@immutable
class PopoutTarget {
  const PopoutTarget.person(String this.uid);
  const PopoutTarget.table() : uid = null;
  final String? uid;
  bool get isTable => uid == null;

  @override
  bool operator ==(Object other) => other is PopoutTarget && other.uid == uid;
  @override
  int get hashCode => uid.hashCode;
  @override
  String toString() => isTable ? 'PopoutTarget.table' : 'PopoutTarget.person($uid)';
}

/// The single floating window. [rect] is in artboard pixels.
@immutable
class PopoutWindowState {
  const PopoutWindowState({required this.target, required this.rect, this.fullScreen = false});
  final PopoutTarget target;
  final Rect rect;
  final bool fullScreen;

  PopoutWindowState copyWith({Rect? rect, bool? fullScreen}) =>
      PopoutWindowState(target: target, rect: rect ?? this.rect, fullScreen: fullScreen ?? this.fullScreen);
}

/// Pure pop-out geometry (prototype `dragWin`).
class PopoutMath {
  PopoutMath._();

  /// Move by [delta], keeping the whole window inside [bounds].
  static Rect move(Rect r, Offset delta, Rect bounds) {
    final x = (r.left + delta.dx).clamp(bounds.left, math.max(bounds.left, bounds.right - r.width));
    final y = (r.top + delta.dy).clamp(bounds.top, math.max(bounds.top, bounds.bottom - r.height));
    return Rect.fromLTWH(x.toDouble(), y.toDouble(), r.width, r.height);
  }

  /// Resize from the bottom-right grip by [delta]: at least [min], never past
  /// [bounds].
  static Rect resize(Rect r, Offset delta, Size min, Rect bounds) {
    final w = math.min(math.max(min.width, r.width + delta.dx), bounds.right - r.left);
    final h = math.min(math.max(min.height, r.height + delta.dy), bounds.bottom - r.top);
    return Rect.fromLTWH(r.left, r.top, w, h);
  }

  /// Fits a default rect into [bounds] (small viewports).
  static Rect fit(Rect r, Rect bounds) {
    final w = math.min(r.width, bounds.width), h = math.min(r.height, bounds.height);
    return move(Rect.fromLTWH(r.left, r.top, w, h), Offset.zero, bounds);
  }
}

/// One window at a time; state is local to this client (ARCHITECTURE §4).
class PopoutController extends Notifier<PopoutWindowState?> {
  @override
  PopoutWindowState? build() => null;

  /// Opening always resets to the default size and position (SPEC §4.2).
  void open(PopoutTarget target, OrientationGeometry g, {Rect? bounds}) {
    final d = g.popoutDefault;
    state = PopoutWindowState(target: target, rect: bounds == null ? d : PopoutMath.fit(d, bounds));
  }

  void close() => state = null;

  void toggleFullScreen() {
    final s = state;
    if (s != null) state = s.copyWith(fullScreen: !s.fullScreen);
  }

  /// Header drag. Ignored in full screen.
  void moveBy(Offset delta, Rect bounds) {
    final s = state;
    if (s == null || s.fullScreen) return;
    state = s.copyWith(rect: PopoutMath.move(s.rect, delta, bounds));
  }

  void resizeBy(Offset delta, Size min, Rect bounds) {
    final s = state;
    if (s == null || s.fullScreen) return;
    state = s.copyWith(rect: PopoutMath.resize(s.rect, delta, min, bounds));
  }
}

final studioPopoutProvider =
    NotifierProvider.autoDispose<PopoutController, PopoutWindowState?>(PopoutController.new);
