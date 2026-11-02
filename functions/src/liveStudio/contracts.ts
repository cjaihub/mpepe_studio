/**
 * LIVE STUDIO v2 — shared contracts (integrator-owned).
 * Mirror of lib/backend/live_studio/contracts/studio_contracts.dart.
 * See docs/live-studio/ARCHITECTURE.md §4–§6. Keep both files in sync.
 */

export const SCHEMA_VERSION = 1;

export const Paths = {
  streams: 'live_streams',
  state: (id: string) => `live_streams/${id}/studio/state`,
  members: (id: string) => `live_streams/${id}/members`,
  comments: (id: string) => `live_streams/${id}/studio_comments`,
  requests: (id: string) => `live_streams/${id}/studio_requests`,
  counters: (id: string) => `live_streams/${id}/studio_counters`,
  rate: (id: string) => `live_streams/${id}/studio_rate`,
  blocks: (id: string) => `live_streams/${id}/studio_blocks`,
  hostSettings: (hostId: string) => `users/${hostId}/live_studio/settings`,
  watchCatalog: 'live_watch_catalog',
} as const;

export const Limits = {
  wallSlots: 6,
  phoneWallSlots: 4,
  /** Most people on the stage panel at once, host included. */
  maxOnStage: 10,
  speakToTakeCenterMs: 1500,
  minCenterHoldMs: 4000,
  leaderFailoverMs: 10000,
  maxDriftMs: 300,
  commentMaxLength: 200,
  commentMinIntervalMs: 2000,
  commentsPerMinute: 20,
  commentBroadcastPerSecond: 25,
  commentHistory: 50,
  reactionMaxPerCall: 10,
  reactionCallsPerSecond: 5,
  reactionAggregateWindowMs: 500,
  countsIntervalMs: 2000,
  frameWidthMin: 0,
  frameWidthMax: 12,
  frameWidthDefault: 4,
  studioDimMin: 0,
  studioDimMax: 0.6,
} as const;

export type StudioRole = 'host' | 'coHost' | 'guest' | 'viewer';
export type StudioStatus = 'preparing' | 'live' | 'ended';
export type StudioTheme = 'dark' | 'light';
export type GuestSize = 's' | 'm' | 'l';
export type SpeakerMode = 'hostPinned' | 'autoActiveSpeaker' | 'manual';
export type TableMode = 'goods' | 'screen' | 'match' | 'movie';
export type PlaybackState = 'playing' | 'paused' | 'ended';
export type GoodsSource = 'biz' | 'stream';
export type JoinRequestStatus = 'pending' | 'approved' | 'declined' | 'cancelled';
export type SystemLineKind = 'joined' | 'love' | 'sparkles' | 'shared' | 'requested' | 'onStage';
export type ReactionKind = 'love' | 'sparkles';
export type ModerationAction = 'mute' | 'removeFromStage' | 'block';
/** `gaming` = host screen share in the center, host camera in a PiP bubble. */
export type LayoutPreset = 'studio' | 'gaming';
export const LAYOUT_PRESETS: readonly LayoutPreset[] = ['studio', 'gaming'];
export const GAME_TITLE_MAX_LENGTH = 60;

export const isManager = (r: StudioRole) => r === 'host' || r === 'coHost';
export const canPublish = (r: StudioRole) => r !== 'viewer';

export const FRAME_COLOR_OPTIONS: Record<StudioTheme, string[]> = {
  dark: ['#15151B', '#2A3550', '#2F7BFF', '#FF2D75'],
  light: ['#3B4763', '#8C97AE', '#2F7BFF', '#FF2D75'],
};

export const ACCENT_PALETTE = ['#FF2D75', '#22C3D6', '#8B5CF6', '#FF6FA3', '#3D8BFF', '#FFB547', '#2DD4BF'];

