import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../connections/linked_accounts.dart';

/// Records, on `live_streams/{id}`, which linked platforms a Oneova live
/// should also go live on. Only platforms with a live API qualify
/// ([LinkedPlatform.live]: YouTube Live, Facebook Live Video).
///
/// The app only writes the request (`restreamTargets.{platform}.status =
/// 'requested'`). Creating the platform broadcast, getting its RTMP ingest
/// and starting a LiveKit egress to it has to run server-side with the
/// platform tokens; that function is not part of this build.
class LiveRestreamService {
  LiveRestreamService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  /// The update for [targets]; accounts that can't go live are skipped.
  static Map<String, dynamic> requestFields(Iterable<LinkedAccount> targets, {DateTime? now}) {
    final usable = targets.where((a) => a.isUsable && a.platform.live).toList();
    final at = Timestamp.fromDate(now ?? DateTime.now());
    return {
      'isMultiPlatform': usable.isNotEmpty,
      'linkedPlatforms': [for (final a in usable) a.platform.id],
      'restreamTargets': {
        for (final a in usable)
          a.platform.id: {
            'accountId': a.accountId,
            'accountName': a.accountName,
            'status': 'requested',
            'requestedAt': at,
          },
      },
    };
  }

  Future<void> request(String streamId, Iterable<LinkedAccount> targets) async {
    final fields = requestFields(targets);
    if (fields['isMultiPlatform'] != true) return;
    await _firestore.collection('live_streams').doc(streamId).set(fields, SetOptions(merge: true));
  }
}

final liveRestreamServiceProvider = Provider<LiveRestreamService>((ref) => LiveRestreamService());
