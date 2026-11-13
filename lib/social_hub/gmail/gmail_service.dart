import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/connections/google_services.dart';

/// The user's own Gmail, connected per user (functions/src/gmailUser.ts).
///
/// Connecting shows Google's consent screen for exactly these scopes and
/// sends a one-time server code to the `gmailConnect` function, which keeps
/// the refresh token encrypted under `users/{uid}/secure_tokens/gmail`
/// (server only). Mail is read and sent through the `gmailCall` function; the
/// app never holds a long-lived Gmail token.
class GmailService {
  static const scopes = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/gmail.modify',
  ];

  /// What the consent covers, in plain words (shown before connecting).
  static const scopeExplained = [
    ('Read your email', 'List, search and open messages in Oneova and for Ova.'),
    ('Send email as you', 'Only when you press Send, or approve Ova\'s card.'),
    ('Organise your inbox', 'Mark read, star, archive or move to Trash when you ask.'),
  ];

  final _fn = FirebaseFunctions.instance;

  /// Links Gmail through Google services (functions/src/googleLink.ts), so
  /// it shows on the person's Google account with their other services.
  /// Returns '' if they cancelled Google's screen.
  Future<String> connect() async {
    try {
      return await GoogleServices.link(GoogleService.gmail) ?? '';
    } on GoogleServicesException catch (e) {
      throw GmailException(e.message);
    }
  }

  Future<void> disconnect() => _call('gmailDisconnect', const {});

  Future<GmailPage> list({String query = 'in:inbox', int limit = 20, String? pageToken}) async {
    final r = await _call('gmailCall', {'action': 'list', 'query': query, 'limit': limit, 'pageToken': ?pageToken});
    final msgs = ((r['messages'] as List?) ?? const []).map((m) => GmailMessage.fromMap(Map<String, dynamic>.from(m as Map))).toList();
    return GmailPage(msgs, r['nextPageToken'] as String?);
  }

  Future<GmailMessage> get(String id) async =>
      GmailMessage.fromMap(await _call('gmailCall', {'action': 'get', 'id': id}));

  Future<void> send({required String to, required String subject, required String body}) =>
      _call('gmailCall', {'action': 'send', 'to': to, 'subject': subject, 'body': body});

  Future<String> reply(String id, String body) async =>
      ((await _call('gmailCall', {'action': 'reply', 'id': id, 'body': body}))['to'] ?? '').toString();

  Future<void> modify(String id, {List<String> add = const [], List<String> remove = const []}) =>
      _call('gmailCall', {'action': 'modify', 'id': id, 'add': add, 'remove': remove});

  Future<void> trash(String id) => _call('gmailCall', {'action': 'trash', 'id': id});

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw GmailException(e.message ?? 'Gmail request failed.', notConnected: e.code == 'failed-precondition');
    }
  }
}

class GmailException implements Exception {
  final String message;
  final bool notConnected;
  const GmailException(this.message, {this.notConnected = false});
  @override
  String toString() => message;
}

class GmailPage {
  final List<GmailMessage> messages;
  final String? nextPageToken;
  const GmailPage(this.messages, this.nextPageToken);
}

class GmailMessage {
  final String id;
  final String threadId;
  final String from;
  final String to;
  final String subject;
  final String date;
  final DateTime? receivedAt;
  final String snippet;
  final bool unread;
  final bool starred;
  final String? body;

  const GmailMessage({
    required this.id,
    required this.threadId,
    required this.from,
    required this.to,
    required this.subject,
    required this.date,
    this.receivedAt,
    required this.snippet,
    required this.unread,
    required this.starred,
    this.body,
  });

  factory GmailMessage.fromMap(Map<String, dynamic> m) => GmailMessage(
        id: (m['id'] ?? '').toString(),
        threadId: (m['threadId'] ?? '').toString(),
        from: (m['from'] ?? '').toString(),
        to: (m['to'] ?? '').toString(),
        subject: (m['subject'] ?? '').toString(),
        date: (m['date'] ?? '').toString(),
        receivedAt: switch (int.tryParse((m['internalDate'] ?? '').toString())) {
          final ms? => DateTime.fromMillisecondsSinceEpoch(ms),
          null => null,
        },
        snippet: _unescape((m['snippet'] ?? '').toString()),
        unread: m['unread'] == true,
        starred: m['starred'] == true,
        body: m['body'] as String?,
      );

  /// `Jane Doe <jane@x.com>` becomes `Jane Doe`.
  String get fromName {
    final n = from.replaceAll(RegExp(r'\s*<.*>'), '').replaceAll('"', '').trim();
    return n.isEmpty ? from : n;
  }

  static String _unescape(String s) =>
      s.replaceAll('&#39;', "'").replaceAll('&quot;', '"').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
}

final gmailServiceProvider = Provider<GmailService>((ref) => GmailService());

/// The connected Gmail address, or null. Written only by the server.
final gmailConnectionProvider = StreamProvider<String?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('social_connections')
      .doc('gmail')
      .snapshots()
      .map((d) => d.exists ? ((d.data()?['accountName'] as String?) ?? '') : null);
});
