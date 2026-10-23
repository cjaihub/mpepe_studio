import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../backend/messaging_repository.dart';
import '../core/ova_tool_result.dart';
import 'ova_device_abilities.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d) => {'type': 'string', 'description': d};

/// Something the user did recently, read from Firestore.
class OvaActivity {
  final String kind; // project, upload, chat, ova
  final String title;
  final String? detail;
  final DateTime at;
  final String? route;

  const OvaActivity(this.kind, this.title, this.at, {this.detail, this.route});
}

/// Ova's working memory: what the user has been doing (projects, uploads,
/// chats, past Ova requests) and reminders, all stored in Firestore.
class OvaMemoryTools {
  OvaMemoryTools._();
  static final OvaMemoryTools instance = OvaMemoryTools._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const names = {'recent_activity', 'set_reminder', 'list_reminders', 'cancel_reminder'};

  List<OvaToolSpec> get specs => [
        OvaToolSpec(
          'recent_activity',
          'Look up what the user has been working on lately: studio projects and drafts, uploads, recent chats and past Ova requests. '
              'Use it for "what was I doing", "where did I leave off", or before suggesting what to do next.',
        ),
        OvaToolSpec('set_reminder', 'Schedule a reminder notification at a time. Saved to the user\'s Oneova account.', properties: {
          'text': _s('What to remind about, e.g. "post the dance reel"'),
          'at': _s('ISO 8601 local time, e.g. 2026-10-16T18:30'),
        }, required: ['text', 'at']),
        OvaToolSpec('list_reminders', 'List the user\'s upcoming reminders.'),
        OvaToolSpec('cancel_reminder', 'Cancel an upcoming reminder.', properties: {
          'query': _s('Words from the reminder text, or its id'),
        }, required: ['query']),
      ];

  String? get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  static const _signIn = OvaResultAction(label: 'Sign in', icon: Icons.login_rounded, route: '/auth/main_login');

  Future<OvaToolResult> run(String name, Map<String, dynamic> a, OvaDeviceAbilities device, BuildContext? context) async {
    String s(String k) => (a[k] ?? '').toString().trim();
    switch (name) {
      case 'recent_activity':
        return recentActivity();
      case 'set_reminder':
        final at = DateTime.tryParse(s('at'));
        if (at == null) return OvaToolResult.fail('When should I remind you?');
        return setReminder(device, context, s('text'), at);
      case 'list_reminders':
        return listReminders();
      case 'cancel_reminder':
        return cancelReminder(device, s('query'));
    }
    return OvaToolResult.fail('Unknown memory action.');
  }

  // ── Recent activity ────────────────────────────────────────────────────

  DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : (v is String ? DateTime.tryParse(v) : null);

