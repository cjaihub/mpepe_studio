// LIVE SETUP WIZARD — the choices the host makes before going live.
//
// Everything maps onto the Live Studio backend:
// - mode / layout → lsStart `kind` + `settings` (StudioSettings);
// - title / cover / category / audience / join requests → lsStart extras;
// - comments → lsSetChatMode right after the start.

import 'package:flutter/material.dart';

import '../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../backend/live_studio/settings/settings_rules.dart';
import '../../../looks/models/oneova_look.dart' show BoostBeautyConfig;

/// How the live is staged.
enum LiveSetupMode {
  /// Just the host on the center screen; join requests start paused and
  /// can be opened during the live without leaving the screen.
  solo('Solo', 'Just you, full focus. Open the stage to guests anytime.', Icons.person_rounded),

  /// Multi-panel studio: guests appear as video windows on the walls and
  /// viewers can request to join.
  studio('Studio', 'Bring guests on stage. Viewers can request to join.', Icons.view_quilt_rounded),

  /// Phone game in the center, host camera in a bubble.
  game('Game', 'Stream your game with your camera in a bubble.', Icons.sports_esports_rounded);

  const LiveSetupMode(this.label, this.blurb, this.icon);
  final String label;
  final String blurb;
  final IconData icon;

  static LiveSetupMode fromQuery(String? q) => switch (q) {
        'studio' => LiveSetupMode.studio,
        'gaming' || 'game' => LiveSetupMode.game,
        _ => LiveSetupMode.solo,
      };
}

/// Who can watch (`audienceMode` on the stream doc, enforced by lsToken).
enum LiveAudience {
  public('public', 'Everyone', 'Anyone on Oneova can find and watch.', Icons.public_rounded),
  followers('followers', 'Followers', 'Only people who follow you can watch.', Icons.group_rounded);

  const LiveAudience(this.wire, this.label, this.blurb, this.icon);
  final String wire;
  final String label;
  final String blurb;
  final IconData icon;
}

/// Comment rules (`lsSetChatMode`).
enum LiveChatMode {
  open('open', 'Open', 'Everyone can comment.', Icons.forum_rounded),
  slow('slow', 'Slow mode', 'One comment per person every few seconds.', Icons.hourglass_bottom_rounded),
  followers('followers', 'Followers only', 'Only your followers can comment.', Icons.how_to_reg_rounded);

  const LiveChatMode(this.wire, this.label, this.blurb, this.icon);
  final String wire;
  final String label;
  final String blurb;
  final IconData icon;
}

/// Beauty levels for the live camera, all 0–1.
@immutable
class LiveBeauty {
  const LiveBeauty({
    this.smooth = 0,
    this.tone = 0,
    this.glow = 0,
    this.slim = 0,
    this.jaw = 0,
    this.nose = 0,
    this.eyes = 0,
    this.eyeLight = 0,
    this.teeth = 0,
  });

  final double smooth;
  final double tone;
  final double glow;
  final double slim;
  final double jaw;
  final double nose;
  final double eyes;
  final double eyeLight;
  final double teeth;

  static const natural = LiveBeauty(smooth: 0.4, tone: 0.25, glow: 0.3, eyeLight: 0.2);
  static const glowUp = LiveBeauty(smooth: 0.55, tone: 0.4, glow: 0.6, eyeLight: 0.4, teeth: 0.3);
  static const sculpt = LiveBeauty(smooth: 0.35, tone: 0.2, glow: 0.25, slim: 0.35, jaw: 0.3, nose: 0.2, eyes: 0.2);
  static const studio = LiveBeauty(smooth: 0.5, tone: 0.5, glow: 0.45, slim: 0.15, eyeLight: 0.35, teeth: 0.2);

  /// Named looks shown as one-tap presets.
  static const presets = <(String, IconData, LiveBeauty)>[
    ('Natural', Icons.spa_rounded, natural),
    ('Glow', Icons.wb_sunny_rounded, glowUp),
    ('Sculpt', Icons.face_retouching_natural_rounded, sculpt),
    ('Studio', Icons.light_mode_rounded, studio),
  ];

  LiveBeauty copyWith({
    double? smooth,
    double? tone,
    double? glow,
    double? slim,
    double? jaw,
    double? nose,
    double? eyes,
    double? eyeLight,
    double? teeth,
  }) =>
      LiveBeauty(
        smooth: smooth ?? this.smooth,
        tone: tone ?? this.tone,
        glow: glow ?? this.glow,
        slim: slim ?? this.slim,
        jaw: jaw ?? this.jaw,
        nose: nose ?? this.nose,
        eyes: eyes ?? this.eyes,
        eyeLight: eyeLight ?? this.eyeLight,
        teeth: teeth ?? this.teeth,
      );

  /// For the live camera's GPU processor.
  BoostBeautyConfig toBoost({bool enabled = true}) => !enabled
      ? const BoostBeautyConfig()
      : BoostBeautyConfig(
          isEnabled: true,
          smoothSkin: smooth,
          evenTone: tone,
          autoBoostLevel: glow,
          faceSlim: slim,
          jawSlim: jaw,
          noseSlim: nose,
          eyeEnlarge: eyes,
          eyeBrighten: eyeLight,
          teethWhitening: teeth,
        );

