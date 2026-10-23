// LIVE STUDIO v2 — realtime social: local ports (workstream #2).
//
// Wiring: the social controllers read the LiveKit room and the studio session
// through these adapters. LiveStudioV2Screen overrides them in its
// ProviderScope (see studio_v2/shell/studio_scope.dart); tests use fakes.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';

/// The connected room for a stream (null while not connected / not wired).
final studioSocialRoomPortProvider =
    Provider.family<StudioRoomPort?, String>((ref, streamId) => null);

/// Authoritative [StudioState] stream for a stream (null when not wired).
final studioSocialStateSourceProvider =
    Provider.family<Stream<StudioState>?, String>((ref, streamId) => null);

/// Live data events for a stream, or an empty stream when no room is wired.
Stream<StudioEvent> studioSocialEvents(Ref ref, String streamId) =>
    ref.watch(studioSocialRoomPortProvider(streamId))?.events ?? const Stream<StudioEvent>.empty();

/// Who the local user is (for optimistic rows). Null when signed out.
class StudioViewerIdentity {
  const StudioViewerIdentity({required this.uid, required this.name, this.avatarUrl = ''});
  final String uid;
  final String name;
  final String avatarUrl;
}

final studioViewerIdentityProvider = Provider<StudioViewerIdentity?>((ref) {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return null;
  return StudioViewerIdentity(
    uid: u.uid,
    name: (u.displayName ?? '').trim().isEmpty ? 'You' : u.displayName!.trim(),
    avatarUrl: u.photoURL ?? '',
  );
});

/// One-time read of the latest comments (late-join history).
abstract class StudioCommentHistorySource {
  /// The last [limit] comments, oldest first.
  Future<List<LiveStudioComment>> latest(String streamId, int limit);
}

class FirestoreCommentHistorySource implements StudioCommentHistorySource {
  FirestoreCommentHistorySource([FirebaseFirestore? db]) : _db = db;
  final FirebaseFirestore? _db;

  @override
  Future<List<LiveStudioComment>> latest(String streamId, int limit) async {
    final db = _db ?? FirebaseFirestore.instance;
    final snap = await db
        .collection(StudioPaths.comments(streamId))
        .orderBy('ts', descending: true)
        .limit(limit)
        .get();
    final out = snap.docs.map((d) {
      final j = Map<String, dynamic>.from(d.data());
      j['id'] = (j['id'] is String && (j['id'] as String).isNotEmpty) ? j['id'] : d.id;
      return LiveStudioComment.fromJson(j);
    }).toList();
    out.sort((a, b) => a.ts.compareTo(b.ts));
    return out;
  }
}

final studioCommentHistorySourceProvider =
    Provider<StudioCommentHistorySource>((ref) => FirestoreCommentHistorySource());

/// Server id for a comment sent with [clientId] (mirrors `commentDocId` in
/// functions/src/liveStudio/social_logic.ts).
String studioCommentDocId(String uid, String clientId) => '${uid}_$clientId';