  Future<List<OvaActivity>> loadActivity({int limit = 10}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final out = <OvaActivity>[];

    Future<void> safe(Future<void> Function() f) async {
      try {
        await f().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[OvaMemory] activity source failed: $e');
      }
    }

    await Future.wait([
      safe(() async {
        final q = await _db.collection('studio_projects').where('ownerId', isEqualTo: uid).limit(30).get();
        for (final d in q.docs) {
          final m = d.data();
          final at = _date(m['updatedAt']) ?? _date(m['createdAt']);
          if (at == null) continue;
          final done = (m['completedSteps'] as num?)?.toInt();
          final total = (m['totalSteps'] as num?)?.toInt();
          out.add(OvaActivity(
            'project',
            (m['title'] as String?)?.trim().isNotEmpty == true ? m['title'] as String : 'Untitled project',
            at,
            detail: [
              ?m['status'] as String?,
              ?m['category'] as String?,
              if (done != null && total != null && total > 0) '$done/$total steps',
            ].join(' · '),
            route: '/create/picker',
          ));
        }
      }),
      safe(() async {
        final q = await _db.collection('content').where('authorId', isEqualTo: uid).limit(30).get();
        for (final d in q.docs) {
          final m = d.data();
          final at = _date(m['createdAt']);
          if (at == null) continue;
          final desc = (m['description'] as String?)?.trim() ?? '';
          out.add(OvaActivity(
            'upload',
            desc.isEmpty ? 'Untitled ${m['type'] ?? 'post'}' : (desc.length > 60 ? '${desc.substring(0, 60)}…' : desc),
            at,
            detail: '${m['viewCount'] ?? 0} views · ${m['likeCount'] ?? 0} likes · ${m['commentCount'] ?? 0} comments',
            route: '/profile/me',
          ));
        }
      }),
      safe(() async {
        final q = await _db
            .collection('chats')
            .where('participants', arrayContains: uid)
            .orderBy('lastMessageTime', descending: true)
            .limit(5)
            .get();
        for (final d in q.docs) {
          final chat = ChatModel.fromFirestore(d);
          final at = chat.lastMessageTime?.toDate();
          if (at == null) continue;
          var name = chat.title ?? '';
          if (name.isEmpty) {
            final other = chat.participants.firstWhere((p) => p != uid, orElse: () => '');
            if (other.isNotEmpty) {
              final u = await _db.collection('users').doc(other).get();
              name = (u.data()?['displayName'] as String?) ?? (u.data()?['username'] as String?) ?? '';
            }
          }
          final unread = chat.unreadCounts[uid] ?? 0;
          out.add(OvaActivity(
            'chat',
            name.isEmpty ? 'A chat' : 'Chat with $name',
            at,
            detail: '${chat.lastMessageSenderId == uid ? 'You: ' : ''}${chat.lastMessage}${unread > 0 ? ' · $unread unread' : ''}',
            route: '/hub/messages',
          ));
        }
      }),
      safe(() async {
        final q = await _db.collection('users').doc(uid).collection('ai_interactions').orderBy('timestamp', descending: true).limit(6).get();
        for (final d in q.docs) {
          final m = d.data();
          final at = _date(m['timestamp']);
          final query = (m['query'] as String?)?.trim() ?? '';
          if (at == null || query.isEmpty) continue;
          out.add(OvaActivity('ova', 'Asked Ova: ${query.length > 60 ? '${query.substring(0, 60)}…' : query}', at));
        }
      }),
    ]);
    out.sort((a, b) => b.at.compareTo(a.at));
    return out.take(limit).toList();
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24 && now.day == t.day) return 'today ${DateFormat.Hm().format(t)}';
    if (d.inDays < 2) return 'yesterday';
    if (d.inDays < 7) return DateFormat.EEEE().format(t);
    return DateFormat.MMMd().format(t);
  }

  static IconData _icon(String kind) => switch (kind) {
        'project' => Icons.movie_edit,
        'upload' => Icons.video_library_rounded,
        'chat' => Icons.chat_bubble_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  Future<OvaToolResult> recentActivity() async {
    if (_uid == null) {
      return const OvaToolResult(ok: false, summary: 'Sign in so I can see what you have been working on.', icon: Icons.lock_rounded, actions: [_signIn]);
    }
    final acts = await loadActivity();
    final reminders = await _upcoming(limit: 3);
    if (acts.isEmpty && reminders.isEmpty) {
      return const OvaToolResult(ok: true, summary: 'No recent projects, uploads or chats on your account yet.', icon: Icons.history_rounded);
    }
    final lines = [
      for (final a in acts) '- [${a.kind}] ${a.title}${a.detail != null && a.detail!.isNotEmpty ? ' (${a.detail})' : ''}, ${_when(a.at)}',
      for (final r in reminders) '- [reminder] ${r.$2} at ${_fmt(r.$3)}',
    ];
    return OvaToolResult(
      ok: true,
      title: 'What you have been up to',
      summary: 'Recent activity:\n${lines.join('\n')}',
      icon: Icons.history_rounded,
      items: [
        for (final a in acts.take(8))
          OvaResultItem(
            title: a.title,
            subtitle: [if (a.detail != null && a.detail!.isNotEmpty) a.detail!, _when(a.at)].join(' · '),
            icon: _icon(a.kind),
            onTap: a.route == null ? null : OvaResultAction(label: 'Open', icon: Icons.open_in_new_rounded, route: a.route),
          ),
        for (final r in reminders)
          OvaResultItem(title: r.$2, subtitle: 'Reminder · ${_fmt(r.$3)}', icon: Icons.notifications_active_rounded),
      ],
    );
  }

  // ── Reminders ──────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>>? get _reminders {
    final uid = _uid;
    return uid == null ? null : _db.collection('users').doc(uid).collection('reminders');
  }

  static String _fmt(DateTime t) {
    final now = DateTime.now();
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = t.year == tomorrow.year && t.month == tomorrow.month && t.day == tomorrow.day;
    final hm = DateFormat.jm().format(t);
    if (sameDay) return 'today $hm';
    if (isTomorrow) return 'tomorrow $hm';
    return '${DateFormat.MMMEd().format(t)} $hm';
  }

  Future<OvaToolResult> setReminder(OvaDeviceAbilities device, BuildContext? context, String text, DateTime at) async {
    if (text.isEmpty) return OvaToolResult.fail('What should I remind you about?');
    final col = _reminders;
    final ref = col?.doc();
    // Stable 31-bit id so the notification can be cancelled later.
    final notifId = (ref?.id.hashCode ?? at.millisecondsSinceEpoch) & 0x7fffffff;
    final res = await device.scheduleReminder(context, text, at, id: notifId);
    if (!res.ok) return res;
    if (ref == null) {
      return OvaToolResult(
        ok: true,
        summary: '${res.summary} (Saved on this phone only. Sign in to keep reminders in your account.)',
        icon: Icons.notifications_active_rounded,
      );
    }
    try {
      await ref.set({
        'text': text,
        'at': Timestamp.fromDate(at),
        'status': 'scheduled',
        'notificationId': notifId,
        'source': 'ova',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[OvaMemory] reminder save failed: $e');
    }
    return OvaToolResult(
      ok: true,
      title: 'Reminder set · ${_fmt(at)}',
      summary: 'Reminder set: "$text" at ${_fmt(at)}.',
      icon: Icons.notifications_active_rounded,
      actions: [
        OvaResultAction(label: 'Cancel it', icon: Icons.notifications_off_rounded, prompt: 'cancel reminder ${ref.id}'),
        const OvaResultAction(label: 'My reminders', icon: Icons.list_rounded, prompt: 'list my reminders'),
      ],
    );
  }

  /// (id, text, at, notificationId) of upcoming reminders.
  Future<List<(String, String, DateTime, int?)>> _upcoming({int limit = 20}) async {
    final col = _reminders;
    if (col == null) return const [];
    try {
      final q = await col.where('status', isEqualTo: 'scheduled').limit(50).get();
      final now = DateTime.now();
      final out = <(String, String, DateTime, int?)>[];
      for (final d in q.docs) {
        final at = _date(d.data()['at']);
        if (at == null) continue;
        if (at.isBefore(now)) {
          // Already fired: mark it done so the list stays accurate.
          d.reference.update({'status': 'done'}).catchError((_) {});
          continue;
        }
        out.add((d.id, (d.data()['text'] as String?) ?? '', at, (d.data()['notificationId'] as num?)?.toInt()));
      }
      out.sort((a, b) => a.$3.compareTo(b.$3));
      return out.take(limit).toList();
    } catch (e) {
      debugPrint('[OvaMemory] reminders load failed: $e');
      return const [];
    }
  }

  Future<OvaToolResult> listReminders() async {
    if (_uid == null) return const OvaToolResult(ok: false, summary: 'Sign in to see your reminders.', icon: Icons.lock_rounded, actions: [_signIn]);
    final list = await _upcoming();
    if (list.isEmpty) return const OvaToolResult(ok: true, summary: 'You have no upcoming reminders.', icon: Icons.notifications_none_rounded);
    return OvaToolResult(
      ok: true,
      title: '${list.length} upcoming reminder${list.length == 1 ? '' : 's'}',
      summary: 'Upcoming reminders:\n${list.map((r) => '- ${r.$2} at ${_fmt(r.$3)} (id ${r.$1})').join('\n')}',
      icon: Icons.notifications_active_rounded,
      items: [
        for (final r in list)
          OvaResultItem(
            title: r.$2,
            subtitle: _fmt(r.$3),
            icon: Icons.notifications_off_rounded,
            onTap: OvaResultAction(label: 'Cancel', icon: Icons.close_rounded, prompt: 'cancel reminder ${r.$1}'),
          ),
      ],
    );
  }

  Future<OvaToolResult> cancelReminder(OvaDeviceAbilities device, String query) async {
    if (_uid == null) return const OvaToolResult(ok: false, summary: 'Sign in to manage reminders.', icon: Icons.lock_rounded, actions: [_signIn]);
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return OvaToolResult.fail('Which reminder?');
    final list = await _upcoming(limit: 50);
    final hit = list.where((r) => r.$1 == query.trim() || r.$2.toLowerCase().contains(q)).toList();
    if (hit.isEmpty) return OvaToolResult.fail('No upcoming reminder matches "$query".', icon: Icons.search_off_rounded);
    final r = hit.first;
    if (r.$4 != null) await device.cancelReminder(r.$4!);
    await _reminders!.doc(r.$1).update({'status': 'cancelled', 'cancelledAt': FieldValue.serverTimestamp()});
    return OvaToolResult(ok: true, summary: 'Cancelled the reminder "${r.$2}" (${_fmt(r.$3)}).', icon: Icons.notifications_off_rounded);
  }

  // ── Prompt context ─────────────────────────────────────────────────────

  String? _brief;
  DateTime? _briefAt;

  /// Loads a short "what the user is up to" brief for the system prompt.
  /// Cached for 10 minutes so each message stays fast.
  Future<void> warm() async {
    if (_briefAt != null && DateTime.now().difference(_briefAt!) < const Duration(minutes: 10)) return;
    if (_uid == null) {
      _brief = null;
      return;
    }
    try {
      final acts = await loadActivity(limit: 5);
      final rem = await _upcoming(limit: 3);
      _brief = [
        for (final a in acts) '${a.kind}: ${a.title} (${_when(a.at)})',
        for (final r in rem) 'reminder: ${r.$2} at ${_fmt(r.$3)}',
      ].join('; ');
      _briefAt = DateTime.now();
    } catch (_) {}
  }

  String contextLine() {
    final b = _brief;
    if (b == null || b.isEmpty) return 'Recent activity: unknown (use recent_activity).';
    return 'Recent activity: $b.';
  }

  /// Forget the cache (after the user does something new).
  void invalidate() => _briefAt = null;
}
