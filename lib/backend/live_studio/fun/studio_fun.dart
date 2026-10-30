// LIVE STUDIO v2 — host entertainment + recording / restream (client side).
//
// - [studioFunProvider] (streamId) → live FunState from `studio/fun`;
// - [StudioFunApi] → lsFun (polls, timers, spotlight, celebrate, raffle);
// - [StudioBroadcastApi] → lsBroadcast / lsDestinations / lsRecordingDecision.
// Server: functions/src/liveStudio/fun.ts, broadcast.ts.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../session/studio_session_controller.dart';

int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';

@immutable
class StudioPoll {
  const StudioPoll({
    required this.id,
    required this.question,
    required this.options,
    required this.counts,
    required this.endsAtMs,
    required this.open,
  });
  final String id;
  final String question;
  final List<String> options;
  final List<int> counts;
  final int endsAtMs;
  final bool open;

  int get total => counts.fold(0, (a, b) => a + b);
  bool acceptingAt(int nowMs) => open && nowMs < endsAtMs;

  static StudioPoll? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final options = [for (final o in (raw['options'] as List? ?? const [])) _str(o)];
    final counts = [for (final c in (raw['counts'] as List? ?? const [])) _int(c)];
    while (counts.length < options.length) {
      counts.add(0);
    }
    return StudioPoll(
      id: _str(raw['id']),
      question: _str(raw['question']),
      options: options,
      counts: counts,
      endsAtMs: _int(raw['endsAtMs']),
      open: raw['open'] == true,
    );
  }
}

@immutable
class StudioFunState {
  const StudioFunState({
    this.poll,
    this.timerLabel,
    this.timerEndsAtMs,
    this.spotlightText,
    this.spotlightName = '',
    this.spotlightAvatarUrl = '',
    this.spotlightAtMs = 0,
    this.celebrateKind,
    this.celebrateAtMs = 0,
    this.raffleWinnerName,
    this.raffleWinnerAvatarUrl = '',
    this.raffleEntrants = 0,
    this.raffleAtMs = 0,
  });

  final StudioPoll? poll;
  final String? timerLabel;
  final int? timerEndsAtMs;
  final String? spotlightText;
  final String spotlightName;
  final String spotlightAvatarUrl;
  final int spotlightAtMs;
  final String? celebrateKind;
  final int celebrateAtMs;
  final String? raffleWinnerName;
  final String raffleWinnerAvatarUrl;
  final int raffleEntrants;
  final int raffleAtMs;

  factory StudioFunState.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const StudioFunState();
    final t = j['timer'], s = j['spotlight'], c = j['celebrate'], r = j['raffle'];
    return StudioFunState(
      poll: StudioPoll.fromJson(j['poll']),
      timerLabel: t is Map ? _str(t['label']) : null,
      timerEndsAtMs: t is Map ? _int(t['endsAtMs']) : null,
      spotlightText: s is Map ? _str(s['text']) : null,
      spotlightName: s is Map ? _str(s['name']) : '',
      spotlightAvatarUrl: s is Map ? _str(s['avatarUrl']) : '',
      spotlightAtMs: s is Map ? _int(s['atMs']) : 0,
      celebrateKind: c is Map ? _str(c['kind']) : null,
      celebrateAtMs: c is Map ? _int(c['atMs']) : 0,
      raffleWinnerName: r is Map ? _str(r['winnerName']) : null,
      raffleWinnerAvatarUrl: r is Map ? _str(r['winnerAvatarUrl']) : '',
      raffleEntrants: r is Map ? _int(r['entrants']) : 0,
      raffleAtMs: r is Map ? _int(r['atMs']) : 0,
    );
  }
}

/// Live entertainment state for a stream (server-written `studio/fun`).
final studioFunProvider = StreamProvider.autoDispose.family<StudioFunState, String>((ref, streamId) {
  final db = ref.watch(studioFirestoreProvider);
  return db
      .doc('${StudioPaths.streams}/$streamId/studio/fun')
      .snapshots()
      .map((d) => StudioFunState.fromJson(d.data()));
});

class StudioFunApi {
  const StudioFunApi(this._call);
  final StudioCallPort _call;

  Future<Map<String, dynamic>> _op(String streamId, String op, [Map<String, dynamic> args = const {}]) =>
      _call.call('lsFun', {'streamId': streamId, 'op': op, ...args});

