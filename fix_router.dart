import 'dart:io';

void main() {
  final file = File('lib/shared/router.dart');
  var content = file.readAsStringSync();

  final helper = '''
CustomTransitionPage<void> _buildPageWithTransition(BuildContext context, GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0), // Slide in from right
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
          child: child,
        ),
      );
    },
  );
}

GoRoute _animatedGoRoute({required String path, required Widget Function(BuildContext, GoRouterState) builder, List<RouteBase>? routes}) {
  return GoRoute(
    path: path,
    routes: routes ?? [],
    pageBuilder: (context, state) => _buildPageWithTransition(context, state, builder(context, state)),
  );
}
''';

  content = content.replaceFirst('final routerProvider', '$helper\nfinal routerProvider');

  // Replace top-level GoRoutes but skip those inside StatefulShellBranch.
  // StatefulShellBranch routes are usually formatted with `routes: [GoRoute(...)` in a single line.
  // We'll replace GoRoute(path: '...', builder: ...) with _animatedGoRoute(path: '...', builder: ...)
  // For simplicity, we can regex it carefully.
  content = content.replaceAllMapped(
    RegExp(r'GoRoute\(\s*path:\s*([^,]+),\s*builder:\s*\([^)]+\)\s*=>\s*([^\)]+?)\s*(?:,\s*routes:\s*\[([^\]]*)\])?\s*\)'),
    (match) {
      final path = match.group(1)!;
      final builderBody = match.group(2)!;
      final routes = match.group(3);
      if (routes != null) {
        return '_animatedGoRoute(path: $path, builder: (context, state) => $builderBody, routes: [$routes])';
      }
      return '_animatedGoRoute(path: $path, builder: (context, state) => $builderBody)';
    }
  );
  
  file.writeAsStringSync(content);
}
