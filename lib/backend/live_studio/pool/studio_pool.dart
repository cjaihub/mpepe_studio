import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_ports.dart';
import 'pool_physics.dart';

int _toInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
double _toDouble(Object? v, [double fallback = 0.0]) => v is num ? v.toDouble() : fallback;
String _toStr(Object? v, [String fallback = '']) => v is String ? v : fallback;
bool _toBool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

@immutable
class PoolChallenger {
  const PoolChallenger({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.joinedAt,
  });

  final String uid;
  final String name;
  final String avatarUrl;
  final int joinedAt;

  factory PoolChallenger.fromJson(Map<String, dynamic> json) {
    return PoolChallenger(
      uid: _toStr(json['uid']),
      name: _toStr(json['name'], 'Challenger'),
      avatarUrl: _toStr(json['avatarUrl']),
      joinedAt: _toInt(json['joinedAt']),
    );
  }
}

@immutable
class PoolFoulData {
  const PoolFoulData({
    required this.reason,
    required this.message,
  });

  final String reason;
  final String message;

  factory PoolFoulData.fromJson(Map<String, dynamic> json) {
    return PoolFoulData(
      reason: _toStr(json['reason']),
      message: _toStr(json['message']),
    );
  }
}

@immutable
class PoolPocketedEvent {
  const PoolPocketedEvent({
    required this.ballId,
    required this.pocketId,
    required this.tMs,
  });

  final int ballId;
  final int pocketId;
  final int tMs;

  factory PoolPocketedEvent.fromJson(Map<String, dynamic> json) {
    return PoolPocketedEvent(
      ballId: _toInt(json['ballId']),
      pocketId: _toInt(json['pocketId']),
      tMs: _toInt(json['tMs']),
    );
  }
}

@immutable
class PoolLastShot {
  const PoolLastShot({
    required this.angle,
    required this.power,
    required this.spinX,
    required this.spinY,
    required this.pocketed,
    this.foul,
    required this.at,
  });

  final double angle;
  final double power;
  final double spinX;
  final double spinY;
  final List<PoolPocketedEvent> pocketed;
  final PoolFoulData? foul;
  final int at;

  factory PoolLastShot.fromJson(Map<String, dynamic> json) {
    final pocketedRaw = json['pocketed'] as List? ?? const [];
    return PoolLastShot(
      angle: _toDouble(json['angle']),
      power: _toDouble(json['power']),
      spinX: _toDouble(json['spinX']),
      spinY: _toDouble(json['spinY']),
      pocketed: [
        for (final p in pocketedRaw)
          if (p is Map) PoolPocketedEvent.fromJson(Map<String, dynamic>.from(p)),
      ],
      foul: json['foul'] is Map ? PoolFoulData.fromJson(Map<String, dynamic>.from(json['foul'] as Map)) : null,
      at: _toInt(json['at']),
    );
  }
}

@immutable
class PoolMatch {
  const PoolMatch({
    required this.v,
    required this.status,
    required this.bestOf,
    required this.rackNumber,
    required this.tableState,
    required this.p1Uid,
    required this.p1Name,
    required this.p1Avatar,
    required this.p1Score,
    this.p1Group,
    this.p2Uid,
    this.p2Name,
    this.p2Avatar,
    required this.p2Score,
    this.p2Group,
    required this.shooterUid,
    required this.balls,
    required this.ballInHand,
    required this.ballInHandKitchenOnly,
    this.calledPocket,
    required this.turnEndsAtMs,
    this.lastShot,
    this.winnerUid,
    this.winReason,
    this.challengerQueue = const [],
  });

  final int v;
  final String status; // 'waiting', 'in_progress', 'game_over', 'closed'
  final int bestOf;
  final int rackNumber;
  final String tableState; // 'open', 'solids', 'stripes'
  final String p1Uid;
  final String p1Name;
  final String p1Avatar;
  final int p1Score;
  final String? p1Group; // 'solids', 'stripes'
  final String? p2Uid;
  final String? p2Name;
  final String? p2Avatar;
  final int p2Score;
  final String? p2Group; // 'solids', 'stripes'
  final String shooterUid;
  final List<BallData> balls;
  final bool ballInHand;
  final bool ballInHandKitchenOnly;
  final int? calledPocket;
  final int turnEndsAtMs;
  final PoolLastShot? lastShot;
  final String? winnerUid;
  final String? winReason;
  final List<PoolChallenger> challengerQueue;

  bool get isWaiting => status == 'waiting';
  bool get isInProgress => status == 'in_progress';
  bool get isGameOver => status == 'game_over';
  bool get isClosed => status == 'closed';

  bool isShooter(String uid) => shooterUid == uid;
  bool isPlayer(String uid) => p1Uid == uid || p2Uid == uid;
  bool isP1(String uid) => p1Uid == uid;
  bool isP2(String uid) => p2Uid == uid;

  String? groupOf(String uid) => uid == p1Uid ? p1Group : (uid == p2Uid ? p2Group : null);

  int remainingGroupBalls(String group) {
    if (group == 'solids') {
      return balls.where((b) => b.isSolid && !b.pocketed).length;
    } else if (group == 'stripes') {
      return balls.where((b) => b.isStripe && !b.pocketed).length;
    }
    return 0;
  }

