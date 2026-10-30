// LIVE SETUP WIZARD — /live/setup  (the only way to go live)
//
// Every "Go live" tap in the app lands here. Six spacious steps, each with a
// phone mock-up of what it sets: Mode → Details → Camera & mic → Layout →
// Audience → Review. "Go live" calls lsStart (with the wizard's settings and
// extras), hands the join token to the studio room (no extra lsToken round
// trip), then opens the Live Studio at /live/studio2/:streamId.

import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../backend/live_studio/fun/studio_fun.dart';
import '../../../backend/live_studio/media/studio_media_api.dart';
import '../../../backend/live_studio/security/studio_security_models.dart';
import '../../../backend/live_studio/settings/studio_settings_controller.dart';
import '../../../looks/live/live_looks_controller.dart';
import '../../../looks/models/oneova_look.dart';
import '../../../shared/theme/app_theme.dart';
import '../go_live/go_live_sheets.dart';
import '../studio_v2/join/device_preview.dart';
import 'live_setup_config.dart';
import 'live_setup_previews.dart';

enum _Step {
  mode('Mode', 'How do you want to go live?', Icons.dashboard_customize_rounded),
  details('Details', 'Title, cover and category', Icons.edit_note_rounded),
  devices('Camera', 'Camera, mic and beauty', Icons.videocam_rounded),
  layout('Layout', 'Studio look and panels', Icons.view_quilt_rounded),
  audience('Audience', 'Who watches, comments and joins', Icons.groups_rounded),
  review('Review', 'Ready when you are', Icons.rocket_launch_rounded);

  const _Step(this.label, this.headline, this.icon);
  final String label;
  final String headline;
  final IconData icon;
}

class LiveSetupWizardScreen extends ConsumerStatefulWidget {
  const LiveSetupWizardScreen({super.key, this.initialMode = LiveSetupMode.solo});
  final LiveSetupMode initialMode;

  @override
  ConsumerState<LiveSetupWizardScreen> createState() => _LiveSetupWizardScreenState();
}

class _LiveSetupWizardScreenState extends ConsumerState<LiveSetupWizardScreen> {
  late LiveSetupConfig _cfg = LiveSetupConfig(mode: widget.initialMode);
  final _pager = PageController();
  final _title = TextEditingController();
  final _game = TextEditingController();
  int _index = 0;

  StudioDevicePreview? _preview;
  StudioDevicePermissions? _perms;
  bool _previewBusy = false;

  bool _starting = false;
  int? _countdown;
  String? _error;

  _Step get _step => _Step.values[_index];
  String get _hostName => FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty == true
      ? FirebaseAuth.instance.currentUser!.displayName!.trim()
      : 'You';

