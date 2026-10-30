// LIVE STUDIO v2 — Live controls hub: one sheet, everything in reach.
//   Fun        (host · co-host): poll, countdown, spotlight, celebrate, raffle,
//                                gifts leaderboard, mute all guests
//   Voice      (anyone on stage): microphone sound presets
//   Broadcast  (host):           1080p recording + restream to platforms
//   View       (everyone):       clean view, effects on/off, top gifters
// Tabs sit side by side so related settings are always next to each other.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../../../../backend/live_studio/media/livekit_studio_room.dart';
import '../../../../backend/live_studio/roles/roles.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import 'gifts_ui.dart';
import '../shell/shell_widgets.dart';
import '../theme/live_studio_tokens.dart';

Future<void> showLiveControlHub(
  BuildContext context, {
  required String streamId,
  required bool isHost,
  required bool isManager,
  StudioRoomPort? room,
  bool onStage = false,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: LiveStudioAccent.clear,
    barrierColor: LiveStudioTokens.dimTint(0.35),
    sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 520), reverseDuration: Duration(milliseconds: 360)),
    builder: (_) => LiveControlHub(streamId: streamId, isHost: isHost, isManager: isManager, room: room, onStage: onStage),
  );
}

class LiveControlHub extends ConsumerStatefulWidget {
  const LiveControlHub({
    super.key,
    required this.streamId,
    required this.isHost,
    required this.isManager,
    this.room,
    this.onStage = false,
  });
  final String streamId;
  final bool isHost;
  final bool isManager;
  final StudioRoomPort? room;
  final bool onStage;

  @override
  ConsumerState<LiveControlHub> createState() => _LiveControlHubState();
}

class _LiveControlHubState extends ConsumerState<LiveControlHub> {
  late final List<(String, IconData)> _tabs = [
    if (widget.isManager) ('Fun', Icons.celebration_rounded),
    if (widget.onStage && widget.room is LiveKitStudioRoom) ('Voice', Icons.graphic_eq_rounded),
    if (widget.isHost) ('Broadcast', Icons.cell_tower_rounded),
    ('View', Icons.visibility_rounded),
  ];
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final name = _tabs[_tab].$1;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.78),
      decoration: const BoxDecoration(
        color: LiveStudioWorld.popHeader,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 38, height: 4, decoration: BoxDecoration(color: LiveStudioWorld.textDim, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text('Live controls', style: LiveStudioType.s(18, FontWeight.w800, LiveStudioWorld.textHigh)),
              const Spacer(),
              for (final (i, t) in _tabs.indexed)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _TabChip(label: t.$1, icon: t.$2, selected: i == _tab, onTap: () => setState(() => _tab = i)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: c),
              ),
              child: KeyedSubtree(
                key: ValueKey(name),
                child: switch (name) {
                  'Fun' => _FunTab(streamId: widget.streamId),
                  'Voice' => _VoiceTab(room: widget.room! as LiveKitStudioRoom),
                  'Broadcast' => _BroadcastTab(streamId: widget.streamId),
                  _ => _ViewTab(streamId: widget.streamId),
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? LiveStudioAccent.blue : LiveStudioWorld.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: LiveStudioAccent.white),
            const SizedBox(width: 4),
            Text(label, style: LiveStudioType.s(12, FontWeight.w700, LiveStudioAccent.white)),
          ]),
        ),
      );
}

// ─── shared bits ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child, this.trailing});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: LiveStudioWorld.surface2, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: LiveStudioAccent.pink),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: LiveStudioType.s(14, FontWeight.w800, LiveStudioWorld.textHigh))),
            ?trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

InputDecoration _field(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: LiveStudioType.s(13, FontWeight.w500, LiveStudioWorld.textDim),
      isDense: true,
      filled: true,
      fillColor: LiveStudioWorld.surface3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    );

TextStyle get _input => LiveStudioType.s(14, FontWeight.w600, LiveStudioWorld.textHigh);

Widget _button(String label, IconData icon, VoidCallback? onTap, {bool primary = true}) => StudioPillButton(
      label: label,
      icon: icon,
      onTap: onTap,
      fill: primary ? LiveStudioAccent.blue : LiveStudioWorld.surface3,
      textColor: LiveStudioAccent.white,
      height: 40,
    );

void _toast(BuildContext context, Object e, {String? ok}) {
  final msg = ok ??
      (e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty ? e.message! : 'Something went wrong. Try again.');
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
}

// ─── Fun ─────────────────────────────────────────────────────────────────────

class _FunTab extends ConsumerStatefulWidget {
  const _FunTab({required this.streamId});
  final String streamId;

  @override
  ConsumerState<_FunTab> createState() => _FunTabState();
}

