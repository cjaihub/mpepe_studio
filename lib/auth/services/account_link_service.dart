import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../security/account_lookup_service.dart';
import '../auth_repository.dart';

final accountLinkServiceProvider = Provider<AccountLinkService>((ref) {
  return AccountLinkService(FirebaseAuth.instance, ref.read(authRepositoryProvider));
});

/// An Oneova profile found for a sign-in method that is not attached to it.
class ExistingAccountMatch {
  final String uid;
  final Map<String, dynamic> data;
  const ExistingAccountMatch(this.uid, this.data);

  String? get phone => (data['phoneNumber'] ?? data['phone']) as String?;
  String? get username => data['username'] as String?;
}

/// Keeps one Oneova account per person across sign-in methods.
///
/// Firebase Auth makes a separate user (uid) for every phone number or
/// Google account that is not linked to an existing user. The profile lives
/// at `users/{uid}`, so signing in with the "other" method used to land on an
/// empty uid and the app asked the person to register again. This service
/// holds the credential of the method that is not linked yet, lets the person
/// sign in to their real account, then links it with `linkWithCredential`.
class AccountLinkService {
  AccountLinkService(this._auth, this._repo);

  final FirebaseAuth _auth;
  final AuthRepository _repo;

  // Static: the credential must survive navigation between the signup
  // wizard and the login screen.
  static AuthCredential? _pending;
  static String? _pendingLabel;
  static String? _pendingPhoneHint;

  CollectionReference<Map<String, dynamic>> get _users => FirebaseFirestore.instance.collection('users');

  AuthCredential? get pendingCredential => _pending;

  /// "Google", "Facebook", ... for messages.
  String? get pendingLabel => _pendingLabel;

  /// Phone number of the account the person should sign in to, if known.
  String? get pendingPhoneHint => _pendingPhoneHint;

  void holdForLinking(AuthCredential credential, {String? phoneHint}) {
    _pending = credential;
    _pendingLabel = labelFor(credential.providerId);
    if (phoneHint != null) _pendingPhoneHint = phoneHint;
  }

  void setPhoneHint(String? phone) => _pendingPhoneHint = phone;

  void clearPending() {
    _pending = null;
    _pendingLabel = null;
    _pendingPhoneHint = null;
  }

  static String labelFor(String providerId) => switch (providerId) {
        'google.com' => 'Google',
        'facebook.com' => 'Facebook',
        'phone' => 'phone number',
        'password' => 'password',
        _ when providerId.startsWith('oidc.tiktok') => 'TikTok',
        _ => providerId,
      };

  Future<bool> hasProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.exists;
  }

  /// Looks for a profile owned by another uid that matches [email] or
  /// [phone], through the server lookup (accountLookup). The phone number
  /// comes back only when this session is signed in with that e-mail/phone.
  Future<ExistingAccountMatch?> findProfileFor({
    String? email,
    String? phone,
    required String exceptUid,
  }) async {
    final lookups = <Future<Map<String, dynamic>?> Function()>[
      if (email != null && email.isNotEmpty) () => AccountLookupService.byEmail(email),
      if (phone != null && phone.isNotEmpty) () => AccountLookupService.byPhone(phone),
    ];
    for (final lookup in lookups) {
      try {
        final m = await lookup();
        final uid = m?['uid'] as String?;
        if (m != null && uid != null && uid != exceptUid) return ExistingAccountMatch(uid, m);
      } catch (e) {
        debugPrint('[AccountLink] profile lookup: $e');
      }
    }
    return null;
  }

  /// Removes the Firebase user that a sign-in has just made for a method
  /// whose owner already has an Oneova account. Only a user with no profile
  /// is removed; that frees the credential so it can be linked to the real
  /// account. Signs out in every case.
  Future<void> releaseEmptyUser(User user) async {
    try {
      if (!await hasProfile(user.uid)) {
        await user.delete();
      }
    } catch (e) {
      // requires-recent-login or offline: the empty user stays; linking then
      // reports credential-already-in-use and an admin merge is needed.
      debugPrint('[AccountLink] could not release empty user ${user.uid}: $e');
    }
    await _auth.signOut();
  }

  /// Links the held credential to [user] after a verified sign-in.
  /// Returns a message for the person, or null when nothing was held.
  Future<String?> linkPending(User user) async {
    final cred = _pending;
    if (cred == null) return null;
    final label = _pendingLabel ?? 'that sign-in';
    try {
      await _linkCredential(user, cred);
      clearPending();
      return '$label is now linked. You can sign in with it next time.';
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        clearPending();
        return null;
      }
      if (e.code == 'invalid-credential' && cred.providerId == GoogleAuthProvider.PROVIDER_ID) {
        // The Google token expired while the person signed in; ask Google again.
        try {
          await linkGoogle(user);
          clearPending();
          return '$label is now linked. You can sign in with it next time.';
        } catch (e2) {
          debugPrint('[AccountLink] Google relink: $e2');
        }
      }
      clearPending();
      return linkErrorMessage(e, label);
    }
  }

  /// Settings: attach a Google account to the signed-in user.
  Future<void> linkGoogle(User user) async {
    final cred = await _repo.googleCredential();
    if (cred == null) throw FirebaseAuthException(code: 'canceled', message: 'Google sign-in was canceled.');
    await _linkCredential(user, cred);
  }

  /// Settings: attach (or confirm) a phone number verified by SMS.
  Future<void> linkPhone(User user, PhoneAuthCredential cred) => _linkCredential(user, cred);

  Future<void> unlink(User user, String providerId) async {
    final providers = user.providerData.map((p) => p.providerId).where((p) => p != 'password').toList();
    if (providers.length <= 1) {
      throw FirebaseAuthException(code: 'last-provider', message: 'Keep at least one way to sign in.');
    }
    final updated = await user.unlink(providerId);
    await recordProviders(updated);
  }

  Future<void> _linkCredential(User user, AuthCredential cred) async {
    final result = await user.linkWithCredential(cred);
    await recordProviders(result.user ?? user);
  }

  /// Mirrors the linked sign-in methods on the profile, so the account can be
  /// found by email or phone from any method.
  Future<void> recordProviders(User user) async {
    final providers = user.providerData.map((p) => p.providerId).toSet().toList()..sort();
    final emails = user.providerData
        .where((p) => p.providerId != 'password')
        .map((p) => p.email?.toLowerCase())
        .whereType<String>()
        .toSet()
        .toList();
    try {
      // update(), not set(): never create a bare profile, which would skip
      // onboarding for an account that has not finished it.
      await _users.doc(user.uid).update({
        'linkedProviders': providers,
        if (emails.isNotEmpty) 'linkedEmails': FieldValue.arrayUnion(emails),
        if (emails.isNotEmpty) 'email': emails.first,
        if (user.phoneNumber != null) 'phoneNumber': user.phoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AccountLink] record providers: $e');
    }
  }

  static String linkErrorMessage(FirebaseAuthException e, String label) => switch (e.code) {
        'credential-already-in-use' || 'account-exists-with-different-credential' || 'email-already-in-use' =>
          'This $label already belongs to a separate Oneova sign-in. Contact support to merge the two accounts.',
        'provider-already-linked' => 'A $label is already linked to this account.',
        'requires-recent-login' => 'Please sign out and in again, then link your $label.',
        'invalid-verification-code' => 'That code is not right. Try again.',
        'canceled' => 'Linking was canceled.',
        'last-provider' => e.message ?? 'Keep at least one way to sign in.',
        _ => 'Could not link your $label: ${e.message ?? e.code}',
      };
}
