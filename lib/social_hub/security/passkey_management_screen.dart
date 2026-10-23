import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/passkey_auth_service.dart';
import '../../backend/security/security_audit_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import '../../shared/theme/app_theme.dart';

class PasskeyManagementScreen extends ConsumerWidget {
  const PasskeyManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passkeyService = ref.read(passkeyAuthServiceProvider);
    final auditService = ref.read(securityAuditServiceProvider);
    // ignore: unused_local_variable
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('Passkey Management', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: context.textPrimary),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FutureBuilder<bool>(
        future: passkeyService.isSupported(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
          }
          
          final isSupported = snapshot.data ?? false;
          
          return ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              Icon(Icons.fingerprint, size: 80, color: context.textPrimary),
              const SizedBox(height: 24),
              Text(
                'Passwordless Sign-In',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                'Use your device\'s Face ID, Touch ID, or screen lock to sign in securely without a password.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: context.textSecondary),
              ),
              const SizedBox(height: 40),
              
              if (!isSupported)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.border, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.brandPink),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your device does not support Passkeys.',
                          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () async {
                    if (user == null) return;
                    try {
                      await passkeyService.registerPasskey(
                        challenge: 'dummy-challenge-from-backend', 
                        relyingPartyId: 'oneova-studio.app',
                        relyingPartyName: 'Oneova Studio',
                        userId: user.uid,
                        userName: user.email ?? 'User',
                      );
                      
                      await auditService.logEvent(
                        userId: user.uid,
                        type: SecurityEventType.passkeyRegistered,
                        description: 'Registered a new Passkey for passwordless sign-in',
                        ipAddress: 'Unknown',
                        userAgent: 'OneovaStudio/Mobile',
                      );
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Passkey registered successfully!')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to register passkey: $e')),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Create a Passkey', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
            ],
          );
        },
      ),
    );
  }
}
