import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../backend/remote_connect_service.dart';
import '../../backend/webrtc_desktop_service.dart';
import '../../shared/theme/app_theme.dart';
import 'computer_action_log.dart';
import 'computer_logs_screen.dart';
import 'controller_link.dart';
import 'ova_computer_live.dart';
import 'widgets/connector_header.dart';
import 'widgets/controller_trackpad.dart';
import 'widgets/live_screen_view.dart';
import 'widgets/ova_live_deck.dart';
import 'widgets/tactile.dart';
import 'widgets/unlock_flow.dart';
import 'widgets/volume_dial.dart';

enum _Deck { trackpad, media, ova }

/// Phone-as-controller for a linked computer: the computer's live screen on
/// top (touch it to drive the mouse), and below it the trackpad, the media
/// deck and Ova Live (voice + vision co-pilot). Wake / unlock are in the app
/// bar, the activity log slides in from the right.
class PhoneControllerScreen extends ConsumerStatefulWidget {
  const PhoneControllerScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<PhoneControllerScreen> createState() =>
      _PhoneControllerScreenState();
}

class _PhoneControllerScreenState extends ConsumerState<PhoneControllerScreen> {
  late final WebRTCDesktopService _service = ref.read(
    webrtcDesktopProvider.notifier,
  );
  late final ComputerActionLog _log = ref.read(computerActionLogProvider.notifier);
  late final ControllerLink _link = ControllerLink.forService(
    _service,
    widget.deviceId,
    recorder: (source, action, params, {secret = false}) =>
        _log.record(source, action, params: params, secret: secret),
  );
  late final OvaComputerLive _ova = ref.read(ovaComputerLiveProvider.notifier);
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<({String deviceToken, Map<String, dynamic> packet})>?
  _incomingSub;
  Timer? _pingTimer;
  Timer? _volumeTrail;
  DateTime _lastVolumeSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ownsConnection = false;
  bool _wasLinked = false;

  _Deck _deck = _Deck.trackpad;
  int _speedIndex = 1;
  bool _dragLock = false;
  bool _screenOn = true;

  int? _rttMs;
  int _volume = 50;
  bool _muted = false;
  bool _volumeKnown = false;
  String? _frontApp;
  bool _locked = false;

  static const _speeds = <(String, double)>[
    ('Precise', 0.7),
    ('Balanced', 1.0),
    ('Swift', 1.5),
  ];

