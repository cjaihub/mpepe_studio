import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
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

  // AI Voice and Model Settings
  Future<Map<String, dynamic>> getUserSettings() async {
    final user = _auth.currentUser;
    if (user == null) return {};
    
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('settings').doc('ai_preferences').get();
      if (doc.exists) {
        return doc.data() ?? {};
      }
      return {};
    } catch (e) {
      debugPrint("Error getting settings: $e");
      return {};
    }
  }

  Future<void> saveUserSettings({String? selectedVoice, String? selectedModel}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    try {
      Map<String, dynamic> data = {};
      if (selectedVoice != null) data['selectedVoice'] = selectedVoice;
      if (selectedModel != null) data['selectedModel'] = selectedModel;
      
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('settings').doc('ai_preferences').set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Error saving settings: $e");
    }
  }
}
