"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.STUDIO_DETECTORS = exports.lsMediaKey = exports.lsSecOnMemberWrite = exports.lsSecOnBlock = exports.lsSecOnIncident = exports.SecPaths = exports.LIVE_STUDIO_E2EE = void 0;
exports.recordStudioSignal = recordStudioSignal;
exports.noteStudioDenial = noteStudioDenial;
exports.withStudioSecurity = withStudioSecurity;
exports.recordTokenSignal = recordTokenSignal;
exports.runLiveHealthMonitor = runLiveHealthMonitor;
exports.studioE2eeEnabled = studioE2eeEnabled;
exports.mediaKeyForToken = mediaKeyForToken;
exports.rotateStudioMediaKey = rotateStudioMediaKey;
/**
 * LIVE STUDIO v2 — security (security workstream).
 *
 *  - `recordStudioSignal()` / `noteStudioDenial()`: attack detection. Other
 *    modules report signals; detectors in security_logic.ts turn them into
 *    incidents at `live_streams/{id}/studio_security/{incidentId}`
 *    (function-only writes). Critical per-account incidents are forwarded to
 *    the existing Ova Guard (`recordSecurityEvent` in ../security.ts).
 *  - `lsSecOnIncident`: AI live-health monitor. On a new warn/critical
 *    incident, at most once per 60 s per stream, it asks Gemini (same
 *    Vertex AI client as the AI gateway / guardExplainEvent)
 *    for a short assessment and 1–3 actions from a FIXED allow-list, validates
 *    the answer strictly and falls back to rules. The advisory goes to the
 *    host and co-hosts only (topic `security`) and is persisted.
 *  - Media E2EE keys: `mediaKeyForToken()` (used by lsStart / lsToken),
 *    `lsMediaKey` (refetch after rotation), and rotation triggers on blocks
 *    and stage removals. See the WHAT E2EE PROTECTS note in security_logic.ts.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const params_1 = require("firebase-functions/params");
const auth_1 = require("firebase-admin/auth");
const firestore_2 = require("firebase-admin/firestore");
const vertexAi_1 = require("../vertexAi");
const contracts_1 = require("./contracts");
const shared = __importStar(require("./shared"));
const shared_1 = require("./shared");
const security_logic_1 = require("./security_logic");
/** Server switch for media E2EE (default on). `LIVE_STUDIO_E2EE=false` turns it off. */
exports.LIVE_STUDIO_E2EE = (0, params_1.defineString)('LIVE_STUDIO_E2EE', { default: 'true' });
/**
 * The AI part of the live-health monitor is opt-in per deployment: set
 * LIVE_STUDIO_AI_MONITOR=true in functions/.env.<project> (Gemini runs on
 * Vertex AI as the function's service account, so no key is needed).
 * Without it the monitor still runs with the rule-based advice
 * (fallbackAdvice), using the same action allow-list.
 */
const AI_MONITOR = process.env.LIVE_STUDIO_AI_MONITOR === 'true';
const MONITOR_SECRETS = [...shared_1.LIVEKIT_SECRETS];
/**
 * The Ova Guard module (../security.ts) defines its own secrets at load time,
 * so it is loaded lazily, only when a critical incident is forwarded.
 */