  String get _wantedMode => _screenOn ? 'remote' : 'controller';

  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable().catchError((_) {}));
    _log.beginSession(widget.deviceId);
    _incomingSub = _service.incoming
        .where((m) => m.deviceToken == widget.deviceId)
        .listen((m) => _onPacket(m.packet));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureConnected());
  }

  void _ensureConnected({bool force = false}) {
    final conn = ref.read(webrtcDesktopProvider).connections[widget.deviceId];
    final open = conn?.isDataChannelOpen == true;
    // A screen-less controller link must be renegotiated to carry video.
    final needsVideo = _screenOn && _service.modeOf(widget.deviceId) == 'controller';
    if (!force && open && !needsVideo) {
      _onLinked();
      return;
    }
    _ownsConnection = true;
    ref.read(remoteConnectProvider.notifier).setActiveComputer(widget.deviceId);
    unawaited(
      _service.connect(
        widget.deviceId,
        mode: _wantedMode,
        force: force || (open && needsVideo),
      ),
    );
  }

  void _onLinked() {
    _link.requestVolume();
    _link.requestStatus();
    _link.ping();
    _log.record(ActionSource.system, 'connect', params: {'mode': _wantedMode});
    _pingTimer?.cancel();
    var tick = 0;
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _link.ping();
      if (++tick % 3 == 0) _link.requestStatus();
    });
  }

  void _onPacket(Map<String, dynamic> packet) {
    if (!mounted) return;
    switch (packet['action']) {
      case 'pong':
        final sent = (packet['t'] as num?)?.toInt();
        if (sent == null) return;
        final rtt = DateTime.now().millisecondsSinceEpoch - sent;
        setState(() {
          // Smooth the readout so it doesn't jitter every ping.
          _rttMs = _rttMs == null ? rtt : ((_rttMs! * 0.6) + rtt * 0.4).round();
        });
        break;
      case 'volume_state':
        final level = (packet['level'] as num?)?.round();
        setState(() {
          if (level != null) _volume = level.clamp(0, 100);
          _muted = packet['muted'] == true;
          _volumeKnown = true;
        });
        break;
      case 'status':
        final app = packet['app'] as String?;
        _log.setFrontApp(app);
        setState(() {
          _frontApp = app;
          _locked = packet['locked'] == true;
        });
        break;
    }
  }

  void _sendVolume(int level, {bool force = false}) {
    _volume = level;
    _link.source = ActionSource.media;
    if (_muted && level > 0) setState(() => _muted = false);
    final now = DateTime.now();
    _volumeTrail?.cancel();
    if (force ||
        now.difference(_lastVolumeSent) > const Duration(milliseconds: 55)) {
      _lastVolumeSent = now;
      _link.setVolume(level, log: force);
    } else {
      _volumeTrail = Timer(const Duration(milliseconds: 60), () {
        _lastVolumeSent = DateTime.now();
        _link.setVolume(_volume, log: false);
      });
    }
  }

  bool _media(String key) {
    _link.source = ActionSource.media;
    return _link.media(key);
  }

  void _toggleScreen() {
    HapticFeedback.selectionClick();
    setState(() => _screenOn = !_screenOn);
    _ensureConnected(force: true);
  }

  Future<void> _wake() async {
    HapticFeedback.selectionClick();
    _link.source = ActionSource.system;
    _link.wake();
  }

  Future<void> _unlock(String computerName) async {
    final secret = await UnlockFlow.obtain(context, widget.deviceId, computerName);
    if (secret == null || !mounted) return;
    HapticFeedback.mediumImpact();
    _link.source = ActionSource.system;
    _link.unlock(secret);
  }

  MediaStreamTrack? _screenTrack() {
    final conn = ref.read(webrtcDesktopProvider).connections[widget.deviceId];
    final tracks = conn?.renderer?.srcObject?.getVideoTracks();
    return (tracks == null || tracks.isEmpty) ? null : tracks.first;
  }

  void _startOva() {
    if (!_screenOn) {
      setState(() => _screenOn = true);
      _ensureConnected(force: true);
    }
    _ova.start(link: _link, videoTrack: _screenTrack);
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _volumeTrail?.cancel();
    unawaited(_incomingSub?.cancel());
    unawaited(WakelockPlus.disable().catchError((_) {}));
    unawaited(_ova.stop());
    unawaited(_log.flush());
    if (_ownsConnection) {
      _service.disconnect(widget.deviceId);
    }
    super.dispose();
  }

  ControllerLinkState _linkState(WebRTCConnection? conn) {
    if (conn?.isDataChannelOpen == true) return ControllerLinkState.linked;
    if (conn?.status == WebRTCStatus.connecting) {
      return ControllerLinkState.connecting;
    }
    return ControllerLinkState.offline;
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(
      webrtcDesktopProvider.select((s) => s.connections[widget.deviceId]),
    );
    final computers = ref.watch(
      remoteConnectProvider.select((s) => s.linkedComputers),
    );
    LinkedComputer? computer;
    for (final c in computers) {
      if (c.id == widget.deviceId) computer = c;
    }
    final name = computer?.name ?? 'Computer';
    final linkState = _linkState(conn);
    final linked = linkState == ControllerLinkState.linked;
    final hasVideo = conn?.hasVideoStream == true;

    if (linked && !_wasLinked) {
      _wasLinked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onLinked();
      });
    } else if (!linked && _wasLinked) {
      _wasLinked = false;
      _pingTimer?.cancel();
      _rttMs = null;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.bg,
      endDrawer: Drawer(
        backgroundColor: context.surface,
        width: MediaQuery.sizeOf(context).width * 0.86,
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: Text(
                  'Activity',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.push('/computer_logs');
                  },
                  child: Text(
                    'Full log & docs',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                  ),
                ),
              ),
              const Expanded(child: ComputerLogPanel(compact: true)),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(
            Icons.arrow_back_rounded,
            color: context.textPrimary,
            size: 20,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/auth/linked_devices');
            }
          },
        ),
        titleSpacing: 0,
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _screenOn ? 'Hide live screen' : 'Show live screen',
            onPressed: _toggleScreen,
            icon: Icon(
              _screenOn ? Icons.tv_rounded : Icons.tv_off_rounded,
              size: 20,
              color: _screenOn ? AppColors.brandBlue : context.textSecondary,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Power',
            enabled: linked,
            icon: Icon(
              _locked ? Icons.lock_rounded : Icons.power_settings_new_rounded,
              size: 20,
              color: _locked ? AppColors.brandPink : context.textPrimary,
            ),
            color: context.surface,
            onSelected: (v) async {
              if (v == 'wake') await _wake();
              if (v == 'unlock') await _unlock(name);
              if (v == 'forget') await UnlockFlow.forget(widget.deviceId);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'wake', child: Text('Wake screen')),
              const PopupMenuItem(value: 'unlock', child: Text('Wake & unlock')),
              const PopupMenuItem(value: 'forget', child: Text('Forget saved password')),
            ],
          ),
          IconButton(
            tooltip: 'Activity log',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            icon: Icon(Icons.receipt_long_outlined, size: 20, color: context.textPrimary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
          child: Column(
            children: [
              if (_screenOn) ...[
                // Pre-sized 16:10 slot: the texture keeps its layout while
                // the stream warms up, so nothing jumps when frames arrive.
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: LiveScreenView(
                    renderer: conn?.renderer,
                    link: _link,
                    hasVideo: hasVideo,
                    enabled: linked,
                    status: _locked ? 'Locked' : _frontApp,
                  ),
                ),
                const SizedBox(height: 8),
                _StatusStrip(
                  linkState: linkState,
                  fastLane: linked && _service.isFastChannelOpen(widget.deviceId),
                  rttMs: _rttMs,
                  onRetry: () => _ensureConnected(force: true),
                ),
              ] else
                ConnectorHeader(
                  computerName: name,
                  linkState: linkState,
                  fastLane: linked && _service.isFastChannelOpen(widget.deviceId),
                  rttMs: _rttMs,
                  onRetry: () {
                    HapticFeedback.lightImpact();
                    _ensureConnected(force: true);
                  },
                ),
              if (linkState == ControllerLinkState.offline &&
                  computer?.isOnline == false)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Open Oneova Desktop on $name to connect.',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              _DeckSwitch(
                deck: _deck,
                onChanged: (d) {
                  HapticFeedback.selectionClick();
                  setState(() => _deck = d);
                  if (d == _Deck.media && linked) _link.requestVolume();
                },
              ),
              const SizedBox(height: 10),
              Expanded(
                // IndexedStack keeps every deck built and laid out, so
                // switching is instant and never janks a frame.
                child: IndexedStack(
                  index: _deck.index,
                  sizing: StackFit.expand,
                  children: [
                    _buildTrackpadDeck(context, linked),
                    _buildMediaDeck(context, linked),
                    OvaLiveDeck(
                      enabled: linked,
                      screenLive: _screenOn && hasVideo,
                      onStart: _startOva,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackpadDeck(BuildContext context, bool linked) {
    final speed = _speeds[_speedIndex];
    return Column(
      key: const ValueKey('trackpad'),
      children: [
        Row(
          children: [
            _OptionChip(
              icon: Icons.speed_rounded,
              label: speed.$1,
              active: true,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(
                  () => _speedIndex = (_speedIndex + 1) % _speeds.length,
                );
              },
            ),
            const SizedBox(width: 8),
            _OptionChip(
              icon: Icons.lock_rounded,
              label: 'Drag lock',
              active: _dragLock,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _dragLock = !_dragLock);
              },
            ),
            const Spacer(),
            Text(
              'Edge rail scrolls',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: context.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.swap_vert_rounded, size: 14, color: context.textMuted),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ControllerTrackpad(
            link: _link,
            enabled: linked,
            sensitivity: speed.$2,
            dragLock: _dragLock,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: _ClickKey(
                  label: 'Left',
                  enabled: linked,
                  // Press/release map to the real button so the thumb can
                  // hold it while another finger drags on the pad.
                  onDown: () {
                    _link.source = ActionSource.trackpad;
                    return _link.leftDown();
                  },
                  onUp: _link.leftUp,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _ClickKey(
                  label: 'Right',
                  enabled: linked,
                  onTap: () {
                    _link.source = ActionSource.trackpad;
                    return _link.rightClick();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaDeck(BuildContext context, bool linked) {
    return LayoutBuilder(
      key: const ValueKey('media'),
      builder: (context, constraints) {
        final dialSize = (constraints.maxHeight - 150).clamp(180.0, 260.0);
        return Container(
          width: double.infinity,
          decoration: Tactile.tile(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              VolumeDial(
                size: dialSize,
                value: _volume,
                muted: _muted,
                enabled: linked,
                onChanged: (v) => _sendVolume(v),
                onChangeEnd: (v) => _sendVolume(v, force: true),
              ),
              const SizedBox(height: 4),
              Text(
                !linked
                    ? 'Connect to control volume'
                    : _volumeKnown
                    ? 'Turn the dial'
                    : 'Reading volume…',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: context.textMuted,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundKey(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Previous',
                    enabled: linked,
                    onTap: () => _media('prev'),
                  ),
                  const SizedBox(width: 18),
                  _RoundKey(
                    icon: Icons.play_arrow_rounded,
                    secondaryIcon: Icons.pause_rounded,
                    tooltip: 'Play / pause',
                    primary: true,
                    enabled: linked,
                    onTap: () => _media('play'),
                  ),
                  const SizedBox(width: 18),
                  _RoundKey(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Next',
                    enabled: linked,
                    onTap: () => _media('next'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SmallKey(
                    icon: Icons.volume_down_rounded,
                    tooltip: 'Volume down',
                    enabled: linked,
                    onTap: () => _media('vol_down'),
                  ),
                  const SizedBox(width: 10),
                  _SmallKey(
                    icon: _muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_mute_rounded,
                    tooltip: _muted ? 'Unmute' : 'Mute',
                    active: _muted,
                    enabled: linked,
                    onTap: () {
                      setState(() => _muted = !_muted);
                      _link.setMuted(_muted);
                    },
                  ),
                  const SizedBox(width: 10),
                  _SmallKey(
                    icon: Icons.volume_up_rounded,
                    tooltip: 'Volume up',
                    enabled: linked,
                    onTap: () => _media('vol_up'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Small building blocks ──────────────────────────────────────────────────

/// Two-position slide switch: a blue cap gliding in a recessed track.
class _DeckSwitch extends StatelessWidget {
  const _DeckSwitch({required this.deck, required this.onChanged});
  final _Deck deck;
  final ValueChanged<_Deck> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(_Deck d, IconData icon, String label) {
      final on = deck == d;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(d),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: on ? AppColors.brandWhite : context.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: on ? AppColors.brandWhite : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: Tactile.recessed(context, radius: AppRadius.md),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            alignment: switch (deck) {
              _Deck.trackpad => Alignment.centerLeft,
              _Deck.media => Alignment.center,
              _Deck.ova => Alignment.centerRight,
            },
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        AppColors.brandBlue,
                        AppColors.brandWhite,
                        0.12,
                      )!,
                      AppColors.brandBlue,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              seg(_Deck.trackpad, Icons.touch_app_rounded, 'Trackpad'),
              seg(_Deck.media, Icons.graphic_eq_rounded, 'Media'),
              seg(_Deck.ova, Icons.auto_awesome_rounded, 'Ova Live'),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: Tactile.raised(
          context,
          radius: AppRadius.full,
          pressed: active,
          borderColor: active
              ? AppColors.brandBlue.withValues(alpha: 0.45)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? AppColors.brandBlue : context.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.brandBlue : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trackpad button keycap. Reacts on pointer down for zero perceived delay;
/// sinks into the deck while held and its LED lights pink.
class _ClickKey extends StatefulWidget {
  const _ClickKey({
    required this.label,
    required this.enabled,
    this.onDown,
    this.onUp,
    this.onTap,
  });
  final String label;
  final bool enabled;
  final bool Function()? onDown;
  final bool Function()? onUp;
  final bool Function()? onTap;

  @override
  State<_ClickKey> createState() => _ClickKeyState();
}

class _ClickKeyState extends State<_ClickKey> {
  bool _pressed = false;

  void _down(PointerDownEvent _) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    HapticFeedback.lightImpact();
    widget.onDown?.call();
  }

  void _up(PointerEvent e) {
    if (!_pressed) return;
    setState(() => _pressed = false);
    widget.onUp?.call();
    if (e is PointerUpEvent) widget.onTap?.call();
  }

  @override
  void dispose() {
    if (_pressed) widget.onUp?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedSlide(
        offset: _pressed ? const Offset(0, 0.03) : Offset.zero,
        duration: const Duration(milliseconds: 90),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: Tactile.raised(
            context,
            radius: AppRadius.lg,
            pressed: _pressed,
            borderColor: _pressed
                ? AppColors.brandBlue.withValues(alpha: 0.6)
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: widget.enabled
                      ? (_pressed ? AppColors.brandBlue : context.textPrimary)
                      : context.textMuted,
                ),
              ),
              Positioned(
                top: 8,
                right: 10,
                child: StatusLed(on: _pressed, size: 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round transport key. The primary (play/pause) is a blue cap with a soft
/// brand glow; the others are matte caps.
class _RoundKey extends StatefulWidget {
  const _RoundKey({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.secondaryIcon,
    this.primary = false,
  });
  final IconData icon;
  final IconData? secondaryIcon;
  final String tooltip;
  final bool enabled;
  final bool primary;
  final bool Function() onTap;

  @override
  State<_RoundKey> createState() => _RoundKeyState();
}

class _RoundKeyState extends State<_RoundKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.primary ? 66.0 : 50.0;
    final primaryOn = widget.primary && widget.enabled;
    final fg = primaryOn
        ? AppColors.brandWhite
        : (widget.enabled ? context.textPrimary : context.textMuted);
    final decoration = primaryOn
        ? BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _pressed
                  ? [
                      AppColors.brandBlue,
                      Color.lerp(
                        AppColors.brandBlue,
                        AppColors.brandWhite,
                        0.14,
                      )!,
                    ]
                  : [
                      Color.lerp(
                        AppColors.brandBlue,
                        AppColors.brandWhite,
                        0.16,
                      )!,
                      AppColors.brandBlue,
                    ],
            ),
            border: Border.all(
              color: Color.lerp(
                AppColors.brandBlue,
                AppColors.brandWhite,
                0.25,
              )!,
              width: 1.0,
            ),
            boxShadow: _pressed
                ? null
                : [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          )
        : Tactile.raised(context, circle: true, pressed: _pressed);

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                HapticFeedback.mediumImpact();
                widget.onTap();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: size,
            height: size,
            decoration: decoration,
            child: widget.secondaryIcon == null
                ? Icon(widget.icon, size: widget.primary ? 28 : 22, color: fg)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, size: 22, color: fg),
                      Icon(widget.secondaryIcon, size: 18, color: fg),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SmallKey extends StatefulWidget {
  const _SmallKey({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SmallKey> createState() => _SmallKeyState();
}

class _SmallKeyState extends State<_SmallKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sunk = _pressed || widget.active;
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) => setState(() => _pressed = true)
            : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: widget.enabled
            ? (_) {
                setState(() => _pressed = false);
                HapticFeedback.selectionClick();
                widget.onTap();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 50,
          height: 40,
          decoration: Tactile.raised(
            context,
            radius: AppRadius.md,
            pressed: sunk,
            borderColor: widget.active
                ? AppColors.brandPink.withValues(alpha: 0.5)
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                widget.icon,
                size: 19,
                color: widget.active
                    ? AppColors.brandPink
                    : (widget.enabled
                          ? context.textPrimary
                          : context.textMuted),
              ),
              Positioned(
                top: 5,
                right: 6,
                child: StatusLed(on: widget.active, size: 3.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim link status under the live screen: LEDs, latency, retry.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.linkState,
    required this.fastLane,
    required this.rttMs,
    required this.onRetry,
  });

  final ControllerLinkState linkState;
  final bool fastLane;
  final int? rttMs;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final linked = linkState == ControllerLinkState.linked;
    final micro = GoogleFonts.inter(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: context.textMuted,
    );
    Widget led(bool on, String label) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusLed(on: on, size: 5),
              const SizedBox(width: 4),
              Text(label, style: micro),
            ],
          ),
        );
    return Row(
      children: [
        led(linked, 'LINK'),
        led(linked && fastLane, 'FAST'),
        led(linked, 'SECURE'),
        const Spacer(),
        if (linkState == ControllerLinkState.offline)
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: Tactile.recessed(context, radius: AppRadius.xs),
            child: Text(
              linked ? (rttMs == null ? '-- ms' : '$rttMs ms') : 'sync…',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: linked ? AppColors.brandBlue : context.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}
