import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/media_rights_models.dart';

final mediaRightsServiceProvider = Provider<MediaRightsService>((ref) {
  return MediaRightsService();
});

class MediaRightsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Fetch rights profile for a given piece of media
  Stream<MediaRightsProfile?> streamMediaRights(String mediaId) {
    return _firestore
        .collection('media_rights')
        .doc(mediaId)
        .snapshots()
        .map((doc) => doc.exists ? MediaRightsProfile.fromFirestore(doc) : null);
  }

  /// Write rights at time of upload or update them later
  Future<void> updateMediaRights(String mediaId, MediaRightsProfile profile) async {
    final uid = _userId;
    // Security: Only the owner or an admin can update rights.
    // Assuming backend security rules enforce this.
    if (uid == null || uid != profile.ownerId) return;

    await _firestore
        .collection('media_rights')
        .doc(mediaId)
        .set(profile.toMap(), SetOptions(merge: true));
  }

  /// A creator revoking rights
  Future<void> revokeReuse(String mediaId) async {
    final uid = _userId;
    if (uid == null) return;
    
    // In production, this sets the flag and triggers a cloud function 
    // to cascade deletions or muting of downstream remixes/duets if policy allows.
    await _firestore
        .collection('media_rights')
        .doc(mediaId)
        .update({
      'isRevoked': true,
      'permissions.allowRemix': false,
      'permissions.allowDuet': false,
      'permissions.allowStitch': false,
      'permissions.allowDownload': false,
    });
  }

  /// Helper to check if current user can interact with the media
  Future<bool> canPerformAction(String mediaId, bool Function(ReusePermissions) actionCheck) async {
    final doc = await _firestore.collection('media_rights').doc(mediaId).get();
    if (!doc.exists) return false;
    
    final profile = MediaRightsProfile.fromFirestore(doc);
    if (profile.isRevoked) return false;
    
    return actionCheck(profile.permissions);
  }
}
