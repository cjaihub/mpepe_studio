/**
 * LIVE STUDIO v2 — recording + restreaming (LiveKit room-composite egress).
 *
 *   lsDestinations({op: list|save|delete, destination?, id?})
 *       The host's RTMP destinations (Facebook, YouTube, TikTok, Twitch…).
 *       Stream keys live in `live_destinations_private/{uid}` (no client
 *       access); the app only ever sees a masked hint.
 *   lsBroadcast({streamId, op: start|stop|status, record?, restream?, frame?})
 *       Host only. One egress renders the stage video + audio at 1080p
 *       (portrait 1080×1920 or landscape 1920×1080) WITHOUT the app's
 *       comments / likes overlays, records it to Storage and/or pushes it to
 *       every enabled destination in real time.
 *   lsRecordingDecision({streamId, keep})
 *       After the live: keep the MP4 in the host's library or delete it.
 *
 * Recordings upload with a service-account JSON kept in Secret Manager as
 * `LIVE_RECORDING_GCS_KEY` (LiveKit Cloud needs explicit storage
 * credentials). It is read at runtime with the function's own identity, so a
 * missing key only disables recording and never blocks a deploy.
 * Pure rules: broadcast_logic.ts.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineString } from 'firebase-functions/params';
import { FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import {
  EgressClient,
  EncodedFileOutput,
  EncodedFileType,
  EncodingOptionsPreset,
  GCPUpload,
  StreamOutput,
  StreamProtocol,
} from 'livekit-server-sdk';
import { Paths } from './contracts';
import { optionalSecret } from '../optionalSecrets';
import {
  LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET,
  LIVEKIT_SECRETS,
  LIVEKIT_URL,
  db,
  loadState,
  rateLimit,
  requireLive,
  requireRole,
  requireString,
  requireUid,
  roomName,
} from './shared';
import {
  BroadcastError,
  Destination,
  MAX_DESTINATIONS,
  ingestUrl,
  masked,
  parseDestination,
  parseFrame,
  recordingPath,
} from './broadcast_logic';

export const LIVE_RECORDING_BUCKET = defineString('LIVE_RECORDING_BUCKET', { default: 'mpepe-2b4bd.firebasestorage.app' });
const RECORDING_KEY_SECRET = 'LIVE_RECORDING_GCS_KEY';

/** Service-account JSON for recording uploads, or null when not configured. */
async function recordingKey(): Promise<string | null> {
  const v = await optionalSecret(RECORDING_KEY_SECRET);
  return v && v.startsWith('{') ? v : null;
}

const destRef = (uid: string) => db().doc(`live_destinations_private/${uid}`);
const recRef = (streamId: string) => db().doc(`live_recordings/${streamId}`);

