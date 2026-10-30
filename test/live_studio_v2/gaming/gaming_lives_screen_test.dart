import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:oneova/backend/live_studio/session/studio_session_controller.dart';
import 'package:oneova/social_hub/live/studio_v2/gaming/gaming_lives_screen.dart';

/// The LIVE pill pulses forever, so pumpAndSettle never settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<void> add(String id, Map<String, dynamic> data) =>
      db.collection('live_streams').doc(id).set({'createdAt': Timestamp.fromMillisecondsSinceEpoch(0), ...data});

  Future<List<String>> pumpScreen(WidgetTester tester) async {
    final pushed = <String>[];
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (c, _) => Scaffold(
            body: TextButton(onPressed: () => c.push('/live/gaming'), child: const Text('go')),
          ),
        ),
        GoRoute(path: '/live/gaming', builder: (_, _) => const GamingLivesScreen()),
        GoRoute(
          path: '/live/viewer/:id',
          builder: (_, s) {
            pushed.add('/live/viewer/${s.pathParameters['id']}');
            return const Scaffold(body: Text('viewer'));
          },
        ),
        GoRoute(
          path: '/live/setup',
          builder: (_, s) {
            pushed.add('/live/setup?mode=${s.uri.queryParameters['mode']}');
            return const Scaffold(body: Text('broadcast'));
          },
        ),
      ],
    );
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [studioFirestoreProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('go'));
    await settle(tester);
    return pushed;
  }

  testWidgets('lists only live gaming streams, newest first, and opens the viewer', (tester) async {
    await add('old', {
      'status': 'live',
      'liveKind': 'gaming',
      'title': 'Old run',
      'gameTitle': 'Ludo',
      'hostDisplayName': 'Ama',
      'viewerCount': 12,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
    await add('new', {
      'status': 'live',
      'liveKind': 'gaming',
      'title': 'Ranked push',
      'gameTitle': 'Free Fire',
      'hostDisplayName': 'Kofi',
      'viewerCount': 1500,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(2000),
    });
    await add('ended', {'status': 'ended', 'liveKind': 'gaming', 'title': 'Ended game'});
    await add('studio', {'status': 'live', 'title': 'Studio show'});

    final pushed = await pumpScreen(tester);
    expect(find.text('Ranked push'), findsOneWidget);
    expect(find.text('Old run'), findsOneWidget);
    expect(find.text('Free Fire'), findsOneWidget);
    expect(find.text('Kofi'), findsOneWidget);
    expect(find.text('1.5K'), findsOneWidget);
    expect(find.text('Ended game'), findsNothing);
    expect(find.text('Studio show'), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('gaming-live-new'))).dx <
          tester.getTopLeft(find.byKey(const ValueKey('gaming-live-old'))).dx,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('gaming-live-new')));
    await settle(tester);
    expect(pushed, ['/live/viewer/new']);

    // Back path: viewer → list → start.
    final ctx = tester.element(find.text('viewer'));
    GoRouter.of(ctx).pop();
    await settle(tester);
    expect(find.text('Gaming lives'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('empty state offers Go live with a game', (tester) async {
    await add('studio', {'status': 'live', 'title': 'Studio show'});
    final pushed = await pumpScreen(tester);
    expect(find.text(GamingLivesScreen.emptyText), findsOneWidget);
    await tester.tap(find.text(GamingLivesScreen.goLiveLabel));
    await settle(tester);
    expect(pushed, ['/live/setup?mode=gaming']);
  });

  test('GamingLive.fromDoc tolerates missing fields', () {
    final g = GamingLive.fromDoc('x', {'gameTitle': '  ', 'viewerCount': 'lots'});
    expect(g.gameTitle, isNull);
    expect(g.viewers, 0);
    expect(g.hostName, 'Oneova creator');
    expect(GamingLiveCard.viewersLabel(999), '999');
    expect(GamingLiveCard.viewersLabel(2500000), '2.5M');
  });
}
