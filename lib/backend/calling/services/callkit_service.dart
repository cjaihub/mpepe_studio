import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../firebase_options.dart';
import '../../../shared/theme/app_theme.dart';
import '../models/call_participant.dart';
import '../providers/call_signaling_service.dart';

/// Push payload `type` values sent by functions/src/calls.ts.
class CallPushType {
  static const incoming = 'incoming_call';
  static const cancel = 'call_cancel';
}

/// How long the native UI rings before it gives up (matches the caller's
/// 45 s ring timeout).
const Duration kCallRingTimeout = Duration(seconds: 45);

String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Native incoming/outgoing call surfaces:
/// * Android: full-screen intent activity over the lock screen, ringtone,
///   heads-up notification, and the plugin's `phoneCall|microphone|camera`
///   foreground service while a call is in progress.
/// * iOS: CallKit (lock-screen answer UI, Recents), fed by PushKit VoIP pushes
///   handled in `ios/Runner/AppDelegate.swift`.
class CallKitService {
  CallKitService._();

  static CallKitParams params({
    required String callkitId,
    required String callId,
    required String callerName,
    String? avatar,
    required bool isVideo,
    bool isGroup = false,
    String? hostId,
  }) {
    return CallKitParams(
      id: callkitId,
      nameCaller: callerName.isEmpty ? 'Oneova' : callerName,
      appName: 'Oneova',
      avatar: avatar,
      handle: isGroup ? 'Group ${isVideo ? 'video' : 'voice'} call' : (isVideo ? 'Video call' : 'Voice call'),
      type: isVideo ? 1 : 0,
      duration: kCallRingTimeout.inMilliseconds,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Oneova call in progress',
        callbackText: 'Hang up',
      ),
      extra: <String, dynamic>{
        'callId': callId,
        'isVideo': isVideo,
        'isGroup': isGroup,
        'hostId': ?hostId,
      },
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        isShowFullLockedScreen: true,
        isImportant: true,
        backgroundColor: _hex(AppColors.brandBlue.toARGB32()),
        actionColor: _hex(AppColors.brandPink.toARGB32()),
        textColor: _hex(AppColors.brandWhite.toARGB32()),
        incomingCallNotificationChannelName: 'Incoming calls',
        missedCallNotificationChannelName: 'Missed calls',
        textAccept: 'Accept',
        textDecline: 'Decline',
      ),
      ios: IOSParams(
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        includesCallsInRecents: true,
        configureAudioSession: true,
        audioSessionMode: isVideo ? 'videoChat' : 'voiceChat',
        audioSessionActive: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );
  }

  static CallKitParams paramsFromPush(Map<String, dynamic> data) => params(
        callkitId: data['callkitId'] as String,
        callId: data['callId'] as String,
        callerName: (data['callerName'] as String?) ?? '',
        avatar: (data['callerAvatar'] as String?)?.isEmpty == true ? null : data['callerAvatar'] as String?,
        isVideo: data['isVideo'] == 'true' || data['isVideo'] == true,
        isGroup: data['isGroup'] == 'true' || data['isGroup'] == true,
        hostId: data['hostId'] as String?,
      );

  static Future<void> showIncoming(CallKitParams p) async {
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(p);
    } catch (e) {
      debugPrint('[CallKit] showIncoming failed: $e');
    }
  }

  /// Stops the ringing UI without reporting a decline.
  static Future<void> hideIncoming(CallKitParams p) async {
    try {
      await FlutterCallkitIncoming.hideCallkitIncoming(p);
    } catch (_) {}
  }

  /// Registers an in-progress call with the OS. On Android this starts the
  /// foreground service (keeps mic/camera alive when the app is in the
  /// background or the screen is off).
  static Future<void> startOngoing(CallKitParams p) async {
    try {
      await FlutterCallkitIncoming.startCall(p);
    } catch (e) {
      debugPrint('[CallKit] startOngoing failed: $e');
    }
  }

  static Future<void> setConnected(String callkitId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(callkitId);
    } catch (_) {}
  }

  static Future<void> end(String callkitId) async {
    try {
      await FlutterCallkitIncoming.endCall(callkitId);
    } catch (_) {}
  }

  static Future<void> showMissed(CallKitParams p) async {
    try {
      await FlutterCallkitIncoming.showMissCallNotification(p);
    } catch (_) {}
  }

  static Future<List<CallKitParams>> activeCalls() async {
    try {
      return await FlutterCallkitIncoming.activeCalls();
    } catch (_) {
      return const [];
    }
  }

  /// Asks for POST_NOTIFICATIONS and (Android 14+) full-screen intent access,
  /// without which incoming calls only show as a heads-up notification.
  static Future<void> requestPermissions() async {
    if (kIsWeb) return;
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notification permission',
        'rationaleMessagePermission': 'Oneova needs notifications to ring you for calls.',
        'postNotificationMessageRequired':
            'Allow notifications in Settings so Oneova can ring you for calls.',
      });
      if (defaultTargetPlatform == TargetPlatform.android) {
        final canFullScreen = await FlutterCallkitIncoming.canUseFullScreenIntent();
        if (!canFullScreen) await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e) {
      debugPrint('[CallKit] permission request failed: $e');
    }
  }

  /// Stores the iOS PushKit token so the server can send VoIP pushes.
  static Future<void> registerVoipToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token is String && token.isNotEmpty) await saveVoipToken(token);
    } catch (e) {
      debugPrint('[CallKit] VoIP token unavailable: $e');
    }
  }

  static Future<void> saveVoipToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('voip_tokens')
        .doc(token)
        .set({
      'token': token,
      'platform': 'ios',
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }
}

