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
exports.ledgerOutboxRetry = exports.ledgerOutboxDeliver = exports.outboxId = exports.outboxEnabled = void 0;
exports.ledgerOutbox = ledgerOutbox;
exports.nextDelayMs = nextDelayMs;
exports.isPermanent = isPermanent;
exports.send = send;
/**
 * Shadow mode for the Postgres ledger (services/ledger).
 *
 *   money function's Firestore transaction → also writes ledger_outbox/{id}
 *   ledgerOutboxDeliver (on create)       → POST {LEDGER_URL}/v1/wallet/{template}
 *   ledgerOutboxRetry (every 10 min)      → re-sends pending/failed ones with backoff
 *
 * The outbox write is inside the same transaction as the wallet change, so the
 * ledger gets every movement exactly once (its idempotency key = the outbox key).
 * Firestore stays the source of truth until reconciliation is green; then the
 * functions read balances from the ledger instead (cut-over, with approval).
 *
 * Off unless LEDGER_OUTBOX=on (functions/.env.<project>). LEDGER_URL is the
 * Cloud Run URL; calls carry a Google ID token for that audience.
 */
const crypto = __importStar(require("crypto"));
const google_auth_library_1 = require("google-auth-library");
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const db = () => (0, firestore_2.getFirestore)();
const MAX_ATTEMPTS = 12;
const outboxEnabled = () => process.env.LEDGER_OUTBOX === 'on';
exports.outboxEnabled = outboxEnabled;
const outboxId = (key) => crypto.createHash('sha256').update(key).digest('hex').slice(0, 40);
exports.outboxId = outboxId;
/** Queues one ledger movement inside the caller's transaction (no-op when off). */
function ledgerOutbox(tx, key, template, args) {
    if (!(0, exports.outboxEnabled)())
        return;
    tx.set(db().doc(`ledger_outbox/${(0, exports.outboxId)(key)}`), {
        key, template, args, status: 'pending', attempts: 0, createdAt: firestore_2.FieldValue.serverTimestamp(),
    });
}
/** Backoff before attempt n (1-based): 1, 2, 4 ... minutes, capped at 6 h. */
function nextDelayMs(attempts) {
    return Math.min(6 * 3600000, 60000 * 2 ** Math.max(0, attempts - 1));
}
/** 4xx other than "insufficient funds" won't succeed on retry. */
function isPermanent(status) {
    return status >= 400 && status < 500 && status !== 422 && status !== 429 && status !== 408;
}
let client = null;
async function send(template, key, args) {
    var _a, _b;
    const base = ((_a = process.env.LEDGER_URL) !== null && _a !== void 0 ? _a : '').replace(/\/$/, '');
    if (base.startsWith('http://localhost')) {
        // Local service with LEDGER_AUTH=off (emulator / tests): no ID token.
        const res = await fetch(`${base}/v1/wallet/${template}`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ idempotency_key: key, args }),
        });
        return { status: res.status, body: await res.json().catch(() => null) };
    }
    if (!base.startsWith('https://'))
        throw new Error('LEDGER_URL is not set');
    if (!client)
        client = await new google_auth_library_1.GoogleAuth().getIdTokenClient(base);
    // Same token twice: Cloud Run's IAM reads X-Serverless-Authorization, the ledger checks X-Ledger-Token.
    const h = (await client.getRequestHeaders());
    const bearer = (_b = (typeof h.get === 'function' ? h.get('authorization') : h.Authorization)) !== null && _b !== void 0 ? _b : '';
    if (!bearer)
        throw new Error('no ID token for the ledger');
    const res = await fetch(`${base}/v1/wallet/${template}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Ledger-Token': bearer, 'X-Serverless-Authorization': bearer },
        body: JSON.stringify({ idempotency_key: key, args }),
        signal: AbortSignal.timeout(15000),
    });
    return { status: res.status, body: await res.json().catch(() => null) };
}
async function deliver(ref) {
    var _a, _b, _c, _d, _e;
    var _f, _g, _h, _j, _k;
    const snap = await ref.get();
    const o = snap.data();
    if (!o || o.status === 'done' || o.status === 'dead')
        return;
    const attempts = Number((_f = o.attempts) !== null && _f !== void 0 ? _f : 0) + 1;
    try {
        const r = await send(o.template, o.key, o.args);
        if (r.status === 200) {
            await ref.update({ status: 'done', attempts, journalId: (_g = (_a = r.body) === null || _a === void 0 ? void 0 : _a.journalId) !== null && _g !== void 0 ? _g : null, replayed: ((_b = r.body) === null || _b === void 0 ? void 0 : _b.replayed) === true, doneAt: firestore_2.FieldValue.serverTimestamp() });
            return;
        }
        const error = String((_j = (_h = (_d = (_c = r.body) === null || _c === void 0 ? void 0 : _c.detail) === null || _d === void 0 ? void 0 : _d.message) !== null && _h !== void 0 ? _h : (_e = r.body) === null || _e === void 0 ? void 0 : _e.detail) !== null && _j !== void 0 ? _j : `HTTP ${r.status}`).slice(0, 300);
        const dead = isPermanent(r.status) || attempts >= MAX_ATTEMPTS;
        await ref.update({
            status: dead ? 'dead' : 'failed', attempts, lastStatus: r.status, lastError: error,
            retryAt: firestore_2.Timestamp.fromMillis(Date.now() + nextDelayMs(attempts)),
        });
        if (dead)
            logger.error('ledger outbox entry needs a person', ref.id, o.template, error);
    }
    catch (e) {
        await ref.update({
            status: attempts >= MAX_ATTEMPTS ? 'dead' : 'failed', attempts, lastError: String((_k = e === null || e === void 0 ? void 0 : e.message) !== null && _k !== void 0 ? _k : e).slice(0, 300),
            retryAt: firestore_2.Timestamp.fromMillis(Date.now() + nextDelayMs(attempts)),
        });
    }
}
exports.ledgerOutboxDeliver = (0, firestore_1.onDocumentCreated)('ledger_outbox/{id}', async (event) => {
    if (!(0, exports.outboxEnabled)() || !event.data)
        return;
    await deliver(event.data.ref);
});
exports.ledgerOutboxRetry = (0, scheduler_1.onSchedule)('every 10 minutes', async () => {
    if (!(0, exports.outboxEnabled)())
        return;
    const due = await db().collection('ledger_outbox').where('status', '==', 'failed')
        .where('retryAt', '<=', firestore_2.Timestamp.now()).orderBy('retryAt').limit(200).get();
    // Oldest first, so a purchase lands before the gift that spends it.
    for (const d of due.docs)
        await deliver(d.ref);
    // Anything stuck in pending (the trigger didn't run) for over 5 minutes.
    const stuck = await db().collection('ledger_outbox').where('status', '==', 'pending')
        .where('createdAt', '<=', firestore_2.Timestamp.fromMillis(Date.now() - 5 * 60000)).limit(200).get();
    for (const d of stuck.docs)
        await deliver(d.ref);
});
//# sourceMappingURL=outbox.js.map