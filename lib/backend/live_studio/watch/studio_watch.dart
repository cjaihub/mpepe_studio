// LIVE STUDIO v2 — "Watch together" layer: model, stream and calls.
//
// The host (or a co-host) puts a YouTube video or a web page on a shared
// layer above the stage; their camera keeps streaming. Nothing is
// re-streamed: every viewer plays the layer locally (YouTube through the
// official IFrame player) and follows `live_streams/{id}/studio/watch`,
// written only by `lsWatch` (server: functions/src/liveStudio/watch.ts).
//
//   target = positionMs + (serverNow − anchorServerMs) × rate   (playing)

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../session/studio_session_controller.dart' show studioFirestoreProvider;

enum WatchKind { youtube, browser }

@immutable
class WatchLayer {
  const WatchLayer({
    required this.kind,
    this.videoId = '',
    this.title = '',
    this.channel = '',
    this.thumbUrl = '',
    this.url = '',
    this.state = PlaybackState.paused,
    this.positionMs = 0,
    this.rate = 1,
    this.anchorServerMs = 0,
    this.by = '',
    this.rev = 0,
  });

  final WatchKind kind;
  final String videoId;
  final String title;
  final String channel;
  final String thumbUrl;

  /// Browser page.
  final String url;
  final PlaybackState state;
  final int positionMs;
  final double rate;
  final int anchorServerMs;
  final String by;
  final int rev;

  bool get isYouTube => kind == WatchKind.youtube;

  /// The same rule [WatchPartySync] runs (catalogId = the video id).
  WatchParty get party => WatchParty(
        catalogId: videoId,
        state: state,
        positionMs: positionMs,
        rate: rate,
        anchorServerMs: anchorServerMs,
      );

  int targetPositionMs(int serverNowMs) => party.targetPositionMs(serverNowMs);

  /// Null when nothing is on the layer.
  static WatchLayer? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    num n(Object? v, num d) => v is num ? v : d;
    String s(Object? v) => v is String ? v : '';
    final yt = j['youtube'] is Map ? Map<String, dynamic>.from(j['youtube'] as Map) : null;
    final br = j['browser'] is Map ? Map<String, dynamic>.from(j['browser'] as Map) : null;
    final common = (
      state: PlaybackState.fromWire(j['state']),
      positionMs: n(j['positionMs'], 0).toInt(),
      rate: n(j['rate'], 1).toDouble(),
      anchor: n(j['anchorServerMs'], 0).toInt(),
      by: s(j['by']),
      rev: n(j['rev'], 0).toInt(),
    );
    if (j['kind'] == 'youtube' && yt != null && s(yt['videoId']).length == 11) {
      return WatchLayer(
        kind: WatchKind.youtube,
        videoId: s(yt['videoId']),
        title: s(yt['title']),
        channel: s(yt['channel']),
        thumbUrl: s(yt['thumbUrl']),
        state: common.state,
        positionMs: common.positionMs,
        rate: common.rate,
        anchorServerMs: common.anchor,
        by: common.by,
        rev: common.rev,
      );
    }
    if (j['kind'] == 'browser' && br != null && s(br['url']).startsWith('https://')) {
      return WatchLayer(kind: WatchKind.browser, url: s(br['url']), by: common.by, rev: common.rev);
    }
    return null;
  }
}

/// The shared layer of [streamId] (null = nothing on it).
final studioWatchProvider = StreamProvider.autoDispose.family<WatchLayer?, String>((ref, streamId) => ref
    .watch(studioFirestoreProvider)
    .doc('${StudioPaths.streams}/$streamId/studio/watch')
    .snapshots()
    .map((d) => WatchLayer.fromJson(d.data())));

@immutable
class YouTubeResult {
  const YouTubeResult({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.thumbUrl,
    this.live = false,
  });
  final String videoId;
  final String title;
  final String channel;
  final String thumbUrl;
  final bool live;

