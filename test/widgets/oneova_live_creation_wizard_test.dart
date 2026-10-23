import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/social_hub/live/widgets/oneova_live_creation_wizard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestWidget({
    ValueChanged<OneovaLiveCreationConfig>? onStartBroadcast,
    VoidCallback? onClose,
    OneovaLiveCreationConfig? initialConfig,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: OneovaLiveCreationWizard(
          onStartBroadcast: onStartBroadcast,
          onClose: onClose,
          initialConfig: initialConfig,
        ),
      ),
    );
  }

  testWidgets('Renders Oneova Live Creation Wizard Step 1 with 3 controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 950));
    await tester.pumpWidget(createTestWidget());
    await tester.pump(const Duration(milliseconds: 200));

    // Check Header
    expect(find.text('Oneova Live Stage'), findsOneWidget);
    expect(find.text('Step 1 of 5 · Broadcast Identity & Topic'), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);

    // Control 1: Title & AI Suggestion Chips
    expect(find.text('BROADCAST TITLE'), findsOneWidget);
    expect(find.text('Late Night Jam'), findsWidgets);
    expect(find.text('Tech & Live Code'), findsOneWidget);
    expect(find.text('Creator Q&A'), findsOneWidget);

    // Tap first suggestion chip
    await tester.tap(find.text('Late Night Jam').first);
    await tester.pump(const Duration(milliseconds: 100));

    // Control 2: Categories
    expect(find.text('BROADCAST CATEGORY'), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Gaming'), findsOneWidget);
    expect(find.text('Tech'), findsOneWidget);
    expect(find.text('Entertainment'), findsOneWidget);
    expect(find.text('Biz'), findsOneWidget);

    // Tap Gaming category
    await tester.tap(find.text('Gaming'));
    await tester.pump(const Duration(milliseconds: 100));

    // Control 3: Audience Mode
    expect(find.text('AUDIENCE & PRIVACY MODE'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Followers Only'), findsOneWidget);
    expect(find.text('Private Room'), findsOneWidget);

    // Tap Next Step to navigate to Step 2
    await tester.tap(find.text('Next Step'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Check Step 2
    expect(find.text('Step 2 of 5 · Hosting Mode & Video Input'), findsOneWidget);
    expect(find.text('HOSTING ARCHITECTURE'), findsOneWidget);
    expect(find.text('Solo Broadcast'), findsOneWidget);
    expect(find.text('Multi-Host Room'), findsOneWidget);
    expect(find.text('PRIMARY VIDEO SOURCE'), findsOneWidget);
    expect(find.text('RESOLUTION & FRAMERATE'), findsOneWidget);

    // Switch hosting mode to Multi-Host Room
    await tester.tap(find.text('Multi-Host Room'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Viewer Join Requests'), findsOneWidget);

    // Navigate to Step 3: Studio Beauty & Retouch Filters
    await tester.tap(find.text('Next Step'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Step 3 of 5 · Studio Beauty & Retouch'), findsOneWidget);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
    expect(find.text('SKIN SMOOTHING & RETOUCH'), findsOneWidget);
    expect(find.text('STUDIO RING LIGHT & WARM GLOW'), findsOneWidget);
    expect(find.text('AI BACKGROUND & GREEN SCREEN'), findsOneWidget);

    // Tap Bokeh Blur filter
    await tester.tap(find.text('AI Bokeh Blur'));
    await tester.pump(const Duration(milliseconds: 100));

    // Navigate to Step 4: Live Media Desk & Atmosphere
    await tester.tap(find.text('Next Step'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Step 4 of 5 · Media Desk & Atmosphere'), findsOneWidget);
    expect(find.text('AI STAGE ATMOSPHERE PRESET'), findsOneWidget);
    expect(find.text('Neon Stadium'), findsWidgets);
    expect(find.text('Cyber-Cinema 7.1'), findsWidgets);
    expect(find.text('Acoustic Loft'), findsWidgets);
    expect(find.text('Cosmic Hologram'), findsWidgets);
    expect(find.text('BACKGROUND MUSIC / AUDIO STREAM'), findsOneWidget);
    expect(find.text('LOWER-THIRD GRAPHIC BANNER TICKER'), findsOneWidget);

    // Navigate to Step 5: Compliance, Regulations & Start Broadcast
    await tester.tap(find.text('Next Step'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Step 5 of 5 · Compliance & Regulations'), findsOneWidget);
    expect(find.text('Almost there!'), findsOneWidget);
    expect(find.text('CONTENT AUDIENCE RATING'), findsOneWidget);
    expect(find.text('All Ages'), findsWidgets);
    expect(find.text('18+ Mature'), findsOneWidget);
    expect(find.text('COPYRIGHT & FAIR-USE DECLARATION'), findsOneWidget);
    expect(find.text('CREATOR CONSENT & COMMUNITY SAFETY'), findsOneWidget);
    expect(find.text('Start Oneova Live Broadcast'), findsOneWidget);

    // Tap Guidelines modal link
    await tester.tap(find.text('View Guidelines & Policies →'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Oneova Live Broadcaster Standards'), findsOneWidget);
    expect(find.text('I Understand & Accept Guidelines'), findsOneWidget);

    // Accept Guidelines in modal
    await tester.tap(find.text('I Understand & Accept Guidelines'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Verify modal closed
    expect(find.text('Oneova Live Broadcaster Standards'), findsNothing);
  });

  testWidgets('Start Broadcast emits valid configuration when consent agreed',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 950));
    OneovaLiveCreationConfig? emittedConfig;

    await tester.pumpWidget(createTestWidget(
      onStartBroadcast: (cfg) => emittedConfig = cfg,
      initialConfig: const OneovaLiveCreationConfig(
        title: 'Oneova Special Event',
        creatorConsentAgreed: true,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // Fast-forward to step 5 by tapping Next Step 4 times
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.text('Next Step'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(find.text('Start Oneova Live Broadcast'), findsOneWidget);
    await tester.tap(find.text('Start Oneova Live Broadcast'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(emittedConfig, isNotNull);
    expect(emittedConfig!.title, 'Oneova Special Event');
    expect(emittedConfig!.creatorConsentAgreed, isTrue);
  });
}
