import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import '../../security/e2e_encryption_service.dart';
import 'notification_service.dart';
import '../services/rich_notification_renderer.dart';
import '../../calling/services/callkit_service.dart';
import '../../../shared/router.dart';
import '../../../auth/services/app_lifecycle_observer.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
  // Incoming/cancelled calls ring natively (full-screen on the lock screen).
  if (await handleCallPushInBackground(message)) return;
  // Activity pushes arrive data-only so we can draw them with photos,
  // grouping and action buttons, also on the lock screen.
  try {
    if (await OneovaRichNotifications.showFromData(message.data)) return;
  } catch (e) {
    debugPrint('Rich push render failed: $e');
  }
  // Example of saving to highly partitioned subcollection for offline sync
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    final shardId = uid.hashCode % 100;
    await FirebaseFirestore.instance
        .collection('user_notifications_shard_$shardId')
        .doc(uid)
        .collection('messages')
        .doc(message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString())
        .set({
      'data': message.data,
      'notification': {
        'title': message.notification?.title,
        'body': message.notification?.body,
      },
      'receivedAt': FieldValue.serverTimestamp(),
      'status': 'delivered_offline'
    });
  }
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(
    ref.read(e2eEncryptionServiceProvider),
    ref.read(notificationServiceProvider),
  );
});

class PushNotificationService {
  final E2EEncryptionService _e2eService;
  final NotificationService _notificationService;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  PushNotificationService(this._e2eService, this._notificationService);

  FlutterLocalNotificationsPlugin get _localNotificationsPlugin => OneovaRichNotifications.plugin;

  String get _currentUserId => _auth.currentUser?.uid ?? '';

