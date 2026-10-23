import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/security/login_security.dart';
import 'widgets/ova_floating_dock.dart';
import 'widgets/ova_gesture_detector.dart';
import 'services/ova_native_service.dart';
import '../widgets/oneova_assistant_overlay.dart';
import '../services/ai_assistant_service.dart';
import '../auth/services/app_lifecycle_observer.dart';

final ovaGestureEnabledProvider =
    NotifierProvider<OvaGestureEnabledNotifier, bool>(OvaGestureEnabledNotifier.new);

class OvaGestureEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;
}

final ovaDoubleTapEnabledProvider =
    NotifierProvider<OvaDoubleTapNotifier, bool>(OvaDoubleTapNotifier.new);

class OvaDoubleTapNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;
}

final ovaDrawOGestureEnabledProvider =
    NotifierProvider<OvaDrawOGestureNotifier, bool>(OvaDrawOGestureNotifier.new);

class OvaDrawOGestureNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;
}

final ovaFloatingTriggerEnabledProvider =
    NotifierProvider<OvaFloatingTriggerNotifier, bool>(OvaFloatingTriggerNotifier.new);

class OvaFloatingTriggerNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;
}

final ovaDrawOneGestureEnabledProvider =
    NotifierProvider<OvaDrawOneGestureNotifier, bool>(OvaDrawOneGestureNotifier.new);

class OvaDrawOneGestureNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEnabled(bool value) => state = value;
}

final ovaDoubleTapHoldEnabledProvider =
    NotifierProvider<OvaDoubleTapHoldNotifier, bool>(OvaDoubleTapHoldNotifier.new);

class OvaDoubleTapHoldNotifier extends Notifier<bool> {
  @override
  bool build() => false; // false = instant double-tap, true = require hold

  void setEnabled(bool value) => state = value;
}

final ovaTripleTapHoldEnabledProvider =
    NotifierProvider<OvaTripleTapHoldNotifier, bool>(OvaTripleTapHoldNotifier.new);

class OvaTripleTapHoldNotifier extends Notifier<bool> {
  @override
  bool build() => true; // Default enabled per user request

  void setEnabled(bool value) => state = value;
}

final ovaOnlyTripleTapHoldProvider =
    NotifierProvider<OvaOnlyTripleTapHoldNotifier, bool>(OvaOnlyTripleTapHoldNotifier.new);

class OvaOnlyTripleTapHoldNotifier extends Notifier<bool> {
  @override
  bool build() => false; // When true: ONLY 3 clicks with 3s hold can summon Ova (safe for home page reels feed)

  void setEnabled(bool value) => state = value;
}

final ovaHoldDurationSecondsProvider =
    NotifierProvider<OvaHoldDurationNotifier, int>(OvaHoldDurationNotifier.new);

class OvaHoldDurationNotifier extends Notifier<int> {
  @override
  int build() => 3; // Default 3 seconds per user request

  void setDuration(int seconds) => state = seconds;
}

final ovaVoiceCallModeEnabledProvider =
    NotifierProvider<OvaVoiceCallModeNotifier, bool>(OvaVoiceCallModeNotifier.new);

class OvaVoiceCallModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) => state = value;
}

/// Global wrapper that wraps any screen or root router builder, enabling:
/// 1. "Triple-Tap & Hold 3s" to summon Oneova Assistant (guaranteed conflict-free on home page feed).
/// 2. "Double-tap anywhere" to summon Oneova Assistant.
/// 3. "Draw O" circular stroke anywhere on the screen with Gemini-style screen vision.
/// 4. Background wake receiver so incoming intents / sleep-wake triggers pop up the overlay.
class OvaAssistantGlobalWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const OvaAssistantGlobalWrapper({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<OvaAssistantGlobalWrapper> createState() =>
      _OvaAssistantGlobalWrapperState();
}

class _OvaAssistantGlobalWrapperState
    extends ConsumerState<OvaAssistantGlobalWrapper> {
  final OvaNativeService _nativeService = OvaNativeService();

  @override
  void initState() {
    super.initState();
    _nativeService.initBackgroundWakeReceiver(([query]) {
      final targetContext = rootNavigatorKey.currentContext ?? context;
      final service = ref.read(oneOvaAssistantServiceProvider);
      final voiceCallMode = ref.read(ovaVoiceCallModeEnabledProvider);
      OneOvaAssistantOverlay.show(
        targetContext,
        service: service,
        autoStartVoice: voiceCallMode,
      );
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: LoginSecurity.instance,
        builder: (context, _) => _buildGuarded(context),
      );

  Widget _buildGuarded(BuildContext context) {
    final gestureEnabled = ref.watch(ovaGestureEnabledProvider);
    final doubleTapEnabled = ref.watch(ovaDoubleTapEnabledProvider);
    final drawOEnabled = ref.watch(ovaDrawOGestureEnabledProvider);
    final drawOneEnabled = ref.watch(ovaDrawOneGestureEnabledProvider);
    final doubleTapHoldEnabled = ref.watch(ovaDoubleTapHoldEnabledProvider);
    final tripleTapHoldEnabled = ref.watch(ovaTripleTapHoldEnabledProvider);
    final onlyTripleTapHold = ref.watch(ovaOnlyTripleTapHoldProvider);
    final holdDurationSeconds = ref.watch(ovaHoldDurationSecondsProvider);
    final voiceCallMode = ref.watch(ovaVoiceCallModeEnabledProvider);

    // The floating Ova bubble sits above every screen.
    final withDock = Stack(children: [widget.child, const OvaFloatingDock()]);

    // Ova gestures (and the tools behind them) stay off until the account
    // has passed the two-check sign-in on this device.
    final verified = LoginSecurity.instance.isVerified(FirebaseAuth.instance.currentUser);
    if (!gestureEnabled || !verified) {
      return withDock;
    }

    final service = ref.watch(oneOvaAssistantServiceProvider);

    return OvaGestureDetector(
      doubleTapEnabled: doubleTapEnabled,
      drawOGestureEnabled: drawOEnabled,
      drawOneGestureEnabled: drawOneEnabled,
      doubleTapHoldEnabled: doubleTapHoldEnabled,
      tripleTapHoldEnabled: tripleTapHoldEnabled,
      onlyTripleTapHold: onlyTripleTapHold,
      holdDurationSeconds: holdDurationSeconds,
      autoVoiceCallMode: voiceCallMode,
      onTriggerOvaWithContext: (screenBytes, circledRect) {
        final targetContext = rootNavigatorKey.currentContext ?? context;
        OneOvaAssistantOverlay.show(
          targetContext,
          service: service,
          screenContextBytes: screenBytes,
          screenContextLabel: "Circled Area",
          autoStartVoice: voiceCallMode,
        );
      },
      onTriggerOva: () {
        final targetContext = rootNavigatorKey.currentContext ?? context;
        OneOvaAssistantOverlay.show(
          targetContext,
          service: service,
          autoStartVoice: voiceCallMode,
        );
      },
      child: withDock,
    );
  }
}

