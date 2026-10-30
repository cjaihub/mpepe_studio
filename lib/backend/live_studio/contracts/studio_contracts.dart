// ─────────────────────────────────────────────────────────────────────────────
// LIVE STUDIO v2 — SHARED CONTRACTS (integrator-owned, see
// docs/live-studio/ARCHITECTURE.md §4–§6).
//
// Every workstream codes against these types. Do not edit from a workstream;
// ask the integrator. The TypeScript mirror is
// functions/src/liveStudio/contracts.ts — keep both in sync.
//
// Wire format: JSON. Enum values travel as their `wire` string. Times are
// epoch milliseconds (server clock unless stated otherwise).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

/// Bumped on any breaking change to the persisted or wire shape.
const int kStudioSchemaVersion = 1;

// ─── Firestore paths (written by Cloud Functions only) ───────────────────────

class StudioPaths {
  StudioPaths._();
  static const String streams = 'live_streams';
  static String state(String streamId) => '$streams/$streamId/studio/state';
  static String members(String streamId) => '$streams/$streamId/members';
  static String comments(String streamId) => '$streams/$streamId/studio_comments';
  static String requests(String streamId) => '$streams/$streamId/studio_requests';
  static String hostSettings(String hostId) => 'users/$hostId/live_studio/settings';
  static const String watchCatalog = 'live_watch_catalog';
}

// ─── Tunables shared by client and server ────────────────────────────────────

class StudioLimits {
  StudioLimits._();

  /// Wall capacity (landscape). Phone shows the first [phoneWallSlots].
  static const int wallSlots = 6;
  static const int phoneWallSlots = 4;

  /// Speaker hysteresis (ARCHITECTURE §8).
  static const Duration speakToTakeCenter = Duration(milliseconds: 1500);
  static const Duration minCenterHold = Duration(seconds: 4);
  static const Duration leaderFailover = Duration(seconds: 10);

  /// Watch-party sync: seek when |drift| exceeds this.
  static const int maxDriftMs = 300;

  /// Comments.
  static const int commentMaxLength = 200;
  static const Duration commentMinInterval = Duration(seconds: 2);
  static const int commentsPerMinute = 20;
  static const int commentBroadcastPerSecond = 25;
  static const int commentHistory = 50;
  static const int commentRenderCap = 50;

  /// Reactions.
  static const int reactionMaxPerCall = 10;
  static const int reactionCallsPerSecond = 5;
  static const Duration reactionAggregateWindow = Duration(milliseconds: 500);

  /// Counts broadcast cadence.
  static const Duration countsInterval = Duration(seconds: 2);

  /// Media fallback.
  static const Duration poorToAudioOnly = Duration(seconds: 5);
  static const Duration goodToRecover = Duration(seconds: 15);
  static const List<Duration> reconnectBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ];

  /// Settings ranges.
  static const int frameWidthMin = 0;
  static const int frameWidthMax = 12;
  static const int frameWidthDefault = 4;
  static const double studioDimMin = 0;
  static const double studioDimMax = 0.6;
}

// ─── Enums ───────────────────────────────────────────────────────────────────

T _byWire<T extends Enum>(List<T> values, Object? wire, T fallback,
    String Function(T) wireOf) {
  for (final v in values) {
    if (wireOf(v) == wire) return v;
  }
  return fallback;
}

enum StudioRole {
  host('host'),
  coHost('coHost'),
  guest('guest'),
  viewer('viewer');

  final String wire;
  const StudioRole(this.wire);
  static StudioRole fromWire(Object? w) =>
      _byWire(values, w, StudioRole.viewer, (v) => v.wire);

  bool get canPublish => this != StudioRole.viewer;
  bool get isManager => this == StudioRole.host || this == StudioRole.coHost;
}

enum StudioStatus {
  preparing('preparing'),
  live('live'),
  ended('ended');

