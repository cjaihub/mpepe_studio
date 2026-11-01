// LIVE STUDIO v2 — "Watch together" layer above the stage.
//
// - YouTube: the official IFrame player in a WebView, one per device. The
//   person who acted last (`layer.by`) drives: their player's play / pause /
//   seek / speed go to lsWatch. Everyone else runs [WatchPartySync] against
//   the server clock (drift > 1.2 s → seek), so all phones play the same
//   second without the video ever entering the LiveKit stream.
// - Browser: the host browses (search or address bar); each page they open
//   is checked by lsWatch and every viewer's WebView loads the same page.
//
// The host's camera keeps streaming on the stage behind this layer.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../../../../backend/live_studio/table/watch_party_sync.dart';
import '../../../../backend/live_studio/watch/studio_watch.dart';
import '../theme/live_studio_tokens.dart';
import 'watch_picker_sheet.dart';

/// Drift a viewer tolerates before seeking (YouTube positions arrive ~2×/s).
const int kWatchMaxDriftMs = 1200;

/// Positions and draws the shared layer; renders nothing when it is empty.
/// Place it in a full-screen Stack (inside SafeArea): taps outside the card
/// fall through to the studio.
class StudioWatchLayer extends ConsumerWidget {
  const StudioWatchLayer({
    super.key,
    required this.streamId,
    required this.tokens,
    required this.phone,
    required this.canControl,
  });

  final String streamId;
  final LiveStudioTokens tokens;
  final bool phone;

  /// Host / co-host: picks content and controls playback.
  final bool canControl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layer = ref.watch(studioWatchProvider(streamId)).value;
    if (layer == null) return const SizedBox.shrink();
    final minimized = ref.watch(studioWatchMinimizedProvider(streamId));
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final Rect r;
      if (phone) {
        final width = w - 16;
        final height = layer.isYouTube ? width * 9 / 16 + 44 : h * 0.52;
        r = Rect.fromLTWH(8, 58, width, height);
      } else {
        final width = (w * 0.5).clamp(320.0, 760.0);
        final height = layer.isYouTube ? width * 9 / 16 + 44 : h - 84 - 112;
        r = Rect.fromLTWH(24, 84, width, height.clamp(180.0, h - 120));
      }
      return Stack(children: [
        // Kept mounted while minimized so playback and sync never stop.
        Positioned(
          left: r.left,
          top: r.top,
          width: r.width,
          height: r.height,
          child: Offstage(
            offstage: minimized,
            child: _WatchCard(
              key: ValueKey('watch-${layer.kind.name}'),
              streamId: streamId,
              tokens: tokens,
              layer: layer,
              canControl: canControl,
            ),
          ),
        ),
        if (minimized)
          Positioned(
            left: r.left,
            top: r.top,
            child: _MinimizedPill(
              tokens: tokens,
              layer: layer,
              onTap: () => ref.read(studioWatchMinimizedProvider(streamId).notifier).set(false),
            ),
          ),
      ]);
    });
  }
}

class _MinimizedPill extends StatelessWidget {
  const _MinimizedPill({required this.tokens, required this.layer, required this.onTap});
  final LiveStudioTokens tokens;
  final WatchLayer layer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Show what everyone is watching',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            decoration: BoxDecoration(
              color: LiveStudioWorld.popHeader,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: LiveStudioWorld.nameplateBorder, width: 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(layer.isYouTube ? Icons.smart_display_rounded : Icons.public_rounded,
                  size: 16, color: LiveStudioAccent.pink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  layer.isYouTube ? (layer.title.isEmpty ? 'Watching together' : layer.title) : _hostLabel(layer.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LiveStudioType.s(12, FontWeight.w600, LiveStudioWorld.textHigh),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.open_in_full_rounded, size: 14, color: LiveStudioWorld.popIcon),
            ]),
          ),
        ),
      );
}

String _hostLabel(String url) => Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;

