import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/security/login_security.dart';
import 'widgets/ova_floating_dock.dart';
import 'widgets/ova_gesture_detector.dart';
import 'services/ova_native_service.dart';
import 'services/ova_trigger_settings.dart';
import '../widgets/oneova_assistant_overlay.dart';
import '../services/ai_assistant_service.dart';
import '../auth/services/app_lifecycle_observer.dart';
import '../providers/settings_provider.dart';

final ovaGestureEnabledProvider =
    NotifierProvider<OvaGestureEnabledNotifier, bool>(OvaGestureEnabledNotifier.new);

class OvaGestureEnabledNotifier extends Notifier<bool> {
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

/// Global wrapper that wraps any screen or root router builder, enabling:
/// 1. "Draw O" circular stroke anywhere on the screen with Gemini-style screen vision.
/// 2. Background wake receiver so incoming intents / sleep-wake triggers pop up the overlay.
/// 3. Mirroring the Ova trigger settings to Android, where the system-wide
///    triggers (Ova handle, button shortcut, lock screen) run.
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
  String? _syncedTriggers;

  @override
  void initState() {
    super.initState();
    // Keep the native trigger config in step with the signed-in user's settings.
    ref.listenManual(settingsProvider, (_, next) {
      if (FirebaseAuth.instance.currentUser == null || !next.hasValue) return;
      final accessibility = next.value?['accessibility'];
      final payload = {
        ...ref.read(ovaTriggerSettingsProvider).toMap(),
        // Native "O" trail / summon animation falls back to a fade.
        'reduceMotion': accessibility is Map && accessibility['reduceMotion'] == true,
      };
      final key = payload.toString();
      if (key == _syncedTriggers) return;
      _syncedTriggers = key;
      _nativeService.syncTriggerConfig(payload);
    }, fireImmediately: true);
    _nativeService.initBackgroundWakeReceiver(([query]) {
      final targetContext = rootNavigatorKey.currentContext ?? context;
      final service = ref.read(oneOvaAssistantServiceProvider);
      final voiceCallMode = ref.read(ovaTriggerSettingsProvider).voiceMode;
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
    final triggers = ref.watch(ovaTriggerSettingsProvider);
    final voiceCallMode = triggers.voiceMode;

    // The floating Ova bubble sits above every screen.
    final withDock = Stack(children: [widget.child, const OvaFloatingDock()]);

    // Ova gestures (and the tools behind them) stay off until the account
    // has passed the two-check sign-in on this device.
    final verified = LoginSecurity.instance.isVerified(FirebaseAuth.instance.currentUser);
    if (!gestureEnabled || !triggers.drawO || !verified) {
      return withDock;
    }

    final service = ref.watch(oneOvaAssistantServiceProvider);

    return OvaGestureDetector(
      // Drawing "O" is the only touch trigger (the detector knows no other).
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