  final String wire;
  const StudioStatus(this.wire);
  static StudioStatus fromWire(Object? w) =>
      _byWire(values, w, StudioStatus.preparing, (v) => v.wire);
}

enum StudioTheme {
  dark('dark'),
  light('light');

  final String wire;
  const StudioTheme(this.wire);
  static StudioTheme fromWire(Object? w) =>
      _byWire(values, w, StudioTheme.dark, (v) => v.wire);
}

enum GuestSize {
  s('s'),
  m('m'),
  l('l');

  final String wire;
  const GuestSize(this.wire);
  static GuestSize fromWire(Object? w) =>
      _byWire(values, w, GuestSize.m, (v) => v.wire);
}

enum SpeakerMode {
  hostPinned('hostPinned'),
  autoActiveSpeaker('autoActiveSpeaker'),
  manual('manual');

  final String wire;
  const SpeakerMode(this.wire);
  static SpeakerMode fromWire(Object? w) =>
      _byWire(values, w, SpeakerMode.hostPinned, (v) => v.wire);
}

/// Stage layout preset. `gaming` = the host's screen share is the center
/// screen and the host camera is a picture-in-picture bubble.
enum LayoutPreset {
  studio('studio'),
  gaming('gaming');

  final String wire;
  const LayoutPreset(this.wire);
  static LayoutPreset fromWire(Object? w) =>
      _byWire(values, w, LayoutPreset.studio, (v) => v.wire);
}

/// Max length of [StudioState.gameTitle].
const int kGameTitleMaxLength = 60;

enum TableMode {
  goods('goods'),
  screen('screen'),
  match('match'),
  movie('movie');

  final String wire;
  const TableMode(this.wire);
  static TableMode fromWire(Object? w) =>
      _byWire(values, w, TableMode.goods, (v) => v.wire);

  bool get isStream => this != TableMode.goods;
  bool get isWatchParty => this == TableMode.match || this == TableMode.movie;
}

enum PlaybackState {
  playing('playing'),
  paused('paused'),
  ended('ended');

  final String wire;
  const PlaybackState(this.wire);
  static PlaybackState fromWire(Object? w) =>
      _byWire(values, w, PlaybackState.paused, (v) => v.wire);
}

enum GoodsSource {
  biz('biz'),
  stream('stream');

  final String wire;
  const GoodsSource(this.wire);
  static GoodsSource fromWire(Object? w) =>
      _byWire(values, w, GoodsSource.biz, (v) => v.wire);
}

enum JoinRequestStatus {
  pending('pending'),
  approved('approved'),
  declined('declined'),
  cancelled('cancelled');

  final String wire;
  const JoinRequestStatus(this.wire);
  static JoinRequestStatus fromWire(Object? w) =>
      _byWire(values, w, JoinRequestStatus.pending, (v) => v.wire);
}

enum SystemLineKind {
  joined('joined'),
  love('love'),
  sparkles('sparkles'),
  shared('shared'),
  requested('requested'),
  onStage('onStage');

  final String wire;
  const SystemLineKind(this.wire);
  static SystemLineKind fromWire(Object? w) =>
      _byWire(values, w, SystemLineKind.joined, (v) => v.wire);
}

enum ReactionKind {
  love('love'),
  sparkles('sparkles');

  final String wire;
  const ReactionKind(this.wire);
  static ReactionKind fromWire(Object? w) =>
      _byWire(values, w, ReactionKind.love, (v) => v.wire);
}

enum ModerationAction {
  mute('mute'),
  removeFromStage('removeFromStage'),
  block('block');

  final String wire;
  const ModerationAction(this.wire);
  static ModerationAction fromWire(Object? w) =>
      _byWire(values, w, ModerationAction.mute, (v) => v.wire);
}

// ─── Parsing helpers ─────────────────────────────────────────────────────────

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
double _dbl(Object? v, [double d = 0]) => v is num ? v.toDouble() : d;
String _str(Object? v, [String d = '']) => v is String ? v : d;
String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
bool _bool(Object? v, [bool d = false]) => v is bool ? v : d;
Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

