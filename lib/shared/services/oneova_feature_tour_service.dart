import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class OneovaTourStepModel {
  final String title;
  final String badge;
  final String description;
  final IconData icon;
  final Color accentColor;
  final String targetArea;

  const OneovaTourStepModel({
    required this.title,
    required this.badge,
    required this.description,
    required this.icon,
    required this.accentColor,
    required this.targetArea,
  });
}

class OneovaFeatureTourService {
  static const String _prefPrefix = 'oneova_feature_tour_completed_';

  static final List<OneovaTourStepModel> steps = [
    const OneovaTourStepModel(
      title: 'For You Reels',
      badge: 'REELS 01/07',
      description:
          'Dynamic full-screen reels curated for you. Auto-plays instantly with zero latency and background preloading.',
      icon: Icons.play_circle_filled_rounded,
      accentColor: AppColors.brandBlue,
      targetArea: 'top_feed',
    ),
    const OneovaTourStepModel(
      title: 'Following & Biz Feeds',
      badge: 'CHANNELS 02/07',
      description:
          'Switch easily between your favorite creator feeds and verified business storefronts in the top bar.',
      icon: Icons.storefront_rounded,
      accentColor: AppColors.brandPink,
      targetArea: 'top_channels',
    ),
    const OneovaTourStepModel(
      title: 'Search & Global Discovery',
      badge: 'EXPLORE 03/07',
      description:
          'Discover trending creators, viral sounds, hashtags, and inspiring content worldwide.',
      icon: Icons.search_rounded,
      accentColor: AppColors.brandBlue,
      targetArea: 'search_button',
    ),
    const OneovaTourStepModel(
      title: 'Creator Chat & Calling',
      badge: 'CHAT 04/07',
      description:
          'Encrypted direct messaging, voice notes, stickers, and fast reel sharing with your network.',
      icon: Icons.chat_bubble_rounded,
      accentColor: AppColors.brandPink,
      targetArea: 'nav_chat',
    ),
    const OneovaTourStepModel(
      title: 'STUDIO (+) Suite',
      badge: 'STUDIO 05/07',
      description:
          'Desktop-grade creative tools: color wheels, Lightroom tone curves, HSL mixers, and camera burst GIFs.',
      icon: Icons.add_circle_rounded,
      accentColor: AppColors.brandBlue,
      targetArea: 'nav_studio',
    ),
    const OneovaTourStepModel(
      title: 'AI Creative Lab',
      badge: 'AI LAB 06/07',
      description:
          'Remix, generate, and edit photos or videos using advanced multimodal AI models and natural conversation.',
      icon: Icons.auto_awesome_rounded,
      accentColor: AppColors.brandPink,
      targetArea: 'nav_ai',
    ),
    const OneovaTourStepModel(
      title: 'Profile & Security Vault',
      badge: 'ACCOUNT 07/07',
      description:
          'Manage your showcase portfolio, biometric passkeys, hardware security diagnostics, and private vault.',
      icon: Icons.person_rounded,
      accentColor: AppColors.brandBlue,
      targetArea: 'nav_me',
    ),
  ];

  Future<bool> shouldShowTour({String? uid}) async {
    final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    
    // Check local preferences first
    final localCompleted = prefs.getBool('$_prefPrefix$effectiveUid') ?? false;
    if (localCompleted) return false;

    // If logged in, cross-verify with Firestore profile
    if (effectiveUid != 'guest') {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(effectiveUid).get();
        if (doc.exists) {
          final data = doc.data() ?? {};
          final remoteCompleted = data['hasCompletedFeatureTour'] as bool? ?? false;
          if (remoteCompleted) {
            await prefs.setBool('$_prefPrefix$effectiveUid', true);
            return false;
          }
        }
      } catch (_) {}
    }

    return true;
  }

  Future<void> markTourCompleted({String? uid}) async {
    final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefPrefix$effectiveUid', true);

    if (effectiveUid != 'guest') {
      try {
        await FirebaseFirestore.instance.collection('users').doc(effectiveUid).set({
          'hasCompletedFeatureTour': true,
          'featureTourCompletedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> resetTour({String? uid}) async {
    final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$effectiveUid');

    if (effectiveUid != 'guest') {
      try {
        await FirebaseFirestore.instance.collection('users').doc(effectiveUid).set({
          'hasCompletedFeatureTour': false,
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }
}

final featureTourServiceProvider = Provider<OneovaFeatureTourService>((ref) {
  return OneovaFeatureTourService();
});

/// Controls whether the interactive feature tour is currently visible on screen
class FeatureTourVisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void show() => state = true;
  void hide() => state = false;
  void setVisible(bool val) => state = val;
}

final featureTourVisibilityProvider =
    NotifierProvider<FeatureTourVisibilityNotifier, bool>(() {
  return FeatureTourVisibilityNotifier();
});

/// Current active step of the feature tour (0..6)
class FeatureTourCurrentStepNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setStep(int step) => state = step;
  void next() => state = state + 1;
  void prev() => state = (state - 1).clamp(0, 99);
}

final featureTourCurrentStepProvider =
    NotifierProvider<FeatureTourCurrentStepNotifier, int>(() {
  return FeatureTourCurrentStepNotifier();
});
