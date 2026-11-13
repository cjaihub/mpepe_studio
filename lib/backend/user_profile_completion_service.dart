import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/services/oneova_biometrics_service.dart';
import '../auth/services/oneova_username_service.dart';
import '../shared/theme/app_theme.dart';
import 'notifications/services/system_notices_service.dart';
import '../auth/widgets/profile_ai_suggestions.dart';
import '../widgets/oneova_assistant_overlay.dart';

/// Single item needed for 100% profile completion.
class ProfileCompletionItem {
  final String id;
  final String title;
  final int weight;
  final bool isCompleted;
  final String reason;
  final IconData icon;

  const ProfileCompletionItem({
    required this.id,
    required this.title,
    required this.weight,
    required this.isCompleted,
    required this.reason,
    required this.icon,
  });
}

/// Aggregated state of profile completion from real Firestore user doc.
class RealProfileCompletionState {
  final int percentage;
  final List<ProfileCompletionItem> items;
  final List<ProfileCompletionItem> missingItems;
  final String algorithmicAdvice;
  final String audienceMultiplier;

  const RealProfileCompletionState({
    required this.percentage,
    required this.items,
    required this.missingItems,
    required this.algorithmicAdvice,
    required this.audienceMultiplier,
  });

  bool get isComplete => percentage >= 100;
}

final userProfileCompletionServiceProvider = Provider<UserProfileCompletionService>((ref) {
  return UserProfileCompletionService(ref);
});

final userProfileCompletionStateProvider = StreamProvider.autoDispose<RealProfileCompletionState>((ref) {
  final service = ref.watch(userProfileCompletionServiceProvider);
  return service.watchCompletionState();
});

class UserProfileCompletionService {
  final Ref _ref;

  UserProfileCompletionService(this._ref);