function egressClient(): EgressClient {
  const url = LIVEKIT_URL.value().replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
  return new EgressClient(url, LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
}

async function destinationsOf(uid: string): Promise<Destination[]> {
  const snap = await destRef(uid).get();
  const items = snap.get('items');
  return Array.isArray(items) ? (items as Destination[]) : [];
}

export const lsDestinations = onCall(async (req) => {
  const uid = requireUid(req);
  const data = (req.data && typeof req.data === 'object' ? req.data : {}) as Record<string, unknown>;
  const op = data.op;
  let items = await destinationsOf(uid);
  if (op === 'save') {
    const id = typeof data.id === 'string' && data.id ? data.id : `d${Date.now().toString(36)}`;
    const existing = items.find((d) => d.id === id);
    const raw = { ...(existing ?? {}), ...((data.destination as Record<string, unknown>) ?? {}) };
    // Editing without re-pasting the key keeps the saved one.
    if (existing && (typeof raw.key !== 'string' || !raw.key.trim())) raw.key = existing.key;
    let d: Destination;
    try {
      d = parseDestination(raw, id);
    } catch (e) {
      if (e instanceof BroadcastError) throw new HttpsError('invalid-argument', e.message);
      throw e;
    }
    items = existing ? items.map((x) => (x.id === id ? d : x)) : [...items, d];
    if (items.length > MAX_DESTINATIONS) throw new HttpsError('failed-precondition', `Up to ${MAX_DESTINATIONS} destinations.`);
    await destRef(uid).set({ items, updatedAt: FieldValue.serverTimestamp() });
  } else if (op === 'delete') {
    items = items.filter((x) => x.id !== data.id);
    await destRef(uid).set({ items, updatedAt: FieldValue.serverTimestamp() });
  } else if (op !== 'list') {
    throw new HttpsError('invalid-argument', 'op must be list, save or delete.');
  }
  return { destinations: items.map(masked) };
});

/** Stops this stream's egress if one is running. Never throws. */
export async function stopStreamEgress(streamId: string): Promise<void> {
  try {
    const snap = await recRef(streamId).get();
    const egressId = snap.get('egressId') as string | undefined;
    if (!egressId || snap.get('status') !== 'active') return;
    await egressClient().stopEgress(egressId);
    await recRef(streamId).set({ status: 'stopping', stoppedAt: FieldValue.serverTimestamp() }, { merge: true });
  } catch (e) {
    console.warn(`[liveStudio] stop egress ${streamId}:`, (e as Error).message);
  }
}

export const lsBroadcast = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = (req.data && typeof req.data === 'object' ? req.data : {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  const op = data.op;
  const state = await loadState(streamId);
  await requireRole(streamId, uid, ['host'], state);

  if (op === 'status') {
    const snap = await recRef(streamId).get();
    return { recording: snap.exists ? publicRecording(snap.data() ?? {}) : null };
  }
  if (op === 'stop') {
    await stopStreamEgress(streamId);
    await db().doc(`${Paths.streams}/${streamId}`).set({ broadcasting: FieldValue.delete() }, { merge: true });
    return { ok: true };
  }
  if (op !== 'start') throw new HttpsError('invalid-argument', 'op must be start, stop or status.');

  requireLive(state);
  await rateLimit(streamId, uid, 'egress', 4, 60_000);
  const existing = await recRef(streamId).get();
  if (existing.exists && existing.get('status') === 'active') {
    return { ok: true, recording: publicRecording(existing.data() ?? {}) };
  }
  const record = data.record !== false;
  const frame = parseFrame(data.frame);
  const targets = data.restream === false ? [] : (await destinationsOf(uid)).filter((d) => d.enabled);
  if (!record && !targets.length) {
    throw new HttpsError('failed-precondition', 'Turn on recording or add a platform in Live destinations.');
  }

  const path = recordingPath(state.hostId, streamId);
  const outputs: { file?: EncodedFileOutput; stream?: StreamOutput } = {};
  if (record) {
    const key = await recordingKey();
    if (!key) {
      throw new HttpsError('failed-precondition', 'Recording storage is not configured yet.');
    }
    outputs.file = new EncodedFileOutput({
      fileType: EncodedFileType.MP4,
      filepath: path,
      output: { case: 'gcp', value: new GCPUpload({ credentials: key, bucket: LIVE_RECORDING_BUCKET.value() }) },
    });
  }
  if (targets.length) {
    outputs.stream = new StreamOutput({ protocol: StreamProtocol.RTMP, urls: targets.map(ingestUrl) });
  }

  let egressId: string;
  try {
    const info = await egressClient().startRoomCompositeEgress(roomName(streamId), outputs, {
      // LiveKit's built-in speaker layout: stage video + mixed audio only.
      // The app's comments, likes and reactions are client overlays, so
      // they are never in the recording or the restream.
      layout: 'speaker',
      encodingOptions:
        frame === 'portrait' ? EncodingOptionsPreset.PORTRAIT_H264_1080P_30 : EncodingOptionsPreset.H264_1080P_30,
    });
    egressId = info.egressId;
  } catch (e) {
    console.error('[liveStudio] start egress failed:', (e as Error).message);
    throw new HttpsError('unavailable', 'Could not start recording / restream. Try again.');
  }

  const platforms = targets.map((t) => t.platform);
  await recRef(streamId).set({
    streamId,
    hostId: state.hostId,
    egressId,
    status: 'active',
    record,
    frame,
    path: record ? path : null,
    platforms,
    startedAt: FieldValue.serverTimestamp(),
  });
  await db().doc(`${Paths.streams}/${streamId}`).set({ broadcasting: { recording: record, platforms } }, { merge: true });
  return { ok: true, recording: { status: 'active', record, frame, platforms } };
});

function publicRecording(d: Record<string, unknown>) {
  return {
    status: d.status ?? null,
    record: d.record === true,
    frame: d.frame ?? 'portrait',
    platforms: Array.isArray(d.platforms) ? d.platforms : [],
    durationMs: typeof d.durationMs === 'number' ? d.durationMs : null,
    sizeBytes: typeof d.sizeBytes === 'number' ? d.sizeBytes : null,
    decision: d.decision ?? null,
    path: d.decision === 'kept' ? d.path ?? null : null,
    error: d.error ?? null,
  };
}

/** LiveKit webhook: egress finished → record the file result. */
export async function onEgressEnded(info: {
  egressId: string;
  roomName: string;
  status: number;
  error?: string;
  fileResults?: { duration?: bigint; size?: bigint; filename?: string }[];
}): Promise<void> {
  const q = await db().collection('live_recordings').where('egressId', '==', info.egressId).limit(1).get();
  const doc = q.docs[0];
  if (!doc) return;
  const f = info.fileResults?.[0];
  const ok = info.status === 3; // EGRESS_COMPLETE
  await doc.ref.set(
    {
      status: ok ? 'ready' : 'failed',
      error: ok ? null : info.error || 'Recording failed',
      durationMs: f?.duration ? Math.round(Number(f.duration) / 1_000_000) : null,
      sizeBytes: f?.size ? Number(f.size) : null,
      endedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export const lsRecordingDecision = onCall(async (req) => {
  const uid = requireUid(req);
  const data = (req.data && typeof req.data === 'object' ? req.data : {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  if (typeof data.keep !== 'boolean') throw new HttpsError('invalid-argument', 'keep must be true or false.');
  const snap = await recRef(streamId).get();
  if (!snap.exists || snap.get('hostId') !== uid) throw new HttpsError('not-found', 'No recording for this live.');
  const path = snap.get('path') as string | null;
  if (!path) throw new HttpsError('failed-precondition', 'This live was not recorded.');
  if (data.keep) {
    const title = ((await db().doc(`${Paths.streams}/${streamId}`).get()).get('title') as string) ?? 'Live';
    await db().doc(`users/${uid}/live_recordings/${streamId}`).set({
      streamId,
      title,
      storagePath: path,
      durationMs: snap.get('durationMs') ?? null,
      sizeBytes: snap.get('sizeBytes') ?? null,
      frame: snap.get('frame') ?? 'portrait',
      savedAt: FieldValue.serverTimestamp(),
    });
    await snap.ref.set({ decision: 'kept' }, { merge: true });
    return { ok: true, kept: true, storagePath: path };
  }
  try {
    await getStorage().bucket(LIVE_RECORDING_BUCKET.value()).file(path).delete({ ignoreNotFound: true });
  } catch (e) {
    console.warn(`[liveStudio] delete recording ${streamId}:`, (e as Error).message);
  }
  await db().doc(`users/${uid}/live_recordings/${streamId}`).delete();
  await snap.ref.set({ decision: 'discarded', path: null }, { merge: true });
  return { ok: true, kept: false };
});