// ─── Settings ────────────────────────────────────────────────────────────────

/// Default frame colors per theme (SPEC §1.1/§1.2).
const Map<StudioTheme, List<String>> kFrameColorOptions = {
  StudioTheme.dark: ['#15151B', '#2A3550', '#2F7BFF', '#FF2D75'],
  StudioTheme.light: ['#3B4763', '#8C97AE', '#2F7BFF', '#FF2D75'],
};

@immutable
class StudioSettings {
  final String studioId;
  final StudioTheme theme;
  final int frameWidth;
  final String frameColor;
  final GuestSize guestSize;
  final bool showNames;
  final double studioDim;
  final SpeakerMode speakerMode;
  final LayoutPreset layoutPreset;

  const StudioSettings({
    this.studioId = 'broadcast_curved_wall',
    this.theme = StudioTheme.dark,
    this.frameWidth = StudioLimits.frameWidthDefault,
    this.frameColor = '#15151B',
    this.guestSize = GuestSize.m,
    this.showNames = true,
    this.studioDim = 0.15,
    this.speakerMode = SpeakerMode.hostPinned,
    this.layoutPreset = LayoutPreset.studio,
  });

  /// Theme-appropriate defaults (light: frame #3B4763, dim 0).
  factory StudioSettings.defaultsFor(StudioTheme theme) => theme == StudioTheme.light
      ? const StudioSettings(theme: StudioTheme.light, frameColor: '#3B4763', studioDim: 0)
      : const StudioSettings();

  factory StudioSettings.fromJson(Map<String, dynamic> j) {
    final theme = StudioTheme.fromWire(j['theme']);
    final d = StudioSettings.defaultsFor(theme);
    return StudioSettings(
      studioId: _str(j['studioId'], d.studioId),
      theme: theme,
      frameWidth: _int(j['frameWidth'], d.frameWidth)
          .clamp(StudioLimits.frameWidthMin, StudioLimits.frameWidthMax),
      frameColor: _str(j['frameColor'], d.frameColor),
      guestSize: GuestSize.fromWire(j['guestSize']),
      showNames: _bool(j['showNames'], d.showNames),
      studioDim: _dbl(j['studioDim'], d.studioDim)
          .clamp(StudioLimits.studioDimMin, StudioLimits.studioDimMax),
      speakerMode: SpeakerMode.fromWire(j['speakerMode']),
      layoutPreset: LayoutPreset.fromWire(j['layoutPreset']),
    );
  }

  Map<String, dynamic> toJson() => {
        'studioId': studioId,
        'theme': theme.wire,
        'frameWidth': frameWidth,
        'frameColor': frameColor,
        'guestSize': guestSize.wire,
        'showNames': showNames,
        'studioDim': studioDim,
        'speakerMode': speakerMode.wire,
        'layoutPreset': layoutPreset.wire,
      };

  StudioSettings copyWith({
    String? studioId,
    StudioTheme? theme,
    int? frameWidth,
    String? frameColor,
    GuestSize? guestSize,
    bool? showNames,
    double? studioDim,
    SpeakerMode? speakerMode,
    LayoutPreset? layoutPreset,
  }) =>
      StudioSettings(
        studioId: studioId ?? this.studioId,
        theme: theme ?? this.theme,
        frameWidth: frameWidth ?? this.frameWidth,
        frameColor: frameColor ?? this.frameColor,
        guestSize: guestSize ?? this.guestSize,
        showNames: showNames ?? this.showNames,
        studioDim: studioDim ?? this.studioDim,
        speakerMode: speakerMode ?? this.speakerMode,
        layoutPreset: layoutPreset ?? this.layoutPreset,
      );

