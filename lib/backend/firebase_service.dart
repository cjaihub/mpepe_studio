import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Central service that manages Blaze-plan Firebase features:
/// - Cloud Storage  (file uploads & deletes)
/// - FCM            (push notifications & token management)
/// - Remote Config  (feature flags & dynamic settings)
/// - App Check      (already initialized in main.dart)
class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  // ─── App Check ────────────────────────────────────────────────────────────

  /// Call once from main() before runApp().
  /// App Check supports: Android, iOS, macOS. NOT supported on Windows/Linux desktop.
  static Future<void> activateAppCheck() async {
    // Skip App Check on unsupported desktop platforms
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) return;

    await FirebaseAppCheck.instance.activate(
      // Android: Play Integrity in production, debug token in dev
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      // iOS / macOS: DeviceCheck in production, debug token in dev
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
    );
  }

  // ─── Remote Config ────────────────────────────────────────────────────────

  /// Fetch & activate Remote Config. Call once from main() after Firebase.initializeApp().
  Future<void> initRemoteConfig() async {
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval:
          kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));

    await _remoteConfig.setDefaults({
      'maintenance_mode': false,
      'max_upload_size_mb': 50,
      'fcm_enabled': true,
      'analytics_enabled': true,
      'ai_features_enabled': true,
      'youtube_upload_enabled': true,
      'new_user_approval_required': true,
    });

    try {
      await _remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint('FirebaseService: Remote Config fetch failed (using defaults): $e');
    }
  }

  /// Read a boolean feature flag from Remote Config.
  bool getFlag(String key) => _remoteConfig.getBool(key);

  /// Read an integer value from Remote Config.
  int getInt(String key) => _remoteConfig.getInt(key);

  /// Read a string value from Remote Config.
  String getString(String key) => _remoteConfig.getString(key);

  // ─── Cloud Storage ────────────────────────────────────────────────────────

  /// Upload raw bytes to [storagePath] (e.g. `users/uid/avatar.jpg`).
  /// Returns the public download URL.
  Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    final ref = _storage.ref(storagePath);
    final uploadTask = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return await uploadTask.ref.getDownloadURL();
  }

  /// Upload a local [file] to [storagePath].
  /// Returns the public download URL.
  Future<String> uploadFile({
    required String storagePath,
    required File file,
    String? contentType,
  }) async {
    final ref = _storage.ref(storagePath);
    final metadata =
        contentType != null ? SettableMetadata(contentType: contentType) : null;
    final uploadTask = await ref.putFile(file, metadata);
    return await uploadTask.ref.getDownloadURL();
  }

  /// Delete a file by its full [downloadUrl].
  Future<void> deleteByUrl(String downloadUrl) async {
    try {
      final ref = _storage.refFromURL(downloadUrl);
      await ref.delete();
    } catch (e) {
      debugPrint('FirebaseService: Failed to delete $downloadUrl — $e');
    }
  }

  /// Delete a file by its storage [path] (e.g. `users/uid/avatar.jpg`).
  Future<void> deleteByPath(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (e) {
      debugPrint('FirebaseService: Failed to delete $path — $e');
    }
  }

  // ─── FCM — Push Notifications ─────────────────────────────────────────────

  /// Returns true if FCM is supported on the current platform.
  static bool get isFCMSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Request notification permissions and return the FCM token (or null if
  /// unsupported / denied).
  Future<String?> initFCM({
    required void Function(RemoteMessage) onForegroundMessage,
    required void Function(RemoteMessage) onMessageOpenedApp,
  }) async {
    if (!isFCMSupported) {
      debugPrint('FirebaseService: FCM not supported on this platform.');
      return null;
    }

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('FirebaseService: FCM permission denied.');
      return null;
    }

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(onMessageOpenedApp);

    final token = await messaging.getToken();
    debugPrint('FirebaseService: FCM Token = $token');
    return token;
  }

  /// Saves [fcmToken] to the user's Firestore document under users/{uid}.
  Future<void> saveFCMTokenToFirestore({
    required String uid,
    required String fcmToken,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set(
        {
          'fcmToken': fcmToken,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('FirebaseService: FCM token saved for user $uid');
    } catch (e) {
      debugPrint('FirebaseService: Failed to save FCM token — $e');
    }
  }

  /// Removes the FCM token from Firestore when the user signs out.
  Future<void> removeFCMTokenFromFirestore(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('FirebaseService: Failed to remove FCM token — $e');
    }
  }
}