export interface StudioSettings {
  studioId: string;
  theme: StudioTheme;
  frameWidth: number;
  frameColor: string;
  guestSize: GuestSize;
  showNames: boolean;
  studioDim: number;
  speakerMode: SpeakerMode;
  layoutPreset: LayoutPreset;
}

export const defaultSettings = (theme: StudioTheme = 'dark'): StudioSettings => ({
  studioId: 'broadcast_curved_wall',
  theme,
  frameWidth: Limits.frameWidthDefault,
  frameColor: theme === 'light' ? '#3B4763' : '#15151B',
  guestSize: 'm',
  showNames: true,
  studioDim: theme === 'light' ? 0 : 0.15,
  speakerMode: 'hostPinned',
  layoutPreset: 'studio',
});

export interface StageLayout {
  centerUid: string;
  /** Always Limits.wallSlots long; null = empty. */
  wall: (string | null)[];
  overflow: string[];
  pinnedUid: string | null;
  updatedAtMs: number;
  updatedBy: string;
}

export interface GoodsRef { source: GoodsSource; productId: string; }
export interface ScreenRef { publisherUid: string; trackName: string; }
export interface WatchParty {
  catalogId: string;
  state: PlaybackState;
  positionMs: number;
  rate: number;
  anchorServerMs: number;
}
export interface TableState {
  mode: TableMode;
  goods: GoodsRef | null;
  screen: ScreenRef | null;
  watch: WatchParty | null;
}

export interface StudioCounts {
  viewers: number;
  participants: number;
  loves: number;
  sparkles: number;
  shares: number;
}

export interface StudioState {
  schemaVersion: number;
  streamId: string;
  hostId: string;
  title: string;
  status: StudioStatus;
  seq: number;
  settings: StudioSettings;
  stage: StageLayout;
  table: TableState;
  counts: StudioCounts;
  /** Game being streamed on a gaming live (≤ GAME_TITLE_MAX_LENGTH). Absent otherwise. */
  gameTitle?: string;
}

export interface StageMember {
  uid: string;
  displayName: string;
  avatarUrl: string;
  accent: string;
  role: StudioRole;
  micOn: boolean;
  camOn: boolean;
  chatMuted: boolean;
  joinedAtMs: number;
}

export interface JoinRequest {
  uid: string;
  displayName: string;
  avatarUrl: string;
  status: JoinRequestStatus;
  requestedAtMs: number;
}

export interface StudioComment {
  id: string;
  uid: string;
  name: string;
  avatarUrl: string;
  text: string;
  kind?: SystemLineKind;
  ts: number;
}

export const Topics = {
  state: 'studio.state',
  chat: 'chat',
  react: 'react',
  counts: 'counts',
  requests: 'stage.req',
  pool: 'studio.pool',
} as const;

export type StudioEvent =
  | { v: 1; type: 'state.patch'; seq: number; path: keyof StudioState | string; value: unknown; ts: number }
  | { v: 1; type: 'state.full'; state: StudioState; ts: number }
  | ({ v: 1; type: 'comment' } & StudioComment)
  | ({ v: 1; type: 'system' } & StudioComment)
  | { v: 1; type: 'comment.deleted'; id: string; ts: number }
  | { v: 1; type: 'reaction.agg'; loves: number; sparkles: number; totals: StudioCounts; ts: number }
  | { v: 1; type: 'counts'; viewers: number; participants: number; ts: number }
  | ({ v: 1; type: 'request.new' | 'request.update' } & JoinRequest & { ts: number })
  | { v: 1; type: `pool.${string}`; [key: string]: unknown };

export const TABLE_SCREEN_TRACK = 'table_screen';

export const emptyStage = (centerUid: string): StageLayout => ({
  centerUid,
  wall: Array(Limits.wallSlots).fill(null),
  overflow: [],
  pinnedUid: null,
  updatedAtMs: 0,
  updatedBy: '',
});

export const shareUrl = (streamId: string) => `https://oneova.web.app/live/${streamId}`;
