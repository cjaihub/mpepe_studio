import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/services/app_lifecycle_observer.dart';
import '../../../firebase_options.dart';
import '../../../shared/services/play_update_service.dart';
import '../../social/models/comment.dart';
import '../../social/repositories/interaction_repository.dart';
import '../../social/repositories/relationship_repository.dart';
import '../../social/services/comment_service.dart';

/// Renders activity pushes as rich system notifications: the person's photo,
/// a post preview, grouping per kind of activity, lock-screen visibility and
/// action buttons (Reply, Like, Follow back, Watch, Update, ...).
///
/// The server (functions/src/notifications.ts) sends Android devices that
/// registered with `richPush: true` a data-only message carrying
/// `render: 'rich'`; this class turns it into the notification, in the
/// background isolate when the app is closed or the phone is locked.
class OneovaRichNotifications {
  OneovaRichNotifications._();

  static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const String activityChannel = 'oneova_high_importance_channel';
  static const String liveChannel = 'oneova_live_channel';
  static const String updatesChannel = 'oneova_updates_channel';

  static const _pendingRouteKey = 'oneova_pending_notification_route';

  /// Initialises the plugin once per isolate. Every part of the app shares
  /// this plugin, so the tap callbacks are set here and nowhere else.
  static Future<void> ensureInitialized() async {
    if (_ready || kIsWeb) return;
    _ready = true;
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: oneovaNotificationActionInBackground,
    );
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      activityChannel,
      'Activity',
      description: 'Likes, comments, new followers and posts from people you follow',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('oneova_notification'),
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      liveChannel,
      'Live from people you follow',
      description: 'When a creator you follow goes live',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('oneova_notification'),
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      updatesChannel,
      'Updates and tips',
      description: 'App updates, profile tips and changes to what you see',
      importance: Importance.defaultImportance,
    ));
  }

  /// Opens the route of a notification tapped while the app was closed.
  static Future<void> openLaunchNotification() async {
    if (kIsWeb) return;
    await ensureInitialized();
    final details = await plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true && response != null) {
      Future.delayed(const Duration(milliseconds: 1200), () => _onResponse(response));
    }
    // A background action (e.g. Reply that needs the app) may have left a route.
    try {
      final prefs = await SharedPreferences.getInstance();
      final route = prefs.getString(_pendingRouteKey);
      if (route != null) {
        await prefs.remove(_pendingRouteKey);
        Future.delayed(const Duration(milliseconds: 1200), () => _open(route));
      }
    } catch (_) {}
  }

  /// Shows a rich notification from a push data map. Returns false when the
  /// message is not one this renderer handles.
  static Future<bool> showFromData(Map<String, dynamic> data) async {
    if (kIsWeb || data['render'] != 'rich') return false;
    await ensureInitialized();

    final category = (data['category'] ?? 'system').toString();
    final title = (data['title'] ?? 'Oneova').toString();
    final body = (data['body'] ?? '').toString();
    final route = (data['route'] ?? '/notifications').toString();
    final groupKey = 'oneova.${data['group'] ?? category}';
    final sound = data['sound'] != 'off';
    final channel = switch (category) {
      'live' => liveChannel,
      'appUpdate' || 'recommendation' || 'profileTip' || 'system' => updatesChannel,
      _ => activityChannel,
    };

    final avatar = await _downloadBitmap(data['avatarUrl']?.toString());
    final picture = await _downloadBitmap(data['imageUrl']?.toString());

    final payload = jsonEncode({
      'route': route,
      'category': category,
      'notificationId': data['notificationId'],
      'actorId': data['actorId'],
      'postId': data['postId'],
      'commentId': data['commentId'],
    });

    final StyleInformation style = picture != null
        ? BigPictureStyleInformation(
            picture,
            largeIcon: avatar,
            contentTitle: title,
            summaryText: body,
            hideExpandedLargeIcon: true,
          )
        : BigTextStyleInformation(body, contentTitle: title);

    final id = (data['notificationId'] ?? '$title$body').hashCode & 0x7fffffff;
    await plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          _channelName(channel),
          importance: channel == updatesChannel ? Importance.defaultImportance : Importance.max,
          priority: channel == updatesChannel ? Priority.defaultPriority : Priority.high,
          visibility: data['private'] == 'true' ? NotificationVisibility.private : NotificationVisibility.public,
          category: category == 'live' ? AndroidNotificationCategory.event : AndroidNotificationCategory.social,
          groupKey: groupKey,
          largeIcon: avatar,
          styleInformation: style,
          color: category == 'live' ? const Color(0xFFFF2D87) : const Color(0xFF0C4FA8),
          playSound: sound,
          sound: sound ? const RawResourceAndroidNotificationSound('oneova_notification') : null,
          ticker: title,
          when: int.tryParse(data['sentAt']?.toString() ?? ''),
          showWhen: true,
          actions: _actionsFor(data['actions']?.toString()),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: sound,
          threadIdentifier: groupKey,
          sound: sound ? 'oneova_notification.wav' : null,
        ),
      ),
      payload: payload,
    );
    await _showGroupSummary(groupKey, channel, category);
    return true;
  }

  static String _channelName(String channel) => switch (channel) {
        liveChannel => 'Live from people you follow',
        updatesChannel => 'Updates and tips',
        _ => 'Activity',
      };

  /// One collapsed summary per kind of activity ("5 new likes").
  static Future<void> _showGroupSummary(String groupKey, String channel, String category) async {
    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    final active = await android.getActiveNotifications();
    final inGroup = active.where((n) => n.groupKey == groupKey && n.id != groupKey.hashCode).toList();
    if (inGroup.length < 2) return;
    await plugin.show(
      id: groupKey.hashCode,
      title: _groupTitle(category, inGroup.length),
      body: inGroup.first.title ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          _channelName(channel),
          groupKey: groupKey,
          setAsGroupSummary: true,
          onlyAlertOnce: true,
          visibility: NotificationVisibility.public,
          color: const Color(0xFF0C4FA8),
          styleInformation: InboxStyleInformation(
            [for (final n in inGroup.take(5)) n.title ?? ''],
            summaryText: _groupTitle(category, inGroup.length),
          ),
        ),
      ),
      payload: jsonEncode({'route': '/notifications'}),
    );
  }

  static String _groupTitle(String category, int count) => switch (category) {
        'like' || 'reaction' => '$count new likes',
        'comment' || 'reply' || 'mention' => '$count new comments',
        'newFollower' || 'followRequest' => '$count new followers',
        'newPost' => '$count new posts from people you follow',
        'live' => '$count people you follow are live',
        _ => '$count new updates',
      };

  /// Action ids the server may ask for, comma separated (e.g. "reply,open").
  static List<AndroidNotificationAction> _actionsFor(String? ids) {
    if (ids == null || ids.isEmpty) return const [];
    final out = <AndroidNotificationAction>[];
    for (final id in ids.split(',').map((s) => s.trim())) {
      switch (id) {
        case 'reply':
          out.add(const AndroidNotificationAction(
            'reply',
            'Reply',
            inputs: [AndroidNotificationActionInput(label: 'Write a reply…')],
            allowGeneratedReplies: true,
            semanticAction: SemanticAction.reply,
          ));
        case 'like':
          out.add(const AndroidNotificationAction('like', 'Like', semanticAction: SemanticAction.thumbsUp));
        case 'follow_back':
          out.add(const AndroidNotificationAction('follow_back', 'Follow back'));
        case 'watch':
          out.add(const AndroidNotificationAction('open', 'Watch', showsUserInterface: true));
        case 'view_profile':
          out.add(const AndroidNotificationAction('open', 'View profile', showsUserInterface: true));
        case 'update':
          out.add(const AndroidNotificationAction('open', 'Update', showsUserInterface: true));
        case 'complete':
          out.add(const AndroidNotificationAction('open', 'Finish profile', showsUserInterface: true));
        case 'open':
          out.add(const AndroidNotificationAction('open', 'Open', showsUserInterface: true));
      }
    }
    return out.take(3).toList();
  }

  static Future<ByteArrayAndroidBitmap?> _downloadBitmap(String? url) async {
    if (url == null || !url.startsWith('http')) return null;
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200 || res.bodyBytes.length > 4 * 1024 * 1024) return null;
      return ByteArrayAndroidBitmap(Uint8List.fromList(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _decode(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final v = jsonDecode(payload);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    // Older local notifications carried the bare route as payload.
    return {'route': payload};
  }

  static void _onResponse(NotificationResponse response) {
    final data = _decode(response.payload);
    final action = response.actionId;
    if (action == 'like' || action == 'follow_back' || action == 'reply') {
      // Same work as the background handler; the app is open so just do it.
      performAction(response).then((_) {
        if (action == 'reply' && (response.input ?? '').trim().isEmpty) {
          _open(data['route']?.toString());
        }
      });
      return;
    }
    if (data['category'] == 'appUpdate') {
      PlayUpdateService.instance.updateNow();
      return;
    }
    _open(data['route']?.toString());
  }

  static void _open(String? route) {
    if (route == null || route.isEmpty) return;
    final context = rootNavigatorKey.currentContext;
    if (context != null) GoRouter.of(context).push(route);
  }

  /// Runs Reply / Like / Follow back for the signed-in person.
  static Future<void> performAction(NotificationResponse response) async {
    final data = _decode(response.payload);
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    try {
      switch (response.actionId) {
        case 'follow_back':
          final actor = data['actorId']?.toString();
          if (actor != null && actor.isNotEmpty) await RelationshipRepository().followUser(me, actor);
        case 'like':
          final post = data['postId']?.toString();
          if (post != null && post.isNotEmpty) {
            final repo = InteractionRepository(FirebaseFirestore.instance);
            if (!await repo.isContentLikedBy(me, post)) await repo.likeContent(me, post);
          }
        case 'reply':
          final text = (response.input ?? '').trim();
          final post = data['postId']?.toString();
          if (text.isEmpty || post == null || post.isEmpty) {
            await _rememberRoute(data['route']?.toString());
            return;
          }
          await CommentService().addComment(
            Comment(
              id: '',
              postId: post,
              authorId: me,
              content: text,
              replyToId: data['commentId']?.toString(),
              createdAt: DateTime.now(),
            ),
            isCreator: data['category'] == 'comment',
          );
      }
    } catch (e) {
      debugPrint('[OneovaRichNotifications] action ${response.actionId} failed: $e');
      await _rememberRoute(data['route']?.toString());
    }
  }

  static Future<void> _rememberRoute(String? route) async {
    if (route == null || route.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingRouteKey, route);
    } catch (_) {}
  }
}

/// Action buttons pressed while the app is closed run here, in a background
/// isolate. Firebase Auth restores the signed-in person from disk.
@pragma('vm:entry-point')
Future<void> oneovaNotificationActionInBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  await OneovaRichNotifications.performAction(response);
}