class _WatchCard extends ConsumerStatefulWidget {
  const _WatchCard({
    super.key,
    required this.streamId,
    required this.tokens,
    required this.layer,
    required this.canControl,
  });
  final String streamId;
  final LiveStudioTokens tokens;
  final WatchLayer layer;
  final bool canControl;

  @override
  ConsumerState<_WatchCard> createState() => _WatchCardState();
}

class _WatchCardState extends ConsumerState<_WatchCard> {
  final _yt = GlobalKey<_YouTubeViewState>();
  bool _muted = false;

  StudioWatchApi get _api => ref.read(studioWatchApiProvider);

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (!mounted) return;
      final msg = e is Exception ? e.toString().replaceFirst(RegExp(r'^.*?\] '), '') : 'Could not update';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.layer;
    final playing = l.state == PlaybackState.playing;
    Widget btn(IconData icon, String label, VoidCallback onTap, {Color color = LiveStudioWorld.popIcon}) => Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: onTap,
            radius: 20,
            child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 20, color: color)),
          ),
        );
    final header = Container(
      height: 44,
      padding: const EdgeInsets.only(left: 10, right: 2),
      color: LiveStudioWorld.popHeader,
      child: Row(children: [
        Icon(l.isYouTube ? Icons.smart_display_rounded : Icons.public_rounded, size: 18, color: LiveStudioAccent.pink),
        const SizedBox(width: 8),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              l.isYouTube ? (l.title.isEmpty ? 'YouTube' : l.title) : _hostLabel(l.url),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LiveStudioType.s(12.5, FontWeight.w700, LiveStudioWorld.textHigh),
            ),
            Text(
              l.isYouTube ? (l.channel.isEmpty ? 'Watching together' : '${l.channel} · watching together') : 'Browsing together',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LiveStudioType.s(10.5, FontWeight.w500, LiveStudioWorld.textMedium),
            ),
          ]),
        ),
        if (l.isYouTube && widget.canControl) ...[
          btn(Icons.replay_10_rounded, 'Back 10 seconds', () => _yt.currentState?.nudge(-10000)),
          btn(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, playing ? 'Pause for everyone' : 'Play for everyone',
              () => _yt.currentState?.togglePlay()),
          btn(Icons.forward_10_rounded, 'Forward 10 seconds', () => _yt.currentState?.nudge(10000)),
        ],
        if (l.isYouTube && !widget.canControl)
          btn(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, _muted ? 'Unmute' : 'Mute', () {
            setState(() => _muted = !_muted);
            _yt.currentState?.setMuted(_muted);
          }),
        if (widget.canControl)
          btn(Icons.swap_horiz_rounded, 'Change what we watch',
              () => showWatchTogetherSheet(context, streamId: widget.streamId, tokens: widget.tokens,
                  initial: l.isYouTube ? WatchKind.youtube : WatchKind.browser)),
        btn(Icons.close_fullscreen_rounded, 'Minimize',
            () => ref.read(studioWatchMinimizedProvider(widget.streamId).notifier).set(true)),
        if (widget.canControl)
          btn(Icons.close_rounded, 'Stop for everyone', () {
            HapticFeedback.lightImpact();
            _run(() => _api.stop(widget.streamId));
          }, color: LiveStudioAccent.pinkLight),
      ]),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LiveStudioWorld.screen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LiveStudioWorld.nameplateBorder, width: 1),
        boxShadow: [BoxShadow(color: LiveStudioTokens.dimTint(0.4), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: [
          header,
          Expanded(
            child: l.isYouTube
                ? _YouTubeView(key: _yt, streamId: widget.streamId, layer: l, canControl: widget.canControl, onError: _run)
                : _BrowserView(streamId: widget.streamId, layer: l, canControl: widget.canControl, tokens: widget.tokens, run: _run),
          ),
        ]),
      ),
    );
  }
}

// ─── YouTube ─────────────────────────────────────────────────────────────────

