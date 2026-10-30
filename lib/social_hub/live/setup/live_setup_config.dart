// LIVE SETUP WIZARD — the choices the host makes before going live.
//
// Everything maps onto the Live Studio backend:
// - mode / layout → lsStart `kind` + `settings` (StudioSettings);
// - title / cover / category / audience / join requests → lsStart extras;
// - comments → lsSetChatMode right after the start.

import 'package:flutter/material.dart';

import '../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../backend/live_studio/settings/settings_rules.dart';

/// How the live is staged.
enum LiveSetupMode {
  /// Just the host on the center screen. No join requests.
  solo('Solo', 'Just you, full focus. Viewers watch and chat.', Icons.person_rounded),

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
    this.smooth = 0.4,
    this.brighten = 0.3,
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
  final double smooth;
  final double brighten;

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
    double? smooth,
    double? brighten,
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
        smooth: smooth ?? this.smooth,
        brighten: brighten ?? this.brighten,
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
