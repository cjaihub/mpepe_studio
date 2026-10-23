import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/ova_assistant/models/ova_context_model.dart';
import 'package:oneova/ova_assistant/services/ova_native_service.dart';
import 'package:oneova/ova_assistant/services/ova_context_service.dart';
import 'package:oneova/ova_assistant/services/ova_action_engine.dart';
import 'package:oneova/ova_assistant/widgets/ova_gesture_detector.dart';
import 'package:oneova/ova_assistant/screens/ova_trigger_settings_screen.dart';

void main() {
  group('Ova Assistant Data Models & Context', () {
    test('AssistantPersona contains Oneova, Ova, and Onyx', () {
      expect(AssistantPersona.all.length, 3);
      final names = AssistantPersona.all.map((p) => p.name).toList();
      expect(names, contains('Oneova'));
      expect(names, contains('Ova'));
      expect(names, contains('Onyx'));
    });

    test('PhoneContextState stores battery, network, and WhatsApp statuses', () {
      const state = PhoneContextState(
        batteryLevel: 0.95,
        isCharging: true,
        networkType: '4G LTE',
        unreadWhatsAppCount: 3,
      );

      expect(state.batteryLevel, 0.95);
      expect(state.isCharging, true);
      expect(state.networkType, '4G LTE');
      expect(state.unreadWhatsAppCount, 3);
    });
  });

  group('OvaActionEngine Phone Control & Awareness', () {
    late OvaNativeService nativeService;
    late OvaContextNotifier contextNotifier;
    late OvaActionEngine engine;

    setUp(() {
      nativeService = OvaNativeService();
      contextNotifier = OvaContextNotifier(nativeService);
      engine = OvaActionEngine(nativeService, contextNotifier);
    });

    test('Suggested chips match the Android home screenshot layout', () {
      final chips = engine.getSuggestedChips();
      expect(chips.length, 3);
      expect(chips[0].label, contains('Send my recent photo to mom'));
      expect(chips[1].label, contains('Plan a budget-friendly safari'));
      expect(chips[1].prefixBadge, 'NEW');
      expect(chips[2].label, contains('Check status updates on WhatsApp'));
    });

    test('Processes "Send my recent photo to mom on WhatsApp" action', () async {
      const context = PhoneContextState(
        recentPhotos: [
          RecentPhotoItem(
            id: 'photo_1',
            title: 'Family Studio Portrait',
            timeAgo: '10m ago',
            assetOrUrl: 'assets/images/oneova_logo.jpg',
          ),
        ],
      );

      final result = await engine.processCommand(
        prompt: 'Send my recent photo to mom on WhatsApp',
        persona: AssistantPersona.all.first,
        context: context,
      );

      expect(result.actionType, 'whatsapp_send');
      expect(result.actionData?['recipientName'], 'Mom ❤️');
      expect(result.actionData?['photoTitle'], 'Family Studio Portrait');
      expect(result.actionData?['phoneNumber'], isNotEmpty);
    });

    test('Processes "Plan a budget-friendly safari" action', () async {
      const context = PhoneContextState();

      final result = await engine.processCommand(
        prompt: 'Plan a budget-friendly safari',
        persona: AssistantPersona.all.first,
        context: context,
      );

      expect(result.actionType, 'safari_plan');
      expect(result.actionData?['budget'], contains('\$280'));
      expect(result.actionData?['days'], isNotEmpty);
    });

    test('Processes "Check status updates on WhatsApp" action', () async {
      const context = PhoneContextState(
        whatsappStatuses: [
          WhatsAppStatusItem(
            contactName: 'Mom ❤️',
            timeAgo: '20m ago',
            previewText: 'Cooking family dinner!',
          ),
        ],
      );

      final result = await engine.processCommand(
        prompt: 'Check status updates on WhatsApp',
        persona: AssistantPersona.all.first,
        context: context,
      );

      expect(result.actionType, 'whatsapp_status');
      final list = result.actionData?['statuses'] as List<dynamic>;
      expect(list.length, 1);
      expect(list.first['name'], 'Mom ❤️');
    });

    test('Processes device status inquiry', () async {
      const context = PhoneContextState(
        batteryLevel: 1.0,
        isCharging: false,
        networkType: '4G LTE',
      );

      final result = await engine.processCommand(
        prompt: "What's going on on my phone?",
        persona: AssistantPersona.all.first,
        context: context,
      );

      expect(result.text, contains('Battery: 100%'));
      expect(result.text, contains('4G LTE'));
    });
  });

  group('OvaGestureDetector Activation Gestures', () {
    testWidgets('Double-tap anywhere triggers Ova Assistant', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              showFloatingTrigger: false,
              doubleTapEnabled: true,
              drawOGestureEnabled: true,
              onTriggerOva: () {
                triggered = true;
              },
              child: const Center(child: Text('Main Content')),
            ),
          ),
        ),
      );

      // Perform double tap at center
      final center = tester.getCenter(find.text('Main Content'));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      expect(triggered, isTrue);
    });

    testWidgets('Drawing "O" circle gesture triggers Ova Assistant', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              showFloatingTrigger: false,
              doubleTapEnabled: true,
              drawOGestureEnabled: true,
              onTriggerOva: () {
                triggered = true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // Draw a circle of radius 60 centered at (200, 300)
      const center = Offset(200, 300);
      const radius = 60.0;
      final gesture = await tester.startGesture(center + const Offset(radius, 0));

      const steps = 32;
      for (int i = 1; i <= steps; i++) {
        final angle = (i / steps) * 2 * math.pi;
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        await gesture.moveTo(Offset(x, y));
        await tester.pump(const Duration(milliseconds: 5));
      }

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(triggered, isTrue);
    });

    testWidgets('Drawing "O" circle invokes onTriggerOvaWithContext exactly once with circled rect', (tester) async {
      int callbackCount = 0;
      Rect? capturedRect;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              drawOGestureEnabled: true,
              onTriggerOvaWithContext: (screenBytes, rect) {
                callbackCount++;
                capturedRect = rect;
              },
              onTriggerOva: () {
                callbackCount++;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      const center = Offset(200, 300);
      const radius = 60.0;
      final gesture = await tester.startGesture(center + const Offset(radius, 0));

      const steps = 32;
      for (int i = 1; i <= steps; i++) {
        final angle = (i / steps) * 2 * math.pi;
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        await gesture.moveTo(Offset(x, y));
        await tester.pump(const Duration(milliseconds: 5));
      }

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      // Fix 3x popup: must be called EXACTLY once!
      expect(callbackCount, 1);
      expect(capturedRect, isNotNull);
    });

    testWidgets('Drawing "1" vertical stroke triggers Ova Assistant', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              showFloatingTrigger: false,
              drawOneGestureEnabled: true,
              onTriggerOva: () {
                triggered = true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // Draw a vertical downward stroke from (200, 150) to (200, 320)
      final gesture = await tester.startGesture(const Offset(200, 150));
      for (int y = 160; y <= 320; y += 15) {
        await gesture.moveTo(Offset(200, y.toDouble()));
        await tester.pump(const Duration(milliseconds: 10));
      }

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(triggered, isTrue);
    });

    testWidgets('Double-tap and hold 3 seconds triggers Ova Assistant', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              showFloatingTrigger: false,
              doubleTapEnabled: true,
              doubleTapHoldEnabled: true,
              holdDurationSeconds: 1, // 1 second for fast test execution
              onTriggerOva: () {
                triggered = true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // First tap
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 50));

      // Second tap: press down and hold for > 1 second
      final gesture = await tester.startGesture(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 100));

      // Advance time past the 1-second hold threshold
      await tester.pump(const Duration(milliseconds: 1200));

      expect(triggered, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Triple-tap and hold 3 seconds triggers Ova Assistant', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              tripleTapHoldEnabled: true,
              holdDurationSeconds: 1, // 1 second for fast test execution
              onTriggerOva: () {
                triggered = true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // Tap 1
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 50));

      // Tap 2
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 50));

      // Tap 3: press down and hold for > 1 second
      final gesture = await tester.startGesture(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 100));

      // Advance time past the hold threshold
      await tester.pump(const Duration(milliseconds: 1200));

      expect(triggered, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('Safe Mode onlyTripleTapHold ignores double-tap and drawing gestures', (tester) async {
      bool triggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OvaGestureDetector(
              onlyTripleTapHold: true,
              tripleTapHoldEnabled: true,
              doubleTapEnabled: true,
              drawOGestureEnabled: true,
              holdDurationSeconds: 1,
              onTriggerOva: () {
                triggered = true;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // Perform a double tap - should NOT trigger in Safe Mode
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(triggered, isFalse);

      // Draw an "O" - should NOT trigger in Safe Mode
      const center = Offset(200, 300);
      const radius = 60.0;
      final circleGesture = await tester.startGesture(center + const Offset(radius, 0));
      for (int i = 1; i <= 32; i++) {
        final angle = (i / 32) * 2 * math.pi;
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        await circleGesture.moveTo(Offset(x, y));
        await tester.pump(const Duration(milliseconds: 5));
      }
      await circleGesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(triggered, isFalse);

      // Now perform Triple-Tap & Hold: should trigger cleanly!
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 50));

      final holdGesture = await tester.startGesture(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 1200));

      expect(triggered, isTrue);
      await holdGesture.up();
      await tester.pumpAndSettle();
    });

    test('OvaNativeService exposes overlay permission, system overlay controls, and settings methods', () async {
      final nativeService = OvaNativeService();
      expect(await nativeService.canDrawOverlays(), isTrue);
      expect(await nativeService.requestOverlayPermission(), isTrue);
      expect(await nativeService.wakeScreen(), isTrue);
      expect(await nativeService.startSystemOverlay(), isTrue);
      expect(await nativeService.stopSystemOverlay(), isTrue);
      expect(await nativeService.isSystemOverlayActive(), isFalse);
      expect(await nativeService.openAssistantSettings(), isFalse); // False in non-Android test env
      expect(await nativeService.openPowerButtonSettings(), isFalse);
    });

    testWidgets('OvaTriggerSettingsScreen renders tabs, switches, and interactive test pad', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: OvaTriggerSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header and Tabs
      expect(find.text('Ova Triggers & System Control'), findsOneWidget);
      expect(find.text('Triggers & Overlay'), findsOneWidget);
      expect(find.text('Conflict Solver & Test'), findsOneWidget);

      // Verify Trigger Options in first tab
      expect(find.text('Floating Assistant Over Apps'), findsOneWidget);
      expect(find.text('Draw "O" Circle Gesture'), findsOneWidget);
      expect(find.text('Draw "1" Vertical Stroke'), findsOneWidget);
      expect(find.text('Double-Tap Anywhere'), findsOneWidget);
      expect(find.textContaining('Safe Mode: Only Triple-Tap & Hold'), findsOneWidget);
      expect(find.text('Triple-Tap & Hold (3s)'), findsOneWidget);
      expect(find.textContaining('Double-Tap & Hold'), findsOneWidget);
      expect(find.text('Auto Voice Call Mode'), findsOneWidget);
      expect(find.text('Power / Side Key Hold'), findsOneWidget);
      expect(find.text('Quick Settings Tile ("Ask Ova")'), findsOneWidget);

      // Switch to Conflict Solver & Test tab
      await tester.tap(find.text('Conflict Solver & Test'));
      await tester.pumpAndSettle();

      expect(find.text('Gesture Conflict Solver Active'), findsOneWidget);
      expect(find.text('Edge Back Gestures (Android 10+)'), findsOneWidget);
      expect(find.text('INTERACTIVE STROKE TEST PAD'), findsOneWidget);
      expect(find.text('Draw an "O" or "1" shape below to test'), findsOneWidget);
    });
  });
}
