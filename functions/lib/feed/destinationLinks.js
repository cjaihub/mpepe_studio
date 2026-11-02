"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.contentOpenDestination = exports.contentSetDestination = void 0;
/**
 * Reel destination links (product / shop / any URL on a post).
 *
 * Callables:
 *   contentSetDestination  `{contentId, url?, productId?, label?}` (author
 *       only). Validates the link (destination_logic.ts), checks web links
 *       with Ova Guard, and writes `content/{id}.destination`. `{contentId,
 *       clear: true}` removes it. Clients cannot write `destination` or the
 *       click counters themselves (firestore.rules).
 *   contentOpenDestination `{contentId}` → `{kind, url, route, verdict,
 *       reasons}`. Re-checks web links (Web Risk is cached 24 h), counts the
 *       click (`destinationClicks`, plus `destinationUniqueClicks` once per
 *       person via `content/{id}/destination_clicks/{uid}`), and blocks the
 *       destination if Ova Guard now says it is dangerous.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const linkSafety_1 = require("../guard/linkSafety");
const reputation_1 = require("../guard/reputation");
const protect_1 = require("../guard/protect");
const destination_logic_1 = require("./destination_logic");
const db = () => (0, firestore_1.getFirestore)();
const CONTENT_ID = /^[A-Za-z0-9_-]{1,64}$/;
async function guardVerdict(url) {
    var _a, _b;
    const finding = (0, linkSafety_1.analyzeUrl)(url);
    if (!finding)
        return { verdict: 'safe', reasons: [] };
    const [rep] = await (0, reputation_1.checkLinks)({ links: [finding], points: 0, reasons: [], categories: [] });
    return { verdict: (_a = rep === null || rep === void 0 ? void 0 : rep.verdict) !== null && _a !== void 0 ? _a : 'safe', reasons: ((_b = rep === null || rep === void 0 ? void 0 : rep.reasons) !== null && _b !== void 0 ? _b : []).slice(0, 3) };
}
function contentIdOf(data) {
    var _a;
    const id = String((_a = data === null || data === void 0 ? void 0 : data.contentId) !== null && _a !== void 0 ? _a : '');
    if (!CONTENT_ID.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Missing post.');
    return id;
}
exports.contentSetDestination = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e;
    const uid = (0, protect_1.requireAccount)(request);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const contentId = contentIdOf(data);
    await (0, protect_1.limit)(uid, 'destination_set', 30, 10 * 60000);
    const ref = db().collection('content').doc(contentId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'That post does not exist.');
    if (snap.get('authorId') !== uid)
        throw new https_1.HttpsError('permission-denied', 'Only the creator can change this link.');
    if (data.clear === true) {
        await ref.update({ destination: firestore_1.FieldValue.delete(), link: null });
        return { ok: true, destination: null };
    }
    const parsed = (0, destination_logic_1.parseDestination)(data);
    if (!parsed.ok)
        throw new https_1.HttpsError('invalid-argument', parsed.reason);
    const d = parsed.value;
    let productTitle = null;
    if (d.kind === 'product' && d.productId) {
        const p = await db().collection('biz_products').doc(d.productId).get();
        if (!p.exists)
            throw new https_1.HttpsError('not-found', 'That product is not in Biz anymore.');
        productTitle = typeof p.get('title') === 'string' ? p.get('title') : null;
    }
    let verdict = 'safe';
    let reasons = [];
    if (d.kind === 'web' && d.url) {
        ({ verdict, reasons } = await guardVerdict(d.url));
        if (verdict === 'dangerous') {
            throw new https_1.HttpsError('failed-precondition', `Ova Guard blocked this link: ${(_b = reasons[0]) !== null && _b !== void 0 ? _b : 'it is on a list of dangerous sites'}.`);
        }
    }
    const destination = {
        kind: d.kind,
        url: d.url,
        host: d.host,
        route: d.route,
        productId: d.productId,
        label: d.label || (0, destination_logic_1.defaultLabel)(d.kind, d.host, productTitle),
        verdict,
        reasons,
        status: 'ok',
        checkedAt: firestore_1.FieldValue.serverTimestamp(),
    };
    await ref.update({
        destination,
        link: (_c = d.url) !== null && _c !== void 0 ? _c : d.route,
        destinationClicks: (_d = snap.get('destinationClicks')) !== null && _d !== void 0 ? _d : 0,
        destinationUniqueClicks: (_e = snap.get('destinationUniqueClicks')) !== null && _e !== void 0 ? _e : 0,
    });
    return { ok: true, destination: Object.assign(Object.assign({}, destination), { checkedAt: null }) };
});
exports.contentOpenDestination = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c;
    const uid = (0, protect_1.requireAccount)(request);
    const contentId = contentIdOf(request.data);
    await (0, protect_1.limit)(uid, 'destination_open', 120, 10 * 60000);
    const ref = db().collection('content').doc(contentId);
    const snap = await ref.get();
    const dest = snap.get('destination');
    if (!snap.exists || !dest)
        throw new https_1.HttpsError('not-found', 'This link is no longer on the post.');
    if (dest.status === 'blocked') {
        return { kind: dest.kind, url: null, route: null, verdict: 'dangerous', reasons: (_a = dest.reasons) !== null && _a !== void 0 ? _a : [] };
    }
    let verdict = String((_b = dest.verdict) !== null && _b !== void 0 ? _b : 'safe');
    let reasons = (_c = dest.reasons) !== null && _c !== void 0 ? _c : [];
    const url = typeof dest.url === 'string' ? dest.url : null;
    if (dest.kind === 'web' && url)
        ({ verdict, reasons } = await guardVerdict(url));
    const clickRef = ref.collection('destination_clicks').doc(uid);
    await db().runTransaction(async (tx) => {
        const click = await tx.get(clickRef);
        const update = { destinationClicks: firestore_1.FieldValue.increment(1) };
        if (!click.exists) {
            update.destinationUniqueClicks = firestore_1.FieldValue.increment(1);
            tx.set(clickRef, { uid, firstAt: firestore_1.FieldValue.serverTimestamp(), lastAt: firestore_1.FieldValue.serverTimestamp(), count: 1 });
        }
        else {
            tx.update(clickRef, { lastAt: firestore_1.FieldValue.serverTimestamp(), count: firestore_1.FieldValue.increment(1) });
        }
        if (verdict === 'dangerous') {
            update['destination.status'] = 'blocked';
            update['destination.verdict'] = 'dangerous';
            update['destination.reasons'] = reasons;
        }
        else if (verdict !== dest.verdict) {
            update['destination.verdict'] = verdict;
            update['destination.reasons'] = reasons;
        }
        tx.update(ref, update);
    });
    return {
        kind: dest.kind,
        url: verdict === 'dangerous' ? null : url,
        route: typeof dest.route === 'string' ? dest.route : null,
        verdict,
        reasons,
    };
});
//# sourceMappingURL=destinationLinks.js.map