  @override
  bool operator ==(Object other) =>
      other is StudioSettings && mapEquals(toJson(), other.toJson());
  @override
  int get hashCode => Object.hashAll(toJson().values);
}

// ─── Stage layout ────────────────────────────────────────────────────────────

/// Landscape wall index → slot id (prototype order s1..s6).
const List<String> kLandscapeSlotOrder = ['L1', 'L2', 'R2', 'R1', 'LP', 'RP'];

/// Phone wall index → slot id (prototype order s1..s4).
const List<String> kPhoneSlotOrder = ['PL1', 'PL2', 'PR1', 'PR2'];

@immutable
class StageLayout {
  final String centerUid;

  /// Ordered, always [StudioLimits.wallSlots] long; null = empty slot.
  final List<String?> wall;
  final List<String> overflow;
  final String? pinnedUid;
  final int updatedAtMs;
  final String updatedBy;

  const StageLayout({
    required this.centerUid,
    this.wall = const [null, null, null, null, null, null],
    this.overflow = const [],
    this.pinnedUid,
    this.updatedAtMs = 0,
    this.updatedBy = '',
  });

  factory StageLayout.fromJson(Map<String, dynamic> j) {
    final raw = j['wall'] is List ? List<Object?>.from(j['wall'] as List) : const [];
    final wall = List<String?>.generate(
        StudioLimits.wallSlots, (i) => i < raw.length ? _strOrNull(raw[i]) : null);
    return StageLayout(
      centerUid: _str(j['centerUid']),
      wall: wall,
      overflow: j['overflow'] is List
          ? (j['overflow'] as List).whereType<String>().toList()
          : const [],
      pinnedUid: _strOrNull(j['pinnedUid']),
      updatedAtMs: _int(j['updatedAtMs']),
      updatedBy: _str(j['updatedBy']),
    );
  }

  Map<String, dynamic> toJson() => {
        'centerUid': centerUid,
        'wall': wall,
        'overflow': overflow,
        'pinnedUid': pinnedUid,
        'updatedAtMs': updatedAtMs,
        'updatedBy': updatedBy,
      };

  /// Everyone on stage (center, wall, overflow), center first.
  List<String> get publishers => [
        if (centerUid.isNotEmpty) centerUid,
        ...wall.whereType<String>(),
        ...overflow,
      ];

  /// Index of [uid] on the wall, or -1.
  int wallIndexOf(String uid) => wall.indexOf(uid);

  /// Slot id for [uid] in the given orientation, or null if not on that wall.
  String? slotIdFor(String uid, {required bool phone}) {
    final i = wallIndexOf(uid);
    final order = phone ? kPhoneSlotOrder : kLandscapeSlotOrder;
    return i >= 0 && i < order.length ? order[i] : null;
  }

  /// Wall members that the phone cannot show (indexes ≥ 4) — listed in
  /// Participants on phone, together with [overflow].
  List<String> get phoneOffWall => [
        for (var i = StudioLimits.phoneWallSlots; i < wall.length; i++)
          if (wall[i] != null) wall[i]!,
        ...overflow,
      ];

  StageLayout copyWith({
    String? centerUid,
    List<String?>? wall,
    List<String>? overflow,
    String? pinnedUid,
    bool clearPin = false,
    int? updatedAtMs,
    String? updatedBy,
  }) =>
      StageLayout(
        centerUid: centerUid ?? this.centerUid,
        wall: wall ?? this.wall,
        overflow: overflow ?? this.overflow,
        pinnedUid: clearPin ? null : (pinnedUid ?? this.pinnedUid),
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        updatedBy: updatedBy ?? this.updatedBy,
      );
}

// ─── Table ───────────────────────────────────────────────────────────────────

@immutable
class GoodsRef {
  final GoodsSource source;
  final String productId;
  const GoodsRef({required this.source, required this.productId});
  factory GoodsRef.fromJson(Map<String, dynamic> j) => GoodsRef(
      source: GoodsSource.fromWire(j['source']), productId: _str(j['productId']));
  Map<String, dynamic> toJson() => {'source': source.wire, 'productId': productId};
}

