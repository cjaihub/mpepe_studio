/**
 * LIVE STUDIO v2 — recording + restreaming rules (pure).
 * The host's stream destinations (RTMP URL + key from Facebook, YouTube,
 * TikTok, Twitch…) and recording options; see broadcast.ts.
 */

export const DESTINATION_PLATFORMS = ['facebook', 'youtube', 'tiktok', 'twitch', 'instagram', 'kick', 'custom'] as const;
export type DestinationPlatform = (typeof DESTINATION_PLATFORMS)[number];
export const MAX_DESTINATIONS = 6;

/** Default ingest servers (the host still pastes their own stream key). */
export const DEFAULT_INGEST: Partial<Record<DestinationPlatform, string>> = {
  facebook: 'rtmps://live-api-s.facebook.com:443/rtmp/',
  youtube: 'rtmp://a.rtmp.youtube.com/live2',
  twitch: 'rtmp://live.twitch.tv/app',
};

export interface Destination {
  id: string;
  platform: DestinationPlatform;
  label: string;
  url: string; // rtmp(s)://host/app
  key: string; // stream key (secret)
  enabled: boolean;
}

export type RecordingFrame = 'portrait' | 'landscape';

export class BroadcastError extends Error {}

const CONTROL = /[\u0000-\u001f\u007f\s]/;

export function parseDestination(raw: unknown, id: string): Destination {
  const d = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const platform = (DESTINATION_PLATFORMS as readonly string[]).includes(d.platform as string)
    ? (d.platform as DestinationPlatform)
    : null;
  if (!platform) throw new BroadcastError('Pick a platform.');
  const url = (typeof d.url === 'string' && d.url.trim() ? d.url.trim() : DEFAULT_INGEST[platform] ?? '').replace(/\/+$/, '');
  if (!/^rtmps?:\/\/[a-z0-9.-]+(:\d{2,5})?(\/\S*)?$/i.test(url) || url.length > 300) {
    throw new BroadcastError('Server URL must start with rtmp:// or rtmps://');
  }
  const key = typeof d.key === 'string' ? d.key.trim() : '';
  if (!key || key.length > 300 || CONTROL.test(key)) throw new BroadcastError('Paste the stream key from the platform.');
  const label = typeof d.label === 'string' && d.label.trim() ? d.label.trim().slice(0, 40) : platform[0].toUpperCase() + platform.slice(1);
  return { id, platform, label, url, key, enabled: d.enabled !== false };
}

/** Full ingest URL LiveKit pushes to. */
export const ingestUrl = (d: Destination) => `${d.url}/${d.key}`;

/** What the app may see: never the key, only its last 4 characters. */
export function masked(d: Destination) {
  return { id: d.id, platform: d.platform, label: d.label, url: d.url, keyHint: `••••${d.key.slice(-4)}`, enabled: d.enabled };
}

export const recordingPath = (hostId: string, streamId: string) => `users/${hostId}/files/live_recordings/${streamId}.mp4`;

export const parseFrame = (v: unknown): RecordingFrame => (v === 'landscape' ? 'landscape' : 'portrait');
