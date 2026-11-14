import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Step-by-step Back for every screen.
///
/// go_router's `go` (used for tabs, deep links and many "open X" actions)
/// replaces the stack, so the router alone often has nothing to pop and Back
/// used to jump straight to the home feed. [OneovaNav] keeps a short trail of
/// the places the person actually visited and walks it back one step at a
/// time. [AndroidBackHandler] uses it for the system Back gesture; screens use
/// [back] for their own back arrows.
class OneovaNav {
  OneovaNav._();

  static const String home = '/hub/home';
  static const int _max = 40;
  static final List<String> _trail = [];
  static GoRouter? _router;

  static bool _skip(String loc) => loc.isEmpty || loc.startsWith('/auth') || loc == '/splash' || loc == '/';

  /// Called by [AndroidBackHandler] once with the app's router.
  static void attach(GoRouter router) {
    if (identical(_router, router)) return;
    _router?.routerDelegate.removeListener(_onChange);
    _router = router;
    router.routerDelegate.addListener(_onChange);
    _onChange();
  }

  static void detach() {
    _router?.routerDelegate.removeListener(_onChange);
    _router = null;
  }

  static String? get _current => _router?.routerDelegate.currentConfiguration.uri.toString();

  static void _onChange() {
    final loc = _current;
    if (loc == null) return;
    if (_skip(loc)) {
      // Signing in or out starts a fresh trail.
      if (loc.startsWith('/auth')) _trail.clear();
      return;
    }
    if (_trail.isNotEmpty && _trail.last == loc) return;
    // Moving back to the previous place: drop the step we left.
    if (_trail.length >= 2 && _trail[_trail.length - 2] == loc) {
      _trail.removeLast();
      return;
    }
    _trail.add(loc);
    if (_trail.length > _max) _trail.removeAt(0);
  }

  /// The place before the current one, if any.
  static String? get previous => _trail.length >= 2 ? _trail[_trail.length - 2] : null;

  /// Goes back one step: pops the current route if it can, otherwise returns
  /// to the previous place visited, otherwise [fallback] (home by default).
  static void back(BuildContext context, {String fallback = home}) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final prev = previous;
    if (prev != null) {
      _trail.removeLast();
      context.go(prev);
      return;
    }
    context.go(fallback);
  }

  /// For the system Back when the router itself couldn't pop. Returns false
  /// when there is nowhere to go (the app may close).
  static bool backFromSystem() {
    final router = _router;
    final prev = previous;
    if (router == null || prev == null) return false;
    _trail.removeLast();
    router.go(prev);
    return true;
  }
}
