import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oneova/shared/navigation/android_back_handler.dart';

void main() {
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/hub/home',
        routes: [
          ShellRoute(
            builder: (context, state, child) => Scaffold(body: child),
            routes: [
              GoRoute(path: '/hub/home', builder: (_, _) => const Text('home')),
              GoRoute(path: '/hub/messages', builder: (_, _) => const Text('messages')),
            ],
          ),
          GoRoute(path: '/notifications', builder: (_, _) => const Text('notifications')),
          GoRoute(path: '/profile/me', builder: (_, _) => const Text('profile')),
        ],
      );

  Future<GoRouter> pump(WidgetTester tester) async {
    final router = buildRouter();
    // Flutter only reports back handling to Android while resumed.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AndroidBackHandler(router: router, child: child!),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  final frameworkHandlesBack = <bool>[];
  setUp(() {
    frameworkHandlesBack.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') frameworkHandlesBack.add(call.arguments as bool);
      return null;
    });
  });

  testWidgets('Back pops a pushed screen instead of closing the app', (tester) async {
    final router = await pump(tester);
    router.push('/notifications');
    await tester.pumpAndSettle();
    router.push('/profile/me');
    await tester.pumpAndSettle();
    expect(find.text('profile'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('notifications'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('Android always routes Back to Flutter (never reports false)', (tester) async {
    final router = await pump(tester);
    router.push('/notifications');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(frameworkHandlesBack, isNotEmpty);
    expect(frameworkHandlesBack.every((v) => v), isTrue);
  });

  testWidgets('Back on another tab goes to the home feed; on home it exits', (tester) async {
    final router = await pump(tester);
    router.go('/hub/messages');
    await tester.pumpAndSettle();
    expect(find.text('messages'), findsOneWidget);

    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    // On the home feed with nothing to pop: not handled → the app may close.
    final handled = await AndroidBackHandlerProbe.didPopRoute(tester);
    expect(handled, isFalse);
  });
}

/// Calls the handler's fallback directly (handlePopRoute would invoke
/// SystemNavigator.pop on the mock channel when nothing handles it).
class AndroidBackHandlerProbe {
  static Future<bool> didPopRoute(WidgetTester tester) async {
    final state = tester.state(find.byType(AndroidBackHandler)) as WidgetsBindingObserver;
    return state.didPopRoute();
  }
}