/// Handles call pushes when the app is in the background or was killed.
/// Returns true when [message] was a call push.
///
/// Called from every FCM background handler in the app (Android only in
/// practice: iOS uses PushKit for incoming calls).
Future<bool> handleCallPushInBackground(RemoteMessage message) async {
  final data = message.data;
  final type = data['type'];
  if (type != CallPushType.incoming && type != CallPushType.cancel) return false;
  if (data['callkitId'] == null || data['callId'] == null) return true;

  final p = CallKitService.paramsFromPush(data);
  if (type == CallPushType.cancel) {
    await CallKitService.end(p.id);
    if (data['reason'] == 'missed') await CallKitService.showMissed(p);
    return true;
  }

  // A push that arrives after the ring window (phone was offline) is a
  // missed call, not a ring.
  final sentAt = int.tryParse('${data['sentAt'] ?? ''}');
  if (sentAt != null &&
      DateTime.now().millisecondsSinceEpoch - sentAt > kCallRingTimeout.inMilliseconds) {
    await CallKitService.showMissed(p);
    return true;
  }
  final existing = await CallKitService.activeCalls();
  if (existing.any((c) => c.id == p.id || c.extra?['callId'] == p.extra?['callId'])) {
    return true;
  }
  await CallKitService.showIncoming(p);
  await _ackDelivered(data['callId'] as String);
  return true;
}

Future<User?> _signedInUser() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  return FirebaseAuth.instance.currentUser ??
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 5));
}

/// Lets the caller see "Ringing…" once this phone is actually ringing.
Future<void> _ackDelivered(String callId) async {
  try {
    if (await _signedInUser() == null) return;
    await CallSignalingService().markDelivered(callId);
  } catch (e) {
    debugPrint('[CallKit] delivery ack failed: $e');
  }
}

/// Runs when the user declines from the native UI while the app is not
/// running, so the caller stops ringing straight away.
@pragma('vm:entry-point')
Future<void> callKitBackgroundEventHandler(CallEvent event) async {
  if (event is! CallEventActionCallDecline) return;
  final callId = event.callKitParams.extra?['callId'] as String?;
  if (callId == null) return;
  try {
    if (await _signedInUser() == null) return;
    final signaling = CallSignalingService();
    if (await signaling.myStatus(callId) == ParticipantStatus.ringing) {
      await signaling.declineCall(callId);
    }
  } catch (e) {
    debugPrint('[CallKit] background decline failed: $e');
  }
}
