import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/studio_background.dart';
import 'mpepe_pin_screen.dart';
import '../services/pin_auth_service.dart';
import '../services/secure_logout_service.dart';

class WorkspaceLockedScreen extends ConsumerStatefulWidget {
  const WorkspaceLockedScreen({super.key});

  @override
  ConsumerState<WorkspaceLockedScreen> createState() => _WorkspaceLockedScreenState();
}

class _WorkspaceLockedScreenState extends ConsumerState<WorkspaceLockedScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isCheckingBiometrics = false;

  @override
  void initState() {
    super.initState();
    // Optionally trigger biometrics immediately on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBiometrics();
    });
  }

  Future<void> _checkBiometrics() async {
    if (_isCheckingBiometrics) return;
    setState(() => _isCheckingBiometrics = true);

    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (canAuthenticate) {
        try {
          final authenticated = await _localAuth.authenticate(
            localizedReason: 'Verify your identity to unlock Mpepe',
            biometricOnly: false,
            persistAcrossBackgrounding: true,
          );
          if (authenticated && mounted) {
            _onUnlockSuccess();
            return;
          }
        } on PlatformException {
          // Biometrics failed or cancelled
        }

        if (mounted) _showPinFallbackSheet();
      } else {
        if (mounted) _showPinFallbackSheet();
      }
    } on PlatformException catch (e) {
      debugPrint(e.toString());
      if (mounted) _showPinFallbackSheet();
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingBiometrics = false;
        });
      }
    }
  }

  void _showPinFallbackSheet() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 40,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ).animate().scale(delay: 50.ms, duration: 300.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 20),
                Text(
                  'Verify Identity',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ).animate().fade().slideY(begin: 0.2, end: 0, duration: 200.ms),
                const SizedBox(height: 8),
                Text(
                  'Enter your PIN to continue',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ).animate().fade(delay: 100.ms),
                const SizedBox(height: 32),
                
                MpepeButton(
                  text: 'Use PIN Code',
                  isPrimary: false,
                  icon: Icons.dialpad_rounded,
                  onPressed: () async {
                    Navigator.pop(context);
                    final success = await Navigator.push(
                      this.context,
                      MaterialPageRoute(
                        builder: (context) => const MpepePinScreen(mode: PinScreenMode.verify),
                      ),
                    );
                    if (success == true && mounted) {
                      _onUnlockSuccess();
                    }
                  },
                ).animate().fade(delay: 150.ms).slideY(begin: 0.1, end: 0, duration: 200.ms),
                const SizedBox(height: 12),
                
                MpepeButton(
                  text: 'Try Fingerprint Again',
                  isPrimary: false,
                  icon: Icons.fingerprint,
                  onPressed: () async {
                    Navigator.pop(context);
                    _checkBiometrics();
                  },
                ).animate().fade(delay: 200.ms).slideY(begin: 0.1, end: 0, duration: 200.ms),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onUnlockSuccess() {
    // Record that we became active now so the observer knows we are fresh
    ref.read(pinAuthServiceProvider).setLastActiveNow(); 
    // And go to home
    context.go('/hub/home');
  }

  Future<void> _logoutAndRedirect() async {
    await ref.read(secureLogoutServiceProvider).logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StudioBackground(
        child: Center(
          child: _isCheckingBiometrics 
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/logos/app_logo.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  Text(
                    'MPEPE STUDIO',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Workspace locked',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 40),
                  MpepeButton(
                    text: 'Unlock Workspace',
                    isPrimary: true,
                    icon: Icons.fingerprint,
                    onPressed: _checkBiometrics,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _logoutAndRedirect,
                        icon: Icon(Icons.switch_account_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), size: 18),
                        label: Text(
                          'Switch Account',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        height: 16,
                        width: 1,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                      TextButton.icon(
                        onPressed: _logoutAndRedirect,
                        icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8), size: 18),
                        label: Text(
                          'Logout',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ).animate().fade(delay: 200.ms),
                ],
              ),
        ),
      ),
    );
  }
}
