"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.voiceStreamToken = exports.voiceConvertOwn = exports.voiceSpeakOwn = exports.voiceDisable = exports.voiceEnrollFinish = exports.voiceEnrollStart = exports.voiceStatus = void 0;
/**
 * "My voice": the person's own voice for translated voice notes and calls,
 * built on Oneova's own GPU server (services/voice). Plan and safety rules:
 * docs/architecture/voice_cloning_selfhosted.md.
 *
 * The server only ever speaks in the CALLER's own voice: every callable uses
 * request.auth.uid, never a uid from the request.
 *
 *   voiceStatus()                       → { available, profile }
 *   voiceEnrollStart({ consent: true }) → { path, prompts }   (uploads go to voice_profiles/{uid}/clips/)
 *   voiceEnrollFinish()                 → build report (enough? which clips to retake)
 *   voiceDisable()                      → deletes recordings, voice and record
 *   voiceSpeakOwn({ text, language })   → { audioBase64 } 24 kHz PCM16 in my voice
 *   voiceStreamToken({ callId })        → { url, token } for the call stream (15 min)
 *
 * Off until the VOICE_SERVER_URL secret is set (after the GPU is approved).
 * `voice_profiles/{uid}` is read-only to its owner; only these functions write it.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const google_auth_library_1 = require("google-auth-library");
const optionalSecrets_1 = require("../optionalSecrets");
const protect_1 = require("../guard/protect");
const voiceLogic_1 = require("./voiceLogic");
const db = () => (0, firestore_1.getFirestore)();
const auth = new google_auth_library_1.GoogleAuth();
function me(req) {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return uid;
}
async function serverUrl() {
    return (0, voiceLogic_1.validVoiceUrl)(await (0, optionalSecrets_1.optionalSecret)('VOICE_SERVER_URL'));
}
async function callServer(path, method, data, binary = false) {
    var _a;
    var _b;
    const url = await serverUrl();
    if (!url)
        throw new https_1.HttpsError('unavailable', 'My voice isn’t switched on yet.');
    const client = await auth.getIdTokenClient(url);
    try {
        const res = await client.request({ url: `${url}${path}`, method, data, timeout: 120000, responseType: binary ? 'arraybuffer' : 'json' });
        return res.data;
    }
    catch (e) {
        const status = Number((_b = (_a = e === null || e === void 0 ? void 0 : e.response) === null || _a === void 0 ? void 0 : _a.status) !== null && _b !== void 0 ? _b : 0);
        if (status === 404)
            throw new https_1.HttpsError('not-found', 'Set up your voice first.');
        throw new https_1.HttpsError('unavailable', 'The voice server is busy. Try again in a minute.');
    }
}
const profileRef = (uid) => db().collection('voice_profiles').doc(uid);
exports.voiceStatus = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    var _c, _d, _e, _f, _g;
    const uid = me(req);
    const p = (_c = (await profileRef(uid).get()).data()) !== null && _c !== void 0 ? _c : null;
    return {
        available: !!(await serverUrl()),
        profile: p ? { status: (_d = p.status) !== null && _d !== void 0 ? _d : 'none', seconds: (_e = p.seconds) !== null && _e !== void 0 ? _e : 0, retake: (_f = p.retake) !== null && _f !== void 0 ? _f : [], builtAt: (_g = (_b = (_a = p.builtAt) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _g !== void 0 ? _g : null } : null,
        prompts: voiceLogic_1.ENROLL_PROMPTS,
    };
});
exports.voiceEnrollStart = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = me(req);
    if (((_a = req.data) === null || _a === void 0 ? void 0 : _a.consent) !== true)
        throw new https_1.HttpsError('failed-precondition', 'Agree to the voice terms first.');
    const claims = (_b = req.auth) === null || _b === void 0 ? void 0 : _b.token;
    if ((claims === null || claims === void 0 ? void 0 : claims.minor) === true)
        throw new https_1.HttpsError('permission-denied', 'My voice is for adults only.');
    await (0, protect_1.limit)(uid, 'voice_enroll', 10, 24 * 3600000);
    await profileRef(uid).set({
        uid,
        status: 'recording',
        consent: { version: voiceLogic_1.CONSENT_VERSION, at: firestore_1.FieldValue.serverTimestamp() },
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { path: `voice_profiles/${uid}/clips/`, consentPath: `voice_profiles/${uid}/consent.m4a`, prompts: voiceLogic_1.ENROLL_PROMPTS };
});
exports.voiceEnrollFinish = (0, https_1.onCall)({ timeoutSeconds: 300 }, async (req) => {
    var _a, _b, _c, _d;
    const uid = me(req);
    const cur = (await profileRef(uid).get()).data();
    if (!(cur === null || cur === void 0 ? void 0 : cur.consent))
        throw new https_1.HttpsError('failed-precondition', 'Start setting up your voice first.');
    await (0, protect_1.limit)(uid, 'voice_build', 10, 24 * 3600000);
    await profileRef(uid).set({ status: 'building', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    const report = await callServer('/v1/profile/build', 'POST', { uid });
    const ok = (report === null || report === void 0 ? void 0 : report.built) === true;
    await profileRef(uid).set(Object.assign(Object.assign({ status: ok ? 'ready' : 'needs_retake', seconds: Number((_a = report === null || report === void 0 ? void 0 : report.goodSeconds) !== null && _a !== void 0 ? _a : 0), retake: Array.isArray(report === null || report === void 0 ? void 0 : report.retake) ? report.retake.slice(0, 20) : [] }, (ok ? { builtAt: firestore_1.FieldValue.serverTimestamp() } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    return { ready: ok, seconds: (_b = report === null || report === void 0 ? void 0 : report.goodSeconds) !== null && _b !== void 0 ? _b : 0, totalSeconds: (_c = report === null || report === void 0 ? void 0 : report.totalSeconds) !== null && _c !== void 0 ? _c : 0, retake: (_d = report === null || report === void 0 ? void 0 : report.retake) !== null && _d !== void 0 ? _d : [] };
});
exports.voiceDisable = (0, https_1.onCall)(async (req) => {
    const uid = me(req);
    if (await serverUrl()) {
        try {
            await callServer(`/v1/profile/${uid}`, 'DELETE');
        }
        catch (_a) {
            // The files below are deleted either way.
        }
    }
    await (0, storage_1.getStorage)().bucket().deleteFiles({ prefix: `voice_profiles/${uid}/` }).catch(() => undefined);
    await profileRef(uid).delete();
    return { ok: true };
});
async function requireReady(uid) {
    const p = (await profileRef(uid).get()).data();
    if ((p === null || p === void 0 ? void 0 : p.status) !== 'ready')
        throw new https_1.HttpsError('failed-precondition', 'Set up your voice first.');
}
exports.voiceSpeakOwn = (0, https_1.onCall)({ timeoutSeconds: 120 }, async (req) => {
    var _a, _b;
    var _c, _d;
    const uid = me(req);
    const text = String((_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.text) !== null && _c !== void 0 ? _c : '').trim().slice(0, voiceLogic_1.MAX_SPEAK_CHARS);
    const language = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.language) !== null && _d !== void 0 ? _d : '').slice(0, 12);
    if (!text || !language)
        throw new https_1.HttpsError('invalid-argument', 'Missing text or language.');
    if ((0, voiceLogic_1.engineFor)(language) !== 'clone')
        throw new https_1.HttpsError('failed-precondition', 'convert');
    await requireReady(uid);
    await (0, protect_1.limit)(uid, 'voice_speak', 120, 3600000);
    const pcm = await callServer('/v1/speak', 'POST', { uid, text, language }, true);
    return { audioBase64: Buffer.from(pcm).toString('base64'), sampleRate: 24000, aiVoice: true };
});
/** Converts speech (e.g. a preset voice speaking Yoruba) into my own voice. */
exports.voiceConvertOwn = (0, https_1.onCall)({ timeoutSeconds: 120 }, async (req) => {
    var _a, _b;
    var _c, _d;
    const uid = me(req);
    const audio = String((_c = (_a = req.data) === null || _a === void 0 ? void 0 : _a.audioBase64) !== null && _c !== void 0 ? _c : '');
    const sr = Number((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.sampleRate) !== null && _d !== void 0 ? _d : 24000);
    if (!audio || audio.length > 4 * 1024 * 1024 || !(sr >= 8000 && sr <= 48000))
        throw new https_1.HttpsError('invalid-argument', 'Bad audio.');
    await requireReady(uid);
    await (0, protect_1.limit)(uid, 'voice_convert', 120, 3600000);
    const pcm = await callServer('/v1/convert', 'POST', { uid, sr, audio }, true);
    return { audioBase64: Buffer.from(pcm).toString('base64'), sampleRate: 24000, aiVoice: true };
});
exports.voiceStreamToken = (0, https_1.onCall)(async (req) => {
    var _a;
    var _b;
    const uid = me(req);
    const callId = String((_b = (_a = req.data) === null || _a === void 0 ? void 0 : _a.callId) !== null && _b !== void 0 ? _b : '');
    if (!/^[A-Za-z0-9_-]{4,100}$/.test(callId))
        throw new https_1.HttpsError('invalid-argument', 'Missing call.');
    const url = await serverUrl();
    const key = await (0, optionalSecrets_1.optionalSecret)('VOICE_STREAM_KEY');
    if (!url || !key)
        throw new https_1.HttpsError('unavailable', 'My voice isn’t switched on yet.');
    await requireReady(uid);
    await (0, protect_1.limit)(uid, 'voice_stream', 30, 3600000);
    return { url: url.replace(/^https:/, 'wss:') + '/v1/stream', token: (0, voiceLogic_1.signStreamToken)(Buffer.from(key), uid, callId) };
});
//# sourceMappingURL=voice.js.map