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
import 'shared/router.dart';
import 'backend/native_plugin_server.dart';
import 'backend/firebase_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'shared/widgets/floating_ai_orb.dart';
import 'desktop_agent/desktop_agent_app.dart';

/// Top-level FCM background message handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Google Sign-In v7: initialize the singleton before any sign-in calls ───
  await GoogleSignIn.instance.initialize();

  // ── Crashlytics: capture all Flutter framework errors ──────────────────────
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // ── App Check: protect backend resources ───────────────────────────────────
  await FirebaseService.activateAppCheck();

  // ── Remote Config: load feature flags before the UI starts ─────────────────
  await FirebaseService.instance.initRemoteConfig();

  // ── FCM background handler ──────────────────────────────────────────────────
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── Analytics: enable data collection ─────────────────────────────────────
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

  // Start the Native Plugin Server to allow desktop apps (like DaVinci) to connect
  NativePluginServer().start();

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
    runApp(const ProviderScope(child: DesktopAgentApp()));
  } else {
    runApp(const ProviderScope(child: MpepeStudioApp()));
  }
}


class MpepeStudioApp extends ConsumerStatefulWidget {
  const MpepeStudioApp({super.key});

  @override
  ConsumerState<MpepeStudioApp> createState() => _MpepeStudioAppState();
}

class _MpepeStudioAppState extends ConsumerState<MpepeStudioApp> with WidgetsBindingObserver {
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
      // Record background time
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('last_active_time', DateTime.now().millisecondsSinceEpoch);
      });
    } else if (state == AppLifecycleState.resumed) {
      // Only lock authenticated sessions
      if (FirebaseAuth.instance.currentUser == null) return;
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

    return MaterialApp.router(
      title: 'MPEPE Studio',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
