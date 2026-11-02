import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import '../../auth/screens/oneova_pin_screen.dart';
import '../../auth/services/oneova_biometrics_service.dart';
import '../../auth/services/oneova_biometric_lock_service.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../widgets/settings_kit.dart';

/// Privacy & Security Screen
/// Controls studio hardware biometric protection, fingerprint enrollment, 2FA, app PIN,
/// private account status, follow requests, interaction safeguards, and GDPR data export.
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
  final RelationshipRepository _relRepo = RelationshipRepository();

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

  Future<void> _handlePrivateAccountToggle(bool isPrivate, Map<String, dynamic> privacySettings) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: context.border, width: 1.0),
        ),
        title: Text(
          isPrivate ? 'Switch to Private Account?' : 'Switch to Public Account?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          isPrivate
              ? 'Only people you approve can see your photos, videos, and follow you. Existing followers will not be affected.'
              : 'Anyone on Oneova will be able to see your profile, photos, and videos. Pending follow requests will be automatically accepted.',
          style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isPrivate ? 'Switch to Private' : 'Switch to Public',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();

    try {
      // 1. Update Firestore user document directly
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isPrivate': isPrivate,
        'defaultPrivacyMode': isPrivate ? 'private' : 'public',
      });

      // 2. Update Settings state
      final command = UpdateSettingCommand(
        ref: ref,
        category: 'privacy',
        undoData: {'isPrivate': !isPrivate, 'publicProfile': isPrivate},
        data: {'isPrivate': isPrivate, 'publicProfile': !isPrivate},
        name: isPrivate ? 'Enable Private Account' : 'Enable Public Account',
      );
      ref.read(undoManagerProvider.notifier).executeAndRegister(command);

      if (mounted) {
        UndoSnackbar.show(context, ref, isPrivate ? 'Account is now Private' : 'Account is now Public');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update privacy: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
        final command = UpdateSettingCommand(
          ref: ref,
          category: 'privacy',
          undoData: {'requireBiometrics': false},
          data: {'requireBiometrics': true},
          name: 'Enable Biometrics',
        );
        ref.read(undoManagerProvider.notifier).executeAndRegister(command);
        ref.read(oneovaBiometricLockServiceProvider).setLockEnabled(true);

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
          ref.read(oneovaBiometricLockServiceProvider).setLockEnabled(false);
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
          backgroundColor: const Color(0xFF10B981),
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

  Future<void> _handleDeactivateAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: context.border, width: 1.0),
        ),
        title: Text(
          'Deactivate Account?',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary),
        ),
        content: Text(
          'Your profile, photos, videos, and comments will be hidden until you reactivate your account by logging back in.',
          style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary, height: 1.4),
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
            child: const Text('Deactivate', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'isDeactivated': true,
          'deactivatedAt': FieldValue.serverTimestamp(),
        });
        await FirebaseAuth.instance.signOut();
        if (mounted) context.go('/splash');
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: context.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: context.border, width: 1.0),
          ),
          title: Text(
            'Delete Account Permanently',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.brandPink),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This action is irreversible. All your posts, studio creations, messages, and followers will be permanently erased.',
                  style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 14),
                Text(
                  'Type DELETE to confirm:',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: textController,
                  onChanged: (_) => setModalState(() {}),
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: context.border),
                    ),
                  ),
                ),
              ],
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
              onPressed: textController.text.trim() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'isDeleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
          });
          await user.delete();
          if (mounted) context.go('/splash');
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Please re-login before deleting your account: $e'),
                backgroundColor: AppColors.brandPink,
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
          final bool isPrivate = privacySettings['isPrivate'] ?? false;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Biometric Hardware Card
              _buildBiometricHardwareCard(isBioRequired),
              const SizedBox(height: 16),

              // 2. Account Privacy (Private Account & Requests)
              _buildSettingsGroup(
                context,
                'Account Privacy',
                [
                  _buildCustomSwitchTile(
                    context: context,
                    icon: Icons.lock_outline_rounded,
                    title: 'Private Account',
                    subtitle: 'Only approved followers can see your posts and stories',
                    value: isPrivate,
                    showDivider: true,
                    onChanged: (val) => _handlePrivateAccountToggle(val, privacySettings),
                  ),
                  if (isPrivate)
                    StreamBuilder<int>(
                      stream: _relRepo.watchPendingFollowRequestsCount(currentUid),
                      builder: (context, countSnap) {
                        final count = countSnap.data ?? 0;
                        return _buildActionTile(
                          context,
                          Icons.group_add_outlined,
                          'Follow Requests',
                          count > 0 ? '$count pending approval' : 'Review requests to follow you',
                          true,
                          () => context.push('/settings/follow-requests'),
                          trailingBadge: count > 0 ? '$count' : null,
                        );
                      },
                    ),
                  _buildActionTile(
                    context,
                    Icons.block_rounded,
                    'Blocked Accounts',
                    'Manage users you\'ve blocked from viewing your content',
                    false,
                    () => context.push('/settings/blocked-users'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 3. Interactions & Content Safety
              _buildSettingsGroup(
                context,
                'Interactions & Safety',
                [
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.security_update_good_rounded,
                    'AI Offensive Words Blocker',
                    'Automatically filter toxic remarks, slurs, and spam comments',
                    'filterOffensiveComments',
                    true,
                  ),
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.alternate_email_rounded,
                    'Allow Mentions & Tags',
                    'Let other creators tag you in stories and post captions',
                    'allowMentions',
                    true,
                  ),
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.chat_bubble_outline_rounded,
                    'Direct Message Requests',
                    'Receive direct messages from creators you don\'t follow',
                    'allowDmRequests',
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 4. Activity & Presence
              _buildSettingsGroup(
                context,
                'Activity & Presence',
                [
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.fiber_manual_record_rounded,
                    'Show Activity Status',
                    'Allow accounts you follow to see when you are active on Oneova',
                    'showActivityStatus',
                    true,
                  ),
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.done_all_rounded,
                    'Read Receipts',
                    'Let others know when you have read their direct messages',
                    'readReceipts',
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 5. Hardware Biometric Security
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

              // 6. Passcodes, 2FA & Login Security
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
                    true,
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const OneovaPinScreen(mode: PinScreenMode.setup),
                        ),
                      );
                    },
                  ),
                  _buildActionTile(
                    context,
                    Icons.history_rounded,
                    'Login Activity',
                    'Every sign-in: device, place, method, failed tries',
                    true,
                    () => context.push('/settings/login-activity'),
                  ),
                  _buildActionTile(
                    context,
                    Icons.link_rounded,
                    'Sign-in Methods',
                    'Link your phone number and Google to one account',
                    false,
                    () => context.push('/settings/sign-in-methods'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 7. Data, Archive & Account Lifecycle
              _buildSettingsGroup(
                context,
                'Data Management & Lifecycle',
                [
                  _buildActionTile(
                    context,
                    Icons.cloud_download_rounded,
                    'Download Your Data',
                    'Request GDPR-compliant archive of all your content and messages',
                    true,
                    () => context.push('/settings/data-export'),
                  ),
                  _buildSwitch(
                    context,
                    ref,
                    privacySettings,
                    Icons.analytics_outlined,
                    'Share Analytics',
                    'Send anonymous rendering and stability telemetry',
                    'shareAnalytics',
                    true,
                  ),
                  _buildActionTile(
                    context,
                    Icons.pause_circle_outline_rounded,
                    'Deactivate Account',
                    'Temporarily hide your profile, reels, and comments',
                    true,
                    _handleDeactivateAccount,
                  ),
                  _buildActionTile(
                    context,
                    Icons.delete_forever_rounded,
                    'Delete Account',
                    'Permanently erase your account, creations, and followers',
                    false,
                    _handleDeleteAccount,
                    isDestructive: true,
                  ),
                ],
              ),
              const SizedBox(height: 32),
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

  Widget _buildCustomSwitchTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool showDivider,
    required ValueChanged<bool> onChanged,
  }) {
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
                  value: value,
                  onChanged: onChanged,
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
    VoidCallback onTap, {
    String? trailingBadge,
    bool isDestructive = false,
  }) {
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
                    color: isDestructive ? AppColors.brandPink.withValues(alpha: 0.1) : context.surfaceMid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDestructive ? AppColors.brandPink.withValues(alpha: 0.3) : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive ? AppColors.brandPink : AppColors.brandBlue,
                    size: 17,
                  ),
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
                          color: isDestructive ? AppColors.brandPink : context.textPrimary,
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
                if (trailingBadge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      trailingBadge,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
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
