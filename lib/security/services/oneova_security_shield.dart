import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../auth/services/secure_logout_service.dart';

final oneovaSecurityShieldProvider = Provider<OneovaSecurityShield>((ref) {
  return OneovaSecurityShield(ref);
});

/// Oneova Security Shield
/// Protects users against phishing, external intent tampering, credential harvesting,
/// and malicious threats with automatic session termination and account isolation.
class OneovaSecurityShield {
  final Ref _ref;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // Known phishing patterns and lookalikes
  static final List<RegExp> _phishingPatterns = [
    RegExp(r'(0neova|one0va|oneovva|oneova-login|oneova-verify|mpepe-claim|free-coins-oneova)\.', caseSensitive: false),
    RegExp(r'https?://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?(/|$)', caseSensitive: false), // Raw IP addresses
    RegExp(r'[?&](password|passwd|token|pin|auth_bypass|secret_key)=', caseSensitive: false), // Credential harvesting params
    RegExp(r'data:text/html', caseSensitive: false), // Data URI injection
    RegExp(r'javascript:', caseSensitive: false), // Script execution
  ];

  OneovaSecurityShield(this._ref);

  /// Checks if a given URI or text contains phishing or malicious payload
  bool isThreat(String? input) {
    if (input == null || input.trim().isEmpty) return false;
    final lower = input.toLowerCase().trim();

    for (final pattern in _phishingPatterns) {
      if (pattern.hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// Evaluates an external deep link, QR code, or clipboard text
  bool validateSafeUrl(String url) {
    if (isThreat(url)) {
      return false;
    }

    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (!uri.isScheme('https') && !uri.isScheme('http'))) {
        return false;
      }
      // Legitimate official domains
      final host = uri.host.toLowerCase();
      if (host.endsWith('oneova.app') ||
          host.endsWith('oneova.web.app') ||
          host.endsWith('firebaseapp.com') ||
          host.endsWith('google.com') ||
          host.endsWith('youtube.com') ||
          host.endsWith('youtu.be') ||
          host.endsWith('tiktok.com')) {
        return true;
      }
      return true; // General external URL, subject to safe external browser
    } catch (_) {
      return false;
    }
  }

  /// Intercepts suspected phishing or session tampering attack:
  /// Revokes active session, purges local credentials, alerts the user,
  /// and routes safely back to the public Reel/Feed screen.
  Future<void> executeEmergencyLogout({
    required BuildContext context,
    required String threatDescription,
  }) async {
    debugPrint('[OneovaSecurityShield] EMERGENCY LOGOUT TRIGGERED: $threatDescription');

    try {
      // 1. Purge secure storage credentials & execute secure logout
      await _storage.deleteAll();
      await _ref.read(secureLogoutServiceProvider).logout();
    } catch (e) {
      debugPrint('[OneovaSecurityShield] error during emergency purge: $e');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }

    if (!context.mounted) return;

    // 3. Show high-visibility executive security dialog
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.brandPink, width: 1.5),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_rounded, color: AppColors.brandPink, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Security Shield Alert',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ctx.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A potential security or phishing anomaly was intercepted:',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: ctx.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ctx.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: ctx.border),
              ),
              child: Text(
                threatDescription,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandPink,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'To protect your data, wallet, and identity, your session was safely terminated. You can continue watching reels as a guest or sign in safely.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: ctx.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ctx.go('/hub/home');
            },
            child: const Text('Continue to Feed', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