  List<LiveDestination>? _destinations;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDefaults());
    unawaited(_loadDestinations());
  }

  Future<void> _loadDestinations() async {
    try {
      final d = await ref.read(studioBroadcastApiProvider).destinations();
      if (mounted) setState(() => _destinations = d);
    } catch (_) {
      if (mounted) setState(() => _destinations = const []);
    }
  }

  /// Pre-fills layout from the host's saved studio settings.
  Future<void> _loadDefaults() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final saved = await ref.read(hostDefaultsProvider(uid).future);
      if (!mounted) return;
      setState(() => _cfg = _cfg.copyWith(settings: saved.copyWith(layoutPreset: LayoutPreset.studio)));
    } catch (_) {
      // First live: keep the defaults.
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _title.dispose();
    _game.dispose();
    unawaited(_releasePreview());
    super.dispose();
  }

  void _set(LiveSetupConfig next) => setState(() => _cfg = next);

  // ─── Navigation ────────────────────────────────────────────────────────────

  Future<void> _goTo(int i) async {
    if (i < 0 || i >= _Step.values.length || _starting) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    final leaving = _step;
    setState(() => _index = i);
    await _pager.animateToPage(i, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    if (leaving == _Step.devices && _step != _Step.devices) unawaited(_releasePreview());
    if (_step == _Step.devices) unawaited(_ensurePreview());
  }

  void _back() {
    if (_index > 0) {
      _goTo(_index - 1);
    } else {
      _exit();
    }
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/home');
    }
  }

  // ─── Camera / mic preview ─────────────────────────────────────────────────

  Future<void> _ensurePreview() async {
    if (_previewBusy) return;
    _previewBusy = true;
    try {
      var p = _preview;
      if (p == null) {
        p = ref.read(studioDevicePreviewFactoryProvider)();
        _preview = p;
        final perms = await p.requestPermissions();
        if (!mounted || !identical(p, _preview)) return;
        setState(() => _perms = perms);
      }
      final perms = _perms;
      await p.setCamera(_cfg.cameraOn && (perms?.cameraOk ?? false));
      await p.setMic(_cfg.micOn && (perms?.micOk ?? false));
      await _syncBeauty();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    } finally {
      _previewBusy = false;
    }
  }

  Future<void> _releasePreview() async {
    final p = _preview;
    _preview = null;
    if (p == null) return;
    try {
      await ref.read(liveLooksControllerProvider.notifier).detachCameraTrack();
    } catch (_) {}
    await p.dispose();
  }

  /// Beauty runs on the preview track now and on the live camera later (the
  /// looks controller keeps the config and re-applies it when the room
  /// publishes the camera).
  Future<void> _syncBeauty() async {
    final looks = ref.read(liveLooksControllerProvider.notifier);
    final beauty = _cfg.beautyOn
        ? BoostBeautyConfig(
            isEnabled: true,
            smoothSkin: _cfg.smooth,
            evenTone: _cfg.smooth * 0.6,
            eyeBrighten: _cfg.brighten,
            autoBoostLevel: _cfg.brighten * 0.5,
          )
        : const BoostBeautyConfig();
    try {
      final p = _preview;
      final id = p is LiveKitDevicePreview ? p.videoTrackId : null;
      if (id != null) await looks.attachCameraTrack(id);
      await looks.applyBeauty(beauty);
    } catch (_) {
      // Beauty is optional; the live still works without the processor.
    }
  }

  // ─── Cover ─────────────────────────────────────────────────────────────────

  Future<void> _pickCover() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1080, imageQuality: 82);
      if (f != null && mounted) _set(_cfg.copyWith(coverPath: f.path));
    } catch (_) {
      _snack('Could not open your photos.');
    }
  }

  Future<String?> _uploadCover(String uid, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref('content/$uid/live_covers/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(File(path), SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (_) {
      return null; // The live starts without a cover rather than failing.
    }
  }

  // ─── Go live ───────────────────────────────────────────────────────────────

  Future<void> _goLive() async {
    if (_starting) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _starting = true;
      _error = null;
      _countdown = 3;
    });
    await _releasePreview();
    // The server start runs during the 3·2·1, so the studio opens already joined.
    final start = _start();
    for (var n = 3; n >= 1; n--) {
      if (!mounted) return;
      setState(() => _countdown = n);
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    try {
      final id = await start;
      if (!mounted) return;
      context.pushReplacement('/live/studio2/$id');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _countdown = null;
        _error = e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty
            ? e.message
            : 'Could not start your live. Check your connection and try again.';
      });
    }
  }

  Future<String> _start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to go live.');
    final cfg = _cfg;
    final partial = cfg.settingsPartial;
    final coverUrl = cfg.coverPath == null ? null : await _uploadCover(uid, cfg.coverPath!);
    // Remember this layout for next time (lsSetSettings with no stream).
    unawaited(_quiet(() => ref.read(studioSettingsApiProvider).save(null, partial)));

    final started = await ref.read(studioMediaApiProvider).start(
          cfg.effectiveTitle,
          settings: partial,
          gaming: cfg.mode == LiveSetupMode.game,
          gameTitle: cfg.mode == LiveSetupMode.game ? cfg.gameTitle : null,
          category: cfg.mode == LiveSetupMode.game ? null : cfg.category,
          coverUrl: coverUrl,
          audienceMode: cfg.audience.wire,
          allowGuestRequests: cfg.acceptsRequests,
        );
    final id = started.streamId;
    ref.read(studioStartCredentialsProvider)[id] = started.credentials;
    ref.read(studioStartMediaProvider)[id] = (mic: cfg.micOn, camera: cfg.cameraOn);

    final call = ref.read(studioCallPortProvider);
    unawaited(_quiet(() => call.call(StudioSecurityWire.setJoinRequests, {'streamId': id, 'open': cfg.acceptsRequests})));
    if (cfg.chatMode != LiveChatMode.open) {
      unawaited(_quiet(() => call.call(StudioSecurityWire.setChatMode, {
            'streamId': id,
            'mode': cfg.chatMode.wire,
            if (cfg.chatMode == LiveChatMode.slow) 'slowSeconds': cfg.slowSeconds,
          })));
    }
    // 1080p recording and/or real-time restream (lsBroadcast egress).
    final dests = _destinations ?? const <LiveDestination>[];
    final restream = cfg.restream && dests.any((d) => d.enabled);
    if (cfg.record || restream) {
      unawaited(_quiet(() => ref.read(studioBroadcastApiProvider).start(
            id,
            record: cfg.record,
            restream: restream,
            frame: cfg.landscape ? 'landscape' : 'portrait',
          )));
    }
    return id;
  }

  static Future<void> _quiet(Future<Object?> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('[LiveSetup] follow-up call failed: $e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

  // ─── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final last = _index == _Step.values.length - 1;
    return PopScope(
      canPop: _index == 0 && !_starting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_starting) _back();
      },
      child: Scaffold(
        backgroundColor: context.bg,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              _Header(
                step: _step,
                index: _index,
                onBack: _starting ? null : _back,
                onClose: _starting ? null : _exit,
                onJump: (i) => i < _index ? _goTo(i) : null,
              ),
              Expanded(
                child: PageView(
                  controller: _pager,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _page(_modeStep()),
                    _page(_detailsStep()),
                    _page(_devicesStep()),
                    _page(_layoutStep()),
                    _page(_audienceStep()),
                    _page(_reviewStep()),
                  ],
                ),
              ),
              _BottomBar(
                last: last,
                busy: _starting,
                error: _error,
                onNext: last ? _goLive : () => _goTo(_index + 1),
              ),
            ]),
          ),
          if (_countdown != null) _Countdown(value: _countdown!),
        ]),
      ),
    );
  }

  Widget _page(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: children,
      );

  // Step 1 — Mode
  List<Widget> _modeStep() => [
        SetupModePreview(config: _cfg),
        const SizedBox(height: 24),
        for (final m in LiveSetupMode.values)
          _ChoiceCard(
            icon: m.icon,
            title: m.label,
            subtitle: m.blurb,
            selected: _cfg.mode == m,
            onTap: () => _set(_cfg.copyWith(mode: m)),
          ),
      ];

  // Step 2 — Details
  List<Widget> _detailsStep() {
    final game = _cfg.mode == LiveSetupMode.game;
    return [
      SetupDetailsPreview(config: _cfg, hostName: _hostName),
      const SizedBox(height: 8),
      Center(child: Text('How your live appears in followers’ feeds', style: _hint(context))),
      const SizedBox(height: 22),
      _Section('Title'),
      TextField(
        controller: _title,
        maxLength: 200,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (v) => _set(_cfg.copyWith(title: v)),
        decoration: _input(context, 'What’s your live about?', Icons.title_rounded),
      ),
      if (game) ...[
        const SizedBox(height: 8),
        _Section('Game'),
        TextField(
          controller: _game,
          maxLength: GameTitleRules.maxLength,
          onChanged: (v) => _set(_cfg.copyWith(gameTitle: v)),
          decoration: _input(context, 'Which game are you playing?', Icons.sports_esports_rounded),
        ),
      ],
      const SizedBox(height: 8),
      _Section('Cover'),
      Row(children: [
        Expanded(
          child: _ActionTile(
            icon: _cfg.coverPath == null ? Icons.add_photo_alternate_rounded : Icons.photo_library_rounded,
            label: _cfg.coverPath == null ? 'Add a cover photo' : 'Change cover',
            onTap: _pickCover,
          ),
        ),
        if (_cfg.coverPath != null) ...[
          const SizedBox(width: 10),
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            onTap: () => _set(_cfg.copyWith(clearCover: true)),
          ),
        ],
      ]),
      if (!game) ...[
        const SizedBox(height: 22),
        _Section('Category'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (name, icon) in GoLiveSheets.categories)
            if (name != 'Gaming')
              _Pill(
                icon: icon,
                label: name,
                selected: _cfg.category == name,
                onTap: () => _set(_cfg.copyWith(category: name)),
              ),
        ]),
      ],
    ];
  }

  // Step 3 — Camera, mic, beauty
  List<Widget> _devicesStep() {
    final p = _preview;
    final perms = _perms;
    final denied = perms != null && (!perms.cameraOk || !perms.micOk);
    return [
      SetupCameraPreview(config: _cfg, video: p?.buildVideo(), micLevel: p?.micLevel),
      const SizedBox(height: 20),
      if (denied)
        _Notice(
          icon: Icons.lock_outline_rounded,
          text: 'Oneova needs camera and microphone access to go live.',
          action: 'Open settings',
          onAction: () => p?.openSettings(),
        ),
      _SwitchRow(
        icon: _cfg.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
        title: 'Camera',
        subtitle: _cfg.cameraOn ? 'You start on camera' : 'Start with your avatar instead',
        value: _cfg.cameraOn,
        onChanged: (v) {
          _set(_cfg.copyWith(cameraOn: v));
          unawaited(_ensurePreview());
        },
      ),
      _SwitchRow(
        icon: _cfg.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
        title: 'Microphone',
        subtitle: _cfg.micOn ? 'Speak to see the level move' : 'You start muted',
        value: _cfg.micOn,
        onChanged: (v) {
          _set(_cfg.copyWith(micOn: v));
          unawaited(_ensurePreview());
        },
      ),
      _SwitchRow(
        icon: Icons.auto_awesome_rounded,
        title: 'Beauty',
        subtitle: 'Natural skin smoothing and brightening',
        value: _cfg.beautyOn,
        accent: AppColors.brandPink,
        onChanged: (v) {
          _set(_cfg.copyWith(beautyOn: v));
          unawaited(_syncBeauty());
        },
      ),
      if (_cfg.beautyOn) ...[
        _SliderRow(
          label: 'Smooth',
          value: _cfg.smooth,
          onChanged: (v) => _set(_cfg.copyWith(smooth: v)),
          onChangeEnd: (_) => unawaited(_syncBeauty()),
        ),
        _SliderRow(
          label: 'Brighten',
          value: _cfg.brighten,
          onChanged: (v) => _set(_cfg.copyWith(brighten: v)),
          onChangeEnd: (_) => unawaited(_syncBeauty()),
        ),
      ],
    ];
  }

  // Step 4 — Layout & panels
  List<Widget> _layoutStep() {
    final s = _cfg.settings;
    final multi = _cfg.multiPanel;
    return [
      SetupPhoneFrame(
        dark: s.theme == StudioTheme.dark || _cfg.mode == LiveSetupMode.game,
        child: SetupStudioMock(config: _cfg),
      ),
      const SizedBox(height: 22),
      _Section('Studio theme'),
      Row(children: [
        for (final t in StudioTheme.values) ...[
          Expanded(
            child: _Pill(
              icon: t == StudioTheme.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              label: t == StudioTheme.dark ? 'Dark' : 'Light',
              selected: s.theme == t,
              onTap: () {
                final d = StudioSettings.defaultsFor(t);
                _set(_cfg.copyWith(
                    settings: s.copyWith(theme: t, frameColor: d.frameColor, studioDim: d.studioDim)));
              },
            ),
          ),
          if (t != StudioTheme.values.last) const SizedBox(width: 10),
        ],
      ]),
      const SizedBox(height: 22),
      if (!multi)
        _Notice(
          icon: Icons.info_outline_rounded,
          text: _cfg.mode == LiveSetupMode.game
              ? 'Game Live keeps your game in the center and your camera in a bubble.'
              : 'Solo keeps you on the center screen. Pick Studio to bring guests on stage.',
          action: _cfg.mode == LiveSetupMode.solo ? 'Switch to Studio' : null,
          onAction: () => _set(_cfg.copyWith(mode: LiveSetupMode.studio)),
        )
      else ...[
        _Section('Guest panel size'),
        Row(children: [
          for (final g in GuestSize.values) ...[
            Expanded(
              child: _Pill(
                icon: switch (g) {
                  GuestSize.s => Icons.photo_size_select_small_rounded,
                  GuestSize.m => Icons.photo_size_select_large_rounded,
                  GuestSize.l => Icons.photo_size_select_actual_rounded,
                },
                label: switch (g) { GuestSize.s => 'Small', GuestSize.m => 'Medium', GuestSize.l => 'Large' },
                selected: s.guestSize == g,
                onTap: () => _set(_cfg.copyWith(settings: s.copyWith(guestSize: g))),
              ),
            ),
            if (g != GuestSize.values.last) const SizedBox(width: 8),
          ],
        ]),
        const SizedBox(height: 22),
        _Section('Who is on the center screen'),
        _ChoiceCard(
          icon: Icons.push_pin_rounded,
          title: 'You, always',
          subtitle: 'You stay in the center; guests sit on the walls.',
          selected: s.speakerMode == SpeakerMode.hostPinned,
          onTap: () => _set(_cfg.copyWith(settings: s.copyWith(speakerMode: SpeakerMode.hostPinned))),
        ),
        _ChoiceCard(
          icon: Icons.record_voice_over_rounded,
          title: 'Whoever speaks',
          subtitle: 'The active speaker moves to the center automatically.',
          selected: s.speakerMode == SpeakerMode.autoActiveSpeaker,
          onTap: () => _set(_cfg.copyWith(settings: s.copyWith(speakerMode: SpeakerMode.autoActiveSpeaker))),
        ),
        _ChoiceCard(
          icon: Icons.touch_app_rounded,
          title: 'I choose',
          subtitle: 'Tap a guest during the live to put them in the center.',
          selected: s.speakerMode == SpeakerMode.manual,
          onTap: () => _set(_cfg.copyWith(settings: s.copyWith(speakerMode: SpeakerMode.manual))),
        ),
      ],
      const SizedBox(height: 8),
      _SwitchRow(
        icon: Icons.badge_rounded,
        title: 'Show names on panels',
        subtitle: 'Name tags under each video window',
        value: s.showNames,
        onChanged: (v) => _set(_cfg.copyWith(settings: s.copyWith(showNames: v))),
      ),
    ];
  }

  // Step 5 — Audience, comments, join requests
  List<Widget> _audienceStep() => [
        SetupAudiencePreview(config: _cfg),
        const SizedBox(height: 22),
        _Section('Who can watch'),
        for (final a in LiveAudience.values)
          _ChoiceCard(
            icon: a.icon,
            title: a.label,
            subtitle: a.blurb,
            selected: _cfg.audience == a,
            onTap: () => _set(_cfg.copyWith(audience: a)),
          ),
        const SizedBox(height: 14),
        _Section('Comments'),
        for (final c in LiveChatMode.values)
          _ChoiceCard(
            icon: c.icon,
            title: c.label,
            subtitle: c.blurb,
            selected: _cfg.chatMode == c,
            onTap: () => _set(_cfg.copyWith(chatMode: c)),
          ),
        if (_cfg.chatMode == LiveChatMode.slow)
          _SliderRow(
            label: '${_cfg.slowSeconds}s',
            value: (_cfg.slowSeconds - 5) / 55,
            onChanged: (v) => _set(_cfg.copyWith(slowSeconds: (5 + v * 55).round())),
          ),
        const SizedBox(height: 14),
        _Section('Guests'),
        _SwitchRow(
          icon: Icons.front_hand_rounded,
          title: 'Join requests',
          subtitle: _cfg.multiPanel
              ? 'Viewers can ask to come on stage. You approve each one.'
              : 'Available in Studio mode',
          value: _cfg.acceptsRequests,
          accent: AppColors.brandPink,
          onChanged: _cfg.multiPanel ? (v) => _set(_cfg.copyWith(joinRequests: v)) : null,
        ),
        const SizedBox(height: 14),
        _Section('Record & restream'),
        _SwitchRow(
          icon: Icons.fiber_manual_record_rounded,
          title: 'Record in 1080p',
          subtitle: 'Just the stage, no comments or likes. Keep or delete it after.',
          value: _cfg.record,
          accent: AppColors.brandPink,
          onChanged: (v) => _set(_cfg.copyWith(record: v)),
        ),
        _SwitchRow(
          icon: Icons.cell_tower_rounded,
          title: 'Restream live',
          subtitle: _destinationsLine(),
          value: _cfg.restream && (_destinations ?? const []).any((d) => d.enabled),
          onChanged: (_destinations ?? const []).any((d) => d.enabled) ? (v) => _set(_cfg.copyWith(restream: v)) : null,
        ),
        if (_cfg.record || _cfg.restream)
          _SwitchRow(
            icon: _cfg.landscape ? Icons.stay_current_landscape_rounded : Icons.stay_current_portrait_rounded,
            title: _cfg.landscape ? 'Landscape 16:9' : 'Portrait 9:16',
            subtitle: 'Frame for the recording and restream',
            value: _cfg.landscape,
            onChanged: (v) => _set(_cfg.copyWith(landscape: v)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              await context.push('/settings/live_destinations');
              unawaited(_loadDestinations());
            },
            icon: const Icon(Icons.add_link_rounded, color: AppColors.brandBlue),
            label: Text('Manage live destinations',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
          ),
        ),
      ];

  String _destinationsLine() {
    final on = (_destinations ?? const <LiveDestination>[]).where((d) => d.enabled).map((d) => d.label).toList();
    if (_destinations == null) return 'Loading your destinations…';
    return on.isEmpty ? 'Add Facebook, YouTube or TikTok first' : 'To ${on.join(', ')}';
  }

  // Step 6 — Review
  List<Widget> _reviewStep() {
    final s = _cfg.settings;
    final rows = <(_Step, IconData, String, String)>[
      (_Step.mode, _cfg.mode.icon, 'Mode', _cfg.mode.label),
      (_Step.details, Icons.title_rounded, 'Title', _cfg.effectiveTitle),
      (_Step.details, Icons.local_offer_rounded, 'Category', _cfg.mode == LiveSetupMode.game ? 'Gaming' : _cfg.category),
      (_Step.details, Icons.image_rounded, 'Cover', _cfg.coverPath == null ? 'None' : 'Added'),
      (
        _Step.devices,
        Icons.videocam_rounded,
        'Camera & mic',
        '${_cfg.cameraOn ? 'Camera on' : 'Camera off'} · ${_cfg.micOn ? 'Mic on' : 'Muted'}${_cfg.beautyOn ? ' · Beauty' : ''}'
      ),
      (
        _Step.layout,
        Icons.view_quilt_rounded,
        'Layout',
        '${s.theme == StudioTheme.dark ? 'Dark' : 'Light'} studio${_cfg.multiPanel ? ' · ${switch (s.guestSize) { GuestSize.s => 'small', GuestSize.m => 'medium', GuestSize.l => 'large' }} panels' : ''}'
      ),
      (_Step.audience, _cfg.audience.icon, 'Audience', _cfg.audience.label),
      (
        _Step.audience,
        _cfg.chatMode.icon,
        'Comments',
        _cfg.chatMode == LiveChatMode.slow ? 'Slow mode · ${_cfg.slowSeconds}s' : _cfg.chatMode.label
      ),
      (_Step.audience, Icons.front_hand_rounded, 'Join requests', _cfg.acceptsRequests ? 'On' : 'Off'),
      (
        _Step.audience,
        Icons.fiber_manual_record_rounded,
        'Record & restream',
        [
          if (_cfg.record) 'Recording 1080p',
          if (_cfg.restream && (_destinations ?? const []).any((d) => d.enabled)) 'Restream on',
        ].join(' · ').ifEmpty('Off'),
      ),
    ];
    return [
      SetupPhoneFrame(
        height: 320,
        dark: s.theme == StudioTheme.dark || _cfg.mode == LiveSetupMode.game,
        child: SetupStudioMock(config: _cfg),
      ),
      const SizedBox(height: 22),
      Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.border),
        ),
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[
            ListTile(
              leading: Icon(r.$2, color: AppColors.brandBlue),
              title: Text(r.$3, style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary)),
              subtitle: Text(r.$4,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
              trailing: Icon(Icons.edit_rounded, size: 18, color: context.textMuted),
              onTap: () => _goTo(r.$1.index),
            ),
            if (i != rows.length - 1) Divider(height: 1, color: context.border),
          ],
        ]),
      ),
    ];
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

