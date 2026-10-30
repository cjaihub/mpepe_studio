import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' hide FirebaseService;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/security/login_security.dart';
import '../../backend/firebase_service.dart';
import '../../firebase_options.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/theme_provider.dart';
import '../widgets/ova_assistant_sheet.dart';

/// Runs the compact Ova overlay shown over other apps, the home screen and
/// the lock screen (Android `OvaAssistActivity`, Dart entrypoint
/// `ovaOverlayMain` in `main.dart`). Only the Ova panel runs here, not the
/// whole Oneova app; "Open Oneova" hands off to the full app.
Future<void> runOvaOverlayApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('[OvaOverlay] dotenv notice: $e');
  }
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (e) {
    debugPrint('[OvaOverlay] Firebase notice: $e');
  }
  FirebaseService.activateAppCheck().catchError((e) => debugPrint('[OvaOverlay] App Check notice: $e'));
  debugPrint('[OvaOverlay] runApp');
  runApp(const ProviderScope(child: OvaOverlayApp()));
}

class OvaOverlayApp extends ConsumerStatefulWidget {
  const OvaOverlayApp({super.key});

  @override
  ConsumerState<OvaOverlayApp> createState() => _OvaOverlayAppState();
}

class _OvaOverlayAppState extends ConsumerState<OvaOverlayApp> {
  static const _channel = MethodChannel('com.oneova.app/ova_overlay');

  bool _unlocked = false;
  bool _voiceMode = false;

  /// Bumped on every open so each one starts a fresh panel.
  int _session = 0;

  late final Future<bool> _signedIn = _checkAccount();

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShow') _apply(call.arguments, newSession: true);
    });
    _channel
        .invokeMethod<Map>('getLaunchState')
        .then((s) => _apply(s, newSession: false))
        .catchError((Object e) => debugPrint('[OvaOverlay] launch state: $e'));
  }

  void _apply(Object? state, {required bool newSession}) {
    debugPrint('[OvaOverlay] state $state');
    if (state is! Map || !mounted) return;
    setState(() {
      _unlocked = state['unlocked'] == true;
      _voiceMode = state['voiceMode'] == true;
      if (newSession) _session++;
    });
  }

  /// Ova only runs for an account that passed the two-check sign-in on this
  /// device, same rule as inside the app.
  Future<bool> _checkAccount() async {
    try {
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user == null) return false;
      await LoginSecurity.instance.restore();
      return LoginSecurity.instance.isVerified(user);
    } catch (e) {
      debugPrint('[OvaOverlay] account check: $e');
      return false;
    }
  }

  void _close() {
    HapticFeedback.lightImpact();
    _channel.invokeMethod('close');
  }

  void _openFullApp([String? route]) {
    HapticFeedback.selectionClick();
    _channel.invokeMethod('openFullApp', {'route': route});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oneova',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ref.watch(themeProvider),
      home: Builder(builder: _buildOverlay),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // The panel pads itself for the keyboard.
      resizeToAvoidBottomInset: false,
      body: !_unlocked
          // Locked: nothing is shown until the user unlocks.
          ? const SizedBox.expand()
          : Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: ColoredBox(color: AppColors.brandBlack.withValues(alpha: 0.35)),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FutureBuilder<bool>(
                    future: _signedIn,
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: 64),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                          ),
                        );
                      }
                      if (snap.data != true) return _SignInCard(onOpen: () => _openFullApp(), onClose: _close);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _OpenAppPill(onTap: () => _openFullApp()),
                          const SizedBox(height: 8),
                          OvaAssistantPanel(
                            key: ValueKey(_session),
                            isSheet: true,
                            autoStartVoice: _voiceMode,
                            onClose: _close,
                            onOpenRoute: _openFullApp,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// "Open Oneova" above the panel: hands off to the full app.
class _OpenAppPill extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenAppPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surface,
      shape: StadiumBorder(side: BorderSide(color: context.border, width: 1)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.open_in_new_rounded, size: 15, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Text(
                'Open full app',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when no verified Oneova account is signed in on this device.
class _SignInCard extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onClose;
  const _SignInCard({required this.onOpen, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.border, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_person_rounded, size: 18, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sign in to use Ova',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
                ),
              ],
            ),
            Text(
              'Ova works over other apps once you have signed in to Oneova on this phone.',
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: onOpen,
                child: Text(
                  'Open Oneova',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandWhite),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
