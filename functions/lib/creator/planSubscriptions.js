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
exports.playBillingNotifications = exports.verifySubscriptionPurchase = exports.PLAN_PRODUCTS = void 0;
/**
 * Oneova plans (Plus / Pro / Biz) sold as Google Play subscriptions.
 *
 *   app → verifySubscriptionPurchase  checks the token with the Play Developer
 *         API (subscriptionsv2), acknowledges it and writes `subscriptions/{uid}`
 *   Play → playBillingNotifications   Real-time developer notifications on the
 *         Pub/Sub topic `play-billing` (renewals, cancels, holds, expiry)
 *
 * Setup: Play Console → Monetize → Subscriptions: create `oneova_plus`,
 * `oneova_pro`, `oneova_biz`, each with base plans `monthly` and `yearly`.
 * Monetization setup → Real-time developer notifications → topic
 * projects/mpepe-2b4bd/topics/play-billing (grant
 * google-play-developer-notifications@system.gserviceaccount.com Publisher).
 */
const crypto = __importStar(require("crypto"));
const googleapis_1 = require("googleapis");
const https_1 = require("firebase-functions/v2/https");
const pubsub_1 = require("firebase-functions/v2/pubsub");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const db = () => (0, firestore_1.getFirestore)();
const PACKAGE = 'com.oneova.app';
exports.PLAN_PRODUCTS = {
    oneova_plus: 'plus',
    oneova_pro: 'pro',
    oneova_biz: 'biz',
};
/** Play states that still give the person their plan. */
const ENTITLED = new Set(['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED']);
function publisher() {
    const auth = new googleapis_1.google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
    return googleapis_1.google.androidpublisher({ version: 'v3', auth });
}
const tokenId = (t) => crypto.createHash('sha256').update(t).digest('hex');
/** Re-reads a token from Play and writes the owner's plan. Returns the plan doc. */
async function sync(token, claimedUid) {
    var _a, _b, _c, _d;
    var _e, _f, _g;
    const map = db().doc(`play_sub_tokens/${tokenId(token)}`);
    const known = (await map.get()).data();
    const sub = (await publisher().purchases.subscriptionsv2.get({ packageName: PACKAGE, token })).data;
    const line = (_a = sub.lineItems) === null || _a === void 0 ? void 0 : _a[0];
    const productId = (_e = line === null || line === void 0 ? void 0 : line.productId) !== null && _e !== void 0 ? _e : '';
    const plan = exports.PLAN_PRODUCTS[productId];
    if (!plan)
        throw new https_1.HttpsError('invalid-argument', 'Unknown plan.');
    const owner = ((_b = sub.externalAccountIdentifiers) === null || _b === void 0 ? void 0 : _b.obfuscatedExternalAccountId) || (known === null || known === void 0 ? void 0 : known.uid) || claimedUid;
    if (!owner)
        throw new https_1.HttpsError('failed-precondition', 'This purchase is not linked to an account.');
    if (claimedUid && owner !== claimedUid)
        throw new https_1.HttpsError('permission-denied', 'This subscription belongs to another account.');
    const expiry = (line === null || line === void 0 ? void 0 : line.expiryTime) ? Date.parse(line.expiryTime) : 0;
    const state = (_f = sub.subscriptionState) !== null && _f !== void 0 ? _f : 'SUBSCRIPTION_STATE_UNSPECIFIED';
    const active = ENTITLED.has(state) && expiry > Date.now();
    const doc = {
        uid: owner,
        plan: active ? plan : 'free',
        productId,
        basePlanId: (_g = (_c = line === null || line === void 0 ? void 0 : line.offerDetails) === null || _c === void 0 ? void 0 : _c.basePlanId) !== null && _g !== void 0 ? _g : null,
        state,
        active,
        autoRenewing: ((_d = line === null || line === void 0 ? void 0 : line.autoRenewingPlan) === null || _d === void 0 ? void 0 : _d.autoRenewEnabled) === true,
        expiresAt: expiry ? firestore_1.Timestamp.fromMillis(expiry) : null,
        tokenHash: tokenId(token),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    };
    const batch = db().batch();
    batch.set(map, { uid: owner, token, productId, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    // A newer token (upgrade / resubscribe) wins; an old one only writes while it is the current one.
    const cur = (await db().doc(`subscriptions/${owner}`).get()).data();
    if (!cur || cur.tokenHash === doc.tokenHash || active || !cur.active) {
        batch.set(db().doc(`subscriptions/${owner}`), doc, { merge: true });
        batch.set(db().doc(`users/${owner}`), { oneovaPlan: doc.plan, oneovaPlanUpdatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    }
    await batch.commit();
    if (sub.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' && active) {
        await publisher().purchases.subscriptions.acknowledge({ packageName: PACKAGE, subscriptionId: productId, token, requestBody: {} })
            .catch((e) => { var _a; return logger.warn('play subscription acknowledge failed (will retry)', (_a = e === null || e === void 0 ? void 0 : e.message) !== null && _a !== void 0 ? _a : e); });
    }
    return doc;
}
exports.verifySubscriptionPurchase = (0, https_1.onCall)({ timeoutSeconds: 60 }, async (req) => {
    var _a, _b, _c;
    var _d, _e, _f;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const token = String((_d = (_b = req.data) === null || _b === void 0 ? void 0 : _b.purchaseToken) !== null && _d !== void 0 ? _d : '');
    if (!token || token.length > 4096)
        throw new https_1.HttpsError('invalid-argument', 'Missing purchase.');
    try {
        const d = await sync(token, uid);
        return { plan: d.plan, active: d.active, expiresAt: (_e = (_c = d.expiresAt) === null || _c === void 0 ? void 0 : _c.toMillis()) !== null && _e !== void 0 ? _e : null, autoRenewing: d.autoRenewing };
    }
    catch (e) {
        if (e instanceof https_1.HttpsError)
            throw e;
        logger.error('play subscription lookup failed', (_f = e === null || e === void 0 ? void 0 : e.message) !== null && _f !== void 0 ? _f : e);
        throw new https_1.HttpsError('unavailable', 'We couldn’t confirm this with Google Play yet. Your plan turns on as soon as it does.');
    }
});
exports.playBillingNotifications = (0, pubsub_1.onMessagePublished)('play-billing', async (event) => {
    var _a;
    var _b;
    const msg = event.data.message.json;
    const token = (_a = msg === null || msg === void 0 ? void 0 : msg.subscriptionNotification) === null || _a === void 0 ? void 0 : _a.purchaseToken;
    if (!token || (msg === null || msg === void 0 ? void 0 : msg.packageName) !== PACKAGE)
        return;
    try {
        await sync(String(token), null);
    }
    catch (e) {
        logger.warn('rtdn sync failed', (_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : e);
    }
});
//# sourceMappingURL=planSubscriptions.js.map