  factory YouTubeResult.fromJson(Map<String, dynamic> j) => YouTubeResult(
        videoId: j['videoId'] as String? ?? '',
        title: j['title'] as String? ?? '',
        channel: j['channel'] as String? ?? '',
        thumbUrl: j['thumbUrl'] as String? ?? '',
        live: j['live'] == true,
      );
}

@immutable
class YouTubeSearchPage {
  const YouTubeSearchPage({required this.enabled, this.items = const [], this.nextPageToken});

  /// False until YOUTUBE_API_KEY exists in Secret Manager.
  final bool enabled;
  final List<YouTubeResult> items;
  final String? nextPageToken;
}

/// 11-char video id from a YouTube link (watch, youtu.be, shorts, live,
/// embed) or a bare id; null when [input] is not one.
String? youTubeIdFrom(String input) {
  final s = input.trim();
  final id = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (id.hasMatch(s)) return s;
  final uri = Uri.tryParse(s.startsWith('http') ? s : 'https://$s');
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst('www.', '').replaceFirst('m.', '');
  String? cand;
  if (host == 'youtu.be') {
    cand = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (host == 'youtube.com' || host == 'music.youtube.com') {
    cand = uri.queryParameters['v'];
    final seg = uri.pathSegments;
    if (cand == null && seg.length >= 2 && const {'shorts', 'live', 'embed', 'v'}.contains(seg.first)) cand = seg[1];
  }
  return cand != null && id.hasMatch(cand) ? cand : null;
}

class StudioWatchApi {
  StudioWatchApi(this._call);
  final StudioCallPort _call;

  Future<void> _op(String streamId, String op, [Map<String, dynamic> args = const {}]) =>
      _call.call('lsWatch', {'streamId': streamId, 'op': op, ...args});

  Future<void> playYouTube(String streamId, YouTubeResult v) => _op(streamId, 'youtube', {
        'videoId': v.videoId,
        if (v.title.isNotEmpty) 'title': v.title,
        if (v.channel.isNotEmpty) 'channel': v.channel,
        if (v.thumbUrl.isNotEmpty) 'thumbUrl': v.thumbUrl,
      });
  Future<void> openPage(String streamId, String url) => _op(streamId, 'browser', {'url': url});
  Future<void> play(String streamId, int positionMs) => _op(streamId, 'play', {'positionMs': positionMs});
  Future<void> pause(String streamId, int positionMs) => _op(streamId, 'pause', {'positionMs': positionMs});
  Future<void> seek(String streamId, int positionMs) => _op(streamId, 'seek', {'positionMs': positionMs});
  Future<void> setRate(String streamId, double rate) => _op(streamId, 'rate', {'rate': rate});
  Future<void> ended(String streamId) => _op(streamId, 'ended');
  Future<void> stop(String streamId) => _op(streamId, 'stop');

  Future<YouTubeSearchPage> search(String streamId, String q, {String? pageToken}) async {
    final r = await _call.call('lsYouTubeSearch', {'streamId': streamId, 'q': q, 'pageToken': ?pageToken});
    final items = [
      for (final i in (r['items'] as List? ?? const []))
        if (i is Map) YouTubeResult.fromJson(Map<String, dynamic>.from(i)),
    ];
    return YouTubeSearchPage(
      enabled: r['enabled'] == true,
      items: items.where((i) => i.videoId.length == 11).toList(),
      nextPageToken: r['nextPageToken'] as String?,
    );
  }
}

final studioWatchApiProvider = Provider<StudioWatchApi>((ref) => StudioWatchApi(ref.watch(studioCallPortProvider)));

/// Viewer-only "minimize": the layer keeps playing in a small pill.
final studioWatchMinimizedProvider = NotifierProvider.autoDispose.family<_Flag, bool, String>(_Flag.new);

class _Flag extends Notifier<bool> {
  _Flag(this.streamId);
  final String streamId;
  @override
  bool build() => false;
  void set(bool v) => state = v;
}
