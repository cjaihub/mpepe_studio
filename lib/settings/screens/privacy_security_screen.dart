import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import '../../auth/screens/oneova_pin_screen.dart';
import '../../auth/services/oneova_biometrics_service.dart';
import '../widgets/settings_kit.dart';

/// Privacy & Security Screen
/// Controls studio hardware biometric protection, fingerprint enrollment, 2FA, app PIN, and creator privacy.
/// Complies with universal dual-mode (Light/Dark), high-density compact scale, and instant auto-save.
class PrivacySecurityScreen extends ConsumerStatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  ConsumerState<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends ConsumerState<PrivacySecurityScreen> {
  BiometricCapability? _capability;
  bool _isLoadingBio = true;
  bool _isProcessingBioEnrollment = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricDiagnostics();
  }

  Future<void> _loadBiometricDiagnostics() async {
    try {
      final bioService = ref.read(oneovaBiometricsServiceProvider);
      final cap = await bioService.getCapabilityDetails();
      if (mounted) {
        setState(() {
          _capability = cap;
          _isLoadingBio = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBio = false);
      }
    }
  }

  Future<void> _handleBiometricToggle(bool enable, Map<String, dynamic> privacySettings) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to configure biometric security.')),
      );
      return;
    }

    final bioService = ref.read(oneovaBiometricsServiceProvider);

    if (enable) {
      setState(() => _isProcessingBioEnrollment = true);
      HapticFeedback.lightImpact();

      final result = await bioService.enrollUserBiometrics(
        userId: user.uid,
        userEmail: user.email ?? 'creator@oneova.app',
        displayName: user.displayName,
      );

      if (!mounted) return;
      setState(() => _isProcessingBioEnrollment = false);

      if (result.isSuccess) {
        HapticFeedback.mediumImpact();
        // Update Riverpod & Firestore setting
        final command = UpdateSettingCommand(
          ref: ref,
          category: 'privacy',
          undoData: {'requireBiometrics': false},
          data: {'requireBiometrics': true},
          name: 'Enable Biometrics',
        );
        ref.read(undoManagerProvider.notifier).executeAndRegister(command);

        await _loadBiometricDiagnostics();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_capability?.typeLabel ?? 'Fingerprint'} protection activated & profile bound.',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.brandBlue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          );
        }
      } else {
        HapticFeedback.vibrate();
        final errorMsg = result.errorMessage ?? 'Biometric enrollment canceled';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg, style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        );
      }
    } else {
      // Disabling Biometrics - Mandatory confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: context.border, width: 1.0),
          ),
          title: Text(
            'Disable Biometric Lock?',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          content: Text(
            'Disabling biometrics removes hardware protection. You will rely on password or app PIN to access Oneova.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: context.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: context.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disable', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        setState(() => _isProcessingBioEnrollment = true);
        final revokeResult = await bioService.revokeUserBiometrics(userId: user.uid);
        if (!mounted) return;
        setState(() => _isProcessingBioEnrollment = false);

        if (revokeResult.isSuccess) {
          final command = UpdateSettingCommand(
            ref: ref,
            category: 'privacy',
            undoData: {'requireBiometrics': true},
            data: {'requireBiometrics': false},
            name: 'Disable Biometrics',
          );
          ref.read(undoManagerProvider.notifier).executeAndRegister(command);
          await _loadBiometricDiagnostics();
          if (mounted) {
            UndoSnackbar.show(context, ref, 'Biometrics disabled');
          }
        }
      }
    }
  }

  Future<void> _testFingerprintSensor() async {
    HapticFeedback.selectionClick();
    final bioService = ref.read(oneovaBiometricsServiceProvider);

    final result = await bioService.authenticateWithDetails(
      reason: 'Testing Oneova hardware sensor verification',
      biometricOnly: true,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Fingerprint sensor test passed! Hardware verified.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981), // Emerald
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      );
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Sensor test not completed',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: AppColors.brandPink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Privacy & Security',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.topBarFg,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            _buildAutoSavePill(context),
          ],
        ),
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue),
        ),
        error: (e, s) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.brandPink)),
        ),
        data: (settings) {
          final privacySettings = settings['privacy'] as Map<String, dynamic>? ?? {};
          final bool isBioRequired = privacySettings['requireBiometrics'] ?? false;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Dedicated Hardware Biometric Protection Header
              _buildBiometricHardwareCard(isBioRequired),
              const SizedBox(height: 16),

              _buildSettingsGroup(
                context,
                'Account Security',
                [
                  _buildActionTile(
                    context,
                    Icons.history_rounded,
                    'Login activity',
                    'Every sign-in: device, place, method, failed tries',
                    true,
                    () => context.push('/settings/login-activity'),
                  ),
                  _buildActionTile(
                    context,
                    Icons.shield_rounded,
                    'Security & login',
                    'Ova Guard alerts, signed-in devices, fingerprint',
                    false,
                    () => context.push('/profile/security'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 2. Biometric Security Controls Group
              _buildSettingsGroup(
                context,
                'Hardware Biometric Security',
                [
                  _buildBiometricSwitchTile(
                    context,
                    isBioRequired: isBioRequired,
                    privacySettings: privacySettings,
                  ),
                  if (isBioRequired) ...[
                    _buildSwitch(
                      context,
                      ref,
                      privacySettings,
                      Icons.shield_outlined,
                      'Studio Vault Protection',
                      'Require biometric verification for 4K exports & payouts',
                      'vaultBiometrics',
                      true,
                    ),
                    _buildActionTile(
                      context,
                      Icons.fingerprint_rounded,
                      'Test Sensor & Credentials',
                      'Verify live hardware reading and response speed',
                      false,
                      _testFingerprintSensor,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // 3. Studio Access & Secondary Passcodes Group
              _buildSettingsGroup(
                context,
                'Studio Passcodes & 2FA',
                [
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.security_rounded,
                    'Two-Factor Auth (2FA)',
                    'Protect studio account with secondary confirmation',
                    'twoFactorEnabled',
                    true,
                  ),
                  _buildActionTile(
                    context,
                    Icons.dialpad_rounded,
                    'Change App PIN',
                    'Configure private 6-digit studio passcode',
                    false,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const OneovaPinScreen(mode: PinScreenMode.setup),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 4. Data & Creator Privacy
              _buildSettingsGroup(
                context,
                'Data & Creator Privacy',
                [
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.public_rounded,
                    'Public Profile',
                    'Allow discovery in explore & creator recommendations',
                    'publicProfile',
                    true,
                  ),
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.analytics_outlined,
                    'Share Analytics',
                    'Send anonymous rendering and stability telemetry',
                    'shareAnalytics',
                    false,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBiometricHardwareCard(bool isBioRequired) {
    final cap = _capability;
    final isReady = cap?.isReadyToAuthenticate ?? false;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isBioRequired ? AppColors.brandBlue.withValues(alpha: 0.5) : context.border,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isBioRequired
                  ? AppColors.brandBlue.withValues(alpha: 0.15)
                  : context.surfaceMid,
              shape: BoxShape.circle,
              border: Border.all(
                color: isBioRequired ? AppColors.brandBlue : context.border,
                width: 1.2,
              ),
            ),
            child: Icon(
              Icons.fingerprint_rounded,
              color: isBioRequired ? AppColors.brandBlue : context.textMuted,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cap?.typeLabel ?? 'Fingerprint Hardware',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isBioRequired
                            ? AppColors.brandBlue.withValues(alpha: 0.12)
                            : (isReady
                                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                : context.surfaceMid),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(
                          color: isBioRequired
                              ? AppColors.brandBlue.withValues(alpha: 0.4)
                              : (isReady ? const Color(0xFF10B981) : context.border),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        isBioRequired ? 'ACTIVE' : (isReady ? 'ENROLLED' : 'DEVICE LOCKED'),
                        style: GoogleFonts.inter(
                          fontSize: 9.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isBioRequired
                              ? AppColors.brandBlue
                              : (isReady ? const Color(0xFF10B981) : context.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isLoadingBio
                      ? 'Checking hardware cryptographic capabilities...'
                      : (cap?.statusDescription ?? 'Biometric hardware verified.'),
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    color: context.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricSwitchTile(
    BuildContext context, {
    required bool isBioRequired,
    required Map<String, dynamic> privacySettings,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isBioRequired ? AppColors.brandBlue.withValues(alpha: 0.15) : context.surfaceMid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isBioRequired ? AppColors.brandBlue : context.border,
                    width: 1.0,
                  ),
                ),
                child: Icon(Icons.fingerprint_rounded,
                    color: isBioRequired ? AppColors.brandBlue : context.textMuted, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Require ${_capability?.typeLabel ?? 'Fingerprint'}',
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Authenticate with hardware biometrics on launch & resume',
                      style: GoogleFonts.inter(
                        fontSize: 11.0,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isProcessingBioEnrollment)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                )
              else
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: isBioRequired,
                    onChanged: (newVal) => _handleBiometricToggle(newVal, privacySettings),
                    activeThumbColor: AppColors.brandBlue,
                    activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: context.border, indent: 58, endIndent: 14),
      ],
    );
  }

  Widget _buildAutoSavePill(BuildContext context) {
    return const SettingsSaveIndicator();
  }

  Widget _buildSettingsGroup(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> privacySettings,
    IconData icon,
    String title,
    String subtitle,
    String key,
    bool showDivider,
  ) {
    final bool oldValue = privacySettings[key] ?? false;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(icon, color: AppColors.brandBlue, size: 17),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11.0,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: oldValue,
                  onChanged: (newVal) {
                    final command = UpdateSettingCommand(
                      ref: ref,
                      category: 'privacy',
                      undoData: {key: oldValue},
                      data: {key: newVal},
                      name: 'Toggle $title',
                    );
                    ref.read(undoManagerProvider.notifier).executeAndRegister(command);
                    UndoSnackbar.show(context, ref, '$title ${newVal ? 'enabled' : 'disabled'}');
                  },
                  activeThumbColor: AppColors.brandBlue,
                  activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: context.border, indent: 58, endIndent: 14),
      ],
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    bool showDivider,
    VoidCallback onTap,
  ) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: Icon(icon, color: AppColors.brandBlue, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 13.0,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11.0,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: context.border, indent: 58, endIndent: 14),
      ],
    );
  }
}