@immutable
class ScreenRef {
  final String publisherUid;
  final String trackName;
  const ScreenRef({required this.publisherUid, this.trackName = kTableScreenTrack});
  factory ScreenRef.fromJson(Map<String, dynamic> j) => ScreenRef(
      publisherUid: _str(j['publisherUid']),
      trackName: _str(j['trackName'], kTableScreenTrack));
  Map<String, dynamic> toJson() => {'publisherUid': publisherUid, 'trackName': trackName};
}

@immutable
class WatchParty {
  final String catalogId;
  final PlaybackState state;
  final int positionMs;
  final double rate;

  /// Server time at which [positionMs] was true.
  final int anchorServerMs;

  const WatchParty({
    required this.catalogId,
    this.state = PlaybackState.paused,
    this.positionMs = 0,
    this.rate = 1.0,
    this.anchorServerMs = 0,
  });

  factory WatchParty.fromJson(Map<String, dynamic> j) => WatchParty(
        catalogId: _str(j['catalogId']),
        state: PlaybackState.fromWire(j['state']),
        positionMs: _int(j['positionMs']),
        rate: _dbl(j['rate'], 1.0),
        anchorServerMs: _int(j['anchorServerMs']),
      );

  Map<String, dynamic> toJson() => {
        'catalogId': catalogId,
        'state': state.wire,
        'positionMs': positionMs,
        'rate': rate,
        'anchorServerMs': anchorServerMs,
      };

  /// Where playback should be at [serverNowMs].
  int targetPositionMs(int serverNowMs) => state == PlaybackState.playing
      ? positionMs + ((serverNowMs - anchorServerMs) * rate).round()
      : positionMs;
}

@immutable
class TableState {
  final TableMode mode;
  final GoodsRef? goods;
  final ScreenRef? screen;
  final WatchParty? watch;

  const TableState({this.mode = TableMode.goods, this.goods, this.screen, this.watch});

  factory TableState.fromJson(Map<String, dynamic> j) => TableState(
        mode: TableMode.fromWire(j['mode']),
        goods: j['goods'] is Map ? GoodsRef.fromJson(_map(j['goods'])) : null,
        screen: j['screen'] is Map ? ScreenRef.fromJson(_map(j['screen'])) : null,
        watch: j['watch'] is Map ? WatchParty.fromJson(_map(j['watch'])) : null,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.wire,
        'goods': goods?.toJson(),
        'screen': screen?.toJson(),
        'watch': watch?.toJson(),
      };
}

// ─── Counts / members ────────────────────────────────────────────────────────

@immutable
class StudioCounts {
  final int viewers;

  /// Stage members + co-hosts + pending requests (ARCHITECTURE Q4).
  final int participants;
  final int loves;
  final int sparkles;
  final int shares;

  const StudioCounts({
    this.viewers = 0,
    this.participants = 0,
    this.loves = 0,
    this.sparkles = 0,
    this.shares = 0,
  });

  factory StudioCounts.fromJson(Map<String, dynamic> j) => StudioCounts(
        viewers: _int(j['viewers']),
        participants: _int(j['participants']),
        loves: _int(j['loves']),
        sparkles: _int(j['sparkles']),
        shares: _int(j['shares']),
      );

  Map<String, dynamic> toJson() => {
        'viewers': viewers,
        'participants': participants,
        'loves': loves,
        'sparkles': sparkles,
        'shares': shares,
      };

  StudioCounts copyWith({int? viewers, int? participants, int? loves, int? sparkles, int? shares}) =>
      StudioCounts(
        viewers: viewers ?? this.viewers,
        participants: participants ?? this.participants,
        loves: loves ?? this.loves,
        sparkles: sparkles ?? this.sparkles,
        shares: shares ?? this.shares,
      );
}

