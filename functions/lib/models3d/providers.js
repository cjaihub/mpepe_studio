"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ENGINES = void 0;
exports.linkProvider = linkProvider;
exports.unlinkProvider = unlinkProvider;
exports.engineFor = engineFor;
exports.engineOf = engineOf;
exports.submitGeneration = submitGeneration;
exports.pollGeneration = pollGeneration;
/**
 * Photo → 3D engines.
 *
 * A seller can link their own provider account (their key is encrypted and
 * kept server-side in `model3d_keys/{uid}`, which no client can read), or
 * Oneova's built-in engine is used when the platform key exists
 * (optional secret MESHY_API_KEY). With neither, generation is off and the
 * app says so; uploads and the private library keep working.
 *
 * Secrets (both optional, see optionalSecrets.ts):
 *   MODEL3D_VAULT_KEY  32 random bytes, base64 (`openssl rand -base64 32`);
 *                      needed before sellers can link their own account
 *   MESHY_API_KEY      Oneova's own engine key (built-in generation)
 */
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const gmailUser_1 = require("../gmailUser");
const optionalSecrets_1 = require("../optionalSecrets");
exports.ENGINES = {
    meshy: { label: 'Meshy', keyHint: 'msy_…' },
};
const db = () => (0, firestore_1.getFirestore)();
const keysRef = (uid) => db().collection('model3d_keys').doc(uid);
const statusRef = (uid, engine) => db().doc(`users/${uid}/model_providers/${engine}`);
async function vaultKey() {
    const k = await (0, optionalSecrets_1.optionalSecret)('MODEL3D_VAULT_KEY');
    const buf = k ? Buffer.from(k, 'base64') : Buffer.alloc(0);
    if (buf.length !== 32)
        throw new https_1.HttpsError('failed-precondition', 'Linking your own 3D provider is not switched on yet.');
    return buf;
}
async function meshy(key, method, path, body) {
    var _a;
    const res = await fetch(`https://api.meshy.ai${path}`, {
        method,
        headers: Object.assign({ Authorization: `Bearer ${key}` }, (body ? { 'Content-Type': 'application/json' } : {})),
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(30000),
    });
    const text = await res.text();
    let json = null;
    try {
        json = text ? JSON.parse(text) : null;
    }
    catch (_b) { /* not JSON */ }
    if (!res.ok) {
        const err = new Error(String((_a = json === null || json === void 0 ? void 0 : json.message) !== null && _a !== void 0 ? _a : `The 3D engine answered ${res.status}.`));
        err.status = res.status;
        throw err;
    }
    return json;
}
/** Saves a seller's own provider key after checking it works. */
async function linkProvider(uid, engine, apiKey) {
    const key = apiKey.trim();
    if (key.length < 12 || key.length > 200 || /\s/.test(key))
        throw new https_1.HttpsError('invalid-argument', 'That key doesn’t look right.');
    const vault = await vaultKey();
    try {
        await meshy(key, 'GET', '/openapi/v1/image-to-3d?page_size=1');
    }
    catch (e) {
        if ((e === null || e === void 0 ? void 0 : e.status) === 401 || (e === null || e === void 0 ? void 0 : e.status) === 403)
            throw new https_1.HttpsError('permission-denied', `${exports.ENGINES[engine].label} did not accept this key.`);
        throw new https_1.HttpsError('unavailable', `${exports.ENGINES[engine].label} can’t be reached right now. Try again in a minute.`);
    }
    await keysRef(uid).set({ [engine]: (0, gmailUser_1.encryptWith)(vault, key, uid), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    await statusRef(uid, engine).set({
        engine, label: exports.ENGINES[engine].label, linked: true, keyEnd: key.slice(-4), linkedAt: firestore_1.FieldValue.serverTimestamp(),
    });
}
async function unlinkProvider(uid, engine) {
    await keysRef(uid).set({ [engine]: firestore_1.FieldValue.delete() }, { merge: true });
    await statusRef(uid, engine).delete();
}
/** The seller's own engine if linked, else Oneova's, else null (generation off). */
async function engineFor(uid) {
    const blob = (await keysRef(uid).get()).get('meshy');
    if (blob) {
        try {
            return { id: 'meshy', key: (0, gmailUser_1.decryptWith)(await vaultKey(), blob, uid), owner: 'user' };
        }
        catch (_a) {
            /* unreadable key: fall through to the built-in engine */
        }
    }
    const platform = await (0, optionalSecrets_1.optionalSecret)('MESHY_API_KEY');
    return platform ? { id: 'meshy', key: platform, owner: 'oneova' } : null;
}
/** The same engine a job started with (jobs outlive one function call). */
async function engineOf(uid, owner) {
    const e = await engineFor(uid);
    if (e && e.owner === owner)
        return e;
    if (owner === 'oneova') {
        const platform = await (0, optionalSecrets_1.optionalSecret)('MESHY_API_KEY');
        return platform ? { id: 'meshy', key: platform, owner: 'oneova' } : null;
    }
    return null;
}
/**
 * Starts a generation. One photo uses image-to-3D; two to four (front first)
 * use multi-image, which is what keeps the sides and the texture true.
 */
async function submitGeneration(engine, imageUrls) {
    const common = { should_texture: true, enable_pbr: true, should_remesh: true, topology: 'triangle', target_polycount: 100000, target_formats: ['glb'] };
    if (imageUrls.length > 1) {
        const r = await meshy(engine.key, 'POST', '/openapi/v1/multi-image-to-3d', Object.assign(Object.assign({}, common), { image_urls: imageUrls.slice(0, 4) }));
        return { taskId: String(r.result), multi: true };
    }
    const r = await meshy(engine.key, 'POST', '/openapi/v1/image-to-3d', Object.assign(Object.assign({}, common), { image_url: imageUrls[0] }));
    return { taskId: String(r.result), multi: false };
}
async function pollGeneration(engine, task) {
    var _a, _b;
    var _c;
    const t = await meshy(engine.key, 'GET', `/openapi/v1/${task.multi ? 'multi-image-to-3d' : 'image-to-3d'}/${encodeURIComponent(task.taskId)}`);
    const progress = Math.min(1, Math.max(0, Number((_c = t === null || t === void 0 ? void 0 : t.progress) !== null && _c !== void 0 ? _c : 0) / 100));
    switch (String(t === null || t === void 0 ? void 0 : t.status)) {
        case 'SUCCEEDED': {
            const glbUrl = (_a = t === null || t === void 0 ? void 0 : t.model_urls) === null || _a === void 0 ? void 0 : _a.glb;
            if (typeof glbUrl !== 'string' || !glbUrl.startsWith('https://'))
                return { state: 'failed', progress, error: 'The engine finished without a model.' };
            return { state: 'done', progress: 1, glbUrl, thumbnailUrl: typeof t.thumbnail_url === 'string' ? t.thumbnail_url : undefined };
        }
        case 'FAILED':
        case 'CANCELED':
            return { state: 'failed', progress, error: String(((_b = t === null || t === void 0 ? void 0 : t.task_error) === null || _b === void 0 ? void 0 : _b.message) || 'The engine could not build this model.').slice(0, 200) };
        default:
            return { state: 'working', progress };
    }
}
//# sourceMappingURL=providers.js.map