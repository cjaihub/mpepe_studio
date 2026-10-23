import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_track.dart';

import '../models/content.dart';

final audioServiceProvider = Provider<AudioService>((ref) => AudioService());

class CopyrightException implements Exception {
  final String message;
  CopyrightException(this.message);
  @override
  String toString() => 'CopyrightException: $message';
}

class AudioService {
  final FirebaseFirestore _firestore;
  AudioService([FirebaseFirestore? firestore]) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _tracks => _firestore.collection('audio_tracks');
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  List<AudioTrack> _fromDocs(Iterable<DocumentSnapshot<Map<String, dynamic>>> docs) =>
      docs.where((d) => d.exists).map((d) => AudioTrack.fromMap({...?d.data(), 'id': d.id})).toList();

  Future<List<AudioTrack>> getTrendingSounds() async {
    final snap = await _tracks.where('isAvailable', isEqualTo: true).limit(30).get();
    return _fromDocs(snap.docs);
  }

  /// Sounds the current user published.
  Future<List<AudioTrack>> getRecentSounds() async {
    final uid = _uid;
    if (uid == null) return [];
    final snap = await _tracks.where('ownerId', isEqualTo: uid).limit(30).get();
    return _fromDocs(snap.docs);
  }

  Future<List<AudioTrack>> getFavorites() async {
    final uid = _uid;
    if (uid == null) return [];
    final favs = await _firestore.collection('users').doc(uid).collection('favorite_sounds').limit(50).get();
    final docs = await Future.wait(favs.docs.map((f) => _tracks.doc(f.id).get()));
    return _fromDocs(docs);
  }

  Future<AudioTrack> getSoundDetails(String id) async {
    final doc = await _tracks.doc(id).get();
    if (!doc.exists) throw StateError('This sound is no longer available.');
    return AudioTrack.fromMap({...?doc.data(), 'id': doc.id});
  }

  Stream<bool> watchIsFavorite(String id) {
    final uid = _uid;
    if (uid == null) return Stream.value(false);
    return _firestore.collection('users').doc(uid).collection('favorite_sounds').doc(id).snapshots().map((d) => d.exists);
  }

  /// Toggles the sound in the user's favorites (one doc per user per sound).
  Future<bool> toggleFavorite(String id) async {
    final uid = _uid;
    if (uid == null) throw StateError('Sign in to save sounds.');
    final ref = _firestore.collection('users').doc(uid).collection('favorite_sounds').doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      await ref.delete();
      return false;
    }
    await ref.set({'savedAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// Discover & Search (title prefix match).
  Future<List<AudioTrack>> searchSounds(String query) async {
    final q = query.trim();
    if (q.isEmpty) return getTrendingSounds();
    final snap = await _tracks.orderBy('title').startAt([q]).endAt(['$q\uf8ff']).limit(30).get();
    return _fromDocs(snap.docs);
  }

  /// Public videos that use this sound.
  Stream<List<Content>> watchVideosForSound(String musicId) {
    return _firestore
        .collection('content')
        .where('mediaMetadata.musicId', isEqualTo: musicId)
        .limit(60)
        .snapshots()
        .map((snap) => snap.docs.map(Content.fromFirestore).where((c) => c.visibility == 'public').toList());
  }

  /// Ingest / Publish Sound
  /// Do not ingest copyrighted music without appropriate rights.
  Future<AudioTrack> ingestSound({
    required String title,
    required String ownerId,
    required String ownerName,
    required AudioType type,
    required AudioLicenseType licenseType,
    required String contentUrl,
    bool hasCopyrightClearance = false,
  }) async {
    // Copyright Enforcement
    if (type == AudioType.licensedMusic || type == AudioType.uploadedMusic) {
      if (licenseType == AudioLicenseType.commercial && !hasCopyrightClearance) {
        throw CopyrightException('Cannot ingest copyrighted music without explicit rights clearance.');
      }
    }

    final track = AudioTrack(
      id: 'sound_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      ownerId: ownerId,
      ownerName: ownerName,
      type: type,
      licenseType: licenseType,
      durationMs: 15000,
      isAvailable: true,
      permissions: const AudioUsagePermissions(
        allowRemix: true,
        allowDownload: false, // Default restrict download for new ingested sounds
      ),
      attribution: 'Original audio by $ownerName',
      contentUrl: contentUrl,
      coverImageUrl: '',
    );

    final ref = _tracks.doc();
    final saved = AudioTrack.fromMap({...track.toMap(), 'id': ref.id});
    await ref.set({...saved.toMap(), 'createdAt': FieldValue.serverTimestamp()});
    return saved;
  }
}
