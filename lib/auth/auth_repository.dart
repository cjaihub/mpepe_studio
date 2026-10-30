import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../backend/settings_service.dart';

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  // In v7, GoogleSignIn is a singleton and must be initialized.
  // We'll return the instance here, and ensure it's initialized before use.
  return GoogleSignIn.instance;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    FirebaseAuth.instance,
    ref.read(googleSignInProvider),
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

class AuthRepository {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  
  AuthRepository(this._auth, this._googleSignIn);

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final credential = await googleCredential();
      if (credential == null) return null;
      lastGoogleCredential = credential;
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      rethrow;
    }
  }

  /// The Google credential from the last [signInWithGoogle], kept so it can
  /// be linked to an existing account (AccountLinkService).
  OAuthCredential? lastGoogleCredential;

  /// Runs the Google account picker and returns a Firebase credential without
  /// signing in, for sign-in or for linking Google to the current user.
  Future<OAuthCredential?> googleCredential() async {
    try {
      // Ensure Google SignIn is initialized before authenticating
      await _googleSignIn.initialize();

      // v7: authenticate() triggers the interactive sign-in flow.
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // v7: authentication getter returns GoogleSignInAuthentication synchronously.
      final String? idToken = googleUser.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('Google Sign-In: idToken is null or empty');
        return null;
      }

      // v7: get the access token via authorizationClient optionally
      String? accessToken;
      try {
        final GoogleSignInClientAuthorization authorization =
            await googleUser.authorizationClient.authorizeScopes(['email']);
        accessToken = authorization.accessToken;
      } catch (scopeError) {
        debugPrint('Google Sign-In optional scope authorization non-fatal: $scopeError');
      }

      return GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );
    } catch (e) {
      debugPrint('Google credential error: $e');
      rethrow;
    }
  }

  Future<UserCredential> createUserWithEmailAndPassword({required String email, required String password}) async {
    return await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  // Phone Auth flow
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) verificationCompleted,
    required Function(FirebaseAuthException) verificationFailed,
    required Function(String, int?) codeSent,
    required Function(String) codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
      throw Exception('Phone Auth is not supported on Windows desktop.');
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      // Reuses the first request's session on "Resend", so Google does not
      // re-check the app (the step that falls back to reCAPTCHA).
      forceResendingToken: forceResendingToken,
      // How long Android waits to read the SMS itself before manual entry.
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> signInWithOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.signInWithCredential(credential);
  }

  // AI Voice and Model Settings: the `ai` category of the one settings
  // store, user_settings/{uid}.
  Future<Map<String, dynamic>> getUserSettings() async {
    final user = _auth.currentUser;
    if (user == null) return {};
    final settings = await SettingsService().getSettings(user.uid);
    return Map<String, dynamic>.from(settings['ai'] as Map? ?? const {});
  }

  Future<void> saveUserSettings({String? selectedVoice, String? selectedModel}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await SettingsService().updateSettingsCategory(user.uid, 'ai', {
        'selectedVoice': ?selectedVoice,
        'selectedModel': ?selectedModel,
      });
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }
}