/// The page every device loads: the official IFrame Player API. Messages go
/// to Dart through the `OvaYT` channel; Dart drives it with the ova* calls.
String _playerHtml({required String videoId, required int startS, required bool controls}) => '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;top:0;left:0;width:100%;height:100%}</style>
</head><body><div id="p"></div><script>
var player,ready=false;
function post(o){try{OvaYT.postMessage(JSON.stringify(o));}catch(e){}}
var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';document.head.appendChild(tag);
function onYouTubeIframeAPIReady(){
 player=new YT.Player('p',{videoId:'$videoId',playerVars:{autoplay:1,start:$startS,controls:${controls ? 1 : 0},disablekb:${controls ? 0 : 1},playsinline:1,rel:0,fs:0,iv_load_policy:3,origin:'https://oneova.web.app'},
  events:{
   onReady:function(){ready=true;post({e:'ready',d:player.getDuration()*1000});player.playVideo();
     setTimeout(function(){var s=player.getPlayerState();if(s!=1&&s!=3&&s!=2){player.mute();player.playVideo();post({e:'muted'});}},2000);},
   onStateChange:function(ev){post({e:'state',s:ev.data,t:player.getCurrentTime()*1000});},
   onPlaybackRateChange:function(ev){post({e:'rate',r:ev.data});},
   onError:function(ev){post({e:'error',c:ev.data});}}});
 setInterval(function(){if(ready){post({e:'tick',t:player.getCurrentTime()*1000,s:player.getPlayerState(),r:player.getPlaybackRate(),d:player.getDuration()*1000,m:player.isMuted()});}},500);
}
function ovaLoad(id,s){if(ready)player.loadVideoById({videoId:id,startSeconds:s});}
function ovaPlay(){if(ready)player.playVideo();}
function ovaPause(){if(ready)player.pauseVideo();}
function ovaSeek(ms){if(ready)player.seekTo(ms/1000,true);}
function ovaRate(r){if(ready)player.setPlaybackRate(r);}
function ovaMute(m){if(ready){if(m){player.mute();}else{player.unMute();player.setVolume(100);}}}
</script></body></html>''';

/// [WatchPlayer] over the IFrame player. Positions are extrapolated between
/// the page's 500 ms ticks.
class _YtPlayer implements WatchPlayer {
  _YtPlayer(this._c);
  final WebViewController _c;

  bool ready = false;
  int _t = 0;
  int _at = 0;
  int state = -1;
  double _rate = 1;
  int? _duration;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  void report({required int t, int? s, double? rate, int? duration}) {
    _t = t;
    _at = _now();
    if (s != null) state = s;
    if (rate != null) _rate = rate;
    if (duration != null && duration > 0) _duration = duration;
  }

  @override
  int get positionMs => isPlaying ? _t + ((_now() - _at) * _rate).round() : _t;

  /// Playing or buffering (do not call play() again while buffering).
  @override
  bool get isPlaying => state == 1 || state == 3;

  @override
  double get rate => _rate;

  @override
  int? get durationMs => _duration;

  Future<void> _js(String code) async {
    if (!ready) return;
    try {
      await _c.runJavaScript(code);
    } catch (e) {
      debugPrint('[watch] js: $e');
    }
  }

  @override
  Future<void> play() async {
    state = 3;
    await _js('ovaPlay()');
  }

  @override
  Future<void> pause() async {
    report(t: positionMs, s: 2);
    await _js('ovaPause()');
  }

  @override
  Future<void> seekTo(int positionMs) async {
    report(t: positionMs);
    await _js('ovaSeek($positionMs)');
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    await _js('ovaRate($rate)');
  }

  Future<void> load(String videoId, int startMs) async {
    report(t: startMs, s: 3);
    await _js("ovaLoad('$videoId', ${startMs ~/ 1000})");
  }

  Future<void> mute(bool m) => _js('ovaMute($m)');
}

class _YouTubeView extends ConsumerStatefulWidget {
  const _YouTubeView({
    super.key,
    required this.streamId,
    required this.layer,
    required this.canControl,
    required this.onError,
  });
  final String streamId;
  final WatchLayer layer;
  final bool canControl;
  final Future<void> Function(Future<void> Function()) onError;

  @override
  ConsumerState<_YouTubeView> createState() => _YouTubeViewState();
}

class _YouTubeViewState extends ConsumerState<_YouTubeView> {
  late final WebViewController _c;
  late final _YtPlayer _player;
  late final StudioClockPort _clock;
  WatchPartySync? _sync;
  String _videoId = '';
  bool _autoMuted = false;
  String? _error;

  /// After this client sends an op, ignore its own player's echo for a bit.
  int _quietUntil = 0;

  String? get _me => ref.read(studioMyUidProvider);

  /// The person who acted last drives the room; everyone else follows.
  bool get _driving => widget.canControl && widget.layer.by == _me;

  StudioWatchApi get _api => ref.read(studioWatchApiProvider);

  @override
  void initState() {
    super.initState();
    _clock = ref.read(studioClockProvider);
    final params = const PlatformWebViewControllerCreationParams();
    _c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(LiveStudioWorld.screen)
      ..addJavaScriptChannel('OvaYT', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // Keep the viewer inside the player: links (title, logo) open nothing.
        onNavigationRequest: (r) => !r.isMainFrame ||
                r.url.startsWith('https://oneova.web.app') ||
                r.url.startsWith('https://www.youtube.com/embed') ||
                r.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ));
    final platform = _c.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    }
    _player = _YtPlayer(_c);
    _load(widget.layer);
    _syncRole();
  }

  void _load(WatchLayer l) {
    _videoId = l.videoId;
    _error = null;
    final start = l.targetPositionMs(_clock.serverNowMs());
    _player.ready = false;
    _player.report(t: start, s: -1);
    unawaited(_c.loadHtmlString(
      _playerHtml(videoId: l.videoId, startS: start ~/ 1000, controls: widget.canControl),
      baseUrl: 'https://oneova.web.app/',
    ));
  }

  /// Followers run the sync loop; the driver's own player is the truth.
  void _syncRole() {
    if (_driving) {
      _sync?.dispose();
      _sync = null;
      return;
    }
    _sync ??= WatchPartySync(player: _player, clock: _clock, maxDriftMs: kWatchMaxDriftMs)..start();
    unawaited(_sync!.update(widget.layer.party));
  }

  @override
  void didUpdateWidget(_YouTubeView old) {
    super.didUpdateWidget(old);
    final l = widget.layer;
    if (l.videoId != _videoId) {
      if (_player.ready) {
        _videoId = l.videoId;
        _error = null;
        unawaited(_player.load(l.videoId, l.targetPositionMs(_clock.serverNowMs())));
      } else {
        _load(l);
      }
    }
    _syncRole();
  }

  @override
  void dispose() {
    _sync?.dispose();
    // Stop audio at once (the WebView may be torn down a frame later).
    unawaited(_c.runJavaScript('try{player.stopVideo()}catch(e){}').catchError((_) {}));
    unawaited(_c.loadHtmlString('<html></html>').catchError((_) {}));
    super.dispose();
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return;
    }
    int? ms(Object? v) => v is num ? v.round() : null;
    switch (m['e']) {
      case 'ready':
        _player
          ..ready = true
          ..report(t: _player.positionMs, duration: ms(m['d']));
        if (_sync != null) unawaited(_sync!.sync());
      case 'muted':
        if (mounted) setState(() => _autoMuted = true);
      case 'tick':
        _player.report(t: ms(m['t']) ?? 0, s: ms(m['s']), rate: (m['r'] as num?)?.toDouble(), duration: ms(m['d']));
        _driverCheckDrift();
      case 'state':
        final s = ms(m['s']) ?? -1;
        _player.report(t: ms(m['t']) ?? _player.positionMs, s: s);
        _driverStateChanged(s);
      case 'rate':
        final r = (m['r'] as num?)?.toDouble();
        if (r != null && _driving && (r - widget.layer.rate).abs() > 0.001 && _quiet()) {
          _send(() => _api.setRate(widget.streamId, r));
        }
      case 'error':
        final c = ms(m['c']);
        if (mounted) {
          setState(() => _error = c == 101 || c == 150
              ? 'The owner of this video does not allow it to play outside YouTube.'
              : 'This video cannot be played right now.');
        }
    }
  }

  bool _quiet() => DateTime.now().millisecondsSinceEpoch >= _quietUntil;

  void _send(Future<void> Function() op) {
    _quietUntil = DateTime.now().millisecondsSinceEpoch + 2500;
    unawaited(widget.onError(op));
  }

  /// The driver used the YouTube controls: tell the room.
  void _driverStateChanged(int s) {
    if (!_driving || !_quiet()) return;
    final l = widget.layer;
    final t = _player.positionMs;
    if (s == 1 && l.state != PlaybackState.playing) {
      _send(() => _api.play(widget.streamId, t));
    } else if (s == 2 && l.state == PlaybackState.playing) {
      _send(() => _api.pause(widget.streamId, t));
    } else if (s == 0 && l.state != PlaybackState.ended) {
      _send(() => _api.ended(widget.streamId));
    }
  }

  /// The driver scrubbed (or buffered far behind): re-anchor the room on
  /// the driver's real position.
  void _driverCheckDrift() {
    if (!_driving || !_quiet() || _player.state != 1) return;
    final l = widget.layer;
    if (l.state != PlaybackState.playing) return;
    final drift = _player.positionMs - l.targetPositionMs(_clock.serverNowMs());
    if (drift.abs() > 3000) _send(() => _api.seek(widget.streamId, _player.positionMs));
  }

  /// Header buttons (host / co-host): act locally at once, then tell the room.
  void togglePlay() {
    HapticFeedback.selectionClick();
    final t = _player.positionMs;
    if (widget.layer.state == PlaybackState.playing) {
      unawaited(_player.pause());
      _send(() => _api.pause(widget.streamId, t));
    } else {
      unawaited(_player.play());
      _send(() => _api.play(widget.streamId, t));
    }
  }

  void nudge(int deltaMs) {
    HapticFeedback.selectionClick();
    var t = _player.positionMs + deltaMs;
    final d = _player.durationMs;
    if (t < 0) t = 0;
    if (d != null && d > 0 && t > d) t = d;
    unawaited(_player.seekTo(t));
    _send(() => _api.seek(widget.streamId, t));
  }

  void setMuted(bool m) {
    if (!m) _autoMuted = false;
    unawaited(_player.mute(m));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      WebViewWidget(controller: _c),
      if (_error != null)
        ColoredBox(
          color: LiveStudioWorld.screen,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.block_rounded, size: 26, color: LiveStudioWorld.textMedium),
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: LiveStudioType.s(12.5, FontWeight.w500, LiveStudioWorld.textHigh)),
              ]),
            ),
          ),
        ),
      if (_autoMuted)
        Positioned(
          right: 8,
          bottom: 8,
          child: Semantics(
            button: true,
            label: 'Turn on sound',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => setMuted(false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: LiveStudioAccent.pink, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.volume_up_rounded, size: 16, color: LiveStudioAccent.white),
                  const SizedBox(width: 4),
                  Text('Tap for sound', style: LiveStudioType.s(11.5, FontWeight.w700, LiveStudioAccent.white)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ─── Browser ─────────────────────────────────────────────────────────────────

/// Address-bar text → https URL (a search when it is not an address).
String watchUrlFromInput(String input) {
  final s = input.trim();
  if (s.isEmpty) return '';
  final looksLikeUrl = !s.contains(' ') && s.contains('.') && !s.endsWith('.');
  if (looksLikeUrl) {
    if (s.startsWith('https://')) return s;
    if (s.startsWith('http://')) return 'https://${s.substring(7)}';
    return 'https://$s';
  }
  return Uri.https('www.google.com', '/search', {'q': s}).toString();
}

class _BrowserView extends ConsumerStatefulWidget {
  const _BrowserView({
    required this.streamId,
    required this.layer,
    required this.canControl,
    required this.tokens,
    required this.run,
  });
  final String streamId;
  final WatchLayer layer;
  final bool canControl;
  final LiveStudioTokens tokens;
  final Future<void> Function(Future<void> Function()) run;

  @override
  ConsumerState<_BrowserView> createState() => _BrowserViewState();
}

class _BrowserViewState extends ConsumerState<_BrowserView> {
  late final WebViewController _c;
  final _address = TextEditingController();
  final _focus = FocusNode();
  String _loaded = '';
  String _sent = '';
  Timer? _debounce;
  double _progress = 1;

  bool get _host => widget.canControl;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(LiveStudioWorld.textHigh)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p / 100);
        },
        onUrlChange: (c) => _onUrl(c.url),
        onNavigationRequest: (r) =>
            r.url.startsWith('https://') || r.url.startsWith('about:') ? NavigationDecision.navigate : NavigationDecision.prevent,
      ));
    _open(widget.layer.url);
  }

  void _open(String url) {
    if (url.isEmpty || url == _loaded) return;
    _loaded = url;
    _sent = url;
    if (!_focus.hasFocus) _address.text = url;
    unawaited(_c.loadRequest(Uri.parse(url)));
  }

  /// Host navigated (link, back, search): share the page after it settles.
  void _onUrl(String? url) {
    if (url == null || !url.startsWith('https://')) return;
    _loaded = url;
    if (!_focus.hasFocus) _address.text = url;
    if (!_host || url == _sent || url == widget.layer.url) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _sent = url;
      unawaited(widget.run(() => ref.read(studioWatchApiProvider).openPage(widget.streamId, url)));
    });
  }

  @override
  void didUpdateWidget(_BrowserView old) {
    super.didUpdateWidget(old);
    // Followers load what the host opened; the host already has it.
    if (widget.layer.url != old.layer.url && widget.layer.url != _loaded) _open(widget.layer.url);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _address.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final url = watchUrlFromInput(v);
    if (url.isEmpty) return;
    _focus.unfocus();
    _loaded = url;
    _sent = url;
    unawaited(_c.loadRequest(Uri.parse(url)));
    unawaited(widget.run(() => ref.read(studioWatchApiProvider).openPage(widget.streamId, url)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (_host)
        Container(
          height: 42,
          color: LiveStudioWorld.surface2,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_rounded, size: 18, color: LiveStudioWorld.popIcon),
              onPressed: () async {
                if (await _c.canGoBack()) await _c.goBack();
              },
            ),
            Expanded(
              child: TextField(
                controller: _address,
                focusNode: _focus,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: _submit,
                onTap: () => _address.selection = TextSelection(baseOffset: 0, extentOffset: _address.text.length),
                style: LiveStudioType.s(12.5, FontWeight.w500, LiveStudioWorld.textHigh),
                cursorColor: LiveStudioAccent.pink,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: LiveStudioWorld.surface3,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: LiveStudioWorld.textMedium),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  hintText: 'Search or type a web address',
                  hintStyle: LiveStudioType.s(12.5, FontWeight.w400, LiveStudioWorld.textMedium),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Reload',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded, size: 18, color: LiveStudioWorld.popIcon),
              onPressed: () => _c.reload(),
            ),
          ]),
        ),
      if (_progress < 1)
        LinearProgressIndicator(
          value: _progress,
          minHeight: 2,
          color: LiveStudioAccent.pink,
          backgroundColor: LiveStudioAccent.clear,
        ),
      Expanded(child: WebViewWidget(controller: _c)),
    ]);
  }
}
