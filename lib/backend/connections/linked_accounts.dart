import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../social_hub/gmail/gmail_service.dart';
import '../../youtube_manager/services/youtube_account_store.dart';
import '../meta_oauth_service.dart';
import '../tiktok_oauth_service.dart';

/// Platforms a user can link to Oneova. Each one has a real connect flow:
/// Gmail and YouTube through Google's own consent screen, TikTok through
/// TikTok Login Kit, Instagram / Facebook / WhatsApp through Facebook Login.
enum LinkedPlatform {
  gmail('Gmail', Icons.mail_rounded, messages: true),
  youtube('YouTube', Icons.smart_display_rounded, publish: true, live: true, comments: true),
  tiktok('TikTok', Icons.music_note_rounded, publish: true),
  instagram('Instagram', Icons.camera_alt_rounded, publish: true, messages: true, comments: true),
  facebook('Facebook', Icons.facebook_rounded, publish: true, live: true, messages: true, comments: true),
  whatsapp('WhatsApp Business', Icons.chat_rounded, messages: true);

  const LinkedPlatform(
    this.label,
    this.icon, {
    this.publish = false,
    this.live = false,
    this.messages = false,
    this.comments = false,
  });

  final String label;
  final IconData icon;

  /// Can receive a cross-posted video or photo.
  final bool publish;

  /// Has a live API that hands out an RTMP ingest (YouTube Live, Facebook
  /// Live Video), so a Oneova live can be restreamed to it.
  final bool live;

  /// Has a message inbox (Gmail, Instagram / Messenger DMs, WhatsApp).
  final bool messages;

  /// Has comments on posts or videos.
  final bool comments;

  String get id => name;

  bool get hasInbox => messages || comments;

  static LinkedPlatform? fromId(String? id) {
    final key = id?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final p in values) {
      if (p.name == key) return p;
    }
    return null;
  }
}

enum LinkStatus {
  /// Authorised through the platform's OAuth flow.
  connected,

  /// The platform's token has expired; the user has to sign in again.
  expired,

  /// A record with no OAuth grant behind it (written by an old build's
  /// simulated wizard). Shown so the user can reconnect, never used.
  needsReconnect,
}

/// One linked account, read from the records the OAuth flows write:
/// `users/{uid}/social_connections/{platform}` and
/// `users/{uid}/youtube_accounts/{googleId}`.
class LinkedAccount {
  final LinkedPlatform platform;
  final String accountId;
  final String accountName;
  final String avatarUrl;
  final LinkStatus status;
  final DateTime? connectedAt;
  final DateTime? expiresAt;

  const LinkedAccount({
    required this.platform,
    required this.accountId,
    required this.accountName,
    this.avatarUrl = '',
    required this.status,
    this.connectedAt,
    this.expiresAt,
  });

  bool get isUsable => status == LinkStatus.connected;

  static DateTime? _time(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return null;
  }

  /// Maps a `social_connections` doc. Returns null for platforms Oneova can't
  /// link. A doc only counts as connected when it carries the evidence the
  /// real flow leaves: a secure-storage token key (TikTok, Meta) or, for
  /// Gmail, the account email and granted scopes written by `gmailConnect`
  /// together with `tokenStore: 'server'` (older phone-only grants have no
  /// server token and need a reconnect).
  static LinkedAccount? fromConnectionDoc(String docId, Map<String, dynamic> data, {DateTime? now}) {
    final platform = LinkedPlatform.fromId(data['platform'] as String? ?? docId);
    if (platform == null || platform == LinkedPlatform.youtube) return null;

    final tokenKey = data['tokenKey'];
    final hasGrant = platform == LinkedPlatform.gmail
        ? (data['email'] is String &&
            (data['email'] as String).isNotEmpty &&
            data['grantedScopes'] is List &&
            data['tokenStore'] == 'server')
        : (tokenKey is String && tokenKey.isNotEmpty);
    final expiresAt = _time(data['tokenExpiresAt']);
    final status = !hasGrant
        ? LinkStatus.needsReconnect
        : (expiresAt != null && expiresAt.isBefore(now ?? DateTime.now()))
            ? LinkStatus.expired
            : LinkStatus.connected;

    final id = data['pageId'] ?? data['openId'] ?? data['email'] ?? docId;
    final name = (data['accountName'] ?? data['email'] ?? '').toString();
    return LinkedAccount(
      platform: platform,
      accountId: id.toString(),
      accountName: name,
      avatarUrl: (data['profilePictureUrl'] ?? '').toString(),
      status: status,
      connectedAt: _time(data['connectedAt']),
      expiresAt: expiresAt,
    );
  }

  /// Maps a `youtube_accounts` doc written by [YtAccountStore] after Google
  /// sign-in. The active channel names the account when there is one.
  static LinkedAccount? fromYoutubeDoc(Map<String, dynamic> data) {
    final googleId = (data['googleId'] ?? '').toString();
    if (googleId.isEmpty) return null;
    final channels = (data['channels'] as List? ?? const []).whereType<Map>().toList();
    final active = channels.where((c) => c['isActive'] == true).firstOrNull ?? channels.firstOrNull;
    return LinkedAccount(
      platform: LinkedPlatform.youtube,
      accountId: googleId,
      accountName: (active?['title'] ?? data['accountName'] ?? data['email'] ?? '').toString(),
      avatarUrl: (active?['thumbnailUrl'] ?? data['profilePictureUrl'] ?? '').toString(),
      status: LinkStatus.connected,
      connectedAt: _time(data['connectedAt']),
    );
  }

  /// Joins both sources, one entry per platform account, sorted in
  /// [LinkedPlatform] order.
  static List<LinkedAccount> combine(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> connections,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> youtube, {
    DateTime? now,
  }) {
    final out = <LinkedAccount>[
      for (final d in connections) ?fromConnectionDoc(d.id, d.data(), now: now),
      for (final d in youtube) ?fromYoutubeDoc(d.data()),
    ];
    out.sort((a, b) => a.platform.index.compareTo(b.platform.index));
    return out;
  }
}

/// Whether a platform's connect flow can work right now (server callable
/// `connectorStatus`). Platforms missing here are "waiting for setup".
class ConnectorReadiness {
  final bool ready;
  final String note;
  const ConnectorReadiness(this.ready, [this.note = '']);
}

const _waitingNote = 'This connection is being set up. Check back soon.';

final connectorReadinessProvider = FutureProvider<Map<LinkedPlatform, ConnectorReadiness>>((ref) async {
  try {
    final res = await FirebaseFunctions.instance.httpsCallable('connectorStatus').call<Map<String, dynamic>>();
    final raw = Map<String, dynamic>.from(res.data['platforms'] as Map? ?? const {});
    return {
      for (final p in LinkedPlatform.values)
        p: raw[p.id] is Map
            ? ConnectorReadiness((raw[p.id] as Map)['ready'] == true, ((raw[p.id] as Map)['note'] ?? '').toString())
            : (p == LinkedPlatform.youtube ? const ConnectorReadiness(true) : const ConnectorReadiness(false, _waitingNote)),
    };
  } catch (_) {
    // Status check not available yet: only the phone-side Google flow is safe.
    return {
      for (final p in LinkedPlatform.values)
        p: p == LinkedPlatform.youtube ? const ConnectorReadiness(true) : const ConnectorReadiness(false, _waitingNote),
    };
  }
});

/// Live list of the signed-in user's linked accounts.
final linkedAccountsProvider = StreamProvider<List<LinkedAccount>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  final user = FirebaseFirestore.instance.collection('users').doc(uid);
  return _combineLatest(
    user.collection('social_connections').snapshots(),
    user.collection('youtube_accounts').snapshots(),
    (a, b) => LinkedAccount.combine(a.docs, b.docs),
  );
});

/// Usable accounts only, for Post / Go Live / inbox pickers.
final usableLinkedAccountsProvider = Provider<List<LinkedAccount>>((ref) {
  final all = ref.watch(linkedAccountsProvider).value ?? const [];
  return all.where((a) => a.isUsable).toList();
});

Stream<R> _combineLatest<A, B, R>(Stream<A> a, Stream<B> b, R Function(A, B) combine) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false, hasB = false;
  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError);
      subB = b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

/// Starts and ends links. Flows with their own wizard return the route to
/// push; Gmail and YouTube open Google's consent screen in place.
class LinkedAccountsController {
  LinkedAccountsController(this.ref);
  final Ref ref;

  /// The wizard route for [platform], or null when [connect] handles it.
  static String? wizardRoute(LinkedPlatform platform) => switch (platform) {
        LinkedPlatform.tiktok => '/social_hub/tiktok_wizard',
        LinkedPlatform.instagram => '/social_hub/meta_wizard/instagram',
        LinkedPlatform.facebook => '/social_hub/meta_wizard/facebook',
        LinkedPlatform.whatsapp => '/social_hub/meta_wizard/whatsapp',
        LinkedPlatform.gmail || LinkedPlatform.youtube => null,
      };

  /// Gmail / YouTube: asks Google for the scopes and records the grant.
  /// Returns false if the user declined.
  Future<bool> connect(LinkedPlatform platform) async {
    switch (platform) {
      case LinkedPlatform.youtube:
        await ref.read(ytAccountStoreProvider.notifier).addAccount();
        final state = ref.read(ytAccountStoreProvider).value;
        return state?.accounts.isNotEmpty ?? false;
      case LinkedPlatform.gmail:
        return _connectGmail();
      default:
        return false;
    }
  }

  /// Gmail is kept on the server: Google's consent screen returns a one-time
  /// code, `gmailConnect` exchanges it and stores the encrypted refresh token
  /// under `users/{uid}/secure_tokens/gmail`, then writes the status doc this
  /// screen listens to. The phone never stores a Gmail token.
  Future<bool> _connectGmail() async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    final email = await ref.read(gmailServiceProvider).connect();
    return email.isNotEmpty;
  }

  Future<void> disconnect(LinkedAccount account) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    switch (account.platform) {
      case LinkedPlatform.youtube:
        await ref.read(ytAccountStoreProvider.notifier).removeAccount(account.accountId);
      case LinkedPlatform.tiktok:
        await ref.read(tiktokOAuthProvider.notifier).disconnect();
      case LinkedPlatform.instagram:
        await ref.read(metaOAuthProvider.notifier).disconnect(MetaApp.instagram);
      case LinkedPlatform.facebook:
        await ref.read(metaOAuthProvider.notifier).disconnect(MetaApp.facebook);
      case LinkedPlatform.whatsapp:
        await ref.read(metaOAuthProvider.notifier).disconnect(MetaApp.whatsapp);
      case LinkedPlatform.gmail:
        // Revokes at Google and deletes the token + status doc server-side.
        await ref.read(gmailServiceProvider).disconnect();
    }
  }
}

final linkedAccountsControllerProvider = Provider<LinkedAccountsController>(LinkedAccountsController.new);
