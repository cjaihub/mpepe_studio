import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Oneova Feedback ("What do you wish Oneova had?") — community feature ideas.
///
/// Firestore: `wish_ideas/{id}` (+ `comments`, `reactions/{uid}`). Counters,
/// AI tags and notifications are written by Cloud Functions
/// (`functions/src/wishIdeas.ts`); the app only writes the user's own idea,
/// comment and reaction. Admin status changes and official replies come from
/// the web dashboard and stream in here in real time.
class WishService {
  WishService._();
  static final WishService instance = WishService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _ideas => _db.collection('wish_ideas');

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<List<WishIdea>> watchIdeas(WishFilter filter) {
    Query<Map<String, dynamic>> q;
    switch (filter) {
      case WishFilter.top:
        q = _ideas.orderBy('reactionCount', descending: true).limit(60);
      case WishFilter.newest:
        q = _ideas.orderBy('createdAt', descending: true).limit(60);
      case WishFilter.inProgress:
        q = _ideas.where('status', whereIn: ['planned', 'building']).limit(60);
      case WishFilter.shipped:
        q = _ideas.where('status', isEqualTo: 'shipped').limit(60);
      case WishFilter.mine:
        q = _ideas.where('authorId', isEqualTo: uid ?? '_').limit(60);
    }
    return q.snapshots().map((s) {
      final list = s.docs.map(WishIdea.fromDoc).toList();
      if (filter == WishFilter.inProgress || filter == WishFilter.shipped || filter == WishFilter.mine) {
        list.sort((a, b) => (b.statusUpdatedAt ?? b.createdAt ?? DateTime(0))
            .compareTo(a.statusUpdatedAt ?? a.createdAt ?? DateTime(0)));
      }
      return list;
    });
  }

  Stream<WishIdea?> watchIdea(String id) =>
      _ideas.doc(id).snapshots().map((d) => d.exists ? WishIdea.fromDoc(d) : null);

  Stream<List<WishComment>> watchComments(String ideaId) => _ideas
      .doc(ideaId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(WishComment.fromDoc).toList());

  Stream<bool> watchMyReaction(String ideaId) {
    final me = uid;
    if (me == null) return Stream.value(false);
    return _ideas.doc(ideaId).collection('reactions').doc(me).snapshots().map((d) => d.exists);
  }

  Future<Map<String, String>> _me() async {
    final user = FirebaseAuth.instance.currentUser!;
    final d = (await _db.collection('users').doc(user.uid).get()).data() ?? const {};
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = d[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    return {
      'authorName': pick(['displayName', 'fullName', 'name', 'username']).isNotEmpty
          ? pick(['displayName', 'fullName', 'name', 'username'])
          : (user.displayName ?? 'Oneova member'),
      'authorPhoto': pick(['avatarUrl', 'profilePhotoUrl', 'photoUrl', 'profileImageUrl']).isNotEmpty
          ? pick(['avatarUrl', 'profilePhotoUrl', 'photoUrl', 'profileImageUrl'])
          : (user.photoURL ?? ''),
    };
  }

  Future<String> postIdea({required String title, required String body}) async {
    final me = uid;
    if (me == null) throw StateError('Sign in to share an idea.');
    final author = await _me();
    final ref = _ideas.doc();
    await ref.set({
      'authorId': me,
      ...author,
      'title': title.trim(),
      'body': body.trim(),
      'status': 'open',
      'reactionCount': 0,
      'commentCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> editIdea(String id, {required String title, required String body}) => _ideas.doc(id).update({
        'title': title.trim(),
        'body': body.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> deleteIdea(String id) => _ideas.doc(id).delete();

  /// One reaction per person: the reaction doc id is the user's uid.
  Future<void> toggleReaction(String ideaId, bool currentlyReacted) async {
    final me = uid;
    if (me == null) return;
    final ref = _ideas.doc(ideaId).collection('reactions').doc(me);
    if (currentlyReacted) {
      await ref.delete();
    } else {
      await ref.set({'uid': me, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> addComment(String ideaId, String text) async {
    final me = uid;
    if (me == null) throw StateError('Sign in to comment.');
    final author = await _me();
    await _ideas.doc(ideaId).collection('comments').add({
      'authorId': me,
      ...author,
      'text': text.trim(),
      'isOfficial': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteComment(String ideaId, String commentId) =>
      _ideas.doc(ideaId).collection('comments').doc(commentId).delete();
}

enum WishFilter { top, newest, inProgress, shipped, mine }

extension WishFilterLabel on WishFilter {
  String get label => switch (this) {
        WishFilter.top => 'Top',
        WishFilter.newest => 'New',
        WishFilter.inProgress => 'In progress',
        WishFilter.shipped => 'Shipped',
        WishFilter.mine => 'Mine',
      };
}

DateTime? _ts(dynamic v) => v is Timestamp ? v.toDate() : null;
String _s(dynamic v) => v is String ? v : '';
int _i(dynamic v) => v is num ? v.toInt() : 0;

class WishIdea {
  WishIdea({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhoto,
    required this.title,
    required this.body,
    required this.status,
    required this.reactionCount,
    required this.commentCount,
    required this.createdAt,
    required this.statusUpdatedAt,
    required this.category,
    required this.aiSummary,
    required this.alreadyExists,
    required this.existingFeature,
    required this.adminReply,
    required this.adminReplyAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorPhoto;
  final String title;
  final String body;
  final String status;
  final int reactionCount;
  final int commentCount;
  final DateTime? createdAt;
  final DateTime? statusUpdatedAt;
  final String category;
  final String aiSummary;
  final bool alreadyExists;
  final String existingFeature;
  final String adminReply;
  final DateTime? adminReplyAt;

  factory WishIdea.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final ai = m['ai'] is Map ? Map<String, dynamic>.from(m['ai'] as Map) : const <String, dynamic>{};
    final reply = m['adminReply'] is Map ? Map<String, dynamic>.from(m['adminReply'] as Map) : const <String, dynamic>{};
    return WishIdea(
      id: d.id,
      authorId: _s(m['authorId']),
      authorName: _s(m['authorName']).isEmpty ? 'Oneova member' : _s(m['authorName']),
      authorPhoto: _s(m['authorPhoto']),
      title: _s(m['title']),
      body: _s(m['body']),
      status: _s(m['status']).isEmpty ? 'open' : _s(m['status']),
      reactionCount: _i(m['reactionCount']),
      commentCount: _i(m['commentCount']),
      createdAt: _ts(m['createdAt']),
      statusUpdatedAt: _ts(m['statusUpdatedAt']),
      category: _s(ai['category']),
      aiSummary: _s(ai['summary']),
      alreadyExists: ai['alreadyExists'] == true,
      existingFeature: _s(ai['existingFeature']),
      adminReply: _s(reply['text']),
      adminReplyAt: _ts(reply['at']),
    );
  }
}

class WishComment {
  WishComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorPhoto,
    required this.text,
    required this.isOfficial,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String authorPhoto;
  final String text;
  final bool isOfficial;
  final DateTime? createdAt;

  factory WishComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return WishComment(
      id: d.id,
      authorId: _s(m['authorId']),
      authorName: _s(m['authorName']).isEmpty ? 'Oneova member' : _s(m['authorName']),
      authorPhoto: _s(m['authorPhoto']),
      text: _s(m['text']),
      isOfficial: m['isOfficial'] == true,
      createdAt: _ts(m['createdAt']),
    );
  }
}
