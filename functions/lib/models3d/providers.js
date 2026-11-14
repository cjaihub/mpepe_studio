"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EngineError = exports.ENGINE_LABEL = void 0;
exports.engineFor = engineFor;
exports.runGeneration = runGeneration;
exports.linkProvider = linkProvider;
exports.unlinkProvider = unlinkProvider;
/**
 * Photo → 3D engine: Oneova's own GPU model server only.
 *
 * Oneova does not use third-party 3D services (Meshy-style SaaS) and sellers
 * don't link outside accounts. Generation runs on open-source models (TRELLIS,
 * TripoSR; MIT) that Oneova hosts on Cloud Run GPU in its own project — see
 * packages/three_d_model_server on the AI 3D branch. Until that server is
 * deployed, generation is off: photos are kept and the model starts with
 * "Build now" once it is on. Uploads and the private library keep working.
 *
 * Configuration (either one; neither means "off"):
 *   env MODEL3D_SERVER_URL or optional secret MODEL3D_SERVER_URL
 *     https://ova3d-model-trellis-….run.app
 * The server must allow only the functions' service account to invoke it
 * (Cloud Run IAM) and set OVA3D_ALLOWED_BUCKET to the app's bucket.
 */
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const google_auth_library_1 = require("google-auth-library");
const optionalSecrets_1 = require("../optionalSecrets");
const engineLogic_1 = require("./engineLogic");
exports.ENGINE_LABEL = 'Oneova 3D builder';
/** Thrown with a message that is safe to show to the seller. */
class EngineError extends Error {
}
exports.EngineError = EngineError;
/** Oneova's own engine when it is configured, else null (generation off). */
async function engineFor(_uid) {
    const raw = process.env.MODEL3D_SERVER_URL || (await (0, optionalSecrets_1.optionalSecret)('MODEL3D_SERVER_URL'));
    const url = (0, engineLogic_1.validEngineUrl)(raw);
    return url ? { id: 'oneova', url, owner: 'oneova' } : null;
}
const auth = new google_auth_library_1.GoogleAuth();
/**
 * Runs image → 3D on the GPU server and waits for it (the model server
 * answers when the GLB is written). Returns the storage path of the GLB.
 */
async function runGeneration(engine, bucket, photoPaths, outputPrefix, timeoutMs) {
    var _a;
    var _b, _c;
    const body = (0, engineLogic_1.buildEngineRequest)(bucket, photoPaths, outputPrefix);
    let data;
    try {
        // Cloud Run IAM: an ID token for the service URL, minted for the functions' service account.
        const client = await auth.getIdTokenClient(engine.url);
        const res = await client.request({ url: `${engine.url}/v1/tasks`, method: 'POST', data: body, timeout: timeoutMs });
        data = res.data;
    }
    catch (e) {
        const status = Number((_b = (_a = e === null || e === void 0 ? void 0 : e.response) === null || _a === void 0 ? void 0 : _a.status) !== null && _b !== void 0 ? _b : e === null || e === void 0 ? void 0 : e.status) || undefined;
        throw new EngineError((0, engineLogic_1.engineErrorMessage)(status));
    }
    try {
        return (0, engineLogic_1.readEngineResult)(data, outputPrefix);
    }
    catch (e) {
        throw new EngineError(String((_c = e === null || e === void 0 ? void 0 : e.message) !== null && _c !== void 0 ? _c : 'The 3D builder finished without a model.'));
    }
}
// ── Old seller-linked provider keys (removed) ───────────────────────────
/** Linking outside 3D accounts is no longer offered. */
async function linkProvider() {
    throw new https_1.HttpsError('failed-precondition', 'Oneova builds 3D models on its own servers, so there is nothing to link.');
}
/** Removes any key a seller linked in an earlier version (kept so they can clear it). */
async function unlinkProvider(uid) {
    const db = (0, firestore_1.getFirestore)();
    await db.collection('model3d_keys').doc(uid).delete();
    const links = await db.collection(`users/${uid}/model_providers`).get();
    await Promise.all(links.docs.map((d) => d.ref.delete()));
}
//# sourceMappingURL=providers.js.map