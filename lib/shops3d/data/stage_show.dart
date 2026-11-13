import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/product_3d_viewer.dart' show CameraPose;

/// What a shop is presenting on its live stage right now
/// (`biz_shops/{shopId}/stage/show`).
///
/// The seller and anyone on the live's stage (co-host, guest) write it; every
/// viewer reads it. Viewers who start exploring on their own simply stop
/// following it on their phone; nothing they do is written anywhere.
@immutable
class StageShow {
  const StageShow({
    this.streamId = '',
    this.shelf = const [],
    this.activeId,
    this.camera,
    this.cameraProductId,
    this.spin,
    this.animation,
    this.by,
    this.spotlight,
    this.view,
    this.viewAt = 0,
  });

  /// A named view the presenter jumped to ([ProductView] name) and when.
  final String? view;
  final int viewAt;

  final String streamId;

  /// Products laid out for this live, in order (empty = whole catalog).
  final List<String> shelf;

  /// The product being presented.
  final String? activeId;

  /// The presenter's camera on [cameraProductId].
  final CameraPose? camera;
  final String? cameraProductId;
  final bool? spin;

  /// One of the model's animations the presenter is playing.
  final String? animation;
  final String? by;

  /// A question the seller answered on air (shown to everyone for a moment).
  final ({String question, String answer, DateTime at})? spotlight;

  static const empty = StageShow();

  /// The presenter's pose when it belongs to [productId].
  CameraPose? poseFor(String productId) => cameraProductId == productId ? camera : null;

  factory StageShow.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return empty;
    final s = d['spotlight'];
    return StageShow(
      streamId: '${d['streamId'] ?? ''}',
      shelf: List<String>.from((d['shelf'] as List?)?.whereType<String>() ?? const []),
      activeId: d['activeId'] as String?,
      camera: CameraPose.parse(d['cam']),
      cameraProductId: d['camProductId'] as String?,
      spin: d['spin'] as bool?,
      animation: d['animation'] as String?,
      by: d['by'] as String?,
      view: d['view'] as String?,
      viewAt: ((d['viewAt'] as num?) ?? 0).toInt(),
      spotlight: s is Map && s['a'] != null
          ? (question: '${s['q'] ?? ''}', answer: '${s['a']}', at: DateTime.fromMillisecondsSinceEpoch((s['at'] as num?)?.toInt() ?? 0))
          : null,
    );
  }
}

@immutable
class ShopChatSummary {
  const ShopChatSummary({
    required this.buyerId,
    required this.buyerName,
    this.productName,
    this.productId,
    this.lastText = '',
    this.lastFrom = '',
    this.unread = 0,
    this.takenOver = false,
    this.updatedAt,
  });
  final String buyerId;
  final String buyerName;
  final String? productName;
  final String? productId;
  final String lastText;
  final String lastFrom;
  final int unread;
  final bool takenOver;
  final DateTime? updatedAt;

  factory ShopChatSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final at = d['updatedAt'];
    return ShopChatSummary(
      buyerId: doc.id,
      buyerName: '${d['buyerName'] ?? 'Buyer'}',
      productName: d['productName'] as String?,
      productId: d['productId'] as String?,
      lastText: '${d['lastText'] ?? ''}',
      lastFrom: '${d['lastFrom'] ?? ''}',
      unread: ((d['unreadSeller'] as num?) ?? 0).toInt(),
      takenOver: d['takenOver'] == true,
      updatedAt: at is Timestamp ? at.toDate() : null,
    );
  }
}

@immutable
class ShopChatMessage {
  const ShopChatMessage({required this.from, required this.text, this.at});

  /// 'buyer', 'ova' or 'seller'.
  final String from;
  final String text;
  final DateTime? at;
}

class StageShowRepository {
  StageShowRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String? get uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _show(String shopId) => _db.doc('biz_shops/$shopId/stage/show');
  DocumentReference<Map<String, dynamic>> _chat(String shopId, String buyerId) => _db.doc('biz_shops/$shopId/chats/$buyerId');

  Stream<StageShow> watchShow(String shopId) => _show(shopId).snapshots().map(StageShow.fromDoc);

  /// Writes part of the show. The owner creates the doc; stage guests can
  /// only update one that already belongs to their live.
  Future<void> present(String shopId, Map<String, dynamic> fields) async {
    final me = uid;
    if (me == null) return;
    final data = {...fields, 'by': me, 'updatedAt': FieldValue.serverTimestamp()};
    try {
      if (me == shopId) {
        await _show(shopId).set(data, SetOptions(merge: true));
      } else {
        await _show(shopId).update(data);
      }
    } catch (_) {/* a dropped camera frame is fine; the next one follows */}
  }