/// Game title length shared with the server (GAME_TITLE_MAX_LENGTH).
class GameTitleRules {
  GameTitleRules._();
  static const int maxLength = 60;
}

TextStyle _hint(BuildContext context) => GoogleFonts.inter(fontSize: 12, color: context.textMuted);

InputDecoration _input(BuildContext context, String hint, IconData icon) => InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.brandBlue),
      filled: true,
      fillColor: context.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: context.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: context.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.brandBlue, width: 2)),
    );

class _Header extends StatelessWidget {
  const _Header({required this.step, required this.index, required this.onBack, required this.onClose, required this.onJump});
  final _Step step;
  final int index;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(children: [
        Row(children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(index == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, color: context.textPrimary),
            tooltip: index == 0 ? 'Close' : 'Back',
          ),
          Expanded(
            child: Column(children: [
              Text('Step ${index + 1} of ${_Step.values.length}',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
              const SizedBox(height: 2),
              Text(step.headline,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
            ]),
          ),
          if (index > 0)
            IconButton(onPressed: onClose, icon: Icon(Icons.close_rounded, color: context.textMuted), tooltip: 'Close')
          else
            const SizedBox(width: 48),
        ]),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final s in _Step.values) ...[
              _StepDot(step: s, state: s.index < index ? 1 : (s.index == index ? 0 : -1), onTap: () => onJump(s.index)),
              if (s != _Step.values.last)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: s.index < index ? AppColors.brandBlue : context.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.step, required this.state, required this.onTap});
  final _Step step;