  Future<void> startPoll(String streamId, String question, List<String> options, {int seconds = 60}) =>
      _op(streamId, 'pollStart', {'question': question, 'options': options, 'seconds': seconds});
  Future<void> endPoll(String streamId) => _op(streamId, 'pollEnd');
  Future<void> vote(String streamId, int option) => _op(streamId, 'pollVote', {'option': option});
  Future<void> startTimer(String streamId, int seconds, {String? label}) =>
      _op(streamId, 'timerStart', {'seconds': seconds, 'label': ?label});
  Future<void> stopTimer(String streamId) => _op(streamId, 'timerStop');
  Future<void> spotlight(String streamId, {String? text, String? commentId}) =>
      _op(streamId, 'spotlight', {'text': ?text, 'commentId': ?commentId});
  Future<void> clearSpotlight(String streamId) => _op(streamId, 'spotlightClear');
  Future<void> celebrate(String streamId, String kind) => _op(streamId, 'celebrate', {'kind': kind});
  Future<void> raffle(String streamId) => _op(streamId, 'raffle');
}

final studioFunApiProvider = Provider<StudioFunApi>((ref) => StudioFunApi(ref.watch(studioCallPortProvider)));

/// A saved restream destination, as the server shows it (key masked).
@immutable
class LiveDestination {
  const LiveDestination({
    required this.id,
    required this.platform,
    required this.label,
    required this.url,
    required this.keyHint,
    required this.enabled,
  });
  final String id;
  final String platform;
  final String label;
  final String url;
  final String keyHint;
  final bool enabled;

  factory LiveDestination.fromJson(Map<String, dynamic> j) => LiveDestination(
        id: _str(j['id']),
        platform: _str(j['platform']),
        label: _str(j['label']),
        url: _str(j['url']),
        keyHint: _str(j['keyHint']),
        enabled: j['enabled'] != false,
      );
}

@immutable
class LiveRecordingStatus {
  const LiveRecordingStatus({
    required this.status,
    required this.record,
    required this.platforms,
    this.durationMs,
    this.sizeBytes,
    this.decision,
    this.path,
    this.error,
  });
  final String? status; // active · stopping · ready · failed
  final bool record;
  final List<String> platforms;
  final int? durationMs;
  final int? sizeBytes;
  final String? decision; // kept · discarded
  final String? path;
  final String? error;

  bool get active => status == 'active';
  bool get ready => status == 'ready';

  static LiveRecordingStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return LiveRecordingStatus(
      status: raw['status'] as String?,
      record: raw['record'] == true,
      platforms: [for (final p in (raw['platforms'] as List? ?? const [])) _str(p)],
      durationMs: raw['durationMs'] is num ? (raw['durationMs'] as num).toInt() : null,
      sizeBytes: raw['sizeBytes'] is num ? (raw['sizeBytes'] as num).toInt() : null,
      decision: raw['decision'] as String?,
      path: raw['path'] as String?,
      error: raw['error'] as String?,
    );
  }
}

class StudioBroadcastApi {
  const StudioBroadcastApi(this._call);
  final StudioCallPort _call;

  List<LiveDestination> _list(Map<String, dynamic> r) => [
        for (final d in (r['destinations'] as List? ?? const []))
          if (d is Map) LiveDestination.fromJson(Map<String, dynamic>.from(d)),
      ];

  Future<List<LiveDestination>> destinations() async => _list(await _call.call('lsDestinations', {'op': 'list'}));

  /// Saves (adds when [id] is null). An empty [key] keeps the saved key.
  Future<List<LiveDestination>> saveDestination({
    String? id,
    required String platform,
    required String label,
    required String url,
    required String key,
    bool enabled = true,
  }) async =>
      _list(await _call.call('lsDestinations', {
        'op': 'save',
        'id': ?id,
        'destination': {'platform': platform, 'label': label, 'url': url, 'key': key, 'enabled': enabled},
      }));

  Future<List<LiveDestination>> deleteDestination(String id) async =>
      _list(await _call.call('lsDestinations', {'op': 'delete', 'id': id}));

  Future<LiveRecordingStatus?> start(String streamId,
          {bool record = true, bool restream = true, String frame = 'portrait'}) async =>
      LiveRecordingStatus.fromJson((await _call.call('lsBroadcast', {
        'streamId': streamId,
        'op': 'start',
        'record': record,
        'restream': restream,
        'frame': frame,
      }))['recording']);

  Future<void> stop(String streamId) => _call.call('lsBroadcast', {'streamId': streamId, 'op': 'stop'});

  Future<LiveRecordingStatus?> status(String streamId) async =>
      LiveRecordingStatus.fromJson((await _call.call('lsBroadcast', {'streamId': streamId, 'op': 'status'}))['recording']);

  /// Returns the Storage path when kept.
  Future<String?> decide(String streamId, {required bool keep}) async {
    final r = await _call.call('lsRecordingDecision', {'streamId': streamId, 'keep': keep});
    return r['storagePath'] as String?;
  }
}