async function forwardToGuard(uid, type, details) {
    const guard = await Promise.resolve().then(() => __importStar(require('../security')));
    await guard.recordSecurityEvent(uid, type, { details });
}
exports.SecPaths = {
    incidents: (id) => `live_streams/${id}/studio_security`,
    advisories: (id) => `live_streams/${id}/studio_security_advisories`,
    counters: (id) => `live_streams/${id}/studio_security_counters`,
    mediaKey: (id) => `live_streams/${id}/studio_secrets/media_key`,
    account: (uid) => `studio_security_uid/${uid}`,
};
const warn = (what, e) => { var _a; return console.warn(`[liveStudio.security] ${what}:`, (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e); };
// ─── Attack detection ──────────────────────────────────────────────────────
/** Per-instance throttle for stream-wide evaluations (reads are the cost). */
const lastStreamEval = new Map();
const STREAM_EVAL_EVERY_MS = 2000;
/**
 * Reports one security-relevant signal. Never throws and never blocks the
 * caller's decision: detection is best effort, enforcement stays with the
 * callables. Safe to call from any ls* callable.
 */
async function recordStudioSignal(streamId, uid, kind, detail = {}) {
    if (!streamId || !uid)
        return;
    const now = Date.now();
    await Promise.all((0, security_logic_1.detectorsFor)(kind, detail).map((spec) => evaluate(spec, streamId, uid, detail, now).catch((e) => warn(`detector ${spec.id}`, e))));
}
/**
 * Hook for shared.ts: call when `rateLimit` / `requireRole` throws.
 * `bucket` is the rate-limit bucket (or a short callable tag).
 */
function noteStudioDenial(streamId, uid, err, bucket) {
    const code = err instanceof https_1.HttpsError ? err.code : err === null || err === void 0 ? void 0 : err.code;
    const s = typeof code === 'string' ? (0, security_logic_1.signalForFailure)(code, bucket) : null;
    if (s)
        void recordStudioSignal(streamId, uid, s.kind, s.detail);
}
/**
 * Wraps a callable step: on failure, reports it, then rethrows unchanged.
 * Usable by any module without touching shared.ts.
 */
async function withStudioSecurity(streamId, uid, bucket, fn) {
    try {
        return await fn();
    }
    catch (e) {
        noteStudioDenial(streamId, uid, e, bucket);
        throw e;
    }
}
// Register with shared.ts once the integrator adds `setStudioDenialHook`
// (requested). Avoids an import cycle: shared.ts never imports this file.
const hookSetter = shared.setStudioDenialHook;
if (typeof hookSetter === 'function')
    hookSetter(noteStudioDenial);
async function evaluate(spec, streamId, uid, detail, now) {
    let count;
    if (spec.scope === 'stream') {
        const c = await bumpStream(spec, streamId, now);
        if (c === null)
            return;
        count = c;
    }
    else {
        const ref = spec.scope === 'account'
            ? (0, shared_1.db)().doc(exports.SecPaths.account(uid))
            : (0, shared_1.db)().doc(`${exports.SecPaths.counters(streamId)}/${spec.id}_${uid}`);
        const field = spec.scope === 'account' ? spec.id : 'log';
        const value = spec.distinct === 'streamId' ? streamId : spec.distinct === 'fingerprint' ? detail.fingerprint : undefined;
        const cap = Math.min(200, spec.distinct ? spec.criticalAt * 8 : spec.criticalAt + 1);
        count = await (0, shared_1.db)().runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const hit = value !== undefined ? { t: now, v: value } : { t: now };
            const log = (0, security_logic_1.slideLog)(snap.exists ? snap.get(field) : undefined, hit, spec.windowMs, cap);
            tx.set(ref, { [field]: log, updatedAtMs: now }, { merge: true });
            return (0, security_logic_1.countLog)(log, !!spec.distinct);
        });
    }
    const incident = (0, security_logic_1.buildIncident)({ spec, streamId, uid, count, now });
    if (incident)
        await persistIncident(incident);
}
/** Increments a sharded bucket; returns the window sum when due for evaluation. */
async function bumpStream(spec, streamId, now) {
    var _a;
    const bucket = (0, security_logic_1.bucketStart)(now);
    const shard = Math.floor(Math.random() * security_logic_1.STREAM_SHARDS);
    await (0, shared_1.db)()
        .doc(`${exports.SecPaths.counters(streamId)}/${(0, security_logic_1.streamCounterId)(spec.id, bucket, shard)}`)
        .set({ detector: spec.id, bucket, count: firestore_2.FieldValue.increment(1) }, { merge: true });
    const key = `${streamId}:${spec.id}`;
    if (now - ((_a = lastStreamEval.get(key)) !== null && _a !== void 0 ? _a : 0) < STREAM_EVAL_EVERY_MS)
        return null;
    lastStreamEval.set(key, now);
    if (lastStreamEval.size > 5000)
        lastStreamEval.clear();
    const refs = (0, security_logic_1.bucketsFor)(now, spec.windowMs).flatMap((b) => Array.from({ length: security_logic_1.STREAM_SHARDS }, (_, s) => (0, shared_1.db)().doc(`${exports.SecPaths.counters(streamId)}/${(0, security_logic_1.streamCounterId)(spec.id, b, s)}`)));
    const snaps = await (0, shared_1.db)().getAll(...refs);
    return (0, security_logic_1.sumBuckets)(snaps.filter((s) => s.exists).map((s) => ({ bucket: Number(s.get('bucket')), count: Number(s.get('count')) })), now, spec.windowMs);
}
/** `create()` dedupes concurrent instances: the id embeds the cooldown slot. */
async function persistIncident(i) {
    try {
        await (0, shared_1.db)().doc(`${exports.SecPaths.incidents(i.streamId)}/${i.id}`).create(Object.assign(Object.assign({}, i), { at: firestore_2.FieldValue.serverTimestamp() }));
    }
    catch (e) {
        if (e.code === 6)
            return; // ALREADY_EXISTS: same alert in this slot
        throw e;
    }
    const g = (0, security_logic_1.guardMapping)(i);
    if (g && i.uid) {
        try {
            await forwardToGuard(i.uid, g.type, g.details);
        }
        catch (e) {
            warn('guard forward', e);
        }
    }
}
/**
 * lsToken signal: account age (raid detection) and a session fingerprint
 * (duplicate-identity joins). The fingerprint is a hash of the ID token's
 * `auth_time` (one value per sign-in session/device); no raw data is stored.
 */
