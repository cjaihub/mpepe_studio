"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsRecordingDecision = exports.lsBroadcast = exports.lsDestinations = void 0;
exports.stopStreamEgress = stopStreamEgress;
exports.onEgressEnded = onEgressEnded;
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
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const livekit_server_sdk_1 = require("livekit-server-sdk");
const contracts_1 = require("./contracts");
const optionalSecrets_1 = require("../optionalSecrets");
const shared_1 = require("./shared");
const broadcast_logic_1 = require("./broadcast_logic");
/** Bucket recordings upload to (the app's default Storage bucket). */
const recordingBucket = () => process.env.LIVE_RECORDING_BUCKET || 'mpepe-2b4bd.firebasestorage.app';
const RECORDING_KEY_SECRET = 'LIVE_RECORDING_GCS_KEY';
/** Service-account JSON for recording uploads, or null when not configured. */
async function recordingKey() {
    const v = await (0, optionalSecrets_1.optionalSecret)(RECORDING_KEY_SECRET);
    return v && v.startsWith('{') ? v : null;
}
const destRef = (uid) => (0, shared_1.db)().doc(`live_destinations_private/${uid}`);
const recRef = (streamId) => (0, shared_1.db)().doc(`live_recordings/${streamId}`);
function egressClient() {
    const url = shared_1.LIVEKIT_URL.value().replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
    return new livekit_server_sdk_1.EgressClient(url, shared_1.LIVEKIT_API_KEY.value(), shared_1.LIVEKIT_API_SECRET.value());
}
async function destinationsOf(uid) {
    const snap = await destRef(uid).get();
    const items = snap.get('items');
    return Array.isArray(items) ? items : [];
}
exports.lsDestinations = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const data = (req.data && typeof req.data === 'object' ? req.data : {});
    const op = data.op;
    let items = await destinationsOf(uid);
    if (op === 'save') {
        const id = typeof data.id === 'string' && data.id ? data.id : `d${Date.now().toString(36)}`;
        const existing = items.find((d) => d.id === id);
        const raw = Object.assign(Object.assign({}, (existing !== null && existing !== void 0 ? existing : {})), ((_a = data.destination) !== null && _a !== void 0 ? _a : {}));
        // Editing without re-pasting the key keeps the saved one.
        if (existing && (typeof raw.key !== 'string' || !raw.key.trim()))
            raw.key = existing.key;
        let d;
        try {
            d = (0, broadcast_logic_1.parseDestination)(raw, id);
        }
        catch (e) {
            if (e instanceof broadcast_logic_1.BroadcastError)
                throw new https_1.HttpsError('invalid-argument', e.message);
            throw e;
        }
        items = existing ? items.map((x) => (x.id === id ? d : x)) : [...items, d];
        if (items.length > broadcast_logic_1.MAX_DESTINATIONS)
            throw new https_1.HttpsError('failed-precondition', `Up to ${broadcast_logic_1.MAX_DESTINATIONS} destinations.`);
        await destRef(uid).set({ items, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    }
    else if (op === 'delete') {
        items = items.filter((x) => x.id !== data.id);
        await destRef(uid).set({ items, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    }
    else if (op !== 'list') {
        throw new https_1.HttpsError('invalid-argument', 'op must be list, save or delete.');
    }
    return { destinations: items.map(broadcast_logic_1.masked) };
});
/** Stops this stream's egress if one is running. Never throws. */
async function stopStreamEgress(streamId) {
    try {
        const snap = await recRef(streamId).get();
        const egressId = snap.get('egressId');
        if (!egressId || snap.get('status') !== 'active')
            return;
        await egressClient().stopEgress(egressId);
        await recRef(streamId).set({ status: 'stopping', stoppedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    }
    catch (e) {
        console.warn(`[liveStudio] stop egress ${streamId}:`, e.message);
    }
}
exports.lsBroadcast = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a, _b;
    const uid = (0, shared_1.requireUid)(req);
    const data = (req.data && typeof req.data === 'object' ? req.data : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const op = data.op;
    const state = await (0, shared_1.loadState)(streamId);
    await (0, shared_1.requireRole)(streamId, uid, ['host'], state);
    if (op === 'status') {
        const snap = await recRef(streamId).get();
        return { recording: snap.exists ? publicRecording((_a = snap.data()) !== null && _a !== void 0 ? _a : {}) : null };
    }
    if (op === 'stop') {
        await stopStreamEgress(streamId);
        await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ broadcasting: firestore_1.FieldValue.delete() }, { merge: true });
        return { ok: true };
    }
    if (op !== 'start')
        throw new https_1.HttpsError('invalid-argument', 'op must be start, stop or status.');
    (0, shared_1.requireLive)(state);
    await (0, shared_1.rateLimit)(streamId, uid, 'egress', 4, 60000);
    const existing = await recRef(streamId).get();
    if (existing.exists && existing.get('status') === 'active') {
        return { ok: true, recording: publicRecording((_b = existing.data()) !== null && _b !== void 0 ? _b : {}) };
    }
    const record = data.record !== false;
    const frame = (0, broadcast_logic_1.parseFrame)(data.frame);
    const targets = data.restream === false ? [] : (await destinationsOf(uid)).filter((d) => d.enabled);
    if (!record && !targets.length) {
        throw new https_1.HttpsError('failed-precondition', 'Turn on recording or add a platform in Live destinations.');
    }
    const path = (0, broadcast_logic_1.recordingPath)(state.hostId, streamId);
    const outputs = {};
    if (record) {
        const key = await recordingKey();
        if (!key) {
            throw new https_1.HttpsError('failed-precondition', 'Recording storage is not configured yet.');
        }
        outputs.file = new livekit_server_sdk_1.EncodedFileOutput({
            fileType: livekit_server_sdk_1.EncodedFileType.MP4,
            filepath: path,
            output: { case: 'gcp', value: new livekit_server_sdk_1.GCPUpload({ credentials: key, bucket: recordingBucket() }) },
        });
    }
    if (targets.length) {
        outputs.stream = new livekit_server_sdk_1.StreamOutput({ protocol: livekit_server_sdk_1.StreamProtocol.RTMP, urls: targets.map(broadcast_logic_1.ingestUrl) });
    }
    let egressId;
    try {
        const info = await egressClient().startRoomCompositeEgress((0, shared_1.roomName)(streamId), outputs, {
            // LiveKit's built-in speaker layout: stage video + mixed audio only.
            // The app's comments, likes and reactions are client overlays, so
            // they are never in the recording or the restream.
            layout: 'speaker',
            encodingOptions: frame === 'portrait' ? livekit_server_sdk_1.EncodingOptionsPreset.PORTRAIT_H264_1080P_30 : livekit_server_sdk_1.EncodingOptionsPreset.H264_1080P_30,
        });
        egressId = info.egressId;
    }
    catch (e) {
        console.error('[liveStudio] start egress failed:', e.message);
        throw new https_1.HttpsError('unavailable', 'Could not start recording / restream. Try again.');
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
        startedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).set({ broadcasting: { recording: record, platforms } }, { merge: true });
    return { ok: true, recording: { status: 'active', record, frame, platforms } };
});
function publicRecording(d) {
    var _a, _b, _c, _d, _e;
    return {
        status: (_a = d.status) !== null && _a !== void 0 ? _a : null,
        record: d.record === true,
        frame: (_b = d.frame) !== null && _b !== void 0 ? _b : 'portrait',
        platforms: Array.isArray(d.platforms) ? d.platforms : [],
        durationMs: typeof d.durationMs === 'number' ? d.durationMs : null,
        sizeBytes: typeof d.sizeBytes === 'number' ? d.sizeBytes : null,
        decision: (_c = d.decision) !== null && _c !== void 0 ? _c : null,
        path: d.decision === 'kept' ? (_d = d.path) !== null && _d !== void 0 ? _d : null : null,
        error: (_e = d.error) !== null && _e !== void 0 ? _e : null,
    };
}
/** LiveKit webhook: egress finished → record the file result. */
async function onEgressEnded(info) {
    var _a;
    const q = await (0, shared_1.db)().collection('live_recordings').where('egressId', '==', info.egressId).limit(1).get();
    const doc = q.docs[0];
    if (!doc)
        return;
    const f = (_a = info.fileResults) === null || _a === void 0 ? void 0 : _a[0];
    const ok = info.status === 3; // EGRESS_COMPLETE
    await doc.ref.set({
        status: ok ? 'ready' : 'failed',
        error: ok ? null : info.error || 'Recording failed',
        durationMs: (f === null || f === void 0 ? void 0 : f.duration) ? Math.round(Number(f.duration) / 1000000) : null,
        sizeBytes: (f === null || f === void 0 ? void 0 : f.size) ? Number(f.size) : null,
        endedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
}
exports.lsRecordingDecision = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    const uid = (0, shared_1.requireUid)(req);
    const data = (req.data && typeof req.data === 'object' ? req.data : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    if (typeof data.keep !== 'boolean')
        throw new https_1.HttpsError('invalid-argument', 'keep must be true or false.');
    const snap = await recRef(streamId).get();
    if (!snap.exists || snap.get('hostId') !== uid)
        throw new https_1.HttpsError('not-found', 'No recording for this live.');
    const path = snap.get('path');
    if (!path)
        throw new https_1.HttpsError('failed-precondition', 'This live was not recorded.');
    if (data.keep) {
        const title = (_a = (await (0, shared_1.db)().doc(`${contracts_1.Paths.streams}/${streamId}`).get()).get('title')) !== null && _a !== void 0 ? _a : 'Live';
        await (0, shared_1.db)().doc(`users/${uid}/live_recordings/${streamId}`).set({
            streamId,
            title,
            storagePath: path,
            durationMs: (_b = snap.get('durationMs')) !== null && _b !== void 0 ? _b : null,
            sizeBytes: (_c = snap.get('sizeBytes')) !== null && _c !== void 0 ? _c : null,
            frame: (_d = snap.get('frame')) !== null && _d !== void 0 ? _d : 'portrait',
            savedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        await snap.ref.set({ decision: 'kept' }, { merge: true });
        return { ok: true, kept: true, storagePath: path };
    }
    try {
        await (0, storage_1.getStorage)().bucket(recordingBucket()).file(path).delete({ ignoreNotFound: true });
    }
    catch (e) {
        console.warn(`[liveStudio] delete recording ${streamId}:`, e.message);
    }
    await (0, shared_1.db)().doc(`users/${uid}/live_recordings/${streamId}`).delete();
    await snap.ref.set({ decision: 'discarded', path: null }, { merge: true });
    return { ok: true, kept: false };
});
//# sourceMappingURL=broadcast.js.map