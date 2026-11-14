import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/live/models/live_models.dart';
import '../../backend/live/services/live_service.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/notifications/models/app_notification.dart';
import '../../backend/notifications/models/notification_preferences.dart';
import '../../backend/notifications/providers/notification_service.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../../ova_assistant/services/ova_device_hub.dart';
import '../../shared/theme/app_theme.dart';
import '../router.dart' show rootNavigatorKey;
import '../services/oneova_sound_service.dart';

/// Wraps the app and pops every in-app notification at the top of the
/// screen: activity from `notifications/`, plus new chat messages while
/// you're anywhere except that chat.
///
/// Nothing is dropped: notifications that arrive while one is showing wait
/// in a queue (shown as "+N"). Each pop-up has a countdown bar, swipes away
/// sideways or up, pulls down to expand, and chat pop-ups have an inline
/// quick reply.
class NotificationOverlayManager extends ConsumerStatefulWidget {
  final Widget child;

  const NotificationOverlayManager({super.key, required this.child});

  @override
  ConsumerState<NotificationOverlayManager> createState() => _NotificationOverlayManagerState();
}

class _NotificationOverlayManagerState extends ConsumerState<NotificationOverlayManager>
    with WidgetsBindingObserver {
  static const MethodChannel _assistantChannel = MethodChannel('com.oneova.app/ova_assistant');

  final List<AppNotification> _queue = [];
  final Set<String> _seen = {};
  OverlayEntry? _entry;
  AppNotification? _current;

  // Chat message pop-ups
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  StreamSubscription<Map<dynamic, dynamic>>? _deviceEventsSub;
  String? _chatUid;
  DateTime _chatSince = DateTime.now();
  DateTime _lastAiPulseAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, ({String name, String? avatar})> _people = {};
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) _syncChatListener();
    });
    _listenToCrossAppNotifications();
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) _triggerLiveStartupAiSuggestion();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      final elapsed = DateTime.now().difference(_lastAiPulseAt);
      if (elapsed.inSeconds >= 90) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) _triggerLiveStartupAiSuggestion();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _chatSub?.cancel();
    _deviceEventsSub?.cancel();
    if (_entry?.mounted ?? false) {
      _entry?.remove();
    }
    _entry = null;
    super.dispose();
  }

  // ───────────────────────── Cross-App Live Notifications & Startup AI Pulse ─────────────────────────

  void _listenToCrossAppNotifications() {
    if (!OvaDeviceHub.supported) return;
    final hub = ref.read(ovaDeviceHubProvider);
    _deviceEventsSub = hub.events.listen((event) {
      if (!mounted) return;
      if (event['type'] == 'notification') {
        if (event['ongoing'] == true) return;
        final n = OvaPhoneNotification.fromMap(event);
        if (n.title.isEmpty && n.text.isEmpty) return;
        _enqueueExternalAppNotification(n);
      }
    }, onError: (_) {});
  }

  void _enqueueExternalAppNotification(OvaPhoneNotification ext) {
    final prefs = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
    final appLabel = ext.app.isNotEmpty ? ext.app : 'External App';
    if (prefs.isExternalPackageBlocked(ext.package) ||
        prefs.isExternalPackageBlocked(appLabel)) {
      if (ext.key.isNotEmpty) {
        ref.read(ovaDeviceHubProvider).dismissNotification(ext.key).catchError((_) => false);
      }
      return;
    }
    final sender = ext.title.isNotEmpty ? ext.title : appLabel;
    final body = ext.text.isNotEmpty ? ext.text : 'New activity in $appLabel';
    final quickReplies = _buildInstantSmartReplies(sender, body, appLabel);
    final id = 'ext_${ext.key}_${ext.postTime.millisecondsSinceEpoch}';

    _enqueue(
      AppNotification(
        id: id,
        userId: FirebaseAuth.instance.currentUser?.uid ?? 'local',
        category: AppNotificationCategory.newMessage,
        priority: AppNotificationPriority.urgent,
        title: sender == appLabel ? '📲 $appLabel' : '📲 $appLabel · $sender',
        body: body,
        groupId: 'ext_${ext.key}',
        payload: {
          'isExternalApp': true,
          'notificationKey': ext.key,
          'appName': appLabel,
          'packageName': ext.package,
          'canReply': ext.canReply,
          'quickReplies': quickReplies,
        },
        createdAt: ext.postTime,
      ),
    );
  }

  Future<void> _blockExternalApp({
    required String packageName,
    required String appName,
    required String notificationKey,
  }) async {
    final prefs = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
    final token = packageName.trim().isNotEmpty ? packageName.trim() : appName.trim();
    if (token.isEmpty) return;
    final nextList = <String>{...prefs.blockedExternalPackages, token}.toList();
    await ref.read(notificationServiceProvider).updatePreferences(
          prefs.copyWith(blockedExternalPackages: nextList),
        );
    if (notificationKey.isNotEmpty) {
      await ref.read(ovaDeviceHubProvider).dismissNotification(notificationKey).catchError((_) => false);
    }
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx != null && navCtx.mounted) {
      ScaffoldMessenger.of(navCtx).showSnackBar(
        SnackBar(
          content: Text('Blocked notifications from $appName'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              final cur = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
              final restored = cur.blockedExternalPackages.where((p) => p != token).toList();
              ref.read(notificationServiceProvider).updatePreferences(
                    cur.copyWith(blockedExternalPackages: restored),
                  );
            },
          ),
        ),
      );
    }
  }

  List<String> _buildInstantSmartReplies(String sender, String text, String appName) {
    final lower = text.toLowerCase();
    if (lower.contains('?') || lower.contains('when') || lower.contains('where') || lower.contains('are you')) {
      return const ['On my way 🚀', 'Give me 5 mins', 'Yes, definitely 👍', 'Call me quick 📞'];
    }
    if (lower.contains('photo') || lower.contains('video') || lower.contains('reel') || lower.contains('look')) {
      return const ['Looks fire 🔥', 'Love this! ❤️', 'Send me the HD file', 'Checking now 👀'];
    }
    if (lower.contains('call') || lower.contains('missed') || lower.contains('urgent')) {
      return const ['Calling you in 2m 📞', 'In the studio, text me', 'Everything okay?', 'On it right now ⚡'];
    }
    return const ['👍 Got it!', 'On my way 🚀', 'Give me 5 mins', 'Let’s do it 🔥'];
  }

  static const List<(String, String)> _fallbackAiSuggestions = [
    (
      '✨ Ova Live AI · Viral Reel Hook',
      'Open your next Reel with a 1.5s motion contrast cut — creators using fast hook transitions are seeing +42% retention today.',
    ),
    (
      '🎵 Ova Studio AI · Multi-Photo + Music',
      'Post up to 10 photos in Status or Reels with an attached track — multi-photo carousels with music are getting 2.3× more replies.',
    ),
    (
      '⚡ Ova Live Pulse · 1-Second Smart Replies',
      'Messages from your other apps pop up live here with 1-tap AI replies so you can respond in a second without leaving Oneova.',
    ),
    (
      '🎨 Ova Color Director · Cinema Grade',
      'Try Golden Hour Warmth or tell Ova AI how to grade your frame in plain English before publishing your next video.',
    ),
    (
      '🚀 Ova Growth AI · Peak Audience Window',
      'Your followers are most active right now — drop a quick status with music or reply to top comments to boost reach.',
    ),
    (
      '🎙️ Ova AI Agent · Voice & Attach Tools',
      'Tap + in Ova AI to attach photos, camera shots, clipboard, or My Computer control and let the agent finish tasks in seconds.',
    ),
  ];

  Future<void> _triggerLiveStartupAiSuggestion() async {
    _lastAiPulseAt = DateTime.now();
    final rng = math.Random();
    var (String title, String body) =
        _fallbackAiSuggestions[rng.nextInt(_fallbackAiSuggestions.length)];

    // Attempt a fast live AI suggestion from OneovaAiGateway (2.5s budget so startup feels snappy)
    try {
      final user = FirebaseAuth.instance.currentUser;
      final nameHint = user?.displayName?.split(' ').first ?? 'Creator';
      final hour = DateTime.now().hour;
      final timeOfDay = hour < 12 ? 'morning' : (hour < 18 ? 'afternoon' : 'evening');
      final aiText = await OneovaAiGateway
          .generate(
            prompt:
                'Give $nameHint ONE punchy, high-energy $timeOfDay creative suggestion (max 18 words) for filming a Reel, posting a multi-photo story with music, or growing their audience on Oneova today. Plain text only, no quotes.',
            systemInstruction:
                'You are Ova Live AI inside Oneova Studio. Reply with a single inspiring, actionable 1-sentence tip under 18 words.',
            temperature: 0.85,
            maxOutputTokens: 60,
          )
          .timeout(const Duration(milliseconds: 2600));
      final cleaned = aiText.replaceAll('"', '').replaceAll('\n', ' ').trim();
      if (cleaned.length >= 16) {
        title = '✨ Ova Live AI · Personalized Tip';
        body = cleaned;
      }
    } catch (_) {
      // Fallback suggestion already selected
    }

    if (!mounted) return;

    // 1. Update the Android system notification so the notification shade shows the live AI suggestion
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _assistantChannel.invokeMethod('updateAssistantNotification', {
          'title': title,
          'body': body,
        });
      } catch (_) {}
    }

    // 2. Check if Notification Access is enabled on Android and if there are recent cross-app notifications
    bool hasNotifAccess = true;
    List<OvaPhoneNotification> recentExternal = const [];
    if (OvaDeviceHub.supported) {
      try {
        final hub = ref.read(ovaDeviceHubProvider);
        final st = await hub.status();
        hasNotifAccess = st.notificationAccess;
        if (hasNotifAccess) {
          final all = await hub.notifications(limit: 2);
          final cutoff = DateTime.now().subtract(const Duration(minutes: 20));
          recentExternal = all.where((x) => x.postTime.isAfter(cutoff)).toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    // 3. Enqueue the in-app Live AI Suggestion popup
    _enqueue(
      AppNotification(
        id: 'ai_startup_${DateTime.now().millisecondsSinceEpoch}',
        userId: FirebaseAuth.instance.currentUser?.uid ?? 'local',
        category: AppNotificationCategory.aiSuggestion,
        priority: AppNotificationPriority.urgent,
        title: title,
        body: body,
        deepLink: '/hub/ai',
        payload: {
          'isStartupAiSuggestion': true,
          'needsNotificationAccess': OvaDeviceHub.supported && !hasNotifAccess,
          'quickReplies': const ['✨ Ask Ova AI', '🎬 Film Reel', '🎵 Story + Music'],
        },
        createdAt: DateTime.now(),
      ),
    );

    // 4. If there's an active recent notification from another app, queue it right behind so user sees what's happening
    for (final ext in recentExternal.take(1)) {
      _enqueueExternalAppNotification(ext);
    }
  }

  // ───────────────────────── Queue ─────────────────────────

  void _enqueue(AppNotification n) {
    if (!_seen.add(n.id)) return;
    if (_seen.length > 300) _seen.remove(_seen.first);

    final prefs = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
    final urgent = n.priority == AppNotificationPriority.urgent;
    // Tips and update notes wait quietly in the centre and the system tray.
    if (n.priority == AppNotificationPriority.low) return;
    if (!prefs.inAppEnabled && !urgent) return;
    if (!prefs.isCategoryEnabled(n.category.name) && !urgent) return;

    // A newer message from the same chat replaces the queued one.
    if (n.groupId != null) _queue.removeWhere((q) => q.groupId == n.groupId);
    if (urgent) {
      _queue.insert(0, n);
    } else {
      _queue.add(n);
    }
    if (_queue.length > 20) _queue.removeRange(20, _queue.length);

    if (_current == null) {
      _presentNext();
    } else {
      _entry?.markNeedsBuild(); // update the "+N" badge
    }
  }

  void _presentNext() {
    if (!mounted || _queue.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ?? rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      _current = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _current == null) _presentNext();
      });
      return;
    }

    final n = _queue.removeAt(0);
    _current = n;
    final prefs = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
    final quiet = prefs.isInQuietHours() && n.priority != AppNotificationPriority.urgent;
    if (!quiet) _ring(n, prefs);

    final isExternal = n.payload?['isExternalApp'] == true;
    final externalKey = n.payload?['notificationKey']?.toString() ?? '';

    _entry = OverlayEntry(
      builder: (_) => _PopupBanner(
        key: ValueKey(n.id),
        notification: n,
        pending: _queue.length,
        duration: Duration(
          seconds: n.isLive
              ? 8
              : (isExternal || n.category == AppNotificationCategory.aiSuggestion || n.category == AppNotificationCategory.newMessage
                  ? 7
                  : 5),
        ),
        onOpen: () {
          _finish();
          if (isExternal && externalKey.isNotEmpty) {
            _openExternalNotification(externalKey, n.payload?['packageName']?.toString());
            return;
          }
          if (mounted && !n.id.startsWith('chat_') && !n.id.startsWith('ai_startup_') && !n.id.startsWith('ext_')) {
            ref.read(notificationServiceProvider).markAsRead(n.id);
          }
          final route = n.route ?? '/notifications';
          final navCtx = rootNavigatorKey.currentContext;
          if (navCtx != null && navCtx.mounted) {
            if (route.startsWith('/hub/home')) {
              GoRouter.of(navCtx).go(route);
            } else {
              GoRouter.of(navCtx).push(route);
            }
          }
        },
        onReply: isExternal && externalKey.isNotEmpty
            ? (text) => _replyExternal(externalKey, text)
            : (n.category == AppNotificationCategory.newMessage && n.payload?['chatId'] is String)
                ? (text) => _reply(n.payload!['chatId'] as String, text)
                : ((n.category == AppNotificationCategory.comment || n.category == AppNotificationCategory.reply) && n.payload?['postId'] is String)
                    ? (text) => _replyComment(n.payload!['postId'] as String, text)
                    : null,
        onQuickAction: (actionId) {
          _finish();
          final navCtx = rootNavigatorKey.currentContext;
          if (actionId == 'block_external_app') {
            _blockExternalApp(
              packageName: n.payload?['packageName']?.toString() ?? '',
              appName: n.payload?['appName']?.toString() ?? 'External App',
              notificationKey: externalKey,
            );
            return;
          }
          if (actionId == 'block_all_external') {
            final cur = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
            ref.read(notificationServiceProvider).updatePreferences(
                  cur.copyWith(blockExternalAppNotifications: true),
                );
            if (externalKey.isNotEmpty) {
              ref.read(ovaDeviceHubProvider).dismissNotification(externalKey).catchError((_) => false);
            }
            return;
          }
          if (actionId == 'link_apps') {
            ref.read(ovaDeviceHubProvider).openNotificationAccess();
            return;
          }
          if (navCtx != null && navCtx.mounted) {
            if (actionId == 'ask_ai') {
              GoRouter.of(navCtx).push('/hub/ai');
            } else if (actionId == 'film_reel') {
              GoRouter.of(navCtx).push('/create');
            } else if (actionId == 'story_music') {
              GoRouter.of(navCtx).go('/hub/home');
            }
          }
        },
        onDone: _finish,
      ),
    );
    overlay.insert(_entry!);
  }

  Future<void> _openExternalNotification(String key, String? packageName) async {
    try {
      final opened = await ref.read(ovaDeviceHubProvider).openNotification(key);
      if (!opened && packageName != null && packageName.isNotEmpty) {
        await _assistantChannel.invokeMethod('launchApp', {'packageName': packageName});
      }
    } catch (_) {}
  }

  Future<void> _replyExternal(String key, String text) async {
    if (text.trim().isEmpty) return;
    try {
      final res = await ref.read(ovaDeviceHubProvider).reply(key, text.trim());
      if (res != 'ok') {
        await Clipboard.setData(ClipboardData(text: text.trim()));
        await ref.read(ovaDeviceHubProvider).openNotification(key);
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text.trim()));
    }
  }

  void _finish() {
    if (_entry?.mounted ?? false) {
      _entry?.remove();
    }
    _entry = null;
    _current = null;
    if (_queue.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 220), () {
        if (mounted && _current == null) _presentNext();
      });
    }
  }

  Future<void> _reply(String chatId, String text) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || text.trim().isEmpty) return;
    await ref.read(messagingRepositoryProvider).sendMessage(chatId, me, text.trim());
  }

  Future<void> _replyComment(String postId, String text) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || text.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('posts').doc(postId).collection('comments').add({
        'postId': postId,
        'authorId': me,
        'content': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'likeCount': 0,
      });
      await FirebaseFirestore.instance.collection('content').doc(postId).update({
        'commentCount': FieldValue.increment(1),
      }).catchError((_) {});
    } catch (e) {
      debugPrint('[NotificationOverlay] replyComment error: $e');
    }
  }

  /// Plays the user's chosen tone. Go-live alerts ring twice with a firmer
  /// haptic when "Ring for live" is on.
  Future<void> _ring(AppNotification notification, NotificationPreferences prefs) async {
    final sound = OneOvaSoundService();
    final tone = prefs.soundEnabled ? prefs.ringtone : 'mute';
    if (!prefs.soundEnabled && !prefs.vibrateEnabled) return;
    if (prefs.vibrateEnabled) HapticFeedback.lightImpact();
    if (notification.isLive && prefs.ringForLive) {
      if (prefs.vibrateEnabled) await OneOvaSoundService.playHaptic('heavy');
      await sound.playNotificationChime(tone);
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      await sound.playNotificationChime(tone);
      return;
    }
    await sound.playNotificationChime(tone);
  }

  // ───────────────────────── Chat messages ─────────────────────────

  void _syncChatListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == _chatUid) return;
    _chatSub?.cancel();
    _chatSub = null;
    _chatUid = uid;
    if (uid == null) return;
    _chatSince = DateTime.now();
    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .limit(15)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type == DocumentChangeType.removed) continue;
        _onChatChanged(uid, c.doc);
      }
    }, onError: (Object e) => debugPrint('[NotificationOverlay] chat listener: $e'));
  }

  Future<void> _onChatChanged(String me, DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data();
    if (d == null) return;
    final sender = d['lastMessageSenderId'] as String?;
    final ts = d['lastMessageTime'];
    final at = ts is Timestamp ? ts.toDate() : null;
    if (sender == null || sender == me || at == null || !at.isAfter(_chatSince)) return;
    final muted = d['mutedBy'];
    if (muted is List && muted.contains(me)) return;

    // Already looking at this chat (or in a call): don't pop.
    final path = _currentPath();
    if (path == '/hub/messages/${doc.id}' || path.startsWith('/call/')) return;

    final person = await _person(sender);
    final isGroup = d['isGroup'] == true || ((d['participants'] as List?)?.length ?? 0) > 2;
    final chatName = (d['name'] ?? d['groupName'] ?? d['title']) as String?;
    final preview = (d['lastMessage'] as String?)?.trim();
    _enqueue(AppNotification(
      id: 'chat_${doc.id}_${at.millisecondsSinceEpoch}',
      userId: me,
      actorId: sender,
      category: AppNotificationCategory.newMessage,
      title: isGroup && chatName != null && chatName.isNotEmpty ? '${person.name} · $chatName' : person.name,
      body: preview == null || preview.isEmpty ? 'New message' : preview,
      groupId: 'chat_${doc.id}',
      payload: {'chatId': doc.id, 'senderName': person.name, 'senderAvatar': person.avatar},
      deepLink: '/hub/messages/${doc.id}',
      createdAt: at,
    ));
  }

  Future<({String name, String? avatar})> _person(String uid) async {
    final cached = _people[uid];
    if (cached != null) return cached;
    try {
      final d = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data() ?? {};
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = d[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final p = (
        name: pick(['fullName', 'displayName', 'username']) ?? 'New message',
        avatar: pick(['profilePhotoUrl', 'photoUrl', 'avatarUrl']),
      );
      _people[uid] = p;
      return p;
    } catch (_) {
      return (name: 'New message', avatar: null);
    }
  }

  String _currentPath() {
    try {
      return GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep preferences warm so the first banner already honours them.
    ref.watch(notificationPreferencesProvider);
    ref.listen<AsyncValue<AppNotification>>(
      incomingNotificationProvider,
      (previous, next) {
        final n = next.value;
        if (n != null && !n.isRead) _enqueue(n);
      },
    );
    return widget.child;
  }
}

// ───────────────────────── Pop-up ─────────────────────────

class _PopupBanner extends StatefulWidget {
  final AppNotification notification;
  final int pending;
  final Duration duration;
  final VoidCallback onOpen;
  final VoidCallback onDone;
  final Future<void> Function(String text)? onReply;
  final void Function(String actionId)? onQuickAction;

  const _PopupBanner({
    super.key,
    required this.notification,
    required this.pending,
    required this.duration,
    required this.onOpen,
    required this.onDone,
    this.onReply,
    this.onQuickAction,
  });

  @override
  State<_PopupBanner> createState() => _PopupBannerState();
}

class _PopupBannerState extends State<_PopupBanner> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();
  late final AnimationController _countdown = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _close();
    })
    ..forward();
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _expanded = false;
  bool _replying = false;
  bool _sending = false;
  bool _closing = false;
  bool _draftingAi = false;
  String? _sentQuickReplyLabel;
  double _dragDy = 0;

  AppNotification get n => widget.notification;

  @override
  void dispose() {
    _enter.dispose();
    _countdown.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _countdown.stop();
    await _enter.reverse();
    widget.onDone();
  }

  void _hold() => _countdown.stop();

  void _resume() {
    if (!_replying && !_closing) _countdown.forward();
  }

  void _startReply() {
    HapticFeedback.selectionClick();
    _hold();
    setState(() {
      _replying = true;
      _expanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _replyFocus.requestFocus());
  }

  Future<void> _sendQuickInstantReply(String text) async {
    if (widget.onReply == null || _sending) return;
    _hold();
    HapticFeedback.mediumImpact();
    setState(() {
      _sending = true;
      _sentQuickReplyLabel = text;
    });
    try {
      await widget.onReply!(text);
    } catch (_) {}
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 280));
    if (mounted) _close();
  }

  Future<void> _draftAiReply() async {
    if (_draftingAi) return;
    _hold();
    HapticFeedback.selectionClick();
    setState(() => _draftingAi = true);
    try {
      final draft = await OneovaAiGateway
          .generate(
            prompt:
                'Write a natural, friendly, 1-sentence quick reply (under 14 words) to this message from "${n.title}": "${n.body}". Plain text only, no quotes.',
            systemInstruction: 'Reply with ONLY the short message text ready to send.',
            temperature: 0.7,
            maxOutputTokens: 40,
          )
          .timeout(const Duration(milliseconds: 1800));
      final clean = draft.replaceAll('"', '').trim();
      if (mounted && clean.isNotEmpty) {
        _replyCtrl.text = clean;
        _replyCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _replyCtrl.text.length));
      }
    } catch (_) {
      if (mounted) {
        _replyCtrl.text = 'Got it, on it right now! ⚡';
      }
    } finally {
      if (mounted) setState(() => _draftingAi = false);
    }
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || widget.onReply == null || _sending) return;
    setState(() => _sending = true);
    HapticFeedback.lightImpact();
    try {
      await widget.onReply!(text);
    } catch (_) {}
    if (!mounted) return;
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final isDark = context.isDark;
    final curve = CurvedAnimation(parent: _enter, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);

    return Positioned(
      top: safeTop + 6,
      left: 10,
      right: 10,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, (1 - curve.value) * -120 + _dragDy),
          child: Opacity(opacity: _enter.value.clamp(0.0, 1.0), child: child),
        ),
        child: Dismissible(
          key: ValueKey('dismiss_${n.id}'),
          direction: _replying ? DismissDirection.none : DismissDirection.horizontal,
          onDismissed: (_) {
            _closing = true;
            widget.onDone();
          },
          child: GestureDetector(
            onTap: _replying ? null : widget.onOpen,
            onLongPressStart: (_) {
              HapticFeedback.selectionClick();
              _hold();
              setState(() => _expanded = true);
            },
            onLongPressEnd: (_) => _resume(),
            onVerticalDragUpdate: (d) => setState(() => _dragDy = (_dragDy + d.delta.dy).clamp(-80.0, 30.0)),
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (_dragDy < -30 || v < -300) {
                _close();
              } else {
                if (_dragDy > 12 || v > 300) setState(() => _expanded = true);
                setState(() => _dragDy = 0);
              }
            },
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.surface.withValues(alpha: isDark ? 0.93 : 0.96),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.28), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandBlue.withValues(alpha: 0.22),
                          blurRadius: 26,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: AppColors.brandBlack.withValues(alpha: isDark ? 0.6 : 0.1),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 11, 8, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _visual(),
                              const SizedBox(width: 11),
                              Expanded(child: _texts()),
                              const SizedBox(width: 6),
                              Column(
                                children: [
                                  GestureDetector(
                                    onTap: _close,
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(color: context.surfaceMid, shape: BoxShape.circle),
                                      child: Icon(Icons.close_rounded, size: 13, color: context.textSecondary),
                                    ),
                                  ),
                                  if (widget.pending > 0) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.brandPink,
                                        borderRadius: BorderRadius.circular(AppRadius.full),
                                      ),
                                      child: Text('+${widget.pending}',
                                          style: GoogleFonts.inter(
                                              fontSize: 9.5, fontWeight: FontWeight.w900, color: AppColors.brandWhite)),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (!_replying) _quickAiPillsStrip(),
                        if (_replying) _replyField() else _actions(),
                        AnimatedBuilder(
                          animation: _countdown,
                          builder: (_, _) => LinearProgressIndicator(
                            value: 1 - _countdown.value,
                            minHeight: 2,
                            color: n.isLive ? AppColors.brandPink : AppColors.brandBlue,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _texts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                n.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            n.isLive && n.liveStreamId != null
                ? _LiveStatusChip(streamId: n.liveStreamId!)
                : Text('now', style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
          ],
        ),
        const SizedBox(height: 2),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: Text(
            n.body,
            maxLines: _expanded ? 8 : 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, height: 1.3),
          ),
        ),
        if (n.category == AppNotificationCategory.like ||
            n.category == AppNotificationCategory.comment ||
            n.category == AppNotificationCategory.reply) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.28), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      n.category == AppNotificationCategory.like
                          ? Icons.favorite_rounded
                          : Icons.chat_bubble_rounded,
                      size: 10,
                      color: n.category == AppNotificationCategory.like
                          ? AppColors.brandPink
                          : AppColors.brandBlue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      n.category == AppNotificationCategory.like ? 'Liked your reel' : 'New comment on reel',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: n.category == AppNotificationCategory.like
                            ? AppColors.brandPink
                            : AppColors.brandBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (_expanded && n.thumbnailUrl != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.network(n.thumbnailUrl!,
                height: 120, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink()),
          ),
        ],
      ],
    );
  }

  Widget _quickAiPillsStrip() {
    final isStartupAi = n.payload?['isStartupAiSuggestion'] == true || n.category == AppNotificationCategory.aiSuggestion;
    final needsNotifAccess = n.payload?['needsNotificationAccess'] == true;
    if (isStartupAi) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _quickAiPill('✨ Ask Ova AI', () => widget.onQuickAction?.call('ask_ai'), highlight: true),
              const SizedBox(width: 6),
              _quickAiPill('🎬 Film Reel', () => widget.onQuickAction?.call('film_reel')),
              const SizedBox(width: 6),
              _quickAiPill('🎵 Story + Music', () => widget.onQuickAction?.call('story_music')),
              if (needsNotifAccess) ...[
                const SizedBox(width: 6),
                _quickAiPill('⚡ Link Other Apps', () => widget.onQuickAction?.call('link_apps'), highlight: true),
              ],
            ],
          ),
        ),
      );
    }

    if (widget.onReply == null) return const SizedBox.shrink();

    final rawList = n.payload?['quickReplies'];
    final List<String> replies = rawList is List
        ? rawList.map((e) => e.toString()).toList()
        : const ['👍 Got it!', 'On my way 🚀', 'Give me 5 mins', 'Let’s do it 🔥'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded, size: 11, color: AppColors.brandPink),
                  const SizedBox(width: 2),
                  Text(
                    '1s AI',
                    style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.brandPink),
                  ),
                ],
              ),
            ),
            for (final r in replies) ...[
              _quickAiPill(
                _sentQuickReplyLabel == r ? '✓ Sent!' : r,
                () => _sendQuickInstantReply(r),
                highlight: _sentQuickReplyLabel == r,
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quickAiPill(String label, VoidCallback onTap, {bool highlight = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: highlight ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: highlight ? AppColors.brandBlue : AppColors.brandBlue.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: highlight ? AppColors.brandWhite : context.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final isExternal = n.payload?['isExternalApp'] == true;
    final appName = n.payload?['appName']?.toString() ?? 'App';
    final isChat = n.category == AppNotificationCategory.newMessage;
    final isComment = n.category == AppNotificationCategory.comment ||
        n.category == AppNotificationCategory.reply ||
        n.category == AppNotificationCategory.mention;
    final isLike = n.category == AppNotificationCategory.like ||
        n.category == AppNotificationCategory.reaction;
    final (label, icon) = _primaryAction();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
            if ((isChat || isComment) && widget.onReply != null) ...[
              _chip(Icons.reply_rounded, 'Custom Reply', _startReply, primary: true),
              const SizedBox(width: 8),
              _chip(
                Icons.open_in_new_rounded,
                isExternal ? 'Open $appName' : 'View',
                widget.onOpen,
              ),
              if (isExternal) ...[
                const SizedBox(width: 8),
                _chip(
                  Icons.block_rounded,
                  'Block $appName',
                  () => widget.onQuickAction?.call('block_external_app'),
                ),
              ],
            ] else if (isLike) ...[
              _chip(Icons.favorite_rounded, '❤️ Like back', widget.onOpen, primary: true),
              const SizedBox(width: 8),
              _chip(Icons.play_circle_outline_rounded, 'View reel', widget.onOpen),
            ] else ...[
              _chip(icon, label, widget.onOpen, primary: true),
              if (isExternal) ...[
                const SizedBox(width: 8),
                _chip(
                  Icons.block_rounded,
                  'Block $appName',
                  () => widget.onQuickAction?.call('block_external_app'),
                ),
              ],
            ],
          const Spacer(),
          if (!_expanded)
            Text('Hold to expand',
                style: GoogleFonts.inter(fontSize: 10, color: context.textMuted)),
        ],
      ),
    );
  }

  (String, IconData) _primaryAction() {
    switch (n.category) {
      case AppNotificationCategory.call:
      case AppNotificationCategory.missedCall:
        return ('Call back', Icons.call_rounded);
      case AppNotificationCategory.live:
        return ('Join live', Icons.play_arrow_rounded);
      case AppNotificationCategory.newPost:
        return ('Watch', Icons.play_arrow_rounded);
      case AppNotificationCategory.newFollower:
        return ('View profile', Icons.person_rounded);
      case AppNotificationCategory.comment:
      case AppNotificationCategory.reply:
      case AppNotificationCategory.mention:
        return ('View', Icons.chat_bubble_outline_rounded);
      default:
        return ('Open', Icons.arrow_forward_rounded);
    }
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap, {bool primary = false}) {
    final bg = primary ? (n.isLive ? AppColors.brandPink : AppColors.brandBlue) : context.surfaceMid;
    final fg = primary ? AppColors.brandWhite : context.textPrimary;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: primary ? null : Border.all(color: context.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _replyField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: _draftAiReply,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_draftingAi)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandPink),
                    )
                  else
                    const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.brandPink),
                  const SizedBox(width: 4),
                  Text(
                    'AI',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brandPink),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              focusNode: _replyFocus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Reply in 1 second…',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide(color: context.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _sending ? null : _sendReply,
            icon: _sending
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                : const Icon(Icons.send_rounded, color: AppColors.brandBlue, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _visual() {
    final avatar = n.actorAvatarUrl;
    final (icon, color) = _categoryStyle();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (avatar != null && avatar.isNotEmpty)
          CircleAvatar(radius: 21, backgroundColor: color, backgroundImage: NetworkImage(avatar))
        else
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, color: AppColors.brandWhite, size: 22),
          ),
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: context.surface, width: 2),
            ),
            child: Icon(icon, size: 9, color: AppColors.brandWhite),
          ),
        ),
      ],
    );
  }

  (IconData, Color) _categoryStyle() {
    switch (n.category) {
      case AppNotificationCategory.reaction:
      case AppNotificationCategory.like:
        return (Icons.favorite_rounded, AppColors.brandPink);
      case AppNotificationCategory.mention:
      case AppNotificationCategory.comment:
      case AppNotificationCategory.reply:
        return (Icons.chat_bubble_outline_rounded, AppColors.brandBlue);
      case AppNotificationCategory.newMessage:
        return (Icons.chat_bubble_rounded, AppColors.brandBlue);
      case AppNotificationCategory.newFollower:
        return (Icons.person_add_rounded, AppColors.brandBlue);
      case AppNotificationCategory.call:
      case AppNotificationCategory.missedCall:
        return (Icons.call_rounded, AppColors.brandPink);
      case AppNotificationCategory.aiSuggestion:
        return (Icons.auto_awesome_rounded, AppColors.brandPink);
      case AppNotificationCategory.security:
        return (Icons.shield_rounded, AppColors.brandBlue);
      case AppNotificationCategory.live:
        return (Icons.sensors_rounded, AppColors.brandPink);
      case AppNotificationCategory.newPost:
        return (Icons.play_circle_fill_rounded, AppColors.brandBlue);
      default:
        return (Icons.notifications_active_rounded, AppColors.brandBlue);
    }
  }
}

/// LIVE / ENDED pill that follows the stream document in real time.
class _LiveStatusChip extends ConsumerWidget {
  final String streamId;
  const _LiveStatusChip({required this.streamId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(liveStreamProvider(streamId)).value;
    final ended = stream != null &&
        (stream.status == LiveStreamStatus.ended || stream.status == LiveStreamStatus.abandoned);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ended ? context.surfaceMid : AppColors.brandPink,
        borderRadius: BorderRadius.circular(6),
        border: ended ? Border.all(color: context.border, width: 1.0) : null,
      ),
      child: Text(
        ended ? 'ENDED' : 'LIVE',
        style: GoogleFonts.inter(
          color: ended ? context.textSecondary : AppColors.brandWhite,
          fontWeight: FontWeight.w900,
          fontSize: 8.5,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
