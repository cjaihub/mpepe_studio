import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

class _NotificationOverlayManagerState extends ConsumerState<NotificationOverlayManager> {
  final List<AppNotification> _queue = [];
  final Set<String> _seen = {};
  OverlayEntry? _entry;
  AppNotification? _current;

  // Chat message pop-ups
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatSub;
  String? _chatUid;
  DateTime _chatSince = DateTime.now();
  final Map<String, ({String name, String? avatar})> _people = {};
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) _syncChatListener();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _chatSub?.cancel();
    if (_entry?.mounted ?? false) {
      _entry?.remove();
    }
    _entry = null;
    super.dispose();
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

    _entry = OverlayEntry(
      builder: (_) => _PopupBanner(
        key: ValueKey(n.id),
        notification: n,
        pending: _queue.length,
        duration: Duration(seconds: n.isLive ? 8 : (n.category == AppNotificationCategory.newMessage ? 6 : 5)),
        onOpen: () {
          _finish();
          if (mounted && !n.id.startsWith('chat_')) {
            ref.read(notificationServiceProvider).markAsRead(n.id);
          }
          final route = n.route ?? '/notifications';
          final navCtx = rootNavigatorKey.currentContext;
          if (navCtx != null && navCtx.mounted) {
            GoRouter.of(navCtx).push(route);
          }
        },
        onReply: (n.category == AppNotificationCategory.newMessage && n.payload?['chatId'] is String)
            ? (text) => _reply(n.payload!['chatId'] as String, text)
            : ((n.category == AppNotificationCategory.comment || n.category == AppNotificationCategory.reply) && n.payload?['postId'] is String)
                ? (text) => _replyComment(n.payload!['postId'] as String, text)
                : null,
        onDone: _finish,
      ),
    );
    overlay.insert(_entry!);
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

  const _PopupBanner({
    super.key,
    required this.notification,
    required this.pending,
    required this.duration,
    required this.onOpen,
    required this.onDone,
    this.onReply,
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

  Widget _actions() {
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
            _chip(Icons.reply_rounded, 'Reply', _startReply, primary: true),
            const SizedBox(width: 8),
            _chip(Icons.open_in_new_rounded, 'View', widget.onOpen),
          ] else if (isLike) ...[
            _chip(Icons.favorite_rounded, '❤️ Like back', widget.onOpen, primary: true),
            const SizedBox(width: 8),
            _chip(Icons.play_circle_outline_rounded, 'View reel', widget.onOpen),
          ] else
            _chip(icon, label, widget.onOpen, primary: true),
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
          Expanded(
            child: TextField(
              controller: _replyCtrl,
              focusNode: _replyFocus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendReply(),
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Reply…',
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
