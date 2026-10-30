"use strict";
/**
 * LIVE STUDIO v2 — shared contracts (integrator-owned).
 * Mirror of lib/backend/live_studio/contracts/studio_contracts.dart.
 * See docs/live-studio/ARCHITECTURE.md §4–§6. Keep both files in sync.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.shareUrl = exports.emptyStage = exports.TABLE_SCREEN_TRACK = exports.Topics = exports.defaultSettings = exports.ACCENT_PALETTE = exports.FRAME_COLOR_OPTIONS = exports.canPublish = exports.isManager = exports.GAME_TITLE_MAX_LENGTH = exports.LAYOUT_PRESETS = exports.Limits = exports.Paths = exports.SCHEMA_VERSION = void 0;
exports.SCHEMA_VERSION = 1;
exports.Paths = {
    streams: 'live_streams',
    state: (id) => `live_streams/${id}/studio/state`,
    members: (id) => `live_streams/${id}/members`,
    comments: (id) => `live_streams/${id}/studio_comments`,
    requests: (id) => `live_streams/${id}/studio_requests`,
    counters: (id) => `live_streams/${id}/studio_counters`,
    rate: (id) => `live_streams/${id}/studio_rate`,
    blocks: (id) => `live_streams/${id}/studio_blocks`,
    hostSettings: (hostId) => `users/${hostId}/live_studio/settings`,
    watchCatalog: 'live_watch_catalog',
};
exports.Limits = {
    wallSlots: 6,
    phoneWallSlots: 4,
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
};
exports.LAYOUT_PRESETS = ['studio', 'gaming'];
exports.GAME_TITLE_MAX_LENGTH = 60;
const isManager = (r) => r === 'host' || r === 'coHost';
exports.isManager = isManager;
const canPublish = (r) => r !== 'viewer';
exports.canPublish = canPublish;
exports.FRAME_COLOR_OPTIONS = {
    dark: ['#15151B', '#2A3550', '#2F7BFF', '#FF2D75'],
    light: ['#3B4763', '#8C97AE', '#2F7BFF', '#FF2D75'],
};
exports.ACCENT_PALETTE = ['#FF2D75', '#22C3D6', '#8B5CF6', '#FF6FA3', '#3D8BFF', '#FFB547', '#2DD4BF'];
const defaultSettings = (theme = 'dark') => ({
    studioId: 'broadcast_curved_wall',
    theme,
    frameWidth: exports.Limits.frameWidthDefault,
    frameColor: theme === 'light' ? '#3B4763' : '#15151B',
    guestSize: 'm',
    showNames: true,
    studioDim: theme === 'light' ? 0 : 0.15,
    speakerMode: 'hostPinned',
    layoutPreset: 'studio',
});
exports.defaultSettings = defaultSettings;
exports.Topics = {
    state: 'studio.state',
    chat: 'chat',
    react: 'react',
    counts: 'counts',
    requests: 'stage.req',
};
exports.TABLE_SCREEN_TRACK = 'table_screen';
const emptyStage = (centerUid) => ({
    centerUid,
    wall: Array(exports.Limits.wallSlots).fill(null),
    overflow: [],
    pinnedUid: null,
    updatedAtMs: 0,
    updatedBy: '',
});
exports.emptyStage = emptyStage;
const shareUrl = (streamId) => `https://mpepe-2b4bd.web.app/live/${streamId}`;
exports.shareUrl = shareUrl;
//# sourceMappingURL=contracts.js.map