/// Per-user accent palette (prototype guest accents), assigned in join order.
const List<String> kAccentPalette = [
  '#FF2D75', '#22C3D6', '#8B5CF6', '#FF6FA3', '#3D8BFF', '#FFB547', '#2DD4BF',
];

@immutable
class StageMember {
  final String uid;
  final String displayName;
  final String avatarUrl;
  final String accent;
  final StudioRole role;
  final bool micOn;
  final bool camOn;
  final bool chatMuted;
  final int joinedAtMs;

  const StageMember({
    required this.uid,
    required this.displayName,
    this.avatarUrl = '',
    this.accent = '#22C3D6',
    this.role = StudioRole.viewer,
    this.micOn = true,
    this.camOn = true,
    this.chatMuted = false,
    this.joinedAtMs = 0,
  });

  factory StageMember.fromJson(Map<String, dynamic> j) => StageMember(
        uid: _str(j['uid']),
        displayName: _str(j['displayName']),
        avatarUrl: _str(j['avatarUrl']),
        accent: _str(j['accent'], '#22C3D6'),
        role: StudioRole.fromWire(j['role']),
        micOn: _bool(j['micOn'], true),
        camOn: _bool(j['camOn'], true),
        chatMuted: _bool(j['chatMuted']),
        joinedAtMs: _int(j['joinedAtMs']),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'accent': accent,
        'role': role.wire,
        'micOn': micOn,
        'camOn': camOn,
        'chatMuted': chatMuted,
        'joinedAtMs': joinedAtMs,
      };
}

@immutable
class JoinRequest {
  final String uid;
  final String displayName;
  final String avatarUrl;
  final JoinRequestStatus status;
  final int requestedAtMs;

  const JoinRequest({
    required this.uid,
    required this.displayName,
    this.avatarUrl = '',
    this.status = JoinRequestStatus.pending,
    this.requestedAtMs = 0,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
        uid: _str(j['uid']),
        displayName: _str(j['displayName']),
        avatarUrl: _str(j['avatarUrl']),
        status: JoinRequestStatus.fromWire(j['status']),
        requestedAtMs: _int(j['requestedAtMs']),
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'status': status.wire,
        'requestedAtMs': requestedAtMs,
      };
}

// ─── Aggregate state ─────────────────────────────────────────────────────────

@immutable
class StudioState {
  final int schemaVersion;
  final String streamId;
  final String hostId;
  final String title;
  final StudioStatus status;
  final int seq;
  final StudioSettings settings;
  final StageLayout stage;
  final TableState table;
  final StudioCounts counts;

  /// Game being streamed on a gaming live (≤ [kGameTitleMaxLength]); null otherwise.
  final String? gameTitle;

  const StudioState({
    this.schemaVersion = kStudioSchemaVersion,
    required this.streamId,
    required this.hostId,
    this.title = '',
    this.status = StudioStatus.preparing,
    this.seq = 0,
    this.settings = const StudioSettings(),
    required this.stage,
    this.table = const TableState(),
    this.counts = const StudioCounts(),
    this.gameTitle,
  });

  /// True when the stage uses the gaming preset.
  bool get isGaming => settings.layoutPreset == LayoutPreset.gaming;

  factory StudioState.fromJson(Map<String, dynamic> j) => StudioState(
        schemaVersion: _int(j['schemaVersion'], kStudioSchemaVersion),
        streamId: _str(j['streamId']),
        hostId: _str(j['hostId']),
        title: _str(j['title']),
        status: StudioStatus.fromWire(j['status']),
        seq: _int(j['seq']),
        settings: StudioSettings.fromJson(_map(j['settings'])),
        stage: StageLayout.fromJson(_map(j['stage'])),
        table: TableState.fromJson(_map(j['table'])),
        counts: StudioCounts.fromJson(_map(j['counts'])),
        gameTitle: _gameTitle(j['gameTitle']),
      );

