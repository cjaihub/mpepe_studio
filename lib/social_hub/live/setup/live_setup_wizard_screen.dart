// LIVE SETUP WIZARD — /live/setup  (the unified executive Go-Live wizard)
//
// Every "Go live" tap in the app lands here. Six compact, high-density steps,
// each with a real-time studio mock-up or live camera preview:
// Mode → Details → Camera & Effects → Studio Layout → Audience → Review.

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../looks/live/live_look_presets.dart';
import '../../../looks/live/live_looks_controller.dart';
import '../../../shared/theme/app_theme.dart';
import '../go_live/go_live_sheets.dart';
import '../studio_v2/join/device_preview.dart';
import 'live_beauty_panel.dart';
import 'live_setup_config.dart';
import 'live_setup_previews.dart';

enum _Step {
  mode('Mode', 'Choose your studio stage', Icons.dashboard_customize_rounded),
  details('Details', 'Title, cover & category', Icons.edit_note_rounded),
  devices('Effects', 'Camera, mic, looks & beauty', Icons.videocam_rounded),
  layout('Stage', 'Studio stage & panels', Icons.view_quilt_rounded),
  audience('Audience', 'Watch, chat & broadcast', Icons.groups_rounded),
  review('Review', 'Ready to go live', Icons.rocket_launch_rounded);

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncBeauty());
    });
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
    await _pager.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
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

  /// Syncs Beauty, Cinema Look, and Studio Key Lighting onto LiveLooksController
  /// so both the preview camera and the live broadcast render them in real time.
  Future<void> _syncBeauty() async {
    final looks = ref.read(liveLooksControllerProvider.notifier);
    final beauty = _cfg.beauty.toBoost(enabled: _cfg.beautyOn);
    final look = lookPresetById(_cfg.lookId);
    try {
      final p = _preview;
      final id = p is LiveKitDevicePreview ? p.videoTrackId : null;
      if (id != null) await looks.attachCameraTrack(id);
      await looks.applyBeauty(beauty);
      await looks.applyLook(look, crossFade: Duration.zero);
      await looks.applyLightingPreset(_cfg.lightingId);
    } catch (_) {}
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
    await _syncBeauty();
    await _releasePreview();
    // The server start runs during the 3·2·1, so the studio opens already joined.
    final start = _start();
    for (var n = 3; n >= 1; n--) {
      if (!mounted) return;
      setState(() => _countdown = n);
      HapticFeedback.lightImpact();
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
    try {
      final res = await start;
      if (!mounted) return;
      context.pushReplacement(res.route);
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

  Future<({String id, String route})> _start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to go live.');
    final cfg = _cfg;
    final partial = cfg.settingsPartial;

    // Upload cover with a fast 3.5s bound; if still uploading on a slow link,
    // finish in background and patch the stream doc so lsStart never times out.
    Future<String?>? pendingCover;
    String? coverUrl;
    if (cfg.coverPath != null) {
      pendingCover = _uploadCover(uid, cfg.coverPath!);
      coverUrl = await pendingCover.timeout(const Duration(milliseconds: 3500), onTimeout: () => null);
    }

    // Remember this layout for next time (lsSetSettings with no stream).
    unawaited(_quiet(() => ref.read(studioSettingsApiProvider).save(null, partial)));

    // Solo Studio, Multi-Guest Studio and Game Live all open the unified Live Studio.
    final started = await ref
        .read(studioMediaApiProvider)
        .start(
          cfg.effectiveTitle,
          settings: partial,
          gaming: cfg.mode == LiveSetupMode.game,
          gameTitle: cfg.mode == LiveSetupMode.game ? cfg.gameTitle : null,
          category: cfg.mode == LiveSetupMode.game ? null : cfg.category,
          coverUrl: coverUrl,
          audienceMode: cfg.audience.wire,
          allowGuestRequests: cfg.acceptsRequests,
        )
        .timeout(const Duration(seconds: 45));
    if (started.streamId.isEmpty) throw StateError('Could not start your live. Try again.');

    final id = started.streamId;
    ref.read(studioStartCredentialsProvider)[id] = started.credentials;
    ref.read(studioStartMediaProvider)[id] = (mic: cfg.micOn, camera: cfg.cameraOn);

    // Bind live effects to this stream so all viewers see Look, Beauty & Studio Key Lighting.
    ref.read(liveLooksControllerProvider.notifier).bindLiveStream(id);

    // If cover finished after the 3.5s fast bound, attach it to the stream doc.
    if (coverUrl == null && pendingCover != null) {
      unawaited(pendingCover.then((url) async {
        if (url != null && url.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('live_streams').doc(id).update({
              'coverUrl': url,
              'thumbnailUrl': url,
            });
          } catch (_) {}
        }
      }));
    }

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
    return (id: id, route: '/live/studio2/$id');
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: children,
      );

  // Step 1 — Mode (Compact 3-column grid instead of giant vertical cards)
  List<Widget> _modeStep() => [
        SetupModePreview(config: _cfg),
        const SizedBox(height: 12),
        _Section('Stage format'),
        Row(
          children: [
            for (final (i, m) in LiveSetupMode.values.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _CompactGridCard(
                  icon: m.icon,
                  title: m.label,
                  selected: _cfg.mode == m,
                  onTap: () => _set(_cfg.copyWith(
                    mode: m,
                    joinRequests: m == LiveSetupMode.studio ? true : _cfg.joinRequests,
                  )),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _Notice(
          icon: _cfg.mode.icon,
          text: _cfg.mode.blurb,
        ),
      ];

  // Step 2 — Details (Compact title + inline cover button + compact category chips)
  List<Widget> _detailsStep() {
    final game = _cfg.mode == LiveSetupMode.game;
    return [
      SetupDetailsPreview(config: _cfg, hostName: _hostName),
      const SizedBox(height: 12),
      _Section('Title & Cover'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _title,
              maxLength: 120,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) => _set(_cfg.copyWith(title: v)),
              decoration: _input(context, 'What’s your live about?', Icons.title_rounded).copyWith(counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          _ActionTile(
            icon: _cfg.coverPath == null ? Icons.add_photo_alternate_rounded : Icons.check_circle_rounded,
            label: _cfg.coverPath == null ? 'Cover' : 'Changed',
            onTap: _pickCover,
          ),
          if (_cfg.coverPath != null) ...[
            const SizedBox(width: 6),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _set(_cfg.copyWith(clearCover: true)),
              icon: Icon(Icons.close_rounded, size: 18, color: context.textMuted),
              tooltip: 'Remove cover',
            ),
          ],
        ],
      ),
      if (game) ...[
        const SizedBox(height: 10),
        _Section('Game Title'),
        TextField(
          controller: _game,
          maxLength: GameTitleRules.maxLength,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
          onChanged: (v) => _set(_cfg.copyWith(gameTitle: v)),
          decoration: _input(context, 'Which game are you playing?', Icons.sports_esports_rounded).copyWith(counterText: ''),
        ),
      ],
      if (!game) ...[
        const SizedBox(height: 12),
        _Section('Category'),
        Wrap(spacing: 6, runSpacing: 6, children: [
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

  // Step 3 — Camera, mic, Cinema Looks, Studio Key Lighting & Beauty
  List<Widget> _devicesStep() {
    final p = _preview;
    final perms = _perms;
    final denied = perms != null && (!perms.cameraOk || !perms.micOk);
    return [
      SetupCameraPreview(config: _cfg, video: p?.buildVideo(), micLevel: p?.micLevel),
      const SizedBox(height: 10),
      if (denied)
        _Notice(
          icon: Icons.lock_outline_rounded,
          text: 'Camera and microphone access required.',
          action: 'Settings',
          onAction: () => p?.openSettings(),
        ),
      // Compact 2-column Camera & Mic toggle pills
      Row(
        children: [
          Expanded(
            child: _CompactToggleTile(
              icon: _cfg.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: _cfg.cameraOn ? 'Camera On' : 'Camera Off',
              value: _cfg.cameraOn,
              onChanged: (v) {
                _set(_cfg.copyWith(cameraOn: v));
                unawaited(_ensurePreview());
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactToggleTile(
              icon: _cfg.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              label: _cfg.micOn ? 'Mic On' : 'Mic Muted',
              value: _cfg.micOn,
              onChanged: (v) {
                _set(_cfg.copyWith(micOn: v));
                unawaited(_ensurePreview());
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      LiveBeautyPanel(
        enabled: _cfg.beautyOn,
        beauty: _cfg.beauty,
        lookId: _cfg.lookId,
        lightingId: _cfg.lightingId,
        onEnabled: (v) {
          _set(_cfg.copyWith(beautyOn: v));
          unawaited(_syncBeauty());
        },
        onChanged: (b) => _set(_cfg.copyWith(beauty: b)),
        onLookChanged: (id) => _set(_cfg.copyWith(lookId: id)),
        onLightingChanged: (id) => _set(_cfg.copyWith(lightingId: id)),
        onCommit: () => unawaited(_syncBeauty()),
      ),
    ];
  }

  // Step 4 — Unified Studio Stage Layout (works identically for Solo Studio & Multi-Guest Studio)
  List<Widget> _layoutStep() {
    final s = _cfg.settings;
    final isStudioStage = _cfg.multiPanel;
    final frameColors = kFrameColorOptions[s.theme] ?? const <String>[];
    return [
      SetupPhoneFrame(
        height: 180,
        dark: s.theme == StudioTheme.dark || _cfg.mode == LiveSetupMode.game,
        child: SetupStudioMock(config: _cfg),
      ),
      const SizedBox(height: 12),
      _Section('Studio atmosphere & labels'),
      Row(
        children: [
          for (final t in StudioTheme.values) ...[
            Expanded(
              child: _Pill(
                icon: t == StudioTheme.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                label: t == StudioTheme.dark ? 'Dark Studio' : 'Light Studio',
                selected: s.theme == t,
                onTap: () {
                  final d = StudioSettings.defaultsFor(t);
                  _set(_cfg.copyWith(
                      settings: s.copyWith(theme: t, frameColor: d.frameColor, studioDim: d.studioDim)));
                },
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: _CompactToggleTile(
              icon: Icons.badge_rounded,
              label: 'Names',
              value: s.showNames,
              onChanged: (v) => _set(_cfg.copyWith(settings: s.copyWith(showNames: v))),
            ),
          ),
        ],
      ),
      if (isStudioStage) ...[
        const SizedBox(height: 10),
        _Section('Stage frame accent & studio dim'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              for (final hex in frameColors)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _set(_cfg.copyWith(settings: s.copyWith(frameColor: hex)));
                    },
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: s.frameColor.toLowerCase() == hex.toLowerCase() ? AppColors.brandPink : context.border,
                          width: s.frameColor.toLowerCase() == hex.toLowerCase() ? 2.2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.brightness_6_rounded, size: 14, color: context.textMuted),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                  ),
                  child: Slider(
                    value: (s.studioDim / StudioLimits.studioDimMax).clamp(0.0, 1.0),
                    activeColor: AppColors.brandBlue,
                    onChanged: (v) => _set(
                      _cfg.copyWith(
                        settings: s.copyWith(
                          studioDim: ((v * StudioLimits.studioDimMax * 20).round() / 20.0)
                              .clamp(StudioLimits.studioDimMin, StudioLimits.studioDimMax),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Section('Studio wall size & speaker focus'),
        Row(
          children: [
            for (final (i, g) in GuestSize.values.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
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
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (i, (mode, label, icon)) in const [
              (SpeakerMode.hostPinned, 'Host Pinned', Icons.push_pin_rounded),
              (SpeakerMode.autoActiveSpeaker, 'Auto Speaker', Icons.record_voice_over_rounded),
              (SpeakerMode.manual, 'Tap to Swap', Icons.touch_app_rounded),
            ].indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _CompactGridCard(
                  icon: icon,
                  title: label,
                  selected: s.speakerMode == mode,
                  onTap: () => _set(_cfg.copyWith(settings: s.copyWith(speakerMode: mode))),
                ),
              ),
            ],
          ],
        ),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _Notice(
            icon: Icons.sports_esports_rounded,
            text: 'Game Live streams your game in 1080p with your camera in a draggable floating bubble.',
          ),
        ),
    ];
  }

  // Step 5 — Audience, comments, join requests & broadcast (Compact rows & 2x2 grid)
  List<Widget> _audienceStep() {
    final hasDests = (_destinations ?? const []).any((d) => d.enabled);
    return [
      SetupAudiencePreview(config: _cfg),
      const SizedBox(height: 10),
      _Section('Who can watch'),
      Row(
        children: [
          for (final (i, a) in LiveAudience.values.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _Pill(
                icon: a.icon,
                label: a.label,
                selected: _cfg.audience == a,
                onTap: () => _set(_cfg.copyWith(audience: a)),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 10),
      _Section('Comments'),
      Row(
        children: [
          for (final (i, c) in LiveChatMode.values.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _Pill(
                icon: c.icon,
                label: c.label,
                selected: _cfg.chatMode == c,
                onTap: () => _set(_cfg.copyWith(chatMode: c)),
              ),
            ),
          ],
        ],
      ),
      if (_cfg.chatMode == LiveChatMode.slow)
        _SliderRow(
          label: 'Every ${_cfg.slowSeconds}s',
          value: (_cfg.slowSeconds - 5) / 55,
          onChanged: (v) => _set(_cfg.copyWith(slowSeconds: (5 + v * 55).round())),
        ),
      const SizedBox(height: 10),
      _Section('Stage & Broadcast'),
      Row(
        children: [
          Expanded(
            child: _CompactToggleTile(
              icon: Icons.front_hand_rounded,
              label: 'Join Requests',
              value: _cfg.acceptsRequests,
              accent: AppColors.brandPink,
              onChanged: _cfg.multiPanel ? (v) => _set(_cfg.copyWith(joinRequests: v)) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactToggleTile(
              icon: Icons.fiber_manual_record_rounded,
              label: 'Record 1080p',
              value: _cfg.record,
              accent: AppColors.brandPink,
              onChanged: (v) => _set(_cfg.copyWith(record: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _CompactToggleTile(
              icon: Icons.cell_tower_rounded,
              label: hasDests ? 'Restream On' : 'Restream',
              value: _cfg.restream && hasDests,
              onChanged: hasDests ? (v) => _set(_cfg.copyWith(restream: v)) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _CompactToggleTile(
              icon: _cfg.landscape ? Icons.stay_current_landscape_rounded : Icons.stay_current_portrait_rounded,
              label: _cfg.landscape ? '16:9 Landscape' : '9:16 Portrait',
              value: _cfg.landscape,
              onChanged: (v) => _set(_cfg.copyWith(landscape: v)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(Icons.link_rounded, size: 14, color: context.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _destinationsLine(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            onPressed: () async {
              await context.push('/settings/live_destinations');
              unawaited(_loadDestinations());
            },
            child: Text(
              'Destinations',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
            ),
          ),
        ],
      ),
    ];
  }

  String _destinationsLine() {
    final on = (_destinations ?? const <LiveDestination>[]).where((d) => d.enabled).map((d) => d.label).toList();
    if (_destinations == null) return 'Loading destinations…';
    return on.isEmpty ? 'Add YouTube, Facebook or TikTok RTMP' : 'Restreaming to ${on.join(', ')}';
  }

  // Step 6 — Review (Compact 2-column executive summary grid)
  List<Widget> _reviewStep() {
    final s = _cfg.settings;
    final look = lookPresetById(_cfg.lookId);
    final light = lightingPresetById(_cfg.lightingId);
    final cards = <(_Step, IconData, String, String)>[
      (_Step.mode, _cfg.mode.icon, 'Stage Mode', _cfg.mode.label),
      (_Step.details, Icons.title_rounded, 'Title', _cfg.effectiveTitle),
      (
        _Step.details,
        Icons.local_offer_rounded,
        'Category & Cover',
        '${_cfg.mode == LiveSetupMode.game ? 'Gaming' : _cfg.category}${_cfg.coverPath != null ? ' · Cover set' : ''}'
      ),
      (
        _Step.devices,
        Icons.auto_awesome_rounded,
        'Effects & Look',
        '${look.name} · ${light.name}${_cfg.beautyOn ? ' · Beauty' : ''}'
      ),
      (
        _Step.devices,
        Icons.videocam_rounded,
        'Camera & Mic',
        '${_cfg.cameraOn ? 'Cam On' : 'Cam Off'} · ${_cfg.micOn ? 'Mic On' : 'Muted'}'
      ),
      (
        _Step.layout,
        Icons.view_quilt_rounded,
        'Studio Stage',
        '${s.theme == StudioTheme.dark ? 'Dark' : 'Light'} · ${s.guestSize.name.toUpperCase()} walls'
      ),
      (
        _Step.audience,
        _cfg.audience.icon,
        'Audience & Chat',
        '${_cfg.audience.label} · ${_cfg.chatMode.label}'
      ),
      (
        _Step.audience,
        Icons.cell_tower_rounded,
        'Guests & Output',
        [
          if (_cfg.acceptsRequests) 'Join On',
          if (_cfg.record) '1080p Rec',
          if (_cfg.restream && (_destinations ?? const []).any((d) => d.enabled)) 'Restream',
        ].join(' · ').ifEmpty('Standard Live'),
      ),
    ];

    return [
      SetupPhoneFrame(
        height: 175,
        dark: s.theme == StudioTheme.dark || _cfg.mode == LiveSetupMode.game,
        child: SetupStudioMock(config: _cfg),
      ),
      const SizedBox(height: 12),
      _Section('Tap any item to adjust'),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 54,
        ),
        itemBuilder: (context, i) {
          final r = cards[i];
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _goTo(r.$1.index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border),
              ),
              child: Row(
                children: [
                  Icon(r.$2, size: 16, color: AppColors.brandBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: context.textMuted),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          r.$4,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ];
  }
}

// ─── Compact Executive Pieces ────────────────────────────────────────────────

/// Game title length shared with the server (GAME_TITLE_MAX_LENGTH).
class GameTitleRules {
  GameTitleRules._();
  static const int maxLength = 60;
}

InputDecoration _input(BuildContext context, String hint, IconData icon) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
      prefixIcon: Icon(icon, size: 18, color: AppColors.brandBlue),
      prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: context.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5)),
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
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
      child: Column(children: [
        SizedBox(
          height: 38,
          child: Row(children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onBack,
              icon: Icon(index == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, size: 20, color: context.textPrimary),
              tooltip: index == 0 ? 'Close' : 'Back',
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${index + 1}/${_Step.values.length}',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.brandBlue),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      step.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            if (index > 0)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 20, color: context.textMuted),
                tooltip: 'Close',
              )
            else
              const SizedBox(width: 40),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final s in _Step.values) ...[
              _StepDot(step: s, state: s.index < index ? 1 : (s.index == index ? 0 : -1), onTap: () => onJump(s.index)),
              if (s != _Step.values.last)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
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
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: current ? 8 : 0),
          height: 24,
          constraints: BoxConstraints(minWidth: current ? 58 : 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: done || current ? AppColors.brandBlue : context.surface,
            border: Border.all(
              color: current ? AppColors.brandPink : (done ? AppColors.brandBlue : context.border),
              width: current ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                done ? Icons.check_rounded : step.icon,
                size: 12,
                color: done || current ? AppColors.brandWhite : context.textMuted,
              ),
              if (current) ...[
                const SizedBox(width: 4),
                Text(
                  step.label,
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.brandWhite),
                ),
              ],
            ],
          ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: BoxDecoration(color: context.bg, border: Border(top: BorderSide(color: context.border))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.brandPink),
              const SizedBox(width: 6),
              Expanded(child: Text(error!, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary))),
            ]),
          ),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: FilledButton.icon(
            onPressed: busy ? null : onNext,
            style: FilledButton.styleFrom(
              backgroundColor: last ? AppColors.brandPink : AppColors.brandBlue,
              foregroundColor: AppColors.brandWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            icon: busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite))
                : Icon(last ? Icons.sensors_rounded : Icons.arrow_forward_rounded, size: 18),
            label: Text(last ? (busy ? 'Opening Studio…' : 'Go Live Now') : 'Continue'),
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
        color: AppColors.brandBlack.withValues(alpha: 0.80),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (c, a) =>
                  ScaleTransition(scale: Tween(begin: 1.5, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: c)),
              child: Text('$value',
                  key: ValueKey(value),
                  style: GoogleFonts.inter(fontSize: 96, fontWeight: FontWeight.w900, color: AppColors.brandWhite)),
            ),
            const SizedBox(height: 8),
            const SetupLiveBadge(),
            const SizedBox(height: 8),
            Text('Entering your Live Studio…', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
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
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: context.textMuted)),
      );
}

/// Compact 3-column grid card for Mode and Speaker Focus selection.
class _CompactGridCard extends StatelessWidget {
  const _CompactGridCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue.withValues(alpha: 0.12) : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.brandBlue : context.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? AppColors.brandBlue : context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 17, color: selected ? AppColors.brandWhite : context.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? context.textPrimary : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact toggle tile (height ~42px) for 2-column grids.
class _CompactToggleTile extends StatelessWidget {
  const _CompactToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.brandBlue,
  });
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onChanged!(!value);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: value ? accent.withValues(alpha: 0.12) : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: value ? accent : context.border,
            width: value ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: value ? accent : context.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: enabled ? context.textPrimary : context.textMuted,
                ),
              ),
            ),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? accent : context.border,
              ),
            ),
          ],
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
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: selected ? AppColors.brandBlue : context.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: selected ? AppColors.brandWhite : context.textSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.brandWhite : context.textPrimary)),
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
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Text(label,
                  maxLines: 1,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
            ]),
          ),
        ),
      );
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.onChanged});
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        child: SizedBox(
          height: 32,
          child: Row(children: [
            SizedBox(
              width: 72,
              child: Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.textSecondary)),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(0, 1).toDouble(),
                onChanged: onChanged,
                activeColor: AppColors.brandPink,
              ),
            ),
          ]),
        ),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.28)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.brandBlue),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, height: 1.25, color: context.textPrimary))),
          if (action != null)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onAction,
              child: Text(action!, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.brandBlue)),
            ),
        ]),
      );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
