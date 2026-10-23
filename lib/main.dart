import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'shared/router.dart';
import 'backend/native_plugin_server.dart';
import 'backend/firebase_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'shared/notifications/notification_overlay_manager.dart';
import 'desktop_agent/desktop_agent_app.dart';
import 'backend/inbox/providers/presence_service.dart';
import 'ova_assistant/ova_assistant_manager.dart';
import 'shared/design_system/oneova_touch_feedback.dart';
import 'social_hub/calling/widgets/call_overlay_manager.dart';
import 'backend/calling/providers/active_call_controller.dart';
import 'backend/calling/services/callkit_service.dart';
import 'social_hub/live/studio_v2/shell/studio_scope.dart';
import 'backend/dev/firebase_emulators.dart';
import 'security/widgets/ova_guard_watcher.dart';

/// Top-level FCM background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  debugPrint('FCM background message: ${message.messageId}');
  // Incoming/cancelled calls ring natively (full-screen on the lock screen).
  await handleCallPushInBackground(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('dotenv notice: $e');
  }

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase initializeApp notice: $e');
  }

  // Dev/test builds only (--dart-define=USE_EMULATORS=<host>).
  await connectFirebaseEmulatorsIfRequested();

  // Crashlytics: capture all Flutter framework errors
  try {
    FlutterError.onError = (details) {
      // Keep the full stack in logcat so build errors can be traced.
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
  } catch (e) {
    debugPrint('Crashlytics notice: $e');
  }

  // A widget that fails to build shows a quiet placeholder instead of the
  // full-screen red error page. The error is still logged and reported.
  ErrorWidget.builder = (details) => const _BuildErrorFallback();

  // Start the Native Plugin Server to allow OneOva Studio desktop apps to connect
  try {
    NativePluginServer().start();
  } catch (e) {
    debugPrint('NativePluginServer notice: $e');
  }

  // Launch UI immediately so Flutter renders first frame without blocking
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
    runApp(const ProviderScope(child: DesktopAgentApp()));
  } else {
    runApp(ProviderScope(overrides: liveStudioV2Overrides, child: const OneOvaApp()));
  }

  // Background initialization of non-critical and network-dependent services
  _initBackgroundServices();
}

void _initBackgroundServices() {
  GoogleSignIn.instance.initialize().catchError((e) {
    debugPrint('GoogleSignIn init notice: $e');
  });

  FirebaseService.activateAppCheck().catchError((e) {
    debugPrint('App Check notice: $e');
  });

  FirebaseService.instance.initRemoteConfig().catchError((e) {
    debugPrint('Remote Config notice: $e');
  });

  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('FCM notice: $e');
  }

  FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true).catchError((e) {
    debugPrint('Analytics notice: $e');
  });
}

class OneOvaApp extends ConsumerStatefulWidget {
  const OneOvaApp({super.key});

  @override
  ConsumerState<OneOvaApp> createState() => _OneOvaAppState();
}

typedef OneovaStudioApp = OneOvaApp;

class _OneOvaAppState extends ConsumerState<OneOvaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Mark presence offline when app goes to background or closes
      try {
        ref.read(presenceServiceProvider).setOffline();
      } catch (_) {}
      // Record background time
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
      });
    } else if (state == AppLifecycleState.resumed) {
      // Mark presence online when app resumes
      try {
        ref.read(presenceServiceProvider).setOnline();
      } catch (_) {}
      // Only lock authenticated sessions
      if (FirebaseAuth.instance.currentUser == null) return;
      // Never lock someone out of a ringing or ongoing call.
      if (ref.read(activeCallControllerProvider).isLive) return;
      SharedPreferences.getInstance().then((prefs) {
        final lastActive = prefs.getInt('last_active_time');
        if (lastActive == null) return;
        final elapsed = DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(lastActive));
        // 5-minute session timeout — locks from any screen inside the app
        if (elapsed.inMinutes >= 5) {
          ref.read(routerProvider).go('/auth/main_login');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);
    final settings = ref.watch(settingsProvider).value ?? const <String, dynamic>{};
    final appearance = settings['appearance'] as Map? ?? const {};
    final accessibility = settings['accessibility'] as Map? ?? const {};
    final textFactor = switch (appearance['textSize']) {
          'small' => 0.92,
          'large' => 1.10,
          'xlarge' => 1.20,
          _ => 1.0,
        } *
        (accessibility['largeText'] == true ? 1.12 : 1.0);

    return MaterialApp.router(
      title: 'Oneova',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Display preferences from Settings → Appearance / Accessibility.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(mq.textScaler.scale(1.0) * textFactor),
            boldText: mq.boldText || appearance['boldText'] == true,
            highContrast: mq.highContrast || accessibility['highContrast'] == true,
            disableAnimations: mq.disableAnimations || accessibility['reduceMotion'] == true,
          ),
          child: _buildOverlays(child),
        );
      },
    );
  }

  Widget _buildOverlays(Widget? child) {
    return OneovaTouchGlowOverlay(
      child: OvaAssistantGlobalWrapper(
        child: CallOverlayManager(
          child: NotificationOverlayManager(
            child: OvaGuardWatcher(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

/// Replaces Flutter's red "build failed" box. Works without a surrounding
/// MaterialApp (it can be inserted anywhere in the tree).
class _BuildErrorFallback extends StatelessWidget {
  const _BuildErrorFallback();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Icon(Icons.refresh_rounded, size: 18, color: AppColors.textMuted),
      ),
    );
  }
}
