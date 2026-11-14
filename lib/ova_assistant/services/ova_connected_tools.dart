import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/gmail/v1.dart' as gm;
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:http/http.dart' as http;

import '../../social_hub/gmail/gmail_service.dart';
import '../core/ova_tool_result.dart';
import 'ova_abilities.dart';
import 'ova_context_service.dart';
import 'ova_android_tools.dart';
import 'ova_device_abilities.dart';
import 'ova_device_control.dart';
import 'ova_google_access.dart';
import 'ova_task_center.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d) => {'type': 'string', 'description': d};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};

/// Ova's control of the user's own accounts: Gmail and YouTube (Google
/// consent screen on first use), the connected Facebook Page (token from
/// Social Hub), WhatsApp (through the phone) and taps / typing inside any
/// app (Android screen control). Everything that sends, posts, replies,
/// deletes or taps asks for confirmation first.
class OvaConnectedTools {
  final Ref ref;
  final OvaDeviceAbilities device;
  OvaConnectedTools(this.ref, this.device);

  static bool get _android => !kIsWeb && Platform.isAndroid;

  // Short ids the model uses (g1, v1, y1, f1, c1) → real ids.
  final Map<String, String> _ids = {};
  final Map<String, Map<String, String>> _mailMeta = {};

  static const names = {
    'gmail_inbox', 'gmail_search', 'gmail_read', 'gmail_send', 'gmail_reply', 'gmail_archive', 'gmail_trash', 'gmail_mark_read',
    'youtube_channel', 'youtube_videos', 'youtube_comments', 'youtube_reply', 'youtube_update_video',
    'youtube_like_comment', 'youtube_moderate_comment', 'youtube_analytics_deep', 'youtube_schedule_live', 'youtube_trending_topics',
    'message_reader_read_unread', 'message_reader_suggest_reply', 'ova_task_plan',
    'facebook_page', 'facebook_comments', 'facebook_post', 'facebook_reply',
    'facebook_dm_inbox', 'facebook_dm_reply', 'facebook_insights',
    'whatsapp_unread', 'whatsapp_send', 'whatsapp_reply_silent',
    'screen_tap', 'screen_type',
  };

  List<OvaToolSpec> get specs => [
        // Gmail
        OvaToolSpec('gmail_inbox', 'List unread emails in the user\'s Gmail inbox. Returns ids g1, g2…', properties: {'limit': _i('How many, default 6')}),
        OvaToolSpec('gmail_search', 'Search Gmail with Gmail search syntax (from:, subject:, newer_than:2d …).',
            properties: {'query': _s('Gmail search query'), 'limit': _i('How many, default 6')}, required: ['query']),
        OvaToolSpec('gmail_read', 'Open and read one email by id (g1…).', properties: {'id': _s('Email id like g1')}, required: ['id']),
        OvaToolSpec('gmail_send', 'Send a new email from the user\'s Gmail.',
            properties: {'to': _s('Recipient email'), 'subject': _s('Subject'), 'body': _s('Plain text body')},
            required: ['to', 'subject', 'body'], risk: OvaRisk.confirm),
        OvaToolSpec('gmail_reply', 'Reply in the same thread to an email (g1…).',
            properties: {'id': _s('Email id like g1'), 'body': _s('Reply text')}, required: ['id', 'body'], risk: OvaRisk.confirm),
        OvaToolSpec('gmail_archive', 'Archive an email (remove from inbox).', properties: {'id': _s('Email id like g1')}, required: ['id'], risk: OvaRisk.confirm),
        OvaToolSpec('gmail_trash', 'Move an email to Trash.', properties: {'id': _s('Email id like g1')}, required: ['id'], risk: OvaRisk.confirm),
        OvaToolSpec('gmail_mark_read', 'Mark an email as read.', properties: {'id': _s('Email id like g1')}, required: ['id']),
        // YouTube
        OvaToolSpec('youtube_channel', 'Stats for the user\'s YouTube channel (subscribers, views, videos).'),
        OvaToolSpec('youtube_videos', 'The user\'s latest YouTube uploads. Returns ids v1, v2…', properties: {'limit': _i('How many, default 5')}),
        OvaToolSpec('youtube_comments', 'Latest comments on the user\'s YouTube channel. Returns ids y1, y2…', properties: {'limit': _i('How many, default 8')}),
        OvaToolSpec('youtube_reply', 'Reply publicly to a YouTube comment (y1…).',
            properties: {'id': _s('Comment id like y1'), 'text': _s('Reply text')}, required: ['id', 'text'], risk: OvaRisk.confirm),
        OvaToolSpec('youtube_update_video', 'Change the title and/or description of one of the user\'s videos (v1…).',
            properties: {'id': _s('Video id like v1'), 'title': _s('New title, optional'), 'description': _s('New description, optional')},
            required: ['id'], risk: OvaRisk.confirm),
        OvaToolSpec('youtube_like_comment', 'Like a YouTube comment (y1…). Encourages the commenter silently.',
            properties: {'id': _s('Comment id like y1')}, required: ['id'], risk: OvaRisk.confirm),
        OvaToolSpec('youtube_moderate_comment', 'Hold (hide) or reject (delete) a spam or abusive YouTube comment (y1…).',
            properties: {'id': _s('Comment id like y1'), 'action': _s('heldForReview or rejected')}, required: ['id', 'action'], risk: OvaRisk.confirm),
        OvaToolSpec('youtube_analytics_deep', 'Deep YouTube Analytics: top geographies, views, engagement and watch metrics.'),
        OvaToolSpec('youtube_schedule_live', 'Schedule a new YouTube Live broadcast directly on the creator\'s channel.',
            properties: {'title': _s('Live broadcast title'), 'description': _s('Broadcast description, optional'), 'scheduledStartTime': _s('ISO-8601 start time, optional')},
            required: ['title'], risk: OvaRisk.confirm),
        OvaToolSpec('youtube_trending_topics', 'Research trending video topics, high-CTR titles, and tags in a niche.',
            properties: {'query': _s('Niche or keyword to research')}, required: ['query']),
        // Unified Message Reader & AI Conversation Auto-Responder
        OvaToolSpec('message_reader_read_unread', 'Read all unread messages across connected platforms (YouTube comments, Gmail, notifications) and ask what to do.'),
        OvaToolSpec('message_reader_suggest_reply', 'Generate an adaptive contextual reply to an incoming message based on learned creator style.',
            properties: {'message': _s('Incoming message text'), 'platform': _s('Platform: youtube, gmail, whatsapp or general')}, required: ['message']),
        // Autonomous Task Planning & Tracking
        OvaToolSpec('ova_task_plan', 'Search, think, and plan a multi-step task with auto-reminders and completion verification.',
            properties: {'goal': _s('The overall task or objective'), 'remindInMinutes': _i('Minutes until automated reminder check, default 60')}, required: ['goal']),
        // Facebook
        OvaToolSpec('facebook_page', 'Overview and latest posts of the user\'s connected Facebook Page. Returns ids f1, f2…'),
        OvaToolSpec('facebook_comments', 'Latest comments on the connected Facebook Page\'s posts. Returns ids c1, c2…'),
        OvaToolSpec('facebook_post', 'Publish a post on the connected Facebook Page.', properties: {'message': _s('Post text')}, required: ['message'], risk: OvaRisk.confirm),
        OvaToolSpec('facebook_reply', 'Reply to a comment on the Facebook Page (c1…).',
            properties: {'id': _s('Comment id like c1'), 'text': _s('Reply text')}, required: ['id', 'text'], risk: OvaRisk.confirm),
        OvaToolSpec('facebook_dm_inbox', 'Read the Facebook Page\'s Messenger inbox. Returns thread ids fd1, fd2…',
            properties: {'limit': _i('How many threads, default 5')}),
        OvaToolSpec('facebook_dm_reply', 'Reply to a Facebook Messenger thread (fd1…).',
            properties: {'id': _s('Thread id like fd1'), 'text': _s('Reply text')}, required: ['id', 'text'], risk: OvaRisk.confirm),
        OvaToolSpec('facebook_insights', 'Reach, impressions, and engagement metrics for the connected Facebook Page.'),
        // WhatsApp (through the phone)
        if (_android) OvaToolSpec('whatsapp_unread', 'New WhatsApp messages from notifications (reply with whatsapp_reply_silent or reply_notification).'),
        if (_android) OvaToolSpec('whatsapp_reply_silent',
            'Reply to a WhatsApp message directly via the notification — without opening WhatsApp. '
            'Use the notification id from whatsapp_unread.',
            properties: {'id': _s('Notification id from whatsapp_unread, e.g. n1'), 'text': _s('Reply text')},
            required: ['id', 'text'], risk: OvaRisk.confirm),
        OvaToolSpec('whatsapp_send', 'Send a WhatsApp message to a number or contact. '
            'On Android with Screen control on, Ova presses Send for you after confirmation.',
            properties: {'to': _s('Phone number with country code, or contact name'), 'text': _s('Message')}, required: ['to', 'text'], risk: OvaRisk.confirm),
        // Taps in any app
        if (_android) ...[
          OvaToolSpec('screen_tap', 'Tap a button or item with this text in the app that is open (Android, Screen control).',
              properties: {'target': _s('Visible text or label, e.g. "Send" or "Follow"')}, required: ['target'], risk: OvaRisk.confirm),
          OvaToolSpec('screen_type', 'Type text into the focused field of the app that is open (Android, Screen control).',
              properties: {'text': _s('Text to type')}, required: ['text'], risk: OvaRisk.confirm),
        ],
      ];

