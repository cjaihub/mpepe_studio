import 'dart:io';
import 'dart:ui';
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
import 'backend/notifications/services/rich_notification_renderer.dart';
import 'backend/user_profile_completion_service.dart';
import 'social_hub/coins/incoming_gift_overlay.dart';
import 'package:media_kit/media_kit.dart';
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
import 'shared/navigation/android_back_handler.dart';
import 'looks/providers/looks_providers.dart';
import 'ova_assistant/overlay/ova_overlay_app.dart';
import 'shared/services/draft_store.dart';
import 'shared/services/play_update_service.dart';
import 'shared/services/auto_cache_cleaner.dart';

/// Top-level FCM background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  debugPrint('FCM background message: ${message.messageId}');
  // Incoming/cancelled calls ring natively (full-screen on the lock screen).
  if (await handleCallPushInBackground(message)) return;
  // Rich activity pushes (photo, grouping, Reply / Like / Follow back).
  await OneovaRichNotifications.showFromData(message.data);
}

/// Entrypoint of the compact Ova overlay shown over other apps and the lock
/// screen (Android `OvaAssistActivity`). Runs only the Ova panel.
@pragma('vm:entry-point')
Future<void> ovaOverlayMain() => runOvaOverlayApp();

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

  // Crashlytics: capture all Flutter framework errors and asynchronous Dart errors
  try {
    FlutterError.onError = (details) {
      // Keep the full stack in logcat so build errors can be traced.
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
      return true; // Prevents uncaught async exceptions from terminating the app process
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
    // Keeps caches small: old leftovers out, under a size budget (Settings → Storage).
    AutoCacheCleaner.instance.start();
  }

  // Background initialization of non-critical and network-dependent services
  _initBackgroundServices();
}

void _initBackgroundServices() {
  // serverClientId: the Web OAuth client, so per-user Gmail can get a
  // one-time server code (gmailConnect) and Google sign-in ID tokens match it.
  GoogleSignIn.instance
      .initialize(serverClientId: '90836164478-j7us06gelc2204aq103qvc1tcoa6nc5b.apps.googleusercontent.com')
      .catchError((e) {
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

  DraftStore.instance.init().catchError((e) {
    debugPrint('DraftStore init notice: $e');
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
    PlayUpdateService.instance.check();
    // A gentle, at most weekly note about missing profile details, sent once
    // the person has settled in rather than at launch.
    Future.delayed(const Duration(minutes: 2), () {
      if (mounted) ref.read(userProfileCompletionServiceProvider).nudgeIfIncomplete();
    });
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
      // Flush draft debounce timers immediately on backgrounding
      DraftStore.instance.flush();
      // Install a downloaded Play update in the background, never mid-call.
      if (state == AppLifecycleState.paused &&
          !ref.read(activeCallControllerProvider).isLive) {
        PlayUpdateService.instance.installIfDownloaded();
      }
      // Mark presence offline when app goes to background or closes
      try {
        ref.read(presenceServiceProvider).setOffline();
      } catch (_) {}
      // Record background time
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
      });
    } else if (state == AppLifecycleState.resumed) {
      PlayUpdateService.instance.check();
      // Mark presence online when app resumes
      try {
        ref.read(presenceServiceProvider).setOnline();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeProvider);
    ref.watch(looksUserBootstrapProvider);
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
          // Android Back → previous screen (not app exit); see the class doc.
          child: AndroidBackHandler(router: router, child: _buildOverlays(child)),
        );
      },
    );
  }

  Widget _buildOverlays(Widget? child) {
    return OneovaTouchGlowOverlay(
      child: OvaAssistantGlobalWrapper(
        child: CallOverlayManager(
          child: NotificationOverlayManager(
            child: IncomingGiftOverlay(
              child: OvaGuardWatcher(child: child ?? const SizedBox.shrink()),
            ),
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
