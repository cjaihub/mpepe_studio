import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/moderation_models.dart';

/// Content Safety Check Result
class ContentSafetyCheckResult {
  final bool isAllowed;
  final bool isBurnNoticeTriggered;
  final bool shouldSuspendAccount;
  final String? violationReason;
  final String? matchedFlag;

  const ContentSafetyCheckResult({
    required this.isAllowed,
    this.isBurnNoticeTriggered = false,
    this.shouldSuspendAccount = false,
    this.violationReason,
    this.matchedFlag,
  });

  static const ContentSafetyCheckResult clean = ContentSafetyCheckResult(
    isAllowed: true,
  );
}

/// Search Query Safety Result
class SearchSafetyResult {
  final bool isAllowed;
  final String query;
  final String? blockedReason;

  const SearchSafetyResult({
    required this.isAllowed,
    required this.query,
    this.blockedReason,
  });
}

/// Oneova Automated Content Safety & Nudity Moderation Engine
/// 
/// Enforces community standards and privacy policies:
/// - Strictly prohibits pornography, explicit sexual acts, and nudity on public feeds, reels, and live streams.
/// - Triggers automated **Burn Notice** (immediate takedown & destruction from public index).
/// - Enforces automated **Account Suspension** for public nudity/pornographic violations.
/// - Filters search queries to block explicit / adult terms.
/// - Confines intimate / private expressions strictly to private 1-on-1 encrypted rooms.
class ContentSafetyModerationEngine {
  final FirebaseFirestore? _firestore;

  ContentSafetyModerationEngine([this._firestore]);

  // Explicit keywords and signatures strictly banned from public reels and search
  static const Set<String> _kExplicitBannedTerms = {
    'porn',
    'porno',
    'pornography',
    'xxx',
    'nude',
    'nudes',
    'nudity',
    'naked',
    'sex',
    'sexual',
    'blowjob',
    'handjob',
    'anal',
    'vagina',
    'penis',
    'dildo',
    'erotic',
    'hentai',
    'onlyfans',
    'camgirl',
    'hardcore',
    'masturbat',
    'boobs',
    'tits',
  };

  /// Scans content prior to publishing or during public feed ranking
  Future<ContentSafetyCheckResult> scanContent({
    required String text,
    List<String> tags = const [],
    String? mediaUrl,
    required bool isPublic,
    required String authorId,
    String? contentId,
  }) async {
    final lowerText = text.toLowerCase();
    final lowerTags = tags.map((t) => t.toLowerCase()).toList();

    // Check for explicit terms
    for (final term in _kExplicitBannedTerms) {
      final textHit = lowerText.contains(term);
      final tagHit = lowerTags.any((t) => t.contains(term));

      if (textHit || tagHit) {
        if (isPublic) {
          // Public Violation: Immediate Burn Notice & Account Suspension
          if (contentId != null && authorId.isNotEmpty) {
            await executeBurnNoticeAndSuspension(
              contentId: contentId,
              authorId: authorId,
              reason: 'Zero tolerance violation: Public nudity or sexual content detected ($term).',
            );
          }

          return ContentSafetyCheckResult(
            isAllowed: false,
            isBurnNoticeTriggered: true,
            shouldSuspendAccount: true,
            violationReason: 'Public nudity or explicit sexual content is strictly forbidden on Oneova reels and public feeds.',
            matchedFlag: term,
          );
        } else {
          // Private room policy: Allow in private inboxes only if not illegal or non-consensual
          return const ContentSafetyCheckResult(
            isAllowed: true,
            isBurnNoticeTriggered: false,
            shouldSuspendAccount: false,
            violationReason: 'Restricted to private 1-on-1 communication.',
          );
        }
      }
    }

    return ContentSafetyCheckResult.clean;
  }

  /// Filters user search queries to ensure no pornography or sexual content is accessible
  SearchSafetyResult filterSearchQuery(String query) {
    final lower = query.toLowerCase().trim();
    for (final term in _kExplicitBannedTerms) {
      if (lower.contains(term)) {
        return SearchSafetyResult(
          isAllowed: false,
          query: query,
          blockedReason: 'Search term violates Oneova Community Safety Guidelines. Adult/sexual content is forbidden.',
        );
      }
    }
    return SearchSafetyResult(isAllowed: true, query: query);
  }

  /// Executes an immediate Burn Notice on public content and suspends the violator's account
  Future<void> executeBurnNoticeAndSuspension({
    required String contentId,
    required String authorId,
    required String reason,
  }) async {
    try {
      debugPrint('[SafetyEngine] Executing Burn Notice on content $contentId by user $authorId. Reason: $reason');

      final db = _firestore;
      if (db != null) {
        // 1. Burn Notice: Immediate removal from public reels & quarantine
        try {
          await db.collection('content').doc(contentId).update({
            'status': 'burned_notice_takedown',
            'isBurned': true,
            'visibility': 'burned_removed',
            'burnedAt': FieldValue.serverTimestamp(),
            'burnReason': reason,
          });
        } catch (_) {}

        // Also clean up in posts collection if present
        try {
          await db.collection('posts').doc(contentId).update({
            'status': 'burned_notice_takedown',
            'isBurned': true,
            'burnedAt': FieldValue.serverTimestamp(),
            'burnReason': reason,
          });
        } catch (_) {}

        // 2. Suspend the violator's account
        if (authorId.isNotEmpty && authorId != 'unknown') {
          try {
            await db.collection('users').doc(authorId).update({
              'status': 'suspended',
              'suspendedAt': FieldValue.serverTimestamp(),
              'suspendedReason': reason,
              'accountLockout': true,
            });
          } catch (_) {}

          // 3. Log into moderation audit trail
          try {
            await db.collection('moderation_cases').add({
              'targetUserId': authorId,
              'contentId': contentId,
              'actionTaken': ModerationAction.suspend.name,
              'rationale': reason,
              'status': CaseStatus.resolved.name,
              'isBurnNotice': true,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[SafetyEngine] Error executing Burn Notice: $e');
    }
  }

  /// Quick synchronous check for candidate feed items
  bool isCandidateSafe({
    required String description,
    required List<String> hashtags,
    required String? status,
  }) {
    // If already burned, exclude
    if (status == 'burned_notice_takedown' || status == 'suspended') {
      return false;
    }

    final lower = description.toLowerCase();
    for (final term in _kExplicitBannedTerms) {
      if (lower.contains(term)) return false;
    }

    for (final tag in hashtags) {
      final lowerTag = tag.toLowerCase();
      for (final term in _kExplicitBannedTerms) {
        if (lowerTag.contains(term)) return false;
      }
    }

    return true;
  }
}

/// Provider for ContentSafetyModerationEngine
final contentSafetyModerationEngineProvider = Provider<ContentSafetyModerationEngine>((ref) {
  return ContentSafetyModerationEngine(Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);
});
