import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/feed/providers/oneova_focus_mode_provider.dart';
import 'package:oneova/hub/hub_ai_screen.dart';
import 'package:oneova/ova_assistant/main_interface/ova_live_voice_view.dart';
import 'package:oneova/ova_assistant/main_interface/ova_main_drawer.dart';
import 'package:oneova/ova_assistant/services/ova_shared_history_service.dart';
import 'package:oneova/ova_assistant/services/ova_task_center.dart';
import 'package:oneova/ova_assistant/services/ova_voice_session_controller.dart';
import 'package:oneova/ova_assistant/widgets/ova_assistant_sheet.dart';
import 'package:oneova/ova_assistant/widgets/ova_fluid_voice_orb.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});
  GoogleFonts.config.allowRuntimeFetching = false;

  Widget buildThemedApp({
    required Widget home,
    required ThemeData theme,
    ProviderContainer? container,
  }) {
    final app = MaterialApp(
      theme: theme,
      home: home,
    );
    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: app,
      );
    }
    return ProviderScope(child: app);
  }

  group('Unified Ova Shared History & Library Service', () {
    test('merges Main, Overlay, and Voice turns into shared threads & filters workspaces', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(ovaSharedHistoryProvider.notifier);

      final mainThreadId = await notifier.recordTurn(
        query: 'Plan my weekly creator calendar',
        response: 'Here is a 5-day reel and livestream plan.',
        source: OvaOriginSource.main,
        workspace: OvaWorkspaceId.work,
        persistToFirestore: false,
      );

      await notifier.recordTurn(
        query: 'Turn on flashlight',
        response: 'Flashlight is on.',
        source: OvaOriginSource.overlay,
        workspace: OvaWorkspaceId.personal,
        persistToFirestore: false,
      );

      await notifier.recordTurn(
        query: 'Help me plan a focused week around my priorities.',
        response: 'Absolutely. I am organizing your priorities now.',
        source: OvaOriginSource.voice,
        workspace: OvaWorkspaceId.research,
        persistToFirestore: false,
      );

      final state = container.read(ovaSharedHistoryProvider);
      expect(state.turns.length, 3);
      expect(state.threads.length, 3);
      expect(state.threadsForWorkspace(OvaWorkspaceId.work).length, 1);
      expect(state.threadsForWorkspace(OvaWorkspaceId.personal).length, 1);
      expect(state.threadsForWorkspace(OvaWorkspaceId.research).length, 1);

      // Save to library & delete thread
      await notifier.saveToLibrary(
        title: 'Weekly Creator Calendar',
        content: '5-day reel and livestream plan',
        category: 'Output',
        workspace: OvaWorkspaceId.work,
      );
      expect(container.read(ovaSharedHistoryProvider).library.length, 1);

      await notifier.deleteThread(mainThreadId);
      expect(container.read(ovaSharedHistoryProvider).threads.length, 2);
    });
  });

  group('Ova Main Interface (HubAiScreen) & Drawer', () {
    for (final mode in [('Light', AppTheme.lightTheme), ('Dark', AppTheme.darkTheme)]) {
      testWidgets('renders clean Ova Main Interface, drawer, sections & Live Voice in ${mode.$1} mode',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildThemedApp(
            home: const HubAiScreen(),
            theme: mode.$2,
            container: container,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Main Home interface elements
        expect(find.byType(OvaWordmark), findsOneWidget);
        expect(find.text('WORKSPACE TOOLS'), findsOneWidget);
        expect(find.text('Creative Studio'), findsOneWidget);
        expect(find.text('Weekly Planner'), findsOneWidget);
        expect(find.text('Script Breakdown'), findsOneWidget);
        expect(find.text('Live Voice'), findsOneWidget);

        // Open Slide-out OvaMainDrawer
        await tester.tap(find.byTooltip('Open Ova menu'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(OvaMainDrawer), findsOneWidget);
        expect(find.text('New chat'), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('AI Agents'), findsOneWidget);
        expect(find.text('Explore'), findsOneWidget);
        expect(find.text('Library'), findsOneWidget);
        expect(find.text('History'), findsOneWidget);
        expect(find.text('WORKSPACES'), findsOneWidget);
        expect(find.text('Work projects'), findsOneWidget);
        expect(find.text('Research'), findsOneWidget);
        expect(find.text('Settings'), findsOneWidget);

        // Switch to AI Agents section from drawer
        await tester.tap(find.descendant(of: find.byType(OvaMainDrawer), matching: find.text('AI Agents')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Creator Growth Coach'), findsOneWidget);

        // Enter dedicated Live Voice mode via header Voice pill
        expect(container.read(oneovaFocusModeProvider), isFalse);
        await tester.tap(find.text('Voice'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.byType(OvaLiveVoiceView), findsOneWidget);
        expect(find.byType(OvaFluidVoiceOrb), findsOneWidget);
        expect(find.text('Live Voice'), findsOneWidget);
        expect(find.text('Advanced'), findsOneWidget);
        expect(find.text('Captions'), findsOneWidget);
        expect(find.text('Audio'), findsOneWidget);
        expect(find.text("You're in a private voice session"), findsOneWidget);
        // Bottom nav focus mode enabled during full-screen Live Voice
        expect(container.read(oneovaFocusModeProvider), isTrue);

        // Toggle Captions & Audio inside Live Voice
        await tester.tap(find.text('Captions'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(container.read(ovaMainVoiceSessionProvider).captionsEnabled, isFalse);

        await tester.tap(find.text('Audio'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(container.read(ovaMainVoiceSessionProvider).audioEnabled, isFalse);

        // Back out of Live Voice -> restores Home & exits focus mode
        await tester.tap(find.byTooltip('Back'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(OvaLiveVoiceView), findsNothing);
        expect(container.read(oneovaFocusModeProvider), isFalse);
      });
    }
  });

  group('Separate Interfaces with Shared Histories & Activities', () {
    testWidgets('syncs shared histories & activities between Ova Main and Ova Overlay while keeping sessions separate',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Record one interaction from Overlay and one from Main + an activity in TaskCenter
      await container.read(ovaSharedHistoryProvider.notifier).recordTurn(
            query: 'Set a 10 minute studio break timer',
            response: 'Timer started for 10 minutes.',
            source: OvaOriginSource.overlay,
            persistToFirestore: false,
          );
      await container.read(ovaSharedHistoryProvider.notifier).recordTurn(
            query: 'Draft launch script for Oneova creator pack',
            response: 'Hook: Every creator needs a clean workflow.',
            source: OvaOriginSource.main,
            persistToFirestore: false,
          );
      final taskId = container.read(ovaTaskCenterProvider.notifier).start(
            'Analyze weekly engagement',
            source: 'ai_lab',
          );
      container.read(ovaTaskCenterProvider.notifier).finish(
            taskId,
            ok: true,
            summary: 'Engagement up 18%',
          );

      // 1. Mount Ova Main Interface -> sees both shared history entries on Home landing
      await tester.pumpWidget(
        buildThemedApp(
          home: const HubAiScreen(),
          theme: AppTheme.lightTheme,
          container: container,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('RECENT HISTORY & ACTIVITIES'), findsOneWidget);
      expect(find.textContaining('Set a 10 minute studio break timer'), findsOneWidget);
      expect(find.textContaining('Draft launch script for Oneova creator pack'), findsOneWidget);

      // 2. Mount Ova Overlay Assistant -> empty active chat (separate session!), but shows shared RECENT ACTIVITY
      await tester.pumpWidget(
        buildThemedApp(
          home: const Scaffold(
            body: OvaAssistantPanel(isSheet: false),
          ),
          theme: AppTheme.darkTheme,
          container: container,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('RECENT ACTIVITY'), findsOneWidget);
      expect(find.textContaining('Draft launch script for Oneova creator pack'), findsOneWidget);
      expect(find.textContaining('Analyze weekly engagement'), findsOneWidget);

      // Advance past OvaTaskCenter's 6s completion flash timer
      await tester.pump(const Duration(seconds: 7));
    });
  });

  group('Ova Overlay Assistant Voice Mode', () {
    for (final mode in [('Light', AppTheme.lightTheme), ('Dark', AppTheme.darkTheme)]) {
      testWidgets('switches cleanly between compact Chat and Voice mode in ${mode.$1} mode',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildThemedApp(
            home: const Scaffold(
              body: OvaAssistantPanel(isSheet: false),
            ),
            theme: mode.$2,
            container: container,
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Starts in quick Chat mode with [Chat | Voice] segmented switcher
        expect(find.text('Chat'), findsOneWidget);
        expect(find.text('Voice'), findsOneWidget);
        expect(find.byType(OvaOverlayVoiceCard), findsNothing);

        // Switch to Overlay Voice mode
        await tester.tap(find.text('Voice'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OvaOverlayVoiceCard), findsOneWidget);
        expect(find.text('Overlay Voice'), findsOneWidget);
        expect(find.byType(OvaFluidVoiceOrb), findsOneWidget);
        expect(find.text('Type instead'), findsOneWidget);

        // Pause & resume overlay voice session
        await tester.tap(find.byTooltip('Pause'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(container.read(ovaOverlayVoiceSessionProvider).isPaused, isTrue);

        // Switch back to text chat via 'Type instead'
        await tester.tap(find.text('Type instead'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byType(OvaOverlayVoiceCard), findsNothing);
        expect(find.text('Ask Ova or give a command'), findsOneWidget);
      });
    }
  });
}