  factory PoolMatch.fromFirestore(DocumentSnapshot snap) {
    final data = (snap.data() as Map<String, dynamic>?) ?? {};
    final ballsRaw = data['balls'] as List? ?? const [];
    final queueRaw = data['challengerQueue'] as List? ?? const [];

    return PoolMatch(
      v: _toInt(data['v'], 1),
      status: _toStr(data['status'], 'waiting'),
      bestOf: _toInt(data['bestOf'], 1),
      rackNumber: _toInt(data['rackNumber'], 1),
      tableState: _toStr(data['tableState'], 'open'),
      p1Uid: _toStr(data['p1Uid']),
      p1Name: _toStr(data['p1Name'], 'Player 1'),
      p1Avatar: _toStr(data['p1Avatar']),
      p1Score: _toInt(data['p1Score']),
      p1Group: data['p1Group'] as String?,
      p2Uid: data['p2Uid'] as String?,
      p2Name: data['p2Name'] as String?,
      p2Avatar: data['p2Avatar'] as String?,
      p2Score: _toInt(data['p2Score']),
      p2Group: data['p2Group'] as String?,
      shooterUid: _toStr(data['shooterUid']),
      balls: [
        for (final b in ballsRaw)
          if (b is Map) BallData.fromJson(Map<String, dynamic>.from(b)),
      ],
      ballInHand: _toBool(data['ballInHand']),
      ballInHandKitchenOnly: _toBool(data['ballInHandKitchenOnly']),
      calledPocket: data['calledPocket'] is num ? (data['calledPocket'] as num).toInt() : null,
      turnEndsAtMs: _toInt(data['turnEndsAtMs']),
      lastShot: data['lastShot'] is Map
          ? PoolLastShot.fromJson(Map<String, dynamic>.from(data['lastShot'] as Map))
          : null,
      winnerUid: data['winnerUid'] as String?,
      winReason: data['winReason'] as String?,
      challengerQueue: [
        for (final q in queueRaw)
          if (q is Map) PoolChallenger.fromJson(Map<String, dynamic>.from(q)),
      ],
    );
  }
}

@immutable
class PoolAimTelemetry {
  const PoolAimTelemetry({
    required this.shooterUid,
    required this.angle,
    required this.power,
    required this.spinX,
    required this.spinY,
    this.cueBallX,
    this.cueBallY,
    required this.ts,
  });

  final String shooterUid;
  final double angle;
  final double power;
  final double spinX;
  final double spinY;
  final double? cueBallX;
  final double? cueBallY;
  final int ts;

  factory PoolAimTelemetry.fromJson(Map<String, dynamic> json) {
    return PoolAimTelemetry(
      shooterUid: _toStr(json['shooterUid']),
      angle: _toDouble(json['angle']),
      power: _toDouble(json['power']),
      spinX: _toDouble(json['spinX']),
      spinY: _toDouble(json['spinY']),
      cueBallX: json['cueBallX'] is num ? (json['cueBallX'] as num).toDouble() : null,
      cueBallY: json['cueBallY'] is num ? (json['cueBallY'] as num).toDouble() : null,
      ts: _toInt(json['ts']),
    );
  }
}

class StudioPoolApi {
  const StudioPoolApi(this._call);
  final StudioCallPort _call;

  Future<void> openMatch(
    String streamId, {
    int bestOf = 1,
    String? p2Uid,
  }) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'open',
      'bestOf': bestOf,
      if (p2Uid != null && p2Uid.isNotEmpty) 'p2Uid': p2Uid,
    });
  }

  Future<bool> joinMatch(String streamId) async {
    final res = await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'join',
    });
    return res['joinedAsP2'] == true;
  }

  Future<void> broadcastAim(
    String streamId, {
    required double angle,
    required double power,
    required double spinX,
    required double spinY,
    double? cueBallX,
    double? cueBallY,
  }) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'aim',
      'angle': angle,
      'power': power,
      'spinX': spinX,
      'spinY': spinY,
      'cueBallX': ?cueBallX,
      'cueBallY': ?cueBallY,
    });
  }

  Future<void> placeCueBall(
    String streamId, {
    required double x,
    required double y,
  }) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'placeCueBall',
      'x': x,
      'y': y,
    });
  }

  Future<void> callPocket(
    String streamId,
    int pocketId,
  ) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'callPocket',
      'pocketId': pocketId,
    });
  }

  Future<Map<String, dynamic>> shoot(
    String streamId, {
    required double angle,
    required double power,
    required double spinX,
    required double spinY,
    int? calledPocket,
  }) async {
    final res = await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'shoot',
      'angle': angle,
      'power': power,
      'spinX': spinX,
      'spinY': spinY,
      'calledPocket': ?calledPocket,
    });
    return (res['result'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> timeout(String streamId) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'timeout',
    });
  }

  Future<void> rematch(String streamId) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'rematch',
    });
  }

  Future<void> leaveMatch(String streamId) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'leave',
    });
  }

  Future<void> closeMatch(String streamId) async {
    await _call.call('lsPool', {
      'streamId': streamId,
      'op': 'close',
    });
  }
}

final studioPoolApiProvider = Provider<StudioPoolApi>((ref) {
  return StudioPoolApi(ref.watch(studioCallPortProvider));
});

final studioPoolProvider = StreamProvider.autoDispose.family<PoolMatch?, String>((ref, streamId) {
  final docRef = FirebaseFirestore.instance.doc('live_streams/$streamId/studio/pool');
  return docRef.snapshots().map((snap) {
    if (!snap.exists) return null;
    try {
      final match = PoolMatch.fromFirestore(snap);
      if (match.isClosed) return null;
      return match;
    } catch (e) {
      debugPrint('[studioPoolProvider] error parsing pool doc: $e');
      return null;
    }
  });
});

final studioPoolAimProvider = NotifierProvider.autoDispose
    .family<PoolAimNotifier, PoolAimTelemetry?, String>(PoolAimNotifier.new);

class PoolAimNotifier extends Notifier<PoolAimTelemetry?> {
  PoolAimNotifier(this.streamId);
  final String streamId;

  @override
  PoolAimTelemetry? build() => null;

  void update(PoolAimTelemetry? value) => state = value;
}