  static String? _gameTitle(Object? v) {
    final s = _strOrNull(v)?.trim();
    if (s == null || s.isEmpty) return null;
    return s.length > kGameTitleMaxLength ? s.substring(0, kGameTitleMaxLength) : s;
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'streamId': streamId,
        'hostId': hostId,
        'title': title,
        'status': status.wire,
        'seq': seq,
        'settings': settings.toJson(),
        'stage': stage.toJson(),
        'table': table.toJson(),
        'counts': counts.toJson(),
        if (gameTitle != null) 'gameTitle': gameTitle,
      };

  StudioState copyWith({
    String? title,
    StudioStatus? status,
    int? seq,
    StudioSettings? settings,
    StageLayout? stage,
    TableState? table,
    StudioCounts? counts,
    String? gameTitle,
  }) =>
      StudioState(
        schemaVersion: schemaVersion,
        streamId: streamId,
        hostId: hostId,
        title: title ?? this.title,
        status: status ?? this.status,
        seq: seq ?? this.seq,
        settings: settings ?? this.settings,
        stage: stage ?? this.stage,
        table: table ?? this.table,
        counts: counts ?? this.counts,
        gameTitle: gameTitle ?? this.gameTitle,
      );

  /// Applies a server `state.patch` (top-level section replace).
  StudioState applyPatch(int patchSeq, String path, Object? value) {
    final m = _map(value);
    switch (path) {
      case 'settings':
        return copyWith(seq: patchSeq, settings: StudioSettings.fromJson(m));
      case 'stage':
        return copyWith(seq: patchSeq, stage: StageLayout.fromJson(m));
      case 'table':
        return copyWith(seq: patchSeq, table: TableState.fromJson(m));
      case 'counts':
        return copyWith(seq: patchSeq, counts: StudioCounts.fromJson(m));
      case 'status':
        return copyWith(seq: patchSeq, status: StudioStatus.fromWire(value));
      case 'title':
        return copyWith(seq: patchSeq, title: _str(value, title));
      case 'gameTitle':
        return copyWith(seq: patchSeq, gameTitle: _gameTitle(value));
      default:
        return copyWith(seq: patchSeq);
    }
  }
}

// ─── Realtime events (LiveKit data topics, ARCHITECTURE §5) ──────────────────

const String kTableScreenTrack = 'table_screen';

class StudioTopics {
  StudioTopics._();
  static const String state = 'studio.state';
  static const String chat = 'chat';
  static const String react = 'react';
  static const String counts = 'counts';
  static const String requests = 'stage.req';
}

/// A decoded data message. Unknown types decode to [UnknownEvent] so newer
/// servers never crash older clients.
sealed class StudioEvent {
  const StudioEvent();

