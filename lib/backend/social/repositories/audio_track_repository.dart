import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audio_track.dart';

final audioTrackRepositoryProvider = Provider((ref) => AudioTrackRepository(FirebaseFirestore.instance));

class AudioTrackRepository {
  final FirebaseFirestore _firestore;

  AudioTrackRepository(this._firestore);

  Future<AudioTrack?> getAudioTrack(String id) async {
    try {
      final doc = await _firestore.collection('audio_tracks').doc(id).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      // Firestore document ID might not be in the data
      data['id'] = doc.id;
      return AudioTrack.fromMap(data);
    } catch (e) {
      return null;
    }
  }

  /// Live list of sounds creators can pick when recording.
  Stream<List<AudioTrack>> watchAvailableTracks({int limit = 40}) {
    return _firestore
        .collection('audio_tracks')
        .where('isAvailable', isEqualTo: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AudioTrack.fromMap({...d.data(), 'id': d.id})).toList());
  }
}
