import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import '../../auth/services/oneova_biometrics_service.dart';
import '../../shared/services/oneova_feature_tour_service.dart';
import '../widgets/settings_kit.dart';

/// Profile Settings Screen
/// Controls public creator name, stage handle, and bio.
/// Features continuous auto-save with debouncing and universal dual-mode support.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _initialized = false;
  Timer? _debounce;
  late Map<String, dynamic> _lastSavedProfile;

  @override
  void dispose() {
    _debounce?.cancel();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _onTextChanged(Map<String, dynamic> currentProfile) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _autoSave(currentProfile);
    });
  }

  void _autoSave(Map<String, dynamic> currentProfile) {
    final newProfile = {
      ...currentProfile,
      'displayName': _displayNameController.text.trim(),
      'bio': _bioController.text.trim(),
    };

    if (newProfile['displayName'] == _lastSavedProfile['displayName'] &&
        newProfile['bio'] == _lastSavedProfile['bio']) {
      return;
    }

    final command = UpdateSettingCommand(
      ref: ref,
      category: 'profile',
      undoData: _lastSavedProfile,
      data: newProfile,
      name: 'Update Profile',
    );

    ref.read(undoManagerProvider.notifier).executeAndRegister(command);
    _lastSavedProfile = newProfile;

    UndoSnackbar.show(context, ref, 'Profile auto-saved');
  }

  Widget _buildAutoSavePill(BuildContext context) {
    return const SettingsSaveIndicator();
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
              'Profile Settings',
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
          final profile = settings['profile'] as Map<String, dynamic>? ?? {};
          if (!_initialized) {
            _lastSavedProfile = profile;
            _displayNameController.text = profile['displayName'] ?? '';
            _bioController.text = profile['bio'] ?? '';
            _initialized = true;
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DISPLAY NAME',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _displayNameController,
                      onChanged: (_) => _onTextChanged(profile),
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w500,
                        color: context.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Your creator name or handle',
                        hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                        filled: true,
                        fillColor: context.surfaceMid,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: context.border, width: 1.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: context.border, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'CREATOR BIO',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bioController,
                      onChanged: (_) => _onTextChanged(profile),
                      maxLines: 4,
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w400,
                        color: context.textPrimary,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Tell your audience and collaborators about yourself...',
                        hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                        filled: true,
                        fillColor: context.surfaceMid,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: context.border, width: 1.0),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: context.border, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Profile Security & Hardware Authentication
              FutureBuilder<BiometricCapability>(
                future: ref.read(oneovaBiometricsServiceProvider).getCapabilityDetails(),
                builder: (context, snapshot) {
                  final cap = snapshot.data;
                  final hasHardware = cap?.isHardwareAvailable ?? false;
                  final isReady = cap?.hasEnrolledBiometrics ?? false;

                  return Container(
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'HARDWARE SECURITY & PASSKEY',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: AppColors.brandBlue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isReady ? const Color(0xFF10B981).withValues(alpha: 0.12) : AppColors.brandBlue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                                border: Border.all(
                                  color: isReady ? const Color(0xFF10B981) : AppColors.brandBlue.withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isReady ? 'HARDWARE BOUND' : (hasHardware ? 'SENSOR READY' : 'NO SENSOR'),
                                style: GoogleFonts.inter(
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: isReady ? const Color(0xFF10B981) : AppColors.brandBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => context.push('/settings/privacy'),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: Border.all(color: context.border, width: 1.0),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.brandBlue, width: 1.0),
                                  ),
                                  child: const Icon(Icons.fingerprint_rounded, color: AppColors.brandBlue, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cap?.typeLabel ?? 'Biometric Fingerprint Protection',
                                        style: GoogleFonts.inter(
                                          fontSize: 13.0,
                                          fontWeight: FontWeight.w700,
                                          color: context.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        cap?.statusDescription ?? 'Hardware keystore credential binding & instant 1-tap unlock',
                                        style: GoogleFonts.inter(
                                          fontSize: 11.0,
                                          color: context.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.brandBlue),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // App Feature Walkthrough & Interactive Tour
              Container(
                decoration: AppDecorations.groupedSection(context),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FEATURE WALKTHROUGH',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.brandPink,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        await ref.read(featureTourServiceProvider).resetTour();
                        if (context.mounted) {
                          ref.read(featureTourCurrentStepProvider.notifier).setStep(0);
                          ref.read(featureTourVisibilityProvider.notifier).show();
                          context.go('/hub/home');
                        }
                      },
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                                color: AppColors.brandPink,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Replay Interactive Feature Tour',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.0,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Launch the compact animated bubble guide across all app screens',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.0,
                                      color: context.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.play_circle_fill_rounded, size: 20, color: AppColors.brandPink),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Changes are automatically committed to the Oneova cloud registry as you type.',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    color: context.textMuted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