final studioBroadcastApiProvider =
    Provider<StudioBroadcastApi>((ref) => StudioBroadcastApi(ref.watch(studioCallPortProvider)));

/// Per-viewer display preferences for the studio (local only).
@immutable
class StudioViewPrefs {
  const StudioViewPrefs({this.cleanView = false, this.showEffects = true});
  final bool cleanView;
  final bool showEffects;
  StudioViewPrefs copyWith({bool? cleanView, bool? showEffects}) =>
      StudioViewPrefs(cleanView: cleanView ?? this.cleanView, showEffects: showEffects ?? this.showEffects);
}

class StudioViewPrefsController extends Notifier<StudioViewPrefs> {
  @override
  StudioViewPrefs build() => const StudioViewPrefs();
  void set(StudioViewPrefs p) => state = p;
}

final studioViewPrefsProvider =
    NotifierProvider<StudioViewPrefsController, StudioViewPrefs>(StudioViewPrefsController.new);

// ─── Gifts (server: functions/src/liveStudio/gifts.ts) ───────────────────────

/// Mirror of GIFT_CATALOG (prices are enforced server-side).
enum StudioGift {
  rose('rose', 'Rose', 1),
  heart('heart', 'Heart', 5),
  star('star', 'Star', 10),
  crown('crown', 'Crown', 50),
  rocket('rocket', 'Rocket', 100),
  diamond('diamond', 'Diamond', 500);

  const StudioGift(this.wire, this.label, this.coins);
  final String wire;
  final String label;
  final int coins;

  static StudioGift? fromWire(Object? v) {
    for (final g in values) {
      if (g.wire == v) return g;
    }
    return null;
  }
}

@immutable
class StudioRecentGift {
  const StudioRecentGift({
    required this.id,
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.gift,
    required this.qty,
    required this.atMs,
  });
  final String id;
  final String uid;
  final String name;
  final String avatarUrl;
  final StudioGift gift;
  final int qty;
  final int atMs;
}

/// Recent gifts, newest first (`studio/gifts.recent`).
final studioGiftFeedProvider = StreamProvider.autoDispose.family<List<StudioRecentGift>, String>((ref, streamId) {
  final db = ref.watch(studioFirestoreProvider);
  return db.doc('${StudioPaths.streams}/$streamId/studio/gifts').snapshots().map((d) {
    final out = <StudioRecentGift>[];
    for (final r in (d.data()?['recent'] as List? ?? const [])) {
      if (r is! Map) continue;
      final g = StudioGift.fromWire(r['giftId']);
      if (g == null) continue;
      out.add(StudioRecentGift(
        id: _str(r['id']),
        uid: _str(r['uid']),
        name: _str(r['name']),
        avatarUrl: _str(r['avatarUrl']),
        gift: g,
        qty: _int(r['qty']),
        atMs: _int(r['atMs']),
      ));
    }
    return out;
  });
});

/// Top gifters of a live: (name, avatarUrl, coins), most coins first.
final studioTopGiftersProvider =
    StreamProvider.autoDispose.family<List<({String name, String avatarUrl, int coins})>, String>((ref, streamId) {
  final db = ref.watch(studioFirestoreProvider);
  return db
      .collection('${StudioPaths.streams}/$streamId/studio_gift_totals')
      .orderBy('coins', descending: true)
      .limit(5)
      .snapshots()
      .map((q) => [
            for (final d in q.docs)
              (name: _str(d.data()['name']), avatarUrl: _str(d.data()['avatarUrl']), coins: _int(d.data()['coins'])),
          ]);
});

/// My coin balance (`wallets/{uid}.balanceCoins`, server-written).
final studioMyCoinsProvider = StreamProvider.autoDispose<int>((ref) {
  final uid = ref.watch(studioMyUidProvider);
  if (uid == null) return Stream.value(0);
  return ref.watch(studioFirestoreProvider).doc('wallets/$uid').snapshots().map((d) => _int(d.data()?['balanceCoins']));
});

class StudioGiftApi {
  const StudioGiftApi(this._call);
  final StudioCallPort _call;

  /// Returns the new balance.
  Future<int> send(String streamId, StudioGift gift, {int qty = 1}) async {
    final r = await _call.call('lsGift', {'streamId': streamId, 'giftId': gift.wire, 'qty': qty});
    return _int(r['balanceCoins']);
  }
}

final studioGiftApiProvider = Provider<StudioGiftApi>((ref) => StudioGiftApi(ref.watch(studioCallPortProvider)));
