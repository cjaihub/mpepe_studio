import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/ova_tool_result.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d) => {'type': 'string', 'description': d};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};

/// Ova tools for Instagram Business accounts.
///
/// Auth path: The user's Instagram Business account is linked to the same
/// Facebook Page token stored in Firestore `social_connections/facebook`.
/// At connect time we also store the IG user id in that same document so
/// we never need an extra OAuth round-trip.
///
/// All write tools require [OvaRisk.confirm] — reads are [OvaRisk.safe].
/// Destructive or public actions use hold-to-confirm.
class OvaInstagramTools {
  static const _graph = 'https://graph.facebook.com/v22.0';

  static const _igConnect = OvaResultAction(
    label: 'Connect Instagram',
    icon: Icons.camera_alt_rounded,
    route: '/social_hub/meta_wizard/instagram',
  );

  /// Short ids (ig1, ig2…) the model uses for media → real IG media ids.
  final Map<String, String> _ids = {};
  final Map<String, String> _labels = {};

  // ── Tool names ──────────────────────────────────────────────────────────

  static const names = {
    'instagram_profile',
    'instagram_media',
    'instagram_comments',
    'instagram_reply',
    'instagram_like_comment',
    'instagram_dm_inbox',
    'instagram_dm_reply',
  };

  // ── Specs ───────────────────────────────────────────────────────────────

  List<OvaToolSpec> get specs => [
        OvaToolSpec(
          'instagram_profile',
          "Stats for the user's connected Instagram Business account "
              '(followers, following, media count, username).',
        ),
        OvaToolSpec(
          'instagram_media',
          "The user's latest Instagram posts and Reels. Returns ids ig1, ig2…",
          properties: {'limit': _i('How many, default 6')},
        ),
        OvaToolSpec(
          'instagram_comments',
          'Latest comments on a specific Instagram media item (ig1…).',
          properties: {
            'id': _s('Media id like ig1'),
            'limit': _i('How many, default 10'),
          },
          required: ['id'],
        ),
        OvaToolSpec(
          'instagram_reply',
          'Reply publicly to a comment on an Instagram post.',
          properties: {
            'media_id': _s('Media id like ig1'),
            'comment_id': _s('Comment id like ic1'),
            'text': _s('Reply text'),
          },
          required: ['media_id', 'comment_id', 'text'],
          risk: OvaRisk.confirm,
        ),
        OvaToolSpec(
          'instagram_like_comment',
          'Like a comment on an Instagram post (ic1…).',
          properties: {'comment_id': _s('Comment id like ic1')},
          required: ['comment_id'],
          risk: OvaRisk.confirm,
        ),
        OvaToolSpec(
          'instagram_dm_inbox',
          "Read the user's Instagram Direct Message inbox (Business accounts only).",
          properties: {'limit': _i('How many conversations, default 5')},
        ),
        OvaToolSpec(
          'instagram_dm_reply',
          'Reply to an Instagram DM conversation.',
          properties: {
            'thread_id': _s('Thread id from instagram_dm_inbox'),
            'text': _s('Reply text'),
          },
          required: ['thread_id', 'text'],
          risk: OvaRisk.confirm,
        ),
      ];

  // ── Confirm card descriptions ────────────────────────────────────────────

  OvaPendingAction? describe(String name, Map<String, dynamic> a) {
    String s(String k) => (a[k] ?? '').toString().trim();
    switch (name) {
      case 'instagram_reply':
        return OvaPendingAction(
          toolName: name,
          args: a,
          icon: Icons.reply_rounded,
          service: 'instagram',
          confirmLabel: 'Reply',
          hold: true,
          title: 'Public reply on Instagram',
          target: _labels[s('comment_id')],
          detail: s('text'),
          note: 'Visible to everyone on the post.',
        );
      case 'instagram_like_comment':
        return OvaPendingAction(
          toolName: name,
          args: a,
          icon: Icons.favorite_rounded,
          service: 'instagram',
          confirmLabel: 'Like',
          title: 'Like comment on Instagram',
          target: _labels[s('comment_id')],
          detail: '',
        );
      case 'instagram_dm_reply':
        return OvaPendingAction(
          toolName: name,
          args: a,
          icon: Icons.send_rounded,
          service: 'instagram',
          confirmLabel: 'Send',
          title: 'Instagram DM reply',
          target: _labels[s('thread_id')],
          detail: s('text'),
          note: 'Sends as a reply inside the DM conversation.',
        );
    }
    return null;
  }