class _FunTabState extends ConsumerState<_FunTab> {
  final _question = TextEditingController();
  final _options = [TextEditingController(), TextEditingController()];
  final _spot = TextEditingController();
  int _pollSeconds = 60;
  int _timerSeconds = 60;
  bool _busy = false;

  @override
  void dispose() {
    _question.dispose();
    _spot.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function(StudioFunApi api) f, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f(ref.read(studioFunApiProvider));
      if (mounted && done != null) _toast(context, '', ok: done);
    } catch (e) {
      if (mounted) _toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _muteAll() async {
    final members = ref.read(studioMembersProvider(widget.streamId)).value ?? const <StageMember>[];
    final guests = [for (final m in members) if (m.role == StudioRole.guest && m.micOn) m.uid];
    if (guests.isEmpty) {
      _toast(context, '', ok: 'No guest has their mic on.');
      return;
    }
    setState(() => _busy = true);
    final roles = ref.read(studioRolesApiProvider);
    var done = 0;
    for (final uid in guests) {
      try {
        await roles.moderate(widget.streamId, uid, StudioModerationOp.mute);
        done++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _busy = false);
      _toast(context, '', ok: 'Muted $done guest${done == 1 ? '' : 's'}.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final fun = ref.watch(studioFunProvider(widget.streamId)).value ?? const StudioFunState();
    final now = DateTime.now().millisecondsSinceEpoch;
    final pollOpen = fun.poll?.acceptingAt(now) ?? false;
    final timerOn = fun.timerEndsAtMs != null && fun.timerEndsAtMs! > now;
    final id = widget.streamId;
    return ListView(padding: const EdgeInsets.only(bottom: 16), shrinkWrap: true, children: [
      _Card(
        icon: Icons.poll_rounded,
        title: pollOpen ? 'Poll running' : 'Poll',
        trailing: pollOpen ? _button('End', Icons.stop_rounded, _busy ? null : () => _run((a) => a.endPoll(id))) : null,
        child: pollOpen
            ? Text(fun.poll!.question, style: _input)
            : Column(children: [
                TextField(controller: _question, style: _input, maxLength: 120, decoration: _field('Ask your viewers…')),
                for (final (i, c) in _options.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(controller: c, style: _input, maxLength: 40, decoration: _field('Option ${i + 1}')),
                  ),
                Row(children: [
                  if (_options.length < 4)
                    TextButton.icon(
                      onPressed: () => setState(() => _options.add(TextEditingController())),
                      icon: const Icon(Icons.add_rounded, color: LiveStudioAccent.blue),
                      label: Text('Option', style: LiveStudioType.s(13, FontWeight.w700, LiveStudioAccent.blue)),
                    ),
                  const Spacer(),
                  _SecondsPicker(value: _pollSeconds, options: const [30, 60, 120, 300], onChanged: (v) => setState(() => _pollSeconds = v)),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: _button('Start poll', Icons.play_arrow_rounded, _busy
                      ? null
                      : () {
                          final opts = [for (final c in _options) c.text.trim()]..removeWhere((t) => t.isEmpty);
                          _run((a) => a.startPoll(id, _question.text.trim(), opts, seconds: _pollSeconds));
                        }),
                ),
              ]),
      ),
      _Card(
        icon: Icons.timer_outlined,
        title: timerOn ? 'Countdown running' : 'Countdown',
        trailing: timerOn ? _button('Stop', Icons.stop_rounded, _busy ? null : () => _run((a) => a.stopTimer(id))) : null,
        child: Row(children: [
          _SecondsPicker(value: _timerSeconds, options: const [10, 30, 60, 180, 300, 600], onChanged: (v) => setState(() => _timerSeconds = v)),
          const Spacer(),
          _button('Start', Icons.play_arrow_rounded, _busy ? null : () => _run((a) => a.startTimer(id, _timerSeconds))),
        ]),
      ),
      _Card(
        icon: Icons.push_pin_rounded,
        title: 'Spotlight',
        trailing: fun.spotlightText != null && fun.spotlightText!.isNotEmpty
            ? _button('Clear', Icons.close_rounded, _busy ? null : () => _run((a) => a.clearSpotlight(id)), primary: false)
            : null,
        child: Row(children: [
          Expanded(child: TextField(controller: _spot, style: _input, maxLength: 200, decoration: _field('Pin a message on stage'))),
          const SizedBox(width: 8),
          _button('Pin', Icons.push_pin_rounded, _busy
              ? null
              : () => _run((a) async {
                    await a.spotlight(id, text: _spot.text.trim());
                    _spot.clear();
                  })),
        ]),
      ),
      _Card(
        icon: Icons.auto_awesome_rounded,
        title: 'Celebrate',
        child: Row(children: [
          for (final (k, label, icon) in const [
            ('confetti', 'Confetti', Icons.celebration_rounded),
            ('hearts', 'Hearts', Icons.favorite_rounded),
            ('fireworks', 'Fireworks', Icons.flare_rounded),
          ]) ...[
            Expanded(child: _button(label, icon, _busy ? null : () => _run((a) => a.celebrate(id, k)), primary: false)),
            if (k != 'fireworks') const SizedBox(width: 8),
          ],
        ]),
      ),
      _Card(
        icon: Icons.emoji_events_rounded,
        title: 'Raffle',
        child: Row(children: [
          Expanded(
            child: Text('Pick a random winner from everyone who commented in the last 10 minutes.',
                style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium)),
          ),
          const SizedBox(width: 8),
          _button('Draw', Icons.casino_rounded, _busy ? null : () => _run((a) => a.raffle(id))),
        ]),
      ),
      _Card(
        icon: Icons.mic_off_rounded,
        title: 'Quiet the stage',
        child: Row(children: [
          Expanded(
            child: Text('Mute every guest at once. They can unmute when you are ready.',
                style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium)),
          ),
          const SizedBox(width: 8),
          _button('Mute all', Icons.volume_off_rounded, _busy ? null : _muteAll),
        ]),
      ),
      _Card(
        icon: Icons.card_giftcard_rounded,
        title: 'Top gifters',
        child: StudioTopGifters(streamId: id),
      ),
    ]);
  }
}

class _SecondsPicker extends StatelessWidget {
  const _SecondsPicker({required this.value, required this.options, required this.onChanged});
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  static String fmt(int s) => s < 60 ? '${s}s' : '${s ~/ 60} min';

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: LiveStudioWorld.surface3, borderRadius: BorderRadius.circular(10)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            dropdownColor: LiveStudioWorld.surface3,
            iconEnabledColor: LiveStudioWorld.textMedium,
            style: _input,
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(fmt(o)))],
            onChanged: (v) => v == null ? null : onChanged(v),
          ),
        ),
      );
}