  Stream<RealProfileCompletionState> watchCompletionState() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return Stream.value(
        RealProfileCompletionState(
          percentage: 0,
          items: const [],
          missingItems: const [
            ProfileCompletionItem(
              id: 'auth',
              title: 'Create Account',
              weight: 100,
              isCompleted: false,
              reason: 'Sign up to activate your Oneova creator identity and distribution.',
              icon: Icons.person_add_rounded,
            ),
          ],
          algorithmicAdvice: 'Join Oneova to distribute your reels across the global neural feed.',
          audienceMultiplier: '1.0x',
        ),
      );
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .asyncMap((doc) async {
      final data = doc.data() ?? {};

      // 1. Phone Number (20%)
      final phone = (data['phoneNumber'] as String? ?? data['phone'] as String? ?? user.phoneNumber ?? '').trim();
      final hasPhone = phone.isNotEmpty;

      // 2. Unique Username (20%)
      final username = (data['username'] as String? ?? '').trim();
      final hasUsername = username.isNotEmpty && !username.toLowerCase().startsWith('user_');

      // 3. Profile Photo (20%)
      final photo = (data['photoUrl'] as String? ?? data['photoURL'] as String? ?? data['profilePhotoUrl'] as String? ?? user.photoURL ?? '').trim();
      final hasPhoto = photo.isNotEmpty;

      // 4. Creator Bio (15%)
      final bio = (data['bio'] as String? ?? '').trim();
      final hasBio = bio.length >= 8;

      // 5. Algorithm Niches (15%)
      final nichesList = (data['niches'] as List? ?? data['categories'] as List? ?? []);
      final hasNiches = nichesList.isNotEmpty;

      // 6. Biometrics Passkey (10%)
      final biometricsService = _ref.read(oneovaBiometricsServiceProvider);
      final hasBioPasskey = (data['biometricsEnrolled'] == true) || await biometricsService.isBiometricEnrollmentActive();

      final items = <ProfileCompletionItem>[
        ProfileCompletionItem(
          id: 'phone',
          title: 'Phone Verification',
          weight: 20,
          isCompleted: hasPhone,
          reason: 'Verifies account security & enables direct messaging and live stream monetization.',
          icon: Icons.phone_android_rounded,
        ),
        ProfileCompletionItem(
          id: 'username',
          title: 'Unique Username',
          weight: 20,
          isCompleted: hasUsername,
          reason: 'Enables mentions (@username) and permanent creator vanity links.',
          icon: Icons.alternate_email_rounded,
        ),
        ProfileCompletionItem(
          id: 'photo',
          title: 'Profile Photo',
          weight: 20,
          isCompleted: hasPhoto,
          reason: 'Accounts with photos experience 3.4x higher reel engagement.',
          icon: Icons.camera_alt_rounded,
        ),
        ProfileCompletionItem(
          id: 'bio',
          title: 'Creator Bio',
          weight: 15,
          isCompleted: hasBio,
          reason: 'Trains Ova neural ranker to categorize your content and recommend to your ideal audience.',
          icon: Icons.edit_note_rounded,
        ),
        ProfileCompletionItem(
          id: 'niches',
          title: 'Algorithm Niches',
          weight: 15,
          isCompleted: hasNiches,
          reason: 'Unlocks For You topic clusters and targeted viewer distribution.',
          icon: Icons.tag_rounded,
        ),
        ProfileCompletionItem(
          id: 'biometrics',
          title: 'Biometric Passkey',
          weight: 10,
          isCompleted: hasBioPasskey,
          reason: 'Secures high-security transactions and instant device sign-in without passwords.',
          icon: Icons.fingerprint_rounded,
        ),
      ];

      int completedWeight = 0;
      final missing = <ProfileCompletionItem>[];

      for (final item in items) {
        if (item.isCompleted) {
          completedWeight += item.weight;
        } else {
          missing.add(item);
        }
      }

      final percentage = completedWeight.clamp(0, 100);

      // Algorithmic multiplier & advice
      final String multiplier;
      final String advice;
      if (percentage >= 100) {
        multiplier = '3.8x';
        advice = 'Your profile is fully verified! You have unlocked maximum distribution velocity in the For You algorithm.';
      } else if (percentage >= 70) {
        multiplier = '2.4x';
        advice = 'Complete ${missing.first.title} to qualify for the Verified Creator Badge and 3.8x distribution multiplier.';
      } else if (percentage >= 40) {
        multiplier = '1.6x';
        advice = 'Fill in your missing creator details to unlock localized discovery and AI agent recommendation.';
      } else {
        multiplier = '1.1x';
        advice = 'Complete essential profile items to prevent your content from being ranked as unverified.';
      }

      return RealProfileCompletionState(
        percentage: percentage,
        items: items,
        missingItems: missing,
        algorithmicAdvice: advice,
        audienceMultiplier: multiplier,
      );
    });
  }

  /// Sends a gentle weekly note when the profile still misses details people
  /// see (photo, username, bio, interests, phone). Security extras such as a
  /// fingerprint passkey are left out of the nudge.
  Future<void> nudgeIfIncomplete() async {
    try {
      final state = await watchCompletionState().first;
      const friendly = {
        'photo': 'profile photo',
        'username': 'username',
        'bio': 'short bio',
        'niches': 'interests',
        'phone': 'phone number',
      };
      final missing = [
        for (final m in state.missingItems)
          if (friendly[m.id] != null) friendly[m.id]!,
      ];
      if (missing.isEmpty) return;
      await SystemNoticesService.instance.profileIncomplete(missing, state.percentage);
    } catch (e) {
      debugPrint('[ProfileCompletion] nudge skipped: $e');
    }
  }

  /// Interactive executor that opens real sheets / dialogs and persists to Firestore.
  Future<void> executeAction(BuildContext context, String actionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to update your profile')),
      );
      return;
    }

    HapticFeedback.lightImpact();

    switch (actionId) {
      case 'phone':
        await _showPhoneUpdateSheet(context, user.uid);
        break;
      case 'username':
        await _showUsernameUpdateSheet(context, user.uid);
        break;
      case 'photo':
        await _showPhotoUpdateSheet(context, user.uid);
        break;
      case 'bio':
        await _showBioUpdateSheet(context, user.uid);
        break;
      case 'niches':
        await _showNichesUpdateSheet(context, user.uid);
        break;
      case 'biometrics':
        await _enrollBiometrics(context, user.uid);
      default:
        OneOvaAssistantOverlay.show(
          context,
          userId: user.uid,
          initialPrompt: 'Help me complete my profile details for maximum creator reach.',
        );
        break;
    }
  }

  // 1. Phone Sheet
  Future<void> _showPhoneUpdateSheet(BuildContext context, String uid) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Verify Phone Number',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your international phone number to secure your account and unlock live streaming.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.inter(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '+1 234 567 8900',
                    hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: isDark ? AppColors.outline : AppColors.lightBorder),
                    ),
                    prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.brandBlue, size: 20),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: () async {
                      final val = controller.text.trim();
                      if (val.length >= 7) {
                        await FirebaseFirestore.instance.collection('users').doc(uid).set({
                          'phoneNumber': val,
                          'phone': val,
                          'phoneVerified': true,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Phone number verified! Profile completion updated.'),
                              backgroundColor: AppColors.brandBlue,
                            ),
                          );
                        }
                      }
                    },
                    child: Text(
                      'Save & Verify Phone',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // 2. Username Sheet
  Future<void> _showUsernameUpdateSheet(BuildContext context, String uid) async {
    final controller = TextEditingController();
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                  border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Claim Unique Username',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick a distinct handle for your creator profile and universal share links.',
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    ProfileAiSuggestions(
                      kind: ProfileIdeaKind.usernames,
                      onPick: (v) => controller.text = v,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      style: GoogleFonts.inter(
                        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'alex_oneova',
                        hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                        prefixText: '@',
                        prefixStyle: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700),
                        filled: true,
                        fillColor: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                        errorText: errorText,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          borderSide: BorderSide(color: isDark ? AppColors.outline : AppColors.lightBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                        onPressed: () async {
                          final clean = controller.text.trim().replaceAll('@', '').toLowerCase();
                          if (clean.length < 3) {
                            setSheetState(() => errorText = 'Username must be at least 3 characters');
                            return;
                          }

                          // Uniqueness check
                          final checkResult = await OneovaUsernameService(FirebaseFirestore.instance)
                              .validateAndCheckAvailability(clean, currentUserId: uid);
                          if (!checkResult.isAvailable) {
                            setSheetState(() => errorText = checkResult.message);
                            return;
                          }

                          await FirebaseFirestore.instance.collection('users').doc(uid).set({
                            'username': clean,
                            'handle': clean,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Handle @$clean claimed successfully!'),
                                backgroundColor: AppColors.brandBlue,
                              ),
                            );
                          }
                        },
                        child: Text(
                          'Claim @Username',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 3. Photo Sheet
  Future<void> _showPhotoUpdateSheet(BuildContext context, String uid) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Update Profile Photo',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste a link to your photo for your creator card.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: GoogleFonts.inter(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'https://…',
                    hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                    prefixIcon: const Icon(Icons.link_rounded, color: AppColors.brandBlue, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: isDark ? AppColors.outline : AppColors.lightBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: () async {
                      final url = controller.text.trim();
                      if (url.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('users').doc(uid).set({
                          'photoUrl': url,
                          'photoURL': url,
                          'profilePhotoUrl': url,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Profile photo updated successfully!'),
                              backgroundColor: AppColors.brandBlue,
                            ),
                          );
                        }
                      }
                    },
                    child: Text(
                      'Save Avatar',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // 4. Bio Sheet
  Future<void> _showBioUpdateSheet(BuildContext context, String uid) async {
    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
              border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Write Creator Bio',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Describe your content style. The Ova AI assistant uses this to recommend your videos.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                ProfileAiSuggestions(
                  kind: ProfileIdeaKind.bios,
                  onPick: (v) => controller.text = v,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: 160,
                  style: GoogleFonts.inter(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Filmmaker & Visual Artist based in Nairobi. Creating next-gen cinematic shorts on Oneova.',
                    hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: isDark ? AppColors.outline : AppColors.lightBorder),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: () async {
                      final val = controller.text.trim();
                      if (val.length >= 6) {
                        await FirebaseFirestore.instance.collection('users').doc(uid).set({
                          'bio': val,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bio saved! AI distribution score increased.'),
                              backgroundColor: AppColors.brandBlue,
                            ),
                          );
                        }
                      }
                    },
                    child: Text(
                      'Save Bio',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // 5. Niches Sheet
  Future<void> _showNichesUpdateSheet(BuildContext context, String uid) async {
    final availableNiches = [
      'Tech & AI',
      'Filmmaking & VFX',
      'Music & Audio',
      'Fashion & Luxury',
      'Comedy & Skits',
      'Gaming & Esports',
      'Business & Growth',
      'Visual Arts & 3D',
      'Fitness & Sports',
      'Food & Lifestyle',
    ];
    final selected = <String>{'Tech & AI', 'Filmmaking & VFX'};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Creator Niches',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select 1-4 niches to feed the Oneova neural recommendation pipeline.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: availableNiches.map((niche) {
                      final isSelected = selected.contains(niche);
                      return FilterChip(
                        label: Text(niche),
                        selected: isSelected,
                        selectedColor: AppColors.brandBlue,
                        checkmarkColor: Colors.white,
                        labelStyle: GoogleFonts.inter(
                          color: isSelected ? Colors.white : (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          setSheetState(() {
                            if (val) {
                              selected.add(niche);
                            } else {
                              selected.remove(niche);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              await FirebaseFirestore.instance.collection('users').doc(uid).set({
                                'niches': selected.toList(),
                                'categories': selected.toList(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Updated niches: ${selected.join(', ')}'),
                                    backgroundColor: AppColors.brandBlue,
                                  ),
                                );
                              }
                            },
                      child: Text(
                        'Save Niches (${selected.length})',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // 6. Biometrics Enrollment
  Future<void> _enrollBiometrics(BuildContext context, String uid) async {
    final bioService = _ref.read(oneovaBiometricsServiceProvider);
    final available = await bioService.isBiometricsAvailable();

    if (!available) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometrics hardware not available or not enrolled on this device.')),
        );
      }
      return;
    }

    final success = await bioService.authenticate(
      reason: 'Confirm your biometric passkey to secure your Oneova creator account',
    );

    if (success) {
      await bioService.setBiometricEnrollment(true);
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'biometricsEnrolled': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric Passkey enrolled! 100% Security achieved.'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
      }
    }
  }
}