  // ── Run ─────────────────────────────────────────────────────────────────

  Future<OvaToolResult> run(String name, Map<String, dynamic> a) async {
    String s(String k) => (a[k] ?? '').toString().trim();
    int limit(String k, int d) =>
        a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k)) ?? d;
    try {
      switch (name) {
        case 'instagram_profile':
          return await _profile();
        case 'instagram_media':
          return await _media(limit('limit', 6));
        case 'instagram_comments':
          return await _comments(s('id'), limit('limit', 10));
        case 'instagram_reply':
          return await _reply(s('media_id'), s('comment_id'), s('text'));
        case 'instagram_like_comment':
          return await _likeComment(s('comment_id'));
        case 'instagram_dm_inbox':
          return await _dmInbox(limit('limit', 5));
        case 'instagram_dm_reply':
          return await _dmReply(s('thread_id'), s('text'));
      }
    } catch (e) {
      debugPrint('[OvaInstagramTools] $name: $e');
      return OvaToolResult.fail(_friendly(e));
    }
    return OvaToolResult.fail('Unknown Instagram action "$name".');
  }

  // ── Auth ────────────────────────────────────────────────────────────────

  /// Returns (igUserId, pageToken) or null if not connected.
  Future<(String igId, String token)?> _auth() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('social_connections')
        .doc('facebook')
        .get();
    final d = doc.data();
    final tokenKey = d?['tokenKey'] as String?;
    final igId = d?['instagramUserId'] as String?;
    if (tokenKey == null || igId == null) return null;
    final token = await const FlutterSecureStorage().read(key: tokenKey);
    if (token == null) return null;
    return (igId, token);
  }

  OvaToolResult get _missing => const OvaToolResult(
        ok: false,
        summary: 'No Instagram Business account is connected yet.\n'
            'Connect it via the Meta Wizard in Social Hub.',
        icon: Icons.camera_alt_rounded,
        actions: [_igConnect],
      );

  // ── HTTP helpers ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
      String path, Map<String, String> q, String token) async {
    final res = await http.get(
        Uri.parse('$_graph/$path')
            .replace(queryParameters: {...q, 'access_token': token}));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(
          'Instagram ${res.statusCode}: ${(body['error'] as Map?)?['message'] ?? res.body}');
    }
    return body;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, String> fields, String token) async {
    final res = await http.post(
        Uri.parse('$_graph/$path'),
        body: {...fields, 'access_token': token});
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(
          'Instagram ${res.statusCode}: ${(body['error'] as Map?)?['message'] ?? res.body}');
    }
    return body;
  }

  // ── Short id helpers ─────────────────────────────────────────────────────

  String _shortMedia(String realId, {String? label}) {
    final existing =
        _ids.entries.where((e) => e.value == realId && e.key.startsWith('ig'));
    if (existing.isNotEmpty) return existing.first.key;
    final n = _ids.keys.where((k) => k.startsWith('ig')).length + 1;
    final id = 'ig$n';
    _ids[id] = realId;
    if (label != null) _labels[id] = label;
    return id;
  }

  String _shortComment(String realId, {String? label}) {
    final existing =
        _ids.entries.where((e) => e.value == realId && e.key.startsWith('ic'));
    if (existing.isNotEmpty) return existing.first.key;
    final n = _ids.keys.where((k) => k.startsWith('ic')).length + 1;
    final id = 'ic$n';
    _ids[id] = realId;
    if (label != null) _labels[id] = label;
    return id;
  }

  String _shortThread(String realId, {String? label}) {
    final existing =
        _ids.entries.where((e) => e.value == realId && e.key.startsWith('it'));
    if (existing.isNotEmpty) return existing.first.key;
    final n = _ids.keys.where((k) => k.startsWith('it')).length + 1;
    final id = 'it$n';
    _ids[id] = realId;
    if (label != null) _labels[id] = label;
    return id;
  }

  // ── Implementations ──────────────────────────────────────────────────────

  Future<OvaToolResult> _profile() async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (igId, token) = auth;
    final d = await _get(igId, {
      'fields': 'username,name,followers_count,follows_count,media_count,biography'
    }, token);
    final lines = [
      'Username: @${d['username'] ?? ''}',
      'Name: ${d['name'] ?? ''}',
      'Followers: ${d['followers_count'] ?? 0}',
      'Following: ${d['follows_count'] ?? 0}',
      'Posts: ${d['media_count'] ?? 0}',
    ];
    return OvaToolResult(
      ok: true,
      title: '@${d['username'] ?? 'Your Instagram'}',
      summary: lines.join('\n'),
      icon: Icons.camera_alt_rounded,
      items: [for (final l in lines) OvaResultItem(title: l, icon: Icons.fiber_manual_record_rounded)],
      actions: const [
        OvaResultAction(
            label: 'Latest posts',
            icon: Icons.grid_on_rounded,
            prompt: 'show my instagram posts'),
        OvaResultAction(
            label: 'DM inbox',
            icon: Icons.mail_rounded,
            prompt: 'show my instagram dms'),
      ],
    );
  }

  Future<OvaToolResult> _media(int limit) async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (igId, token) = auth;
    final d = await _get(
        '$igId/media',
        {
          'fields': 'id,caption,media_type,thumbnail_url,media_url,timestamp,like_count,comments_count',
          'limit': '${limit.clamp(1, 15)}',
        },
        token);
    final posts = (d['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (posts.isEmpty) {
      return const OvaToolResult(
          ok: true, summary: 'No posts yet.', icon: Icons.grid_on_rounded);
    }
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final p in posts) {
      final cap = ((p['caption'] ?? '') as String).trim();
      final short = cap.length > 60 ? '${cap.substring(0, 60)}…' : cap;
      final type = (p['media_type'] ?? 'IMAGE').toString();
      final id = _shortMedia(p['id'].toString(), label: short.isEmpty ? type : short);
      lines.add('[$id] ${type.toLowerCase()}: $short (❤️ ${p['like_count'] ?? 0}, 💬 ${p['comments_count'] ?? 0})');
      items.add(OvaResultItem(
        title: short.isEmpty ? type : short,
        subtitle:
            '${p['like_count'] ?? 0} likes · ${p['comments_count'] ?? 0} comments',
        imageUrl: (p['thumbnail_url'] ?? p['media_url']) as String?,
        icon: type == 'VIDEO' ? Icons.play_circle_rounded : Icons.image_rounded,
        onTap: OvaResultAction(
          label: 'Comments',
          icon: Icons.forum_rounded,
          prompt: 'show instagram comments for $id',
        ),
      ));
    }
    return OvaToolResult(
      ok: true,
      title: 'Instagram posts',
      summary: 'Posts:\n${lines.join('\n')}',
      icon: Icons.grid_on_rounded,
      items: items,
    );
  }

  Future<OvaToolResult> _comments(String mediaShort, int limit) async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (_, token) = auth;
    final realId = _ids[mediaShort];
    if (realId == null) {
      return OvaToolResult.fail(
          'I don\'t know post "$mediaShort". List your posts first.');
    }
    final d = await _get(
        '$realId/comments',
        {
          'fields': 'id,text,username,timestamp,like_count,replies{id,text,username}',
          'limit': '${limit.clamp(1, 25)}',
        },
        token);
    final comments =
        (d['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (comments.isEmpty) {
      return const OvaToolResult(
          ok: true,
          summary: 'No comments on this post.',
          icon: Icons.forum_rounded);
    }
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final c in comments) {
      final who = (c['username'] ?? 'someone').toString();
      final text = (c['text'] ?? '').toString();
      final id = _shortComment(c['id'].toString(),
          label: '$who: ${text.length > 40 ? '${text.substring(0, 40)}…' : text}');
      lines.add('[$id] @$who: $text (❤️ ${c['like_count'] ?? 0})');
      items.add(OvaResultItem(
        title: '@$who',
        subtitle: text,
        icon: Icons.person_rounded,
        onTap: OvaResultAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          prompt: 'Help me reply to Instagram comment $id on post $mediaShort',
        ),
      ));
    }
    return OvaToolResult(
      ok: true,
      title: 'Instagram comments',
      summary: 'Comments:\n${lines.join('\n')}',
      icon: Icons.forum_rounded,
      items: items,
    );
  }

  Future<OvaToolResult> _reply(
      String mediaShort, String commentShort, String text) async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (_, token) = auth;
    final commentId = _ids[commentShort];
    if (commentId == null) {
      return OvaToolResult.fail(
          'I don\'t know comment "$commentShort". Show comments first.');
    }
    await _post('$commentId/replies', {'message': text}, token);
    return const OvaToolResult(
      ok: true,
      summary: 'Reply posted on Instagram.',
      icon: Icons.mark_chat_read_rounded,
    );
  }

  Future<OvaToolResult> _likeComment(String commentShort) async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (_, token) = auth;
    final commentId = _ids[commentShort];
    if (commentId == null) {
      return OvaToolResult.fail(
          'I don\'t know comment "$commentShort". Show comments first.');
    }
    await _post('$commentId/likes', {}, token);
    return OvaToolResult(
      ok: true,
      summary: 'Liked comment ${_labels[commentShort] ?? commentShort}.',
      icon: Icons.favorite_rounded,
    );
  }

  Future<OvaToolResult> _dmInbox(int limit) async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (igId, token) = auth;
    // Requires pages_messaging permission on the Page token.
    final d = await _get(
        '$igId/conversations',
        {
          'fields': 'id,participants,messages.limit(1){message,from,created_time}',
          'limit': '${limit.clamp(1, 10)}',
          'platform': 'instagram',
        },
        token);
    final convs =
        (d['data'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (convs.isEmpty) {
      return const OvaToolResult(
        ok: true,
        summary: 'No DM conversations yet.',
        icon: Icons.mail_rounded,
      );
    }
    final items = <OvaResultItem>[];
    final lines = <String>[];
    for (final c in convs) {
      // Get first participant that is not the IG account itself.
      final parts =
          ((c['participants'] as Map?)?['data'] as List? ?? const [])
              .cast<Map<String, dynamic>>();
      final sender = parts.isNotEmpty ? parts.first['name']?.toString() ?? 'User' : 'User';
      final msgs = ((c['messages'] as Map?)?['data'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      final lastMsg = msgs.isNotEmpty ? (msgs.first['message'] ?? '').toString() : '';
      final id = _shortThread(c['id'].toString(), label: sender);
      lines.add('[$id] $sender: $lastMsg');
      items.add(OvaResultItem(
        title: sender,
        subtitle: lastMsg,
        icon: Icons.chat_bubble_outline_rounded,
        onTap: OvaResultAction(
          label: 'Reply',
          icon: Icons.reply_rounded,
          prompt: 'Help me reply to Instagram DM from $sender (thread $id)',
        ),
      ));
    }
    return OvaToolResult(
      ok: true,
      title: 'Instagram DMs',
      summary: 'Conversations:\n${lines.join('\n')}',
      icon: Icons.mail_rounded,
      items: items,
    );
  }

  Future<OvaToolResult> _dmReply(String threadShort, String text) async {
    final auth = await _auth();
    if (auth == null) return _missing;
    final (igId, token) = auth;
    final threadId = _ids[threadShort];
    if (threadId == null) {
      return OvaToolResult.fail(
          'I don\'t know thread "$threadShort". Show DMs first.');
    }
    // POST /{ig-user-id}/messages with recipient thread
    await _post('$igId/messages', {
      'recipient': jsonEncode({'thread_key': threadId}),
      'message': jsonEncode({'text': text}),
    }, token);
    return OvaToolResult(
      ok: true,
      summary: 'DM sent to ${_labels[threadShort] ?? threadShort} on Instagram.',
      icon: Icons.mark_chat_read_rounded,
    );
  }

  // ── Error formatting ─────────────────────────────────────────────────────

  static String _friendly(Object e) {
    final t = e.toString();
    if (t.contains('190')) {
      return 'Instagram access expired. Re-connect via the Meta Wizard.';
    }
    if (t.contains('200') || t.contains('permissions')) {
      return 'Missing Instagram permission. Make sure the account is a Business/Creator account connected via Meta Wizard.';
    }
    if (t.contains('SocketException') || t.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    return 'Instagram error: ${t.length > 160 ? '${t.substring(0, 160)}…' : t}';
  }
}

final ovaInstagramToolsProvider =
    Provider<OvaInstagramTools>((ref) => OvaInstagramTools());
