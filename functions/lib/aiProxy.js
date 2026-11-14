"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.aiProxy = void 0;
/**
 * aiProxy — OpenRouter-compatible proxy so the app never ships an AI key.
 *
 * The app calls `<fn url>/api/v1/chat/completions` (or `/api/v1/models`) with
 * `Authorization: Bearer <Firebase ID token>`. We verify the token, apply a
 * per-user daily cap, then forward the request to OpenRouter with the
 * OPENROUTER_API_KEY secret and stream the response back unchanged (SSE too).
 */
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const auth_1 = require("firebase-admin/auth");
const app_check_1 = require("firebase-admin/app-check");
const firestore_1 = require("firebase-admin/firestore");
const stream_1 = require("stream");
const openRouterSecret = (0, params_1.defineSecret)('OPENROUTER_API_KEY');
const UPSTREAM = 'https://openrouter.ai/api/v1';
const DAILY_LIMIT = 400;
const MAX_BODY_BYTES = 6 * 1024 * 1024;
async function underDailyCap(uid) {
    const day = new Date().toISOString().substring(0, 10).replace(/-/g, '');
    const ref = (0, firestore_1.getFirestore)().collection('users').doc(uid).collection('quotas').doc(`ai_${day}`);
    return (0, firestore_1.getFirestore)().runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(ref);
        const count = (_a = snap.get('count')) !== null && _a !== void 0 ? _a : 0;
        if (count >= DAILY_LIMIT)
            return false;
        tx.set(ref, { count: firestore_1.FieldValue.increment(1), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    });
}
exports.aiProxy = (0, https_1.onRequest)({ secrets: [openRouterSecret], timeoutSeconds: 300, memory: '512MiB', cors: true }, async (req, res) => {
    var _a;
    var _b, _c;
    const path = req.path.replace(/^\/api\/v1/, '');
    const isChat = req.method === 'POST' && path === '/chat/completions';
    const isModels = req.method === 'GET' && path === '/models';
    if (!isChat && !isModels) {
        res.status(404).json({ error: { message: 'Not found' } });
        return;
    }
    const token = ((_b = req.get('Authorization')) !== null && _b !== void 0 ? _b : '').replace(/^Bearer\s+/i, '');
    let uid;
    try {
        uid = (await (0, auth_1.getAuth)().verifyIdToken(token)).uid;
    }
    catch (_d) {
        res.status(401).json({ error: { message: 'Sign in to use Oneova AI.' } });
        return;
    }
    // App Check: verified whenever the app sends it; required once
    // APP_CHECK_ENFORCE=true (same switch as the callables, globalOptions.ts).
    const appCheck = req.get('X-Firebase-AppCheck');
    let appVerified = false;
    if (appCheck) {
        try {
            await (0, app_check_1.getAppCheck)().verifyToken(appCheck);
            appVerified = true;
        }
        catch (_e) {
            appVerified = false;
        }
    }
    if (!appVerified && process.env.APP_CHECK_ENFORCE === 'true') {
        res.status(401).json({ error: { message: 'Update Oneova to keep using AI.' } });
        return;
    }
    if (isChat) {
        if (((_c = (_a = req.rawBody) === null || _a === void 0 ? void 0 : _a.length) !== null && _c !== void 0 ? _c : 0) > MAX_BODY_BYTES) {
            res.status(413).json({ error: { message: 'Request too large.' } });
            return;
        }
        if (!(await underDailyCap(uid))) {
            res.status(429).json({ error: { message: 'Daily AI limit reached. Try again tomorrow.' } });
            return;
        }
    }
    const key = openRouterSecret.value();
    if (!key) {
        res.status(503).json({ error: { message: 'AI is not configured.' } });
        return;
    }
    const upstream = await fetch(`${UPSTREAM}${path}`, {
        method: req.method,
        headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${key}`,
            'HTTP-Referer': 'https://mpepe-2b4bd.web.app',
            'X-Title': 'Oneova',
        },
        body: isChat ? new Uint8Array(req.rawBody) : undefined,
    });
    res.status(upstream.status);
    const type = upstream.headers.get('content-type');
    if (type)
        res.setHeader('Content-Type', type);
    if (!upstream.body) {
        res.end();
        return;
    }
    stream_1.Readable.fromWeb(upstream.body).pipe(res);
});
//# sourceMappingURL=aiProxy.js.map