  Future<void> initialize() async {
    if (const bool.fromEnvironment('FLUTTER_TEST_FORCE_MOBILE_UI')) {
      debugPrint('[PushNotificationService] Skipping in test mode');
      return;
    }
    
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 1. Request OS Permissions
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('[PushNotificationService] User granted permission');

      // 2. Get FCM Token
      String? token = await _messaging.getToken();
      if (token != null) {
        await _saveDeviceToken(token);
      }

      // Listen for token refreshes
      _messaging.onTokenRefresh.listen(_saveDeviceToken);

      // 3. Local notifications (shared plugin, channels, action buttons).
      await OneovaRichNotifications.ensureInitialized();
      await OneovaRichNotifications.openLaunchNotification();

      // 4. Listen to Foreground Messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Calls are rung by CallOverlayManager's Firestore listener while the
        // app is open; a cancel just stops any native ringer.
        final type = message.data['type'];
        if (type == CallPushType.incoming) return;
        if (type == CallPushType.cancel) {
          handleCallPushInBackground(message);
          return;
        }
        // Activity pushes mirror a notifications/ doc; the in-app banner
        // already rings for those while the app is open.
        if (message.data['notificationId'] != null) {
          // Low-priority notes (updates, tips) skip the banner, so the
          // system tray shows them instead.
          if (message.data['priority'] == 'low') OneovaRichNotifications.showFromData(message.data);
          return;
        }
        // Chat messages pop up in-app (NotificationOverlayManager watches
        // the user's chats), so skip the duplicate system notification.
        if (message.data['chatId'] != null) return;
        _showForegroundNotification(message);
      });

      // 5. Handle notification tap when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final route = message.data['route'] as String?;
        if (route != null) {
          _navigateToRoute(route);
        }
      });

      // 6. Handle notification tap when app was fully terminated
      // Android re-delivers the launch intent of an old notification tap when
      // the app is reopened from recents, so each message opens its route
      // once, and only if it is recent.
      final initialMessage = await _messaging.getInitialMessage();
      final route = initialMessage?.data['route'] as String?;
      if (initialMessage != null && route != null && await _claimInitialMessage(initialMessage)) {
        // Delay to let the router fully initialize first
        Future.delayed(const Duration(milliseconds: 1200), () => _navigateToRoute(route));
      }
    }
  }

  Future<bool> _claimInitialMessage(RemoteMessage message) async {
    final sent = message.sentTime;
    if (sent != null && DateTime.now().difference(sent) > const Duration(minutes: 10)) return false;
    final id = message.messageId ?? '${message.sentTime?.millisecondsSinceEpoch}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('push_last_opened_message') == id) return false;
      await prefs.setString('push_last_opened_message', id);
    } catch (_) {}
    return true;
  }

  void _navigateToRoute(String route) {
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      GoRouter.of(context).push(route);
    }
  }

  Future<void> _saveDeviceToken(String token) async {
    final uid = _currentUserId;
    if (uid.isEmpty) return;

    // Partitioning FCM tokens for 10 Billion users scale
    final shardId = uid.hashCode % 100;
    
    await _firestore
        .collection('fcm_tokens_shard_$shardId')
        .doc(token)
        .set({
      'token': token,
      'userId': uid,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('device_tokens')
        .doc(token)
        .set({
      'token': token,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      // This build draws data-only activity pushes itself (photos, grouping,
      // Reply / Like / Follow back buttons); see functions/src/notifications.ts.
      'richPush': !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  void _showForegroundNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    String? title = notification?.title;
    String? body = notification?.body;

    // Handle E2EE data-only payloads
    if (message.data['isE2EE'] == 'true') {
      try {
        final senderPubKey = message.data['senderPublicKey'];
        final encryptedTitle = message.data['encryptedTitle'];
        final encryptedBody = message.data['encryptedBody'];

        if (senderPubKey != null) {
          if (encryptedTitle != null) {
            title = await _e2eService.decryptMessage(encryptedTitle, senderPubKey);
          }
          if (encryptedBody != null) {
            body = await _e2eService.decryptMessage(encryptedBody, senderPubKey);
          }
        }
      } catch (e) {
        debugPrint('[PushNotificationService] Failed to decrypt E2EE notification: $e');
        title = 'New Encrypted Message';
        body = 'Open the app to read it.';
      }
    }

    if ((title != null || body != null) && !kIsWeb) {
      final prefs = await _notificationService.getPreferences();
      final category = message.data['category'] ?? 'system';
      
      // Do not show if muted or in DND
      if (prefs.isMutedForCategory(category)) {
        return;
      }

      String soundFile = prefs.ringtone;
      if (soundFile == 'default') {
        soundFile = 'notification_sound'; // Or default channel sound
      }

      _localNotificationsPlugin.show(
        id: message.hashCode,
        title: title ?? 'New Message',
        body: body ?? '',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'oneova_high_importance_channel',
            'OneOva Priority Alerts',
            channelDescription: 'Real-time OneOva Studio, social interactions, and live creator updates',
            importance: Importance.max,
            priority: Priority.high,
            visibility: NotificationVisibility.public,
            ticker: title,
            styleInformation: BigTextStyleInformation(
              body ?? '',
              contentTitle: title,
              summaryText: 'Oneova',
            ),
            color: const Color(0xFF0C4FA8),
            ledColor: const Color(0xFF0C4FA8),
            ledOnMs: 1000,
            ledOffMs: 500,
            enableLights: true,
            icon: android?.smallIcon,
            playSound: prefs.soundEnabled,
            sound: prefs.soundEnabled 
                ? const RawResourceAndroidNotificationSound('oneova_notification')
                : null,
            enableVibration: prefs.vibrateEnabled,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: prefs.soundEnabled,
            sound: prefs.soundEnabled ? 'oneova_notification.wav' : null,
          ),
        ),
        payload: message.data['route'],
      );
    }
  }

  Future<void> deleteToken() async {
    String? token = await _messaging.getToken();
    if (token != null) {
      final uid = _currentUserId;
      final shardId = uid.hashCode % 100;

      await _firestore
          .collection('fcm_tokens_shard_$shardId')
          .doc(token)
          .delete();
          
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('device_tokens')
          .doc(token)
          .delete();
      await _messaging.deleteToken();
    }
  }
}