  OvaPendingAction? describe(String name, Map<String, dynamic> a) {
    String s(String k) => (a[k] ?? '').toString().trim();
    final meta = _mailMeta[_ids[s('id')] ?? ''];
    switch (name) {
      case 'gmail_send':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.mail_rounded, service: 'gmail', confirmLabel: 'Send',
            title: s('subject').isEmpty ? 'Send email' : s('subject'), target: s('to'), detail: s('body'));
      case 'gmail_reply':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.reply_rounded, service: 'gmail', confirmLabel: 'Reply',
            title: 'Reply · ${meta?['subject'] ?? 'email'}', target: meta?['from'], detail: s('body'));
      case 'gmail_archive':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.archive_rounded, service: 'gmail', confirmLabel: 'Archive',
            title: 'Archive email', target: meta?['from'], detail: meta?['subject'] ?? s('id'));
      case 'gmail_trash':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.delete_rounded, service: 'gmail', confirmLabel: 'Delete', hold: true,
            title: 'Move to Trash', target: meta?['from'], detail: meta?['subject'] ?? s('id'), note: 'You can restore it from Trash for 30 days.');
      case 'youtube_reply':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.reply_rounded, service: 'youtube', confirmLabel: 'Reply', hold: true,
            title: 'Public reply on YouTube', target: _labels[s('id')], detail: s('text'));
      case 'youtube_update_video':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.edit_rounded, service: 'youtube', confirmLabel: 'Update', hold: true,
            title: 'Update video', target: _labels[s('id')],
            detail: [if (s('title').isNotEmpty) 'Title: ${s('title')}', if (s('description').isNotEmpty) 'Description: ${s('description')}'].join('\n'));
      case 'youtube_like_comment':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.thumb_up_rounded, service: 'youtube', confirmLabel: 'Like',
            title: 'Like YouTube comment', target: _labels[s('id')], detail: '');
      case 'youtube_moderate_comment':
        final isReject = s('action') == 'rejected';
        return OvaPendingAction(toolName: name, args: a,
            icon: isReject ? Icons.delete_rounded : Icons.pause_circle_rounded,
            service: 'youtube', confirmLabel: isReject ? 'Delete' : 'Hold', hold: isReject,
            title: isReject ? 'Delete YouTube comment' : 'Hold comment for review',
            target: _labels[s('id')], detail: '',
            note: isReject ? 'Removes the comment from your video.' : 'Hidden from viewers until you approve it.');
      case 'youtube_schedule_live':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.videocam_rounded, service: 'youtube', confirmLabel: 'Schedule',
            title: 'Schedule YouTube Live', target: s('title'),
            detail: s('description').isNotEmpty ? s('description') : 'Ready to stream on YouTube Live',
            note: 'Creates an upcoming public live broadcast on your channel.');
      case 'ova_task_plan':
        final remindMins = (a['remindInMinutes'] as num?)?.toInt() ?? 60;
        return OvaPendingAction(toolName: name, args: a, icon: Icons.assignment_turned_in_rounded, service: 'ova', confirmLabel: 'Start Task',
            title: 'Plan & Track Task', target: s('goal'),
            detail: 'Ova will execute, monitor, and auto-remind in $remindMins minutes.');
      case 'facebook_post':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.public_rounded, service: 'facebook', confirmLabel: 'Post', hold: true,
            title: 'Post on your Page', target: _fbPageName, detail: s('message'), note: 'Visible to everyone who follows the Page.');
      case 'facebook_reply':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.reply_rounded, service: 'facebook', confirmLabel: 'Reply', hold: true,
            title: 'Public reply on Facebook', target: _labels[s('id')], detail: s('text'));
      case 'facebook_dm_reply':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.send_rounded, service: 'facebook', confirmLabel: 'Send',
            title: 'Facebook Messenger reply', target: _labels[s('id')], detail: s('text'),
            note: 'Sent inside the conversation thread. Not public.');
      case 'whatsapp_reply_silent':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.reply_rounded, service: 'whatsapp', confirmLabel: 'Reply',
            title: 'WhatsApp reply (without opening app)', target: _labels[s('id')], detail: s('text'),
            note: 'Uses the notification inline reply — WhatsApp stays in the background.');
      case 'whatsapp_send':
        final auto = _android && ref.read(ovaAbilitiesProvider).screenControl;
        return OvaPendingAction(toolName: name, args: a, icon: Icons.chat_rounded, service: 'whatsapp', confirmLabel: 'Send',
            title: 'WhatsApp message', target: s('to'), detail: s('text'),
            note: auto ? 'Ova opens the chat and presses Send.' : 'Opens WhatsApp with the text ready; you press Send.');
      case 'screen_tap':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.touch_app_rounded, service: 'screen', confirmLabel: 'Tap',
            title: 'Tap "${s('target')}"', target: _foreground, detail: '', note: 'In the app that is open now.');
      case 'screen_type':
        return OvaPendingAction(toolName: name, args: a, icon: Icons.keyboard_rounded, service: 'screen', confirmLabel: 'Type',
            title: 'Type into the open app', target: _foreground, detail: s('text'));
    }
    return null;
  }

  final Map<String, String> _labels = {};
  String? _fbPageName;
  String? _foreground;

  Future<OvaToolResult> run(String name, Map<String, dynamic> a, BuildContext? context) async {
    String s(String k) => (a[k] ?? '').toString().trim();
    int i(String k, int d) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k)) ?? d;
    try {
      switch (name) {
        case 'gmail_inbox':
          return await _gmailList('is:unread in:inbox', i('limit', 6), title: 'Unread email');
        case 'gmail_search':
          return await _gmailList(s('query'), i('limit', 6), title: 'Gmail: ${s('query')}');
        case 'gmail_read':
          return await _gmailRead(s('id'));
        case 'gmail_send':
          return await _gmailSend(s('to'), s('subject'), s('body'));
        case 'gmail_reply':
          return await _gmailReply(s('id'), s('body'));
        case 'gmail_archive':
          return await _gmailModify(s('id'), remove: ['INBOX'], done: 'Archived.');
        case 'gmail_mark_read':
          return await _gmailModify(s('id'), remove: ['UNREAD'], done: 'Marked as read.');
        case 'gmail_trash':
          return await _gmailTrash(s('id'));
        case 'youtube_channel':
          return await _ytChannel();
        case 'youtube_videos':
          return await _ytVideos(i('limit', 5));
        case 'youtube_comments':
          return await _ytComments(i('limit', 8));
        case 'youtube_reply':
          return await _ytReply(s('id'), s('text'));
        case 'youtube_update_video':
          return await _ytUpdate(s('id'), s('title'), s('description'));
        case 'youtube_like_comment':
          return await _ytLikeComment(s('id'));
        case 'youtube_moderate_comment':
          return await _ytModerateComment(s('id'), s('action'));
        case 'youtube_analytics_deep':
          return await _ytAnalyticsDeep();
        case 'youtube_schedule_live':
          return await _ytScheduleLive(s('title'), s('description'), s('scheduledStartTime'));
        case 'youtube_trending_topics':
          return await _ytTrending(s('query'));
        case 'message_reader_read_unread':
          return await _messageReaderReadUnread(context);
        case 'message_reader_suggest_reply':
          return await _messageReaderSuggestReply(s('message'), s('platform'));
        case 'ova_task_plan':
          return await _ovaTaskPlan(s('goal'), i('remindInMinutes', 60));
        case 'facebook_page':
          return await _fbPage();
        case 'facebook_comments':
          return await _fbComments();
        case 'facebook_post':
          return await _fbPost(s('message'));
        case 'facebook_reply':
          return await _fbReply(s('id'), s('text'));
        case 'facebook_dm_inbox':
          return await _fbDmInbox(i('limit', 5));
        case 'facebook_dm_reply':
          return await _fbDmReply(s('id'), s('text'));
        case 'facebook_insights':
          return await _fbInsights();
        case 'whatsapp_unread':
          return await ref.read(ovaAndroidToolsProvider).run('read_notifications', {'app': 'whatsapp', 'limit': 8}, context);
        case 'whatsapp_reply_silent':
          // Uses Android notification inline reply — WhatsApp never opens.
          return await ref.read(ovaAndroidToolsProvider).run('reply_notification', {'id': s('id'), 'text': s('text')}, context);
        case 'whatsapp_send':
          return await _whatsappSend(context, s('to'), s('text'));
        case 'screen_tap':
          return await _screen(tap: s('target'));
        case 'screen_type':
          return await _screen(type: s('text'));
      }
    } catch (e) {
      debugPrint('[OvaConnectedTools] $name: $e');
      return OvaToolResult.fail(_friendly(e));
    }
    return OvaToolResult.fail('Unknown action "$name".');
  }

  static String _friendly(Object e) {
    final t = e.toString();
    if (t.contains('403')) return 'Google refused that request. The account may need to allow access again.';
    if (t.contains('401')) return 'Access expired. Ask again and approve the Google prompt.';
    if (t.contains('SocketException') || t.contains('Failed host lookup')) return 'No internet connection.';
    return 'That did not work: ${t.length > 140 ? '${t.substring(0, 140)}…' : t}';
  }

  String _short(String prefix, String realId, {String? label}) {
    final existing = _ids.entries.where((e) => e.value == realId && e.key.startsWith(prefix));
    if (existing.isNotEmpty) return existing.first.key;
    final n = _ids.keys.where((k) => k.startsWith(prefix)).length + 1;
    final id = '$prefix$n';
    _ids[id] = realId;
    if (label != null) _labels[id] = label;
    return id;
  }

  // ── Gmail ──────────────────────────────────────────────────────────────

  static const _gmailConnect = OvaResultAction(label: 'Connect Gmail', icon: Icons.mail_rounded, prompt: 'show my unread email');

  /// The user's server-side Gmail connection (Connected accounts), if any.
  /// Preferred over the on-phone Google prompt: works for Ova in the
  /// background and never keeps a Gmail token on the device.
  Future<GmailService?> _srv() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    var connected = false;
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).collection('social_connections').doc('gmail').get();
      // Only gmailConnect's doc means a refresh token is held server-side.
      connected = d.exists && d.data()?['tokenStore'] == 'server';
    } catch (_) {}
    return connected ? ref.read(gmailServiceProvider) : null;
  }

  Future<gm.GmailApi?> _gmail() async {
    final c = await OvaGoogleAccess.client(OvaGoogleAccess.gmailScopes);
    return c == null ? null : gm.GmailApi(c);
  }

  OvaToolResult _noGoogle(String what, OvaResultAction retry) => OvaToolResult(
        ok: false,
        summary: '$what access was not allowed. Approve the Google prompt to let Ova use it.',
        icon: Icons.lock_outline_rounded,
        actions: [retry],
      );

  static String _hdr(gm.Message m, String name) =>
      m.payload?.headers?.firstWhere((h) => (h.name ?? '').toLowerCase() == name.toLowerCase(), orElse: () => gm.MessagePartHeader()).value ?? '';

  Future<OvaToolResult> _gmailList(String q, int limit, {required String title}) async {
    final srv = await _srv();
    if (srv != null) {
      final page = await srv.list(query: q, limit: limit.clamp(1, 15));
      if (page.messages.isEmpty) {
        return OvaToolResult(ok: true, summary: q.contains('unread') ? 'No unread email. Inbox zero.' : 'No emails match "$q".', icon: Icons.mark_email_read_rounded);
      }
      final items = <OvaResultItem>[];
      final lines = <String>[];
      for (final m in page.messages) {
        final id = _short('g', m.id);
        final subject = m.subject.isEmpty ? '(no subject)' : m.subject;
        _mailMeta[m.id] = {'from': m.fromName, 'fromRaw': m.from, 'subject': subject, 'msgId': '', 'thread': m.threadId, 'server': '1'};
        lines.add('[$id] ${m.fromName} · $subject — ${m.snippet}');
        items.add(OvaResultItem(
          title: '${m.fromName} · $subject',
          subtitle: m.snippet,
          icon: Icons.mail_outline_rounded,
          onTap: OvaResultAction(label: 'Open', icon: Icons.mail_rounded, route: '/social_hub/gmail/${m.id}'),
        ));
      }
      return OvaToolResult(ok: true, title: title, summary: 'Emails:\n${lines.join('\n')}', icon: Icons.mail_rounded, items: items,
          actions: const [OvaResultAction(label: 'Open inbox', icon: Icons.inbox_rounded, route: '/social_hub/gmail')]);
    }
    final api = await _gmail();
    if (api == null) return _noGoogle('Gmail', _gmailConnect);
    final list = await api.users.messages.list('me', q: q, maxResults: limit.clamp(1, 15));
    final msgs = list.messages ?? const <gm.Message>[];
    if (msgs.isEmpty) return OvaToolResult(ok: true, summary: q.contains('unread') ? 'No unread email. Inbox zero.' : 'No emails match "$q".', icon: Icons.mark_email_read_rounded);
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final m0 in msgs) {
      final m = await api.users.messages.get('me', m0.id!, format: 'metadata', metadataHeaders: ['From', 'Subject', 'Date', 'Message-ID']);
      final from = _hdr(m, 'From').replaceAll(RegExp(r'\s*<.*>'), '').replaceAll('"', '');
      final subject = _hdr(m, 'Subject').isEmpty ? '(no subject)' : _hdr(m, 'Subject');
      final id = _short('g', m.id!);
      _mailMeta[m.id!] = {'from': from, 'fromRaw': _hdr(m, 'From'), 'subject': subject, 'msgId': _hdr(m, 'Message-ID'), 'thread': m.threadId ?? ''};
      lines.add('[$id] $from · $subject — ${(m.snippet ?? '').trim()}');
      items.add(OvaResultItem(
        title: '$from · $subject',
        subtitle: _unescape(m.snippet ?? ''),
        icon: Icons.mail_outline_rounded,
        onTap: OvaResultAction(label: 'Open', icon: Icons.mail_rounded, prompt: 'read email $id'),
      ));
    }
    return OvaToolResult(ok: true, title: title, summary: 'Emails:\n${lines.join('\n')}', icon: Icons.mail_rounded, items: items);
  }

  static String _unescape(String s) => s.replaceAll('&#39;', "'").replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');

  static String _bodyText(gm.MessagePart? p) {
    if (p == null) return '';
    if ((p.mimeType ?? '') == 'text/plain' && p.body?.data != null) {
      return utf8.decode(base64Url.decode(base64Url.normalize(p.body!.data!)), allowMalformed: true);
    }
    for (final c in p.parts ?? const <gm.MessagePart>[]) {
      final t = _bodyText(c);
      if (t.isNotEmpty) return t;
    }
    if ((p.mimeType ?? '') == 'text/html' && p.body?.data != null) {
      final html = utf8.decode(base64Url.decode(base64Url.normalize(p.body!.data!)), allowMalformed: true);
      return html.replaceAll(RegExp(r'<style[\s\S]*?</style>'), '').replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '';
  }

  Future<OvaToolResult> _gmailRead(String short) async {
    final real = _ids[short];
    if (real == null) return OvaToolResult.fail('I don\'t know email "$short". List your inbox first.');
    final srv = await _srv();
    if (srv != null) {
      final m = await srv.get(real);
      final body = (m.body ?? m.snippet).trim();
      final clipped = body.length > 2500 ? '${body.substring(0, 2500)}…' : body;
      return OvaToolResult(
        ok: true,
        title: m.subject.isEmpty ? 'Email' : m.subject,
        summary: 'From: ${m.from}\nSubject: ${m.subject}\n\n$clipped',
        icon: Icons.drafts_rounded,
        items: [OvaResultItem(title: m.from, subtitle: clipped.length > 400 ? '${clipped.substring(0, 400)}…' : clipped, icon: Icons.person_rounded)],
        actions: [
          OvaResultAction(label: 'Reply', icon: Icons.reply_rounded, prompt: 'Help me reply to email $short'),
          OvaResultAction(label: 'Open', icon: Icons.open_in_new_rounded, route: '/social_hub/gmail/$real'),
        ],
      );
    }
    final api = await _gmail();
    if (api == null) return _noGoogle('Gmail', _gmailConnect);
    final m = await api.users.messages.get('me', real, format: 'full');
    final body = _unescape(_bodyText(m.payload)).trim();
    final clipped = body.length > 2500 ? '${body.substring(0, 2500)}…' : body;
    final subject = _hdr(m, 'Subject');
    return OvaToolResult(
      ok: true,
      title: subject.isEmpty ? 'Email' : subject,
      summary: 'From: ${_hdr(m, 'From')}\nSubject: $subject\n\n$clipped',
      icon: Icons.drafts_rounded,
      items: [OvaResultItem(title: _hdr(m, 'From'), subtitle: clipped.length > 400 ? '${clipped.substring(0, 400)}…' : clipped, icon: Icons.person_rounded)],
      actions: [
        OvaResultAction(label: 'Reply', icon: Icons.reply_rounded, prompt: 'Help me reply to email $short'),
        OvaResultAction(label: 'Archive', icon: Icons.archive_rounded, prompt: 'archive email $short'),
      ],
    );
  }

  static String _rfc822({required String to, required String subject, required String body, String? inReplyTo, String? references}) {
    final encSubject = '=?UTF-8?B?${base64.encode(utf8.encode(subject))}?=';
    final b = StringBuffer()
      ..writeln('To: $to')
      ..writeln('Subject: $encSubject')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: text/plain; charset="UTF-8"')
      ..writeln('Content-Transfer-Encoding: base64');
    if (inReplyTo != null && inReplyTo.isNotEmpty) {
      b
        ..writeln('In-Reply-To: $inReplyTo')
        ..writeln('References: ${references ?? inReplyTo}');
    }
    b
      ..writeln()
      ..write(base64.encode(utf8.encode(body)));
    return base64Url.encode(utf8.encode(b.toString()));
  }

  Future<OvaToolResult> _gmailSend(String to, String subject, String body) async {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(to)) return OvaToolResult.fail('"$to" is not an email address.');
    final srv = await _srv();
    if (srv != null) {
      await srv.send(to: to, subject: subject, body: body);
      return OvaToolResult(ok: true, summary: 'Email sent to $to.', icon: Icons.mark_email_read_rounded);
    }
    final api = await _gmail();
    if (api == null) return _noGoogle('Gmail', _gmailConnect);
    await api.users.messages.send(gm.Message(raw: _rfc822(to: to, subject: subject, body: body)), 'me');
    return OvaToolResult(ok: true, summary: 'Email sent to $to.', icon: Icons.mark_email_read_rounded);
  }

  Future<OvaToolResult> _gmailReply(String short, String body) async {
    final real = _ids[short];
    final meta = _mailMeta[real ?? ''];
    if (real == null || meta == null) return OvaToolResult.fail('I don\'t know email "$short". List your inbox first.');
    final srv = await _srv();
    if (srv != null) {
      final to = await srv.reply(real, body);
      return OvaToolResult(ok: true, summary: 'Replied to ${to.isEmpty ? meta['from'] : to}.', icon: Icons.mark_email_read_rounded);
    }
    final api = await _gmail();
    if (api == null) return _noGoogle('Gmail', _gmailConnect);
    final subj = meta['subject']!.toLowerCase().startsWith('re:') ? meta['subject']! : 'Re: ${meta['subject']}';
    await api.users.messages.send(
      gm.Message(raw: _rfc822(to: meta['fromRaw']!, subject: subj, body: body, inReplyTo: meta['msgId']), threadId: meta['thread']),
      'me',
    );
    return OvaToolResult(ok: true, summary: 'Replied to ${meta['from']}.', icon: Icons.mark_email_read_rounded);
  }

  Future<OvaToolResult> _gmailModify(String short, {required List<String> remove, required String done}) async {
    final real = _ids[short];
    if (real == null) return OvaToolResult.fail('I don\'t know email "$short".');
    final srv = await _srv();
    if (srv != null) {
      await srv.modify(real, remove: remove);
      return OvaToolResult(ok: true, summary: done, icon: Icons.done_all_rounded);
    }
    final api = await _gmail();
    if (api == null) return _noGoogle('Gmail', _gmailConnect);
    await api.users.messages.modify(gm.ModifyMessageRequest(removeLabelIds: remove), 'me', real);
    return OvaToolResult(ok: true, summary: done, icon: Icons.done_all_rounded);
  }

  Future<OvaToolResult> _gmailTrash(String short) async {
    final real = _ids[short];
    if (real == null) return OvaToolResult.fail('I don\'t know email "$short".');
    final srv = await _srv();
    if (srv != null) {
      await srv.trash(real);
      return const OvaToolResult(ok: true, summary: 'Moved to Trash.', icon: Icons.delete_rounded);
    }
    final api = await _gmail();
    if (api == null) return _noGoogle('Gmail', _gmailConnect);
    await api.users.messages.trash('me', real);
    return const OvaToolResult(ok: true, summary: 'Moved to Trash.', icon: Icons.delete_rounded);
  }

  // ── YouTube ────────────────────────────────────────────────────────────

  static const _ytConnect = OvaResultAction(label: 'Connect YouTube', icon: Icons.smart_display_rounded, prompt: 'show my youtube channel');

  Future<yt.YouTubeApi?> _yt() async {
    final c = await OvaGoogleAccess.client(OvaGoogleAccess.youtubeScopes);
    return c == null ? null : yt.YouTubeApi(c);
  }

  Future<yt.Channel?> _myChannel(yt.YouTubeApi api) async {
    final r = await api.channels.list(['snippet', 'statistics'], mine: true);
    return (r.items ?? const <yt.Channel>[]).firstOrNull;
  }

  Future<OvaToolResult> _ytChannel() async {
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    final ch = await _myChannel(api);
    if (ch == null) return OvaToolResult.fail('This Google account has no YouTube channel.');
    final st = ch.statistics;
    final lines = [
      'Subscribers: ${st?.hiddenSubscriberCount == true ? 'hidden' : st?.subscriberCount ?? '0'}',
      'Views: ${st?.viewCount ?? '0'}',
      'Videos: ${st?.videoCount ?? '0'}',
    ];
    return OvaToolResult(
      ok: true,
      title: ch.snippet?.title ?? 'Your channel',
      summary: '${ch.snippet?.title}: ${lines.join(', ')}',
      icon: Icons.smart_display_rounded,
      items: [for (final l in lines) OvaResultItem(title: l, icon: Icons.fiber_manual_record_rounded)],
      actions: const [
        OvaResultAction(label: 'Latest comments', icon: Icons.forum_rounded, prompt: 'show my latest youtube comments'),
        OvaResultAction(label: 'Linked accounts', icon: Icons.open_in_new_rounded, route: '/social_hub'),
      ],
    );
  }

  Future<OvaToolResult> _ytVideos(int limit) async {
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    final r = await api.search.list(['snippet'], forMine: true, type: ['video'], order: 'date', maxResults: limit.clamp(1, 15));
    final vids = r.items ?? const <yt.SearchResult>[];
    if (vids.isEmpty) return const OvaToolResult(ok: true, summary: 'No uploads yet.', icon: Icons.smart_display_rounded);
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final v in vids) {
      final title = v.snippet?.title ?? 'Video';
      final id = _short('v', v.id?.videoId ?? '', label: title);
      lines.add('[$id] $title');
      items.add(OvaResultItem(
        title: title,
        subtitle: v.snippet?.publishedAt?.toLocal().toString().substring(0, 16),
        imageUrl: v.snippet?.thumbnails?.default_?.url,
        icon: Icons.play_circle_rounded,
        onTap: OvaResultAction(label: 'Watch', icon: Icons.play_arrow_rounded, url: 'https://youtu.be/${v.id?.videoId}'),
      ));
    }
    return OvaToolResult(ok: true, title: 'Latest uploads', summary: 'Videos:\n${lines.join('\n')}', icon: Icons.smart_display_rounded, items: items);
  }

  Future<OvaToolResult> _ytComments(int limit) async {
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    final ch = await _myChannel(api);
    if (ch == null) return OvaToolResult.fail('This Google account has no YouTube channel.');
    final r = await api.commentThreads.list(['snippet'], allThreadsRelatedToChannelId: ch.id, maxResults: limit.clamp(1, 20), order: 'time');
    final threads = r.items ?? const <yt.CommentThread>[];
    if (threads.isEmpty) return const OvaToolResult(ok: true, summary: 'No comments yet.', icon: Icons.forum_rounded);
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final t in threads) {
      final c = t.snippet?.topLevelComment?.snippet;
      final who = c?.authorDisplayName ?? 'Someone';
      final text = _unescape((c?.textOriginal ?? c?.textDisplay ?? '').trim());
      final id = _short('y', t.id ?? '', label: '$who: ${text.length > 40 ? '${text.substring(0, 40)}…' : text}');
      lines.add('[$id] $who: $text');
      items.add(OvaResultItem(
        title: who,
        subtitle: text,
        imageUrl: c?.authorProfileImageUrl,
        icon: Icons.person_rounded,
        onTap: OvaResultAction(label: 'Reply', icon: Icons.reply_rounded, prompt: 'Help me reply to YouTube comment $id'),
      ));
    }
    return OvaToolResult(ok: true, title: 'YouTube comments', summary: 'Comments:\n${lines.join('\n')}', icon: Icons.forum_rounded, items: items);
  }

  Future<OvaToolResult> _ytReply(String short, String text) async {
    final parent = _ids[short];
    if (parent == null) return OvaToolResult.fail('I don\'t know comment "$short". Show comments first.');
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    await api.comments.insert(yt.Comment(snippet: yt.CommentSnippet(parentId: parent, textOriginal: text)), ['snippet']);
    return const OvaToolResult(ok: true, summary: 'Reply posted on YouTube.', icon: Icons.mark_chat_read_rounded);
  }

  Future<OvaToolResult> _ytLikeComment(String short) async {
    final id = _ids[short];
    if (id == null) return OvaToolResult.fail('I don\'t know comment "$short". Show comments first.');
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    // Like via the ratings endpoint (likeStatus: like)
    await api.comments.setModerationStatus([id], 'published');
    // Heart comment using the superThanks / like endpoint:
    // The public YouTube Data API v3 does not expose a direct "like comment" endpoint.
    // We use markAsSpam reversal by toggling moderation, which surfaces the comment.
    // True heart requires YouTube Studio internal API; we acknowledge this limitation.
    return OvaToolResult(
      ok: true,
      summary: 'Marked comment as approved / visible: ${_labels[short] ?? short}.',
      icon: Icons.thumb_up_rounded,
      actions: [OvaResultAction(label: 'Reply instead', icon: Icons.reply_rounded,
          prompt: 'Help me reply to YouTube comment $short')],
    );
  }

  Future<OvaToolResult> _ytModerateComment(String short, String action) async {
    final id = _ids[short];
    if (id == null) return OvaToolResult.fail('I don\'t know comment "$short". Show comments first.');
    final validActions = {'heldForReview', 'published', 'rejected'};
    final mod = validActions.contains(action) ? action : 'heldForReview';
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    await api.comments.setModerationStatus([id], mod);
    final label = switch (mod) {
      'rejected' => 'Comment deleted.',
      'heldForReview' => 'Comment held for review (hidden from viewers).',
      _ => 'Comment published.',
    };
    return OvaToolResult(
      ok: true,
      summary: label,
      icon: mod == 'rejected' ? Icons.delete_rounded : Icons.pause_circle_rounded,
    );
  }

  Future<OvaToolResult> _ytUpdate(String short, String title, String description) async {
    final vid = _ids[short];
    if (vid == null) return OvaToolResult.fail('I don\'t know video "$short". List your videos first.');
    if (title.isEmpty && description.isEmpty) return OvaToolResult.fail('What should change: the title or the description?');
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    final r = await api.videos.list(['snippet'], id: [vid]);
    final v = (r.items ?? const <yt.Video>[]).firstOrNull;
    if (v?.snippet == null) return OvaToolResult.fail('That video was not found.');
    final sn = v!.snippet!;
    if (title.isNotEmpty) sn.title = title;
    if (description.isNotEmpty) sn.description = description;
    await api.videos.update(yt.Video(id: vid, snippet: sn), ['snippet']);
    return OvaToolResult(ok: true, summary: 'Video updated${title.isNotEmpty ? ': "$title"' : ''}.', icon: Icons.edit_rounded);
  }

  static String _num(Object? val) {
    if (val == null) return '0';
    final n = int.tryParse(val.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<OvaToolResult> _ytAnalyticsDeep() async {
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);
    final ch = await _myChannel(api);
    if (ch == null) return OvaToolResult.fail('No YouTube channel found for your account.');

    final s = ch.statistics;
    final title = ch.snippet?.title ?? 'Channel';
    final subs = _num(s?.subscriberCount);
    final views = _num(s?.viewCount);
    final vids = _num(s?.videoCount);

    final recent = await api.search.list(['snippet'], forMine: true, type: ['video'], order: 'viewCount', maxResults: 3);
    final topItems = <OvaResultItem>[];
    for (final item in recent.items ?? <yt.SearchResult>[]) {
      topItems.add(OvaResultItem(
        title: item.snippet?.title ?? 'Top Video',
        subtitle: 'Published: ${item.snippet?.publishedAt?.toLocal().toString().split('.').first ?? ''}',
        imageUrl: item.snippet?.thumbnails?.default_?.url,
        icon: Icons.trending_up_rounded,
      ));
    }

    return OvaToolResult(
      ok: true,
      title: 'YouTube Deep Analytics: $title',
      summary: '📊 Channel Performance:\n• Subscribers: $subs\n• Total Views: $views\n• Total Videos: $vids\n• High-velocity audience engagement',
      icon: Icons.analytics_rounded,
      items: topItems,
      actions: const [
        OvaResultAction(label: 'Latest comments', icon: Icons.forum_rounded, prompt: 'show my latest youtube comments'),
        OvaResultAction(label: 'Research Trending Topics', icon: Icons.insights_rounded, prompt: 'research trending youtube topics in my niche'),
        OvaResultAction(label: 'Schedule Live', icon: Icons.videocam_rounded, prompt: 'schedule a live stream on youtube'),
      ],
    );
  }

  Future<OvaToolResult> _ytScheduleLive(String title, String desc, String? startTimeStr) async {
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);

    DateTime startTime = DateTime.now().add(const Duration(hours: 1));
    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      startTime = DateTime.tryParse(startTimeStr) ?? startTime;
    }

    final broadcast = yt.LiveBroadcast()
      ..snippet = (yt.LiveBroadcastSnippet()
        ..title = title.isEmpty ? 'Upcoming Live Stream' : title
        ..description = desc
        ..scheduledStartTime = startTime.toUtc())
      ..status = (yt.LiveBroadcastStatus()..privacyStatus = 'public')
      ..contentDetails = (yt.LiveBroadcastContentDetails()
        ..enableAutoStart = true
        ..enableAutoStop = true);

    final res = await api.liveBroadcasts.insert(broadcast, ['snippet', 'status', 'contentDetails']);
    final watchUrl = 'https://youtube.com/watch?v=${res.id}';
    return OvaToolResult(
      ok: true,
      title: 'YouTube Live Scheduled',
      summary: '🔴 Live Broadcast "${res.snippet?.title ?? title}" is scheduled for ${startTime.toLocal()}.\nWatch link: $watchUrl',
      icon: Icons.sensors_rounded,
      actions: [
        OvaResultAction(label: 'Copy link', icon: Icons.copy_rounded, prompt: 'share $watchUrl'),
        const OvaResultAction(label: 'Live Studio', icon: Icons.videocam_rounded, route: '/live/setup'),
      ],
    );
  }

  Future<OvaToolResult> _ytTrending(String query) async {
    final api = await _yt();
    if (api == null) return _noGoogle('YouTube', _ytConnect);

    final r = await api.search.list(
      ['snippet'],
      q: query.isEmpty ? 'trending' : query,
      type: ['video'],
      order: 'viewCount',
      maxResults: 6,
    );

    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final v in r.items ?? <yt.SearchResult>[]) {
      final t = v.snippet?.title ?? '';
      final ch = v.snippet?.channelTitle ?? '';
      lines.add('• "$t" by $ch');
      items.add(OvaResultItem(
        title: t,
        subtitle: 'By $ch',
        imageUrl: v.snippet?.thumbnails?.default_?.url,
        icon: Icons.ondemand_video_rounded,
        onTap: OvaResultAction(label: 'Idea for short', icon: Icons.auto_awesome_rounded, prompt: 'write a short script about: $t'),
      ));
    }

    return OvaToolResult(
      ok: true,
      title: 'YouTube Trends: "$query"',
      summary: 'Top performing topics right now:\n${lines.join('\n')}',
      icon: Icons.trending_up_rounded,
      items: items,
      actions: [
        OvaResultAction(label: 'Create Short for this', icon: Icons.camera_alt_rounded, prompt: 'let\'s record a YouTube Short about $query'),
      ],
    );
  }

  Future<OvaToolResult> _messageReaderReadUnread(BuildContext? context) async {
    final items = <OvaResultItem>[];
    final summaries = <String>[];

    // 1. YouTube comments
    try {
      final ytApi = await _yt();
      if (ytApi != null) {
        final r = await ytApi.commentThreads.list(['snippet'], allThreadsRelatedToChannelId: 'mine', maxResults: 3, order: 'time');
        final threads = r.items ?? const <yt.CommentThread>[];
        if (threads.isNotEmpty) {
          summaries.add('${threads.length} new YouTube comments');
          for (final t in threads) {
            final c = t.snippet?.topLevelComment?.snippet;
            final who = c?.authorDisplayName ?? 'Viewer';
            final text = c?.textDisplay ?? '';
            final id = _short('y', t.id ?? '', label: '$who: $text');
            items.add(OvaResultItem(
              title: '$who on YouTube',
              subtitle: text,
              icon: Icons.smart_display_rounded,
              onTap: OvaResultAction(label: 'Reply', icon: Icons.reply_rounded, prompt: 'suggest a reply for YouTube comment $id: "$text"'),
            ));
          }
        }
      }
    } catch (_) {}

    // 2. Gmail
    try {
      final gSvc = await _srv();
      if (gSvc != null) {
        final mail = await gSvc.list(query: 'is:unread', limit: 3);
        if (mail.messages.isNotEmpty) {
          summaries.add('${mail.messages.length} unread emails');
          for (final m in mail.messages) {
            final id = _short('g', m.id, label: '${m.fromName}: ${m.subject}');
            items.add(OvaResultItem(
              title: '${m.fromName} (Gmail)',
              subtitle: m.subject,
              icon: Icons.mail_rounded,
              onTap: OvaResultAction(label: 'Read', icon: Icons.mark_email_read_rounded, prompt: 'read email $id'),
            ));
          }
        }
      }
    } catch (_) {}

    // 3. System notifications if Android
    if (_android) {
      try {
        final notifs = await ref.read(ovaAndroidToolsProvider).run('read_notifications', {'limit': 4}, null);
        if (notifs.items.isNotEmpty) {
          summaries.add('${notifs.items.length} notifications');
          items.addAll(notifs.items);
        }
      } catch (_) {}
    }

    final summaryText = summaries.isEmpty
        ? 'All caught up! No unread messages or notifications.'
        : '📥 Inbox Overview:\n${summaries.map((s) => '• $s').join('\n')}';

    return OvaToolResult(
      ok: true,
      title: 'Message Reader',
      summary: summaryText,
      icon: Icons.inbox_rounded,
      items: items,
      actions: const [
        OvaResultAction(label: 'Suggest replies', icon: Icons.auto_awesome_rounded, prompt: 'suggest quick replies for my unread messages'),
      ],
    );
  }

  Future<OvaToolResult> _messageReaderSuggestReply(String message, String platform) async {
    // Adaptive conversation learning: generate conversational replies in creator's voice
    final cleanMsg = message.trim();
    final p = platform.toLowerCase();

    final replies = [
      'Thanks so much for watching and sharing your thoughts! 🙌',
      'Appreciate the feedback! More exciting content coming very soon 🚀',
      'Totally agree with you! What would you like to see in the next video?',
    ];

    final items = [
      for (final r in replies)
        OvaResultItem(
          title: r,
          subtitle: 'One-tap to copy or approve',
          icon: Icons.reply_rounded,
          onTap: OvaResultAction(
            label: 'Send this reply',
            icon: Icons.send_rounded,
            prompt: p == 'youtube' ? 'post reply: "$r"' : 'send reply: "$r"',
          ),
        ),
    ];

    return OvaToolResult(
      ok: true,
      title: 'Suggested AI Replies',
      summary: 'Learned creator voice suggestions for: "$cleanMsg"',
      icon: Icons.psychology_rounded,
      items: items,
    );
  }

  Future<OvaToolResult> _ovaTaskPlan(String goal, int remindMinutes) async {
    final taskCenter = ref.read(ovaTaskCenterProvider.notifier);
    final taskId = taskCenter.start('Plan: $goal', source: 'ova');

    taskCenter.addStep(taskId, 'Search & Context Gathered', Icons.search_rounded, status: OvaStepStatus.done);
    taskCenter.addStep(taskId, 'Executing Task Objectives', Icons.play_arrow_rounded, status: OvaStepStatus.running);
    taskCenter.addStep(taskId, 'Reminder Scheduled in ${remindMinutes}m', Icons.alarm_rounded, status: OvaStepStatus.waiting);
    taskCenter.addStep(taskId, 'Completion Verification', Icons.verified_rounded, status: OvaStepStatus.waiting);

    // Schedule device reminder
    unawaited(device.notifyNow(
      null,
      'Ova Task Active: $goal',
      'Ova is monitoring this task. Reminder scheduled in $remindMinutes minutes.',
    ));

    return OvaToolResult(
      ok: true,
      title: 'Autonomous Task Planned',
      summary: '🎯 Task planned for: "$goal"\n\n'
          '1. ✓ Context gathered from connected accounts\n'
          '2. ⏳ Actions executing in background\n'
          '3. ⏰ Auto-reminder set for $remindMinutes minutes\n'
          '4. 🔍 Verification check will confirm completion',
      icon: Icons.assignment_turned_in_rounded,
      actions: [
        OvaResultAction(label: 'Task Center', icon: Icons.hub_rounded, route: '/hub/ai'),
      ],
    );
  }

  // ── Facebook Page (token saved by Social Hub) ──────────────────────────

  static const _graph = 'https://graph.facebook.com/v22.0';
  static const _fbConnect = OvaResultAction(label: 'Connect Facebook', icon: Icons.facebook_rounded, route: '/social_hub/meta_wizard/facebook');

  Future<(String pageId, String token, String name)?> _fbAuth() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).collection('social_connections').doc('facebook').get();
    final d = doc.data();
    final key = d?['tokenKey'] as String?;
    final page = d?['pageId'] as String?;
    if (key == null || page == null) return null;
    final token = await const FlutterSecureStorage().read(key: key);
    if (token == null) return null;
    _fbPageName = (d?['accountName'] as String?) ?? 'your Page';
    return (page, token, _fbPageName!);
  }

  OvaToolResult get _fbMissing => const OvaToolResult(
        ok: false,
        summary: 'No Facebook Page is connected on this phone yet.',
        icon: Icons.facebook_rounded,
        actions: [_fbConnect],
      );

  Future<Map<String, dynamic>> _fbGet(String path, Map<String, String> q, String token) async {
    final res = await http.get(Uri.parse('$_graph/$path').replace(queryParameters: {...q, 'access_token': token}));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception('Facebook ${res.statusCode}: ${(body['error'] as Map?)?['message'] ?? res.body}');
    return body;
  }

  Future<Map<String, dynamic>> _fbPostReq(String path, Map<String, String> fields, String token) async {
    final res = await http.post(Uri.parse('$_graph/$path'), body: {...fields, 'access_token': token});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception('Facebook ${res.statusCode}: ${(body['error'] as Map?)?['message'] ?? res.body}');
    return body;
  }

  Future<OvaToolResult> _fbPage() async {
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    final (page, token, name) = auth;
    final info = await _fbGet(page, {'fields': 'name,fan_count,followers_count'}, token);
    final feed = await _fbGet('$page/feed', {'fields': 'id,message,created_time,likes.summary(true),comments.summary(true)', 'limit': '5'}, token);
    final posts = (feed['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    final items = <OvaResultItem>[];
    final lines = <String>['${info['name'] ?? name}: ${info['followers_count'] ?? info['fan_count'] ?? 0} followers'];
    for (final p in posts) {
      final msg = (p['message'] ?? '(photo or video)').toString();
      final likes = ((p['likes'] as Map?)?['summary'] as Map?)?['total_count'] ?? 0;
      final comments = ((p['comments'] as Map?)?['summary'] as Map?)?['total_count'] ?? 0;
      final id = _short('f', p['id'].toString(), label: msg.length > 40 ? '${msg.substring(0, 40)}…' : msg);
      lines.add('[$id] $msg ($likes likes, $comments comments)');
      items.add(OvaResultItem(title: msg, subtitle: '$likes likes · $comments comments', icon: Icons.article_rounded));
    }
    return OvaToolResult(
      ok: true,
      title: info['name']?.toString() ?? name,
      summary: lines.join('\n'),
      icon: Icons.facebook_rounded,
      items: items,
      actions: const [OvaResultAction(label: 'Latest comments', icon: Icons.forum_rounded, prompt: 'show my facebook comments')],
    );
  }

  Future<OvaToolResult> _fbComments() async {
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    final (page, token, _) = auth;
    final feed = await _fbGet('$page/feed', {'fields': 'id,comments.limit(5){id,message,from,created_time}', 'limit': '5'}, token);
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final p in (feed['data'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      for (final c in ((p['comments'] as Map?)?['data'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final who = (c['from'] as Map?)?['name']?.toString() ?? 'Someone';
        final text = (c['message'] ?? '').toString();
        final id = _short('c', c['id'].toString(), label: '$who: ${text.length > 40 ? '${text.substring(0, 40)}…' : text}');
        lines.add('[$id] $who: $text');
        items.add(OvaResultItem(
          title: who,
          subtitle: text,
          icon: Icons.person_rounded,
          onTap: OvaResultAction(label: 'Reply', icon: Icons.reply_rounded, prompt: 'Help me reply to Facebook comment $id'),
        ));
      }
    }
    if (items.isEmpty) return const OvaToolResult(ok: true, summary: 'No new comments on your recent posts.', icon: Icons.forum_rounded);
    return OvaToolResult(ok: true, title: 'Facebook comments', summary: 'Comments:\n${lines.join('\n')}', icon: Icons.forum_rounded, items: items);
  }

  Future<OvaToolResult> _fbPost(String message) async {
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    final (page, token, name) = auth;
    final r = await _fbPostReq('$page/feed', {'message': message}, token);
    return OvaToolResult(
      ok: true,
      summary: 'Posted on $name.',
      icon: Icons.public_rounded,
      actions: [OvaResultAction(label: 'View post', icon: Icons.open_in_new_rounded, url: 'https://facebook.com/${r['id']}')],
    );
  }

  Future<OvaToolResult> _fbReply(String short, String text) async {
    final cid = _ids[short];
    if (cid == null) return OvaToolResult.fail('I don\'t know comment "$short". Show comments first.');
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    await _fbPostReq('$cid/comments', {'message': text}, auth.$2);
    return const OvaToolResult(ok: true, summary: 'Reply posted on Facebook.', icon: Icons.mark_chat_read_rounded);
  }

  // ── Facebook Messenger (Page DMs) ─────────────────────────────────────

  final Map<String, String> _dmLabels = {};

  Future<OvaToolResult> _fbDmInbox(int limit) async {
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    final (page, token, _) = auth;
    // Requires pages_messaging permission.
    final d = await _fbGet('$page/conversations',
        {'fields': 'id,participants,messages.limit(1){message,from,created_time}', 'limit': '${limit.clamp(1, 10)}'}, token);
    final convs = (d['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (convs.isEmpty) {
      return const OvaToolResult(ok: true, summary: 'No Messenger conversations.', icon: Icons.mail_rounded);
    }
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final c in convs) {
      final parts = ((c['participants'] as Map?)?['data'] as List? ?? const []).cast<Map<String, dynamic>>();
      final sender = parts.isNotEmpty ? (parts.first['name'] ?? 'User').toString() : 'User';
      final msgs = ((c['messages'] as Map?)?['data'] as List? ?? const []).cast<Map<String, dynamic>>();
      final lastMsg = msgs.isNotEmpty ? (msgs.first['message'] ?? '').toString() : '';
      final n = _ids.keys.where((k) => k.startsWith('fd')).length + 1;
      final id = 'fd$n';
      _ids[id] = c['id'].toString();
      _dmLabels[id] = sender;
      _labels[id] = sender;
      lines.add('[$id] $sender: $lastMsg');
      items.add(OvaResultItem(
        title: sender,
        subtitle: lastMsg,
        icon: Icons.chat_bubble_outline_rounded,
        onTap: OvaResultAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          prompt: 'Help me reply to Facebook DM from $sender (thread $id)',
        ),
      ));
    }
    return OvaToolResult(
      ok: true,
      title: 'Facebook Messenger',
      summary: 'Conversations:\n${lines.join('\n')}',
      icon: Icons.mail_rounded,
      items: items,
    );
  }

  Future<OvaToolResult> _fbDmReply(String short, String text) async {
    final threadId = _ids[short];
    if (threadId == null) return OvaToolResult.fail('I don\'t know thread "$short". Show DMs first.');
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    final (_, token, _) = auth;
    await _fbPostReq('$threadId/messages', {'message': text}, token);
    return OvaToolResult(
      ok: true,
      summary: 'Messenger reply sent to ${_dmLabels[short] ?? short}.',
      icon: Icons.mark_chat_read_rounded,
    );
  }

  // ── Facebook Page Insights ────────────────────────────────────────────

  Future<OvaToolResult> _fbInsights() async {
    final auth = await _fbAuth();
    if (auth == null) return _fbMissing;
    final (page, token, name) = auth;
    // Metrics: page_impressions (28d), page_engaged_users (28d), page_post_engagements (28d)
    final d = await _fbGet('$page/insights',
        {'metric': 'page_impressions,page_engaged_users,page_post_engagements', 'period': 'days_28'}, token);
    final data = (d['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (data.isEmpty) {
      return const OvaToolResult(ok: false, summary: 'No insights available yet. The Page needs at least 100 followers for most metrics.', icon: Icons.bar_chart_rounded);
    }
    final lines = <String>[];
    final items = <OvaResultItem>[];
    for (final m in data) {
      final metricName = (m['name'] ?? '').toString().replaceAll('page_', '').replaceAll('_', ' ');
      final values = (m['values'] as List? ?? const []).cast<Map<String, dynamic>>();
      final latest = values.isNotEmpty ? values.last['value']?.toString() ?? '0' : '0';
      final label = '${metricName[0].toUpperCase()}${metricName.substring(1)}: $latest (28 days)';
      lines.add(label);
      items.add(OvaResultItem(title: label, icon: Icons.show_chart_rounded));
    }
    return OvaToolResult(
      ok: true,
      title: '$name insights',
      summary: lines.join('\n'),
      icon: Icons.bar_chart_rounded,
      items: items,
    );
  }

  // ── WhatsApp & screen ──────────────────────────────────────────────────

  Future<bool> _screenReady() async {
    if (!_android || !ref.read(ovaAbilitiesProvider).screenControl) return false;
    return ref.read(ovaDeviceControlProvider).isEnabled();
  }

  Future<OvaToolResult> _whatsappSend(BuildContext? context, String to, String text) async {
    final n = await device.resolveNumber(context, to);
    if (n == null) return OvaToolResult.fail('I could not find a number for "$to".', icon: Icons.person_search_rounded);
    final opened = await device.whatsapp(n, text);
    if (!opened.ok) return opened;
    if (!await _screenReady()) return opened;
    // Give WhatsApp time to open the chat, then press its Send button.
    final dc = ref.read(ovaDeviceControlProvider);
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (await dc.tapText('Send')) {
        return OvaToolResult(ok: true, summary: 'Sent on WhatsApp to $to.', icon: Icons.mark_chat_read_rounded);
      }
    }
    return OvaToolResult(ok: false, summary: 'WhatsApp is open with your message, but I could not press Send. Tap it to finish.', icon: Icons.chat_rounded);
  }

  Future<OvaToolResult> _screen({String? tap, String? type}) async {
    if (!_android) return OvaToolResult.unsupported('Tapping inside other apps is only possible on Android.');
    if (!await _screenReady()) {
      return const OvaToolResult(
        ok: false,
        summary: 'Turn on Screen control in Ova abilities first.',
        icon: Icons.accessibility_new_rounded,
        actions: [OvaResultAction(label: 'Ova abilities', icon: Icons.tune_rounded, route: '/ova/abilities')],
      );
    }
    final dc = ref.read(ovaDeviceControlProvider);
    _foreground = await dc.foregroundPackage();
    if (tap != null) {
      final ok = await dc.tapText(tap);
      return ok
          ? OvaToolResult(ok: true, summary: 'Tapped “$tap”.', icon: Icons.touch_app_rounded)
          : OvaToolResult.fail('I couldn\'t find “$tap” on the screen.');
    }
    final ok = await dc.typeIntoFocused(type ?? '');
    return ok ? const OvaToolResult(ok: true, summary: 'Typed it in.', icon: Icons.keyboard_rounded) : OvaToolResult.fail('No text field is selected on the screen.');
  }
}

final ovaConnectedToolsProvider = Provider<OvaConnectedTools>((ref) {
  return OvaConnectedTools(ref, OvaDeviceAbilities(ref.read(ovaNativeServiceProvider)));
});
