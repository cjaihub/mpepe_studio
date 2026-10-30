import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Makes Android Back go to the previous screen instead of closing the app.
///
/// Why: on Android 14+ (and by default for apps targeting SDK 36 on Android
/// 16) the OS uses predictive back. It only hands Back to Flutter while the
/// framework reports "I can pop" (NavigationNotification.canHandlePop). With
/// go_router's nested navigators (the HubShell tabs plus routes pushed on top)
/// that signal is lost, so the OS closed the app on almost every screen.
///
/// Fix:
/// 1. Always report "can handle pop", so Back always reaches Flutter. The
///    router then pops the right navigator, and PopScope(canPop: false)
///    screens still get their onPopInvoked callbacks.
/// 2. When nothing can pop: off the home feed → go to /hub/home; on the home
///    feed → let the app close as usual.
class AndroidBackHandler extends StatefulWidget {
  const AndroidBackHandler({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  static const String homePath = '/hub/home';

  @override
  State<AndroidBackHandler> createState() => _AndroidBackHandlerState();
}

class _AndroidBackHandlerState extends State<AndroidBackHandler> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Added after the Router's own back dispatcher, so this runs only when
    // the router could not pop anything.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    final path = widget.router.routerDelegate.currentConfiguration.uri.path;
    if (path.isEmpty || path == AndroidBackHandler.homePath) return false; // close the app
    // Auth and splash have no "previous screen" inside the app.
    if (path.startsWith('/auth') || path == '/splash') return false;
    widget.router.go(AndroidBackHandler.homePath);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: (n) {
        if (n.canHandlePop) return false;
        // Re-dispatch from above this listener so WidgetsApp keeps routing
        // Android Back to Flutter.
        const NavigationNotification(canHandlePop: true).dispatch(context);
        return true;
      },
      child: widget.child,
    );
  }
}
