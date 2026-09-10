import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
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

      // v7: authentication only has idToken; accessToken comes from authorization.
      final String? idToken = (await googleUser.authentication).idToken;

      // v7: get the access token via authorizationClient.
      final GoogleSignInClientAuthorization authorization =
          await googleUser.authorizationClient.authorizeScopes(['email']);

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authorization.accessToken,
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

  // Windows Desktop bypass: signInWithEmailAndPassword
  // Firebase Auth supports Email/Password on Windows.
  Future<void> devBypassLogin() async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: 'dev@mpepe.studio',
        password: 'password123',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        // Create it if it doesn't exist
        await _auth.createUserWithEmailAndPassword(
          email: 'dev@mpepe.studio',
          password: 'password123',
        );
      } else {
        rethrow;
      }
    }
  }

  // Phone Auth flow
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) verificationCompleted,
    required Function(FirebaseAuthException) verificationFailed,
    required Function(String, int?) codeSent,
    required Function(String) codeAutoRetrievalTimeout,
  }) async {
    if (!kIsWeb && Platform.isWindows) {
      throw Exception('Phone Auth is not supported on Windows desktop. Please use dev bypass.');
    }

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
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
      print("Error getting settings: $e");
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
      print("Error saving settings: $e");
    }
  }
}