  factory LiveBeauty.fromBoost(BoostBeautyConfig b) => LiveBeauty(
        smooth: b.smoothSkin,
        tone: b.evenTone,
        glow: b.autoBoostLevel,
        slim: b.faceSlim,
        jaw: b.jawSlim,
        nose: b.noseSlim,
        eyes: b.eyeEnlarge,
        eyeLight: b.eyeBrighten,
        teeth: b.teethWhitening,
      );

  @override
  bool operator ==(Object other) =>
      other is LiveBeauty &&
      other.smooth == smooth &&
      other.tone == tone &&
      other.glow == glow &&
      other.slim == slim &&
      other.jaw == jaw &&
      other.nose == nose &&
      other.eyes == eyes &&
      other.eyeLight == eyeLight &&
      other.teeth == teeth;

  @override
  int get hashCode => Object.hash(smooth, tone, glow, slim, jaw, nose, eyes, eyeLight, teeth);
}

/// The wizard's draft, immutable.
@immutable
class LiveSetupConfig {
  const LiveSetupConfig({
    this.mode = LiveSetupMode.solo,
    this.title = '',
    this.category = 'Entertainment',
    this.gameTitle = '',
    this.coverPath,
    this.cameraOn = true,
    this.micOn = true,
    this.beautyOn = false,
    this.beauty = LiveBeauty.natural,
    this.settings = const StudioSettings(),
    this.audience = LiveAudience.public,
    this.chatMode = LiveChatMode.open,
    this.slowSeconds = 15,
    this.joinRequests = true,
    this.record = false,
    this.restream = true,
    this.landscape = false,
  });

  final LiveSetupMode mode;
  final String title;
  final String category;
  final String gameTitle;

  /// Local file picked for the cover; uploaded when going live.
  final String? coverPath;
  final bool cameraOn;
  final bool micOn;
  final bool beautyOn;

  /// Beauty levels (applied only while [beautyOn]).
  final LiveBeauty beauty;

  /// Studio look + panels (theme, guest size, speaker mode, names).
  final StudioSettings settings;
  final LiveAudience audience;
  final LiveChatMode chatMode;
  final int slowSeconds;

  /// Viewers may request to join (studio mode only).
  final bool joinRequests;

  /// Record the 1080p stage (no comments / likes) to the host's library.
  final bool record;

  /// Push the live to the host's enabled Live destinations (RTMP).
  final bool restream;

  /// 16:9 recording / restream frame instead of 9:16.
  final bool landscape;

  bool get multiPanel => mode == LiveSetupMode.studio;
  bool get acceptsRequests => multiPanel && joinRequests;

  String get effectiveTitle {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    return mode == LiveSetupMode.game && gameTitle.trim().isNotEmpty ? 'Playing ${gameTitle.trim()}' : 'Live on Oneova';
  }

  /// `settings` partial for lsStart / lsSetSettings.
  Map<String, Object?> get settingsPartial => {
        StudioSettingsKeys.theme: settings.theme.wire,
        StudioSettingsKeys.frameColor: settings.frameColor,
        StudioSettingsKeys.studioDim: settings.studioDim,
        StudioSettingsKeys.guestSize: settings.guestSize.wire,
        StudioSettingsKeys.showNames: settings.showNames,
        StudioSettingsKeys.speakerMode: (multiPanel ? settings.speakerMode : SpeakerMode.hostPinned).wire,
        StudioSettingsKeys.studioId: settings.studioId,
      };

  LiveSetupConfig copyWith({
    LiveSetupMode? mode,
    String? title,
    String? category,
    String? gameTitle,
    String? coverPath,
    bool clearCover = false,
    bool? cameraOn,
    bool? micOn,
    bool? beautyOn,
    LiveBeauty? beauty,
    StudioSettings? settings,
    LiveAudience? audience,
    LiveChatMode? chatMode,
    int? slowSeconds,
    bool? joinRequests,
    bool? record,
    bool? restream,
    bool? landscape,
  }) =>
      LiveSetupConfig(
        mode: mode ?? this.mode,
        title: title ?? this.title,
        category: category ?? this.category,
        gameTitle: gameTitle ?? this.gameTitle,
        coverPath: clearCover ? null : (coverPath ?? this.coverPath),
        cameraOn: cameraOn ?? this.cameraOn,
        micOn: micOn ?? this.micOn,
        beautyOn: beautyOn ?? this.beautyOn,
        beauty: beauty ?? this.beauty,
        settings: settings ?? this.settings,
        audience: audience ?? this.audience,
        chatMode: chatMode ?? this.chatMode,
        slowSeconds: slowSeconds ?? this.slowSeconds,
        joinRequests: joinRequests ?? this.joinRequests,
        record: record ?? this.record,
        restream: restream ?? this.restream,
        landscape: landscape ?? this.landscape,
      );
}
