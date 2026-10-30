"use strict";
/**
 * LIVE STUDIO v2 — recording + restreaming rules (pure).
 * The host's stream destinations (RTMP URL + key from Facebook, YouTube,
 * TikTok, Twitch…) and recording options; see broadcast.ts.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseFrame = exports.recordingPath = exports.ingestUrl = exports.BroadcastError = exports.DEFAULT_INGEST = exports.MAX_DESTINATIONS = exports.DESTINATION_PLATFORMS = void 0;
exports.parseDestination = parseDestination;
exports.masked = masked;
exports.DESTINATION_PLATFORMS = ['facebook', 'youtube', 'tiktok', 'twitch', 'instagram', 'kick', 'custom'];
exports.MAX_DESTINATIONS = 6;
/** Default ingest servers (the host still pastes their own stream key). */
exports.DEFAULT_INGEST = {
    facebook: 'rtmps://live-api-s.facebook.com:443/rtmp/',
    youtube: 'rtmp://a.rtmp.youtube.com/live2',
    twitch: 'rtmp://live.twitch.tv/app',
};
class BroadcastError extends Error {
}
exports.BroadcastError = BroadcastError;
const CONTROL = /[\u0000-\u001f\u007f\s]/;
function parseDestination(raw, id) {
    var _a;
    const d = (raw && typeof raw === 'object' ? raw : {});
    const platform = exports.DESTINATION_PLATFORMS.includes(d.platform)
        ? d.platform
        : null;
    if (!platform)
        throw new BroadcastError('Pick a platform.');
    const url = (typeof d.url === 'string' && d.url.trim() ? d.url.trim() : (_a = exports.DEFAULT_INGEST[platform]) !== null && _a !== void 0 ? _a : '').replace(/\/+$/, '');
    if (!/^rtmps?:\/\/[a-z0-9.-]+(:\d{2,5})?(\/\S*)?$/i.test(url) || url.length > 300) {
        throw new BroadcastError('Server URL must start with rtmp:// or rtmps://');
    }
    const key = typeof d.key === 'string' ? d.key.trim() : '';
    if (!key || key.length > 300 || CONTROL.test(key))
        throw new BroadcastError('Paste the stream key from the platform.');
    const label = typeof d.label === 'string' && d.label.trim() ? d.label.trim().slice(0, 40) : platform[0].toUpperCase() + platform.slice(1);
    return { id, platform, label, url, key, enabled: d.enabled !== false };
}
/** Full ingest URL LiveKit pushes to. */
const ingestUrl = (d) => `${d.url}/${d.key}`;
exports.ingestUrl = ingestUrl;
/** What the app may see: never the key, only its last 4 characters. */
function masked(d) {
    return { id: d.id, platform: d.platform, label: d.label, url: d.url, keyHint: `••••${d.key.slice(-4)}`, enabled: d.enabled };
}
const recordingPath = (hostId, streamId) => `users/${hostId}/files/live_recordings/${streamId}.mp4`;
exports.recordingPath = recordingPath;
const parseFrame = (v) => (v === 'landscape' ? 'landscape' : 'portrait');
exports.parseFrame = parseFrame;
//# sourceMappingURL=broadcast_logic.js.map