  // ── Product questions ──

  Stream<List<ShopChatSummary>> watchChats(String shopId) => _db
      .collection('biz_shops/$shopId/chats')
      .orderBy('updatedAt', descending: true)
      .limit(40)
      .snapshots()
      .map((s) => s.docs.map(ShopChatSummary.fromDoc).toList());

  Stream<ShopChatSummary?> watchChat(String shopId, String buyerId) =>
      _chat(shopId, buyerId).snapshots().map((d) => d.exists ? ShopChatSummary.fromDoc(d) : null);

  Stream<List<ShopChatMessage>> watchMessages(String shopId, String buyerId) => _chat(shopId, buyerId)
      .collection('messages')
      .orderBy('at', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => [
            for (final d in s.docs.reversed)
              ShopChatMessage(
                from: '${d.data()['from']}',
                text: '${d.data()['text']}',
                at: d.data()['at'] is Timestamp ? (d.data()['at'] as Timestamp).toDate() : null,
              ),
          ]);

  /// The buyer asks; Ova answers unless the seller has taken over.
  Future<void> ask(String shopId, String text, {String? productId}) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('shopChatSend', options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call({'shopId': shopId, 'productId': ?productId, 'text': text});
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Your question was not sent. Try again.');
    }
  }

  /// The seller steps in (Ova stops answering) or hands the chat back to Ova.
  Future<void> setTakenOver(String shopId, String buyerId, bool on) =>
      _chat(shopId, buyerId).update({'takenOver': on, 'unreadSeller': 0, 'updatedAt': FieldValue.serverTimestamp()});

  Future<void> markRead(String shopId, String buyerId) => _chat(shopId, buyerId).update({'unreadSeller': 0});

  /// The seller answers. With [onAir] the question and answer are also shown
  /// to everyone watching the stage.
  Future<void> reply(String shopId, String buyerId, String text, {String? question, bool onAir = false}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final chat = _chat(shopId, buyerId);
    await chat.collection('messages').add({'from': 'seller', 'text': t, 'at': FieldValue.serverTimestamp(), if (onAir) 'onAir': true});
    await chat.update({'lastText': t, 'lastFrom': 'seller', 'unreadSeller': 0, 'takenOver': true, 'updatedAt': FieldValue.serverTimestamp()});
    if (onAir) {
      await present(shopId, {
        'spotlight': {'q': (question ?? '').trim(), 'a': t, 'at': DateTime.now().millisecondsSinceEpoch},
      });
    }
  }

  /// Views of each product today (the seller's own counter).
  Stream<Map<String, int>> watchViewsToday(String shopId) {
    final now = DateTime.now().toUtc();
    final day = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return _db.doc('biz_shops/$shopId/daily/$day').snapshots().map((d) {
      final by = d.data()?['byProduct'];
      if (by is! Map) return const <String, int>{};
      return {
        for (final e in by.entries)
          if (e.value is Map) '${e.key}': (((e.value as Map)['views'] as num?) ?? 0).toInt(),
      };
    });
  }
}

final stageShowRepositoryProvider = Provider<StageShowRepository>((ref) => StageShowRepository());

final stageShowProvider = StreamProvider.autoDispose.family<StageShow, String>(
  (ref, shopId) => ref.watch(stageShowRepositoryProvider).watchShow(shopId),
);

final shopChatsProvider = StreamProvider.autoDispose.family<List<ShopChatSummary>, String>(
  (ref, shopId) => ref.watch(stageShowRepositoryProvider).watchChats(shopId),
);

final shopChatProvider = StreamProvider.autoDispose.family<ShopChatSummary?, (String, String)>(
  (ref, k) => ref.watch(stageShowRepositoryProvider).watchChat(k.$1, k.$2),
);

final shopChatMessagesProvider = StreamProvider.autoDispose.family<List<ShopChatMessage>, (String, String)>(
  (ref, k) => ref.watch(stageShowRepositoryProvider).watchMessages(k.$1, k.$2),
);

final shopViewsTodayProvider = StreamProvider.autoDispose.family<Map<String, int>, String>(
  (ref, shopId) => ref.watch(stageShowRepositoryProvider).watchViewsToday(shopId),
);