// ─── Broadcast ───────────────────────────────────────────────────────────────

class _BroadcastTab extends ConsumerStatefulWidget {
  const _BroadcastTab({required this.streamId});
  final String streamId;

  @override
  ConsumerState<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends ConsumerState<_BroadcastTab> {
  LiveRecordingStatus? _status;
  List<LiveDestination>? _dests;
  bool _record = true;
  bool _restream = true;
  String _frame = 'portrait';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = ref.read(studioBroadcastApiProvider);
    try {
      final r = await Future.wait([api.status(widget.streamId), api.destinations()]);
      if (!mounted) return;
      setState(() {
        _status = r[0] as LiveRecordingStatus?;
        _dests = r[1] as List<LiveDestination>;
      });
    } catch (_) {
      if (mounted) setState(() => _dests ??= const []);
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final api = ref.read(studioBroadcastApiProvider);
    try {
      if (_status?.active ?? false) {
        await api.stop(widget.streamId);
      } else {
        await api.start(widget.streamId, record: _record, restream: _restream, frame: _frame);
      }
      await _load();
    } catch (e) {
      if (mounted) _toast(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _status?.active ?? false;
    final enabled = (_dests ?? const []).where((d) => d.enabled).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 16), shrinkWrap: true, children: [
      _Card(
        icon: active ? Icons.fiber_manual_record_rounded : Icons.videocam_rounded,
        title: active ? 'On air everywhere' : 'Record & restream',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Your stage is rendered at 1080p without comments or likes, '
            'saved as a video and pushed live to your platforms in real time.',
            style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium),
          ),
          const SizedBox(height: 10),
          _SwitchLine(
            label: 'Record in 1080p',
            value: active ? (_status?.record ?? false) : _record,
            onChanged: active ? null : (v) => setState(() => _record = v),
          ),
          _SwitchLine(
            label: 'Restream to ${enabled.isEmpty ? 'my platforms' : enabled.map((d) => d.label).join(', ')}',
            value: active ? (_status?.platforms.isNotEmpty ?? false) : _restream && enabled.isNotEmpty,
            onChanged: active || enabled.isEmpty ? null : (v) => setState(() => _restream = v),
          ),
          if (!active)
            Row(children: [
              Text('Frame', style: LiveStudioType.s(13, FontWeight.w600, LiveStudioWorld.textHigh)),
              const Spacer(),
              for (final (f, label, icon) in const [
                ('portrait', '9:16', Icons.stay_current_portrait_rounded),
                ('landscape', '16:9', Icons.stay_current_landscape_rounded),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _TabChip(label: label, icon: icon, selected: _frame == f, onTap: () => setState(() => _frame = f)),
                ),
            ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: StudioPillButton(
              label: active ? 'Stop recording & restream' : 'Start',
              icon: active ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
              onTap: _busy ? null : _toggle,
              fill: active ? LiveStudioWorld.surface3 : LiveStudioAccent.pink,
              textColor: LiveStudioAccent.white,
              height: 46,
            ),
          ),
        ]),
      ),
      _Card(
        icon: Icons.cell_tower_rounded,
        title: 'Live destinations',
        trailing: TextButton(
          onPressed: () async {
            await context.push('/settings/live_destinations');
            unawaited(_load());
          },
          child: Text('Manage', style: LiveStudioType.s(13, FontWeight.w700, LiveStudioAccent.blue)),
        ),
        child: _dests == null
            ? const LinearProgressIndicator(color: LiveStudioAccent.blue, backgroundColor: LiveStudioWorld.surface3)
            : _dests!.isEmpty
                ? Text('Add Facebook, YouTube, TikTok or any RTMP server with its stream key.',
                    style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium))
                : Column(children: [
                    for (final d in _dests!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(Icons.circle, size: 9, color: d.enabled ? LiveStudioAccent.pink : LiveStudioWorld.textDim),
                          const SizedBox(width: 8),
                          Expanded(child: Text(d.label, style: _input)),
                          Text(d.keyHint, style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium)),
                        ]),
                      ),
                  ]),
      ),
    ]);
  }
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: LiveStudioType.s(13, FontWeight.w600, LiveStudioWorld.textHigh))),
        Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: LiveStudioAccent.pink),
      ]);
}

