import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final oneovaUsernameServiceProvider = Provider<OneovaUsernameService>((ref) {
  return OneovaUsernameService(FirebaseFirestore.instance);
});

enum UsernameValidationStatus {
  valid,
  tooShort,
  tooLong,
  invalidCharacters,
  consecutiveDots,
  reserved,
  taken,
  checking,
}

enum OneovaBadgeType {
  none,
  verifiedCreator,
  verifiedBusiness,
  vipOfficial,
}

class UsernameCheckResult {
  final UsernameValidationStatus status;
  final String? message;
  final bool isAvailable;
  final OneovaBadgeType potentialBadge;

  const UsernameCheckResult({
    required this.status,
    this.message,
    required this.isAvailable,
    this.potentialBadge = OneovaBadgeType.none,
  });

  bool get isValidAndAvailable => status == UsernameValidationStatus.valid && isAvailable;
}

class OneovaUsernameService {
  final FirebaseFirestore _firestore;

  OneovaUsernameService([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const List<String> _reservedHandles = [
    'oneova',
    'oneova_official',
    'oneova_admin',
    'oneova_support',
    'oneova_security',
    'oneova_app',
    'admin',
    'root',
    'support',
    'help',
    'security',
    'official',
    'verified',
    'billing',
    'moderator',
    'safety',
    'legal',
    'tiktok',
    'instagram',
    'whatsapp',
    'youtube',
  ];

  /// Validates format locally and checks availability in Firestore.
  Future<UsernameCheckResult> validateAndCheckAvailability(
    String rawUsername, {
    String? currentUserId,
    String? accountType, // 'creator', 'business', 'personal'
  }) async {
    final clean = rawUsername.trim().toLowerCase();

    // 1. Length checks
    if (clean.length < 3) {
      return const UsernameCheckResult(
        status: UsernameValidationStatus.tooShort,
        message: 'Username must be at least 3 characters.',
        isAvailable: false,
      );
    }
    if (clean.length > 24) {
      return const UsernameCheckResult(
        status: UsernameValidationStatus.tooLong,
        message: 'Username must be 24 characters or less.',
        isAvailable: false,
      );
    }

    // 2. Format checks (alphanumeric, underscore, dot)
    final formatRegex = RegExp(r'^[a-z0-9_.]+$');
    if (!formatRegex.hasMatch(clean)) {
      return const UsernameCheckResult(
        status: UsernameValidationStatus.invalidCharacters,
        message: 'Only lowercase letters, numbers, underscores, and dots are allowed.',
        isAvailable: false,
      );
    }

    if (clean.startsWith('.') || clean.endsWith('.')) {
      return const UsernameCheckResult(
        status: UsernameValidationStatus.invalidCharacters,
        message: 'Username cannot start or end with a period.',
        isAvailable: false,
      );
    }

    if (clean.contains('..')) {
      return const UsernameCheckResult(
        status: UsernameValidationStatus.consecutiveDots,
        message: 'Consecutive periods are not allowed.',
        isAvailable: false,
      );
    }

    // 3. Reserved handles check
    if (_reservedHandles.contains(clean)) {
      return const UsernameCheckResult(
        status: UsernameValidationStatus.reserved,
        message: 'This username is reserved by Oneova.',
        isAvailable: false,
      );
    }

    // 4. Remote Firestore uniqueness check
    try {
      final query = await _firestore
          .collection('users')
          .where('username', isEqualTo: clean)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final existingDoc = query.docs.first;
        if (currentUserId != null && existingDoc.id == currentUserId) {
          // User already owns this username
          return UsernameCheckResult(
            status: UsernameValidationStatus.valid,
            message: 'Current handle.',
            isAvailable: true,
            potentialBadge: _calculatePotentialBadge(accountType),
          );
        }

        return const UsernameCheckResult(
          status: UsernameValidationStatus.taken,
          message: 'Username is already taken by another creator.',
          isAvailable: false,
        );
      }

      // Also check dedicated usernames registry if present
      final reservationDoc = await _firestore.collection('usernames').doc(clean).get();
      if (reservationDoc.exists) {
        final reservedUid = reservationDoc.data()?['uid'];
        if (currentUserId != null && reservedUid == currentUserId) {
          return UsernameCheckResult(
            status: UsernameValidationStatus.valid,
            message: 'Reserved for you.',
            isAvailable: true,
            potentialBadge: _calculatePotentialBadge(accountType),
          );
        }

        return const UsernameCheckResult(
          status: UsernameValidationStatus.taken,
          message: 'Username is already taken.',
          isAvailable: false,
        );
      }

      return UsernameCheckResult(
        status: UsernameValidationStatus.valid,
        message: 'Username is available!',
        isAvailable: true,
        potentialBadge: _calculatePotentialBadge(accountType),
      );
    } catch (e) {
      // In case of network timeout/offline, allow if format is strictly valid
      return UsernameCheckResult(
        status: UsernameValidationStatus.valid,
        message: 'Format verified.',
        isAvailable: true,
        potentialBadge: _calculatePotentialBadge(accountType),
      );
    }
  }

  /// Reserves username for the given user in Firestore.
  Future<void> claimUsername(String userId, String username) async {
    final clean = username.trim().toLowerCase();
    final usernameRef = _firestore.collection('usernames').doc(clean);
    final userRef = _firestore.collection('users').doc(userId);

    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(usernameRef);
      if (doc.exists) {
        final currentOwner = doc.data()?['uid'];
        if (currentOwner != null && currentOwner != userId) {
          throw Exception('Username was claimed by someone else.');
        }
      }

      tx.set(usernameRef, {
        'uid': userId,
        'username': clean,
        'claimedAt': FieldValue.serverTimestamp(),
      });

      tx.update(userRef, {
        'username': clean,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  OneovaBadgeType _calculatePotentialBadge(String? accountType) {
    if (accountType == 'business' || accountType == 'Brand / Business') {
      return OneovaBadgeType.verifiedBusiness;
    } else if (accountType == 'creator' || accountType == 'Creator / Influencer') {
      return OneovaBadgeType.verifiedCreator;
    }
    return OneovaBadgeType.none;
  }
}