  /// 1 done · 0 current · -1 upcoming.
  final int state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = state == 0;
    final done = state == 1;
    return Tooltip(
      message: step.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: current ? 36 : 28,
          height: current ? 36 : 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || current ? AppColors.brandBlue : context.surface,
            border: Border.all(color: current ? AppColors.brandPink : (done ? AppColors.brandBlue : context.border), width: 2),
          ),
          child: Icon(done ? Icons.check_rounded : step.icon,
              size: current ? 18 : 14, color: done || current ? AppColors.brandWhite : context.textMuted),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.last, required this.busy, required this.error, required this.onNext});
  final bool last;
  final bool busy;
  final String? error;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(color: context.bg, border: Border(top: BorderSide(color: context.border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.brandPink),
              const SizedBox(width: 8),
              Expanded(child: Text(error!, style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary))),
            ]),
          ),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: busy ? null : onNext,
            style: FilledButton.styleFrom(
              backgroundColor: last ? AppColors.brandPink : AppColors.brandBlue,
              foregroundColor: AppColors.brandWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
              textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            icon: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite))
                : Icon(last ? Icons.sensors_rounded : Icons.arrow_forward_rounded),
            label: Text(last ? (busy ? 'Going live…' : 'Go live') : 'Next'),
          ),
        ),
      ]),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.brandBlack.withValues(alpha: 0.78),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (c, a) => ScaleTransition(scale: Tween(begin: 1.6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
              child: Text('$value',
                  key: ValueKey(value),
                  style: GoogleFonts.inter(fontSize: 120, fontWeight: FontWeight.w900, color: AppColors.brandWhite)),
            ),
            const SizedBox(height: 8),
            const SetupLiveBadge(),
            const SizedBox(height: 10),
            Text('Opening your studio…', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.textMuted)),
      );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AppColors.brandBlue.withValues(alpha: 0.1) : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: selected ? AppColors.brandBlue : context.border, width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brandBlue : context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: selected ? AppColors.brandWhite : context.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12.5, height: 1.3, color: context.textSecondary)),
                ]),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.brandBlue : context.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: selected ? AppColors.brandBlue : context.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: selected ? AppColors.brandWhite : context.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w700, color: selected ? AppColors.brandWhite : context.textPrimary)),
          ),
        ]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: AppColors.brandBlue),
              const SizedBox(width: 10),
              Flexible(
                child: Text(label,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ),
            ]),
          ),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.brandBlue,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border),
          ),
          child: Row(children: [
            Icon(icon, color: value ? accent : context.textMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
              ]),
            ),
            Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: accent),
          ]),
        ),
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.onChanged, this.onChangeEnd});
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 6),
        child: Row(children: [
          SizedBox(
            width: 70,
            child: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textSecondary)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, 1).toDouble(),
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
              activeColor: AppColors.brandPink,
            ),
          ),
        ]),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action, this.onAction});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.brandBlue),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 13, height: 1.3, color: context.textPrimary))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.brandBlue)),
            ),
        ]),
      );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