// ─── View ────────────────────────────────────────────────────────────────────

class _ViewTab extends ConsumerWidget {
  const _ViewTab({required this.streamId});
  final String streamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(studioViewPrefsProvider);
    final c = ref.read(studioViewPrefsProvider.notifier);
    return ListView(padding: const EdgeInsets.only(bottom: 16), shrinkWrap: true, children: [
      _Card(
        icon: Icons.tune_rounded,
        title: 'Your view',
        child: Column(children: [
          _SwitchLine(
            label: 'Clean view (hide comments & buttons)',
            value: p.cleanView,
            onChanged: (v) => c.set(p.copyWith(cleanView: v)),
          ),
          _SwitchLine(
            label: 'Show celebrations & effects',
            value: p.showEffects,
            onChanged: (v) => c.set(p.copyWith(showEffects: v)),
          ),
          Text('Only changes what you see. Long-press the controls button to switch clean view.',
              style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium)),
        ]),
      ),
      _Card(icon: Icons.card_giftcard_rounded, title: 'Top gifters', child: StudioTopGifters(streamId: streamId)),
    ]);
  }
}

// ─── Voice ───────────────────────────────────────────────────────────────────

class _VoiceTab extends StatefulWidget {
  const _VoiceTab({required this.room});
  final LiveKitStudioRoom room;

  @override
  State<_VoiceTab> createState() => _VoiceTabState();
}

class _VoiceTabState extends State<_VoiceTab> {
  bool _busy = false;

  Future<void> _pick(StudioVoicePreset p) async {
    if (_busy || p == widget.room.voicePreset) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await widget.room.setVoicePreset(p);
    } catch (e) {
      if (mounted) _toast(context, e, ok: 'Could not switch the microphone.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.room.voicePreset;
    return ListView(padding: const EdgeInsets.only(bottom: 16), shrinkWrap: true, children: [
      _Card(
        icon: Icons.graphic_eq_rounded,
        title: 'Your microphone sound',
        child: Column(children: [
          for (final p in StudioVoicePreset.values)
            GestureDetector(
              onTap: () => _pick(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p == current ? LiveStudioAccent.blueA(0.18) : LiveStudioWorld.surface3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p == current ? LiveStudioAccent.blue : LiveStudioWorld.nameplateBorder),
                ),
                child: Row(children: [
                  Icon(
                    switch (p) {
                      StudioVoicePreset.natural => Icons.record_voice_over_rounded,
                      StudioVoicePreset.clear => Icons.noise_aware_rounded,
                      StudioVoicePreset.studio => Icons.mic_external_on_rounded,
                      StudioVoicePreset.music => Icons.music_note_rounded,
                    },
                    color: p == current ? LiveStudioAccent.blue : LiveStudioWorld.textMedium,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.label, style: LiveStudioType.s(14, FontWeight.w800, LiveStudioWorld.textHigh)),
                      Text(p.description, style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium)),
                    ]),
                  ),
                  if (p == current) const Icon(Icons.check_circle_rounded, color: LiveStudioAccent.blue, size: 20),
                ]),
              ),
            ),
          if (_busy) const LinearProgressIndicator(color: LiveStudioAccent.blue, backgroundColor: LiveStudioWorld.surface3),
        ]),
      ),
    ]);
  }
}