async function recordTokenSignal(streamId, uid, req) {
    var _a, _b;
    var _c;
    try {
        let newAccount = false;
        try {
            const created = Date.parse((await (0, auth_1.getAuth)().getUser(uid)).metadata.creationTime);
            newAccount = Number.isFinite(created) && Date.now() - created < security_logic_1.NEW_ACCOUNT_MS;
        }
        catch (e) {
            warn('account age', e);
        }
        const authTime = String((_c = (_b = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token) === null || _b === void 0 ? void 0 : _b.auth_time) !== null && _c !== void 0 ? _c : '');
        const fingerprint = authTime ? crypto.createHash('sha256').update(`${uid}|${authTime}`).digest('hex').slice(0, 16) : undefined;
        await recordStudioSignal(streamId, uid, 'token', { newAccount, fingerprint });
    }
    catch (e) {
        warn('token signal', e);
    }
}
// ─── AI live-health monitor ────────────────────────────────────────────────
/** Members whose role is coHost (host comes from state). */
async function managerUids(streamId, state) {
    const q = await (0, shared_1.db)().collection(contracts_1.Paths.members(streamId)).where('role', '==', 'coHost').get();
    return [...new Set([state.hostId, ...q.docs.map((d) => d.id)])].filter(Boolean);
}
/** Throttle: one run per stream per MONITOR_MIN_INTERVAL_MS, across instances. */
async function claimMonitorRun(streamId, now) {
    const ref = (0, shared_1.db)().doc(`${exports.SecPaths.counters(streamId)}/_monitor`);
    return (0, shared_1.db)().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!(0, security_logic_1.monitorShouldRun)(snap.exists ? Number(snap.get('lastRunAtMs')) : undefined, now))
            return false;
        tx.set(ref, { lastRunAtMs: now }, { merge: true });
        return true;
    });
}
async function askModel(summary) {
    var _a;
    if (!AI_MONITOR)
        return null;
    const ai = (0, vertexAi_1.vertexAi)();
    const call = ai.models.generateContent({
        model: 'gemini-2.5-flash',
        contents: [{ role: 'user', parts: [{ text: JSON.stringify(summary) }] }],
        config: {
            systemInstruction: security_logic_1.MONITOR_SYSTEM_PROMPT,
            responseMimeType: 'application/json',
            maxOutputTokens: 300,
            temperature: 0.1,
        },
    });
    const timeout = new Promise((r) => setTimeout(() => r(null), 8000));
    const res = await Promise.race([call, timeout]);
    return res ? String((_a = res.text) !== null && _a !== void 0 ? _a : '') : null;
}
/** Runs the monitor for one stream now (exported for an admin/manual trigger). */
async function runLiveHealthMonitor(streamId, now = Date.now()) {
    var _a, _b;
    var _c, _d, _e, _f, _g, _h, _j;
    const state = await (0, shared_1.loadState)(streamId);
    if (state.status === 'ended')
        return null;
    const incSnap = await (0, shared_1.db)()
        .collection(exports.SecPaths.incidents(streamId))
        .where('atMs', '>=', now - security_logic_1.MONITOR_LOOKBACK_MS)
        .orderBy('atMs', 'desc')
        .limit(20)
        .get();
    const incidents = incSnap.docs.map((d) => d.data());
    if (!incidents.some((i) => i.severity !== 'info'))
        return null;
    // People in incidents: role + on-stage (for validation) and a display name
    // (host UI only; never sent to the model).
    const uids = [...new Set(incidents.map((i) => i.uid).filter((u) => !!u))].slice(0, 20);
    const st = state.stage;
    const onStage = (u) => st.centerUid === u || st.wall.includes(u) || st.overflow.includes(u);
    const memberSnaps = uids.length ? await (0, shared_1.db)().getAll(...uids.map((u) => (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${u}`))) : [];
    const people = {};
    for (const s of memberSnaps) {
        const m = s.exists ? s.data() : {};
        people[s.id] = { onStage: onStage(s.id), role: state.hostId === s.id ? 'host' : ((_c = m.role) !== null && _c !== void 0 ? _c : 'viewer'), name: (_d = m.displayName) !== null && _d !== void 0 ? _d : '' };
    }
    // Chat rate + short samples from flagged accounts (one single-field query).
    const recent = await (0, shared_1.db)()
        .collection(contracts_1.Paths.comments(streamId))
        .where('ts', '>=', now - 60000)
        .orderBy('ts', 'desc')
        .limit(200)
        .get();
    const flagged = new Set(uids);
    const samples = {};
    for (const d of recent.docs) {
        const u = String((_e = d.get('uid')) !== null && _e !== void 0 ? _e : '');
        if (!flagged.has(u) || d.get('kind'))
            continue;
        const list = ((_f = samples[u]) !== null && _f !== void 0 ? _f : (samples[u] = []));
        if (list.length < 2)
            list.push(String((_g = d.get('text')) !== null && _g !== void 0 ? _g : ''));
    }
    const metrics = {
        viewers: (_h = (_a = state.counts) === null || _a === void 0 ? void 0 : _a.viewers) !== null && _h !== void 0 ? _h : 0,
        participants: (_j = (_b = state.counts) === null || _b === void 0 ? void 0 : _b.participants) !== null && _j !== void 0 ? _j : 0,
        chatPerMin: recent.size,
        qos: null, // QoS samples go to telemetry, not Firestore; not available server-side yet.
    };
    // PRIVACY: the summary has aliases instead of uids, no names, and at most
    // 3 sanitized samples of ≤ 60 chars (see buildHealthSummary).
    const { summary, aliases } = (0, security_logic_1.buildHealthSummary)({ incidents, metrics, now, people, samples });
    let source = 'rules';
    let advice = null;
    try {
        const raw = await askModel(summary);
        advice = raw ? (0, security_logic_1.validateModelOutput)(raw, { summary, aliases }) : null;
        if (advice)
            source = 'ai';
    }
    catch (e) {
        warn('model', e);
    }
    advice !== null && advice !== void 0 ? advice : (advice = (0, security_logic_1.fallbackAdvice)(incidents, people));
    const advisory = (0, security_logic_1.buildAdvisory)(Object.assign({ streamId, now, incidents, source }, advice));
    const withNames = Object.assign(Object.assign({}, advisory), { actions: advisory.actions.map((a) => { var _a; var _b; return (a.targetUid ? Object.assign(Object.assign({}, a), { targetName: (_b = (_a = people[a.targetUid]) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : '' }) : a); }) });
    await (0, shared_1.db)().doc(`${exports.SecPaths.advisories(streamId)}/${advisory.id}`).set(Object.assign(Object.assign({}, withNames), { at: firestore_2.FieldValue.serverTimestamp() }));
    const to = await managerUids(streamId, state);
    await (0, shared_1.broadcast)(streamId, security_logic_1.SECURITY_TOPIC, { v: 1, type: 'security.advisory', advisory: withNames, ts: now }, { to });
    return withNames;
}
/** New incident → maybe a live-health advisory (warn/critical, ≤ 1/min/stream). */
exports.lsSecOnIncident = (0, firestore_1.onDocumentCreated)({ document: 'live_streams/{streamId}/studio_security/{incidentId}', secrets: MONITOR_SECRETS }, async (event) => {
    var _a;
    const severity = (_a = event.data) === null || _a === void 0 ? void 0 : _a.get('severity');
    if (severity !== 'warn' && severity !== 'critical')
        return;
    const streamId = event.params.streamId;
    const now = Date.now();
    try {
        if (!(await claimMonitorRun(streamId, now)))
            return;
        await runLiveHealthMonitor(streamId, now);
    }
    catch (e) {
        warn(`monitor ${streamId}`, e);
    }
});
// ─── Media E2EE keys ───────────────────────────────────────────────────────
const random = (n) => new Uint8Array(crypto.randomBytes(n));
function studioE2eeEnabled() {
    try {
        return (0, security_logic_1.e2eeEnabled)(exports.LIVE_STUDIO_E2EE.value());
    }
    catch (_a) {
        return true;
    }
}
/**
 * The stream's shared media key, created on first use. Returns null when
 * E2EE is off. The key doc is function-only (no client rules access).
 */
async function mediaKeyForToken(streamId) {
    if (!studioE2eeEnabled())
        return null;
    const ref = (0, shared_1.db)().doc(exports.SecPaths.mediaKey(streamId));
    const doc = await (0, shared_1.db)().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const cur = snap.exists ? snap.data() : undefined;
        if ((0, security_logic_1.isValidKeyDoc)(cur))
            return cur;
        const fresh = (0, security_logic_1.newMediaKey)(random, Date.now());
        tx.set(ref, fresh);
        return fresh;
    });
    return (0, security_logic_1.keyPayload)(doc);
}
/**
 * Rotates the key (new random 32 bytes, next ring index) and tells the room
 * on topic `security`. The data message carries ONLY the index: it travels
 * through the SFU, so clients fetch the key itself over HTTPS (lsMediaKey).
 */
async function rotateStudioMediaKey(streamId, reason) {
    if (!studioE2eeEnabled())
        return null;
    const ref = (0, shared_1.db)().doc(exports.SecPaths.mediaKey(streamId));
    const next = await (0, shared_1.db)().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists)
            return null; // no E2EE live yet (or a v1 stream): nothing to rotate
        const cur = snap.data();
        const n = (0, security_logic_1.rotateMediaKey)((0, security_logic_1.isValidKeyDoc)(cur) ? cur : null, random, Date.now(), reason);
        tx.set(ref, n);
        return n;
    });
    if (next)
        await (0, shared_1.broadcast)(streamId, security_logic_1.SECURITY_TOPIC, (0, security_logic_1.keyUpdateEvent)(next.keyIndex, Date.now()));
    return next;
}
/** Someone was blocked → rotate (they keep no usable key). */
exports.lsSecOnBlock = (0, firestore_1.onDocumentCreated)({ document: 'live_streams/{streamId}/studio_blocks/{uid}', secrets: shared_1.LIVEKIT_SECRETS }, async (event) => {
    try {
        await rotateStudioMediaKey(event.params.streamId, 'blocked');
    }
    catch (e) {
        warn('rotate on block', e);
    }
});
/** A publisher left / was removed from the stage → rotate. */
exports.lsSecOnMemberWrite = (0, firestore_1.onDocumentWritten)({ document: 'live_streams/{streamId}/members/{uid}', secrets: shared_1.LIVEKIT_SECRETS }, async (event) => {
    var _a, _b, _c, _d;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    if (!(0, security_logic_1.memberChangeNeedsRotation)(before, after))
        return;
    try {
        await rotateStudioMediaKey(event.params.streamId, 'stage_removed');
    }
    catch (e) {
        warn('rotate on stage removal', e);
    }
});
/** Current media key for an allowed client (after a `key.update`). Returns `{enabled, key?, keyIndex?}`. */
exports.lsMediaKey = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const streamId = (0, shared_1.requireString)((_a = req.data) === null || _a === void 0 ? void 0 : _a.streamId, 'streamId', 128);
    if (!studioE2eeEnabled())
        return { enabled: false };
    const state = await (0, shared_1.loadState)(streamId);
    if (state.status === 'ended')
        throw new https_1.HttpsError('failed-precondition', 'This live has ended.');
    if (await (0, shared_1.isBlocked)(streamId, uid)) {
        void recordStudioSignal(streamId, uid, 'blocked_token');
        throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
    }
    await withStudioSecurity(streamId, uid, 'mediakey', () => (0, shared_1.rateLimit)(streamId, uid, 'mediakey', 10, 60000));
    const k = await mediaKeyForToken(streamId);
    return k ? Object.assign({ enabled: true }, k) : { enabled: false };
});
/** Exposed for tests / tooling: the detector table. */
exports.STUDIO_DETECTORS = security_logic_1.DETECTORS;
//# sourceMappingURL=security.js.map