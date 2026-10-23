import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live/models/live_models.dart';
import 'package:oneova/social_hub/live/widgets/oneova_virtual_stage_room.dart';

void main() {
  final now = DateTime.now();
  final testStream = LiveStream(
    id: 'stream_stage_test',
    hostId: 'host_01',
    hostDisplayName: 'Oneova Streamer',
    hostAvatarUrl: '',
    title: '3D Amphitheater Stage Event',
    category: 'Showcase',
    type: LiveStreamType.multiGuest,
    status: LiveStreamStatus.live,
    stageScene: LiveStageScene.holographicStage,
    endpoint: LiveStreamEndpoint(
      keyExpiresAt: now.add(const Duration(days: 30)),
    ),
    viewerCount: 200000,
    createdAt: now,
    stageConfig: const LiveStageConfig(
      atmospherePreset: 'Neon Stadium',
      audioPreset: 'Studio HD',
    ),
  );

  testWidgets(
      'Renders OneovaVirtualStageRoom with 7 cove wall screens and goods table',
      (WidgetTester tester) async {
    bool showLoveTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OneovaVirtualStageRoom(
            stream: testStream,
            isHost: false,
            customLowerThird: 'SINGLE SEARCHING',
            onShowLove: () => showLoveTapped = true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify 7 Cove Wall screens are present (Host, Guests, Media Deck)
    expect(find.text('Oneova Streamer'), findsWidgets);
    expect(find.text('David K.'), findsOneWidget);
    expect(find.text('Elena Vance'), findsOneWidget);
    expect(find.text('Marcus Tech'), findsOneWidget);
    expect(find.text('Chloe Bloom'), findsOneWidget);
    expect(find.text('Media Desk Deck'), findsOneWidget);

    // 2. Verify "Presentation table for goods" holographic pedestal
    expect(find.textContaining('Presentation table'), findsOneWidget);

    // 3. Verify Left-Side "Request to join" button
    expect(find.text('Request\nto join'), findsOneWidget);

    // 4. Verify Right-Side "SHOW LOVE" button
    expect(find.text('SHOW\nLOVE'), findsOneWidget);

    // 5. Verify Ticker Text is rendered
    expect(find.text('SINGLE SEARCHING'), findsOneWidget);

    // 6. Tap "SHOW LOVE"
    await tester.tap(find.text('SHOW\nLOVE'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(showLoveTapped, isTrue);
  });

  testWidgets('Tapping Request to join triggers callback',
      (WidgetTester tester) async {
    bool requestJoinTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OneovaVirtualStageRoom(
            stream: testStream,
            isHost: false,
            onRequestToJoin: () => requestJoinTapped = true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Request\nto join'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(requestJoinTapped, isTrue);
  });

  testWidgets('Tapping Presentation table triggers callback',
      (WidgetTester tester) async {
    bool presentationTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OneovaVirtualStageRoom(
            stream: testStream,
            isHost: false,
            onTapPresentationTable: () => presentationTapped = true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.textContaining('Presentation table'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(presentationTapped, isTrue);
  });
}