  static StudioEvent decode(String topic, Map<String, dynamic> j) {
    final type = _str(j['type']);
    switch (type) {
      case 'state.patch':
        return StatePatchEvent(_int(j['seq']), _str(j['path']), j['value']);
      case 'state.full':
        return StateFullEvent(StudioState.fromJson(_map(j['state'])));
      case 'comment':
        return CommentEvent(LiveStudioComment.fromJson(j));
      case 'system':
        return SystemLineEvent(LiveStudioComment.fromJson(j));
      case 'comment.deleted':
        return CommentDeletedEvent(_str(j['id']));
      case 'reaction.agg':
        return ReactionAggEvent(
          loves: _int(j['loves']),
          sparkles: _int(j['sparkles']),
          totals: StudioCounts.fromJson(_map(j['totals'])),
        );
      case 'counts':
        return CountsEvent(viewers: _int(j['viewers']), participants: _int(j['participants']));
      case 'request.new':
      case 'request.update':
        return JoinRequestEvent(JoinRequest.fromJson(j));
      default:
        return UnknownEvent(topic, type);
    }
  }
}

class StatePatchEvent extends StudioEvent {
  final int seq;
  final String path;
  final Object? value;
  const StatePatchEvent(this.seq, this.path, this.value);
}

class StateFullEvent extends StudioEvent {
  final StudioState state;
  const StateFullEvent(this.state);
}

class CommentEvent extends StudioEvent {
  final LiveStudioComment comment;
  const CommentEvent(this.comment);
}

class SystemLineEvent extends StudioEvent {
  final LiveStudioComment line;
  const SystemLineEvent(this.line);
}

class CommentDeletedEvent extends StudioEvent {
  final String id;
  const CommentDeletedEvent(this.id);
}

class ReactionAggEvent extends StudioEvent {
  final int loves;
  final int sparkles;
  final StudioCounts totals;
  const ReactionAggEvent({required this.loves, required this.sparkles, required this.totals});
}

class CountsEvent extends StudioEvent {
  final int viewers;
  final int participants;
  const CountsEvent({required this.viewers, required this.participants});
}

class JoinRequestEvent extends StudioEvent {
  final JoinRequest request;
  const JoinRequestEvent(this.request);
}

class UnknownEvent extends StudioEvent {
  final String topic;
  final String type;
  const UnknownEvent(this.topic, this.type);
}

/// A comment or system line in the feed.
@immutable
class LiveStudioComment {
  final String id;
  final String uid;
  final String name;
  final String avatarUrl;
  final String text;

  /// Non-null for system lines.
  final SystemLineKind? system;
  final int ts;

  const LiveStudioComment({
    required this.id,
    required this.uid,
    required this.name,
    this.avatarUrl = '',
    this.text = '',
    this.system,
    required this.ts,
  });

  bool get isSystem => system != null;

  factory LiveStudioComment.fromJson(Map<String, dynamic> j) => LiveStudioComment(
        id: _str(j['id']),
        uid: _str(j['uid']),
        name: _str(j['name']),
        avatarUrl: _str(j['avatarUrl']),
        text: _str(j['text']),
        system: j['kind'] == null ? null : SystemLineKind.fromWire(j['kind']),
        ts: _int(j['ts']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uid': uid,
        'name': name,
        'avatarUrl': avatarUrl,
        'text': text,
        if (system != null) 'kind': system!.wire,
        'ts': ts,
      };
}

// ─── Callable function names (functions/src/liveStudio/*) ────────────────────

class StudioCallables {
  StudioCallables._();
  static const String start = 'lsStart';
  static const String token = 'lsToken';
  static const String end = 'lsEnd';
  static const String comment = 'lsComment';
  static const String deleteComment = 'lsDeleteComment';
  static const String muteChat = 'lsMuteChat';
  static const String react = 'lsReact';
  static const String share = 'lsShare';
  static const String requestJoin = 'lsRequestJoin';
  static const String cancelRequest = 'lsCancelRequest';
  static const String respondRequest = 'lsRespondRequest';
  static const String setLayout = 'lsSetLayout';
  static const String setTable = 'lsSetTable';
  static const String playback = 'lsPlayback';
  static const String setSettings = 'lsSetSettings';
  static const String moderate = 'lsModerate';
  static const String leaveStage = 'lsLeaveStage';
  static const String setOwnMedia = 'lsSetOwnMedia';
  static const String time = 'lsTime';
  static const String stateFull = 'lsStateFull';
}

/// `lsSetLayout` operations.
class LayoutOps {
  LayoutOps._();
  static const String swap = 'swap'; // {index}
  static const String pin = 'pin'; // {uid}
  static const String unpin = 'unpin';
  static const String setMode = 'setMode'; // {mode}
  static const String rotateIn = 'rotateIn'; // {uid, index}
  static const String autoPromote = 'autoPromote'; // {uid} — leader only
}

/// Share link format (ARCHITECTURE Q6).
String studioShareUrl(String streamId) => 'https://mpepe-2b4bd.web.app/live/$streamId';
