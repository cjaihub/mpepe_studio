"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsFun = void 0;
/**
 * LIVE STUDIO v2 — host entertainment: `lsFun({streamId, op, ...})`.
 *   host / co-host: pollStart {question, options[2..4], seconds} · pollEnd
 *                   timerStart {label?, seconds} · timerStop
 *                   spotlight {text} | {commentId} · spotlightClear
 *                   celebrate {kind: confetti|hearts|fireworks} · raffle
 *   everyone:       pollVote {option}  (one vote per person, can change it)
 * State: `live_streams/{id}/studio/fun` (clients listen). Pure rules: fun_logic.ts.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const fun_logic_1 = require("./fun_logic");
const funPath = (streamId) => `${contracts_1.Paths.streams}/${streamId}/studio/fun`;
const votePath = (streamId, pollId, uid) => `${contracts_1.Paths.streams}/${streamId}/studio_fun_votes/${pollId}_${uid}`;
function guard(fn) {
    try {
        return fn();
    }
    catch (e) {
        if (e instanceof fun_logic_1.FunError)
            throw new https_1.HttpsError('invalid-argument', e.message);
        throw e;
    }
}
async function readFun(streamId) {
    var _a;
    const snap = await (0, shared_1.db)().doc(funPath(streamId)).get();
    return Object.assign(Object.assign({}, (0, fun_logic_1.emptyFun)()), ((_a = snap.data()) !== null && _a !== void 0 ? _a : {}));
}
exports.lsFun = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a, _b, _c, _d, _e, _f;
    const uid = (0, shared_1.requireUid)(req);
    const data = (req.data && typeof req.data === 'object' ? req.data : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const op = guard(() => (0, fun_logic_1.parseOp)(data.op));
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    const ref = (0, shared_1.db)().doc(funPath(streamId));
    const now = Date.now();
    if (op === 'pollVote') {
        if (await (0, shared_1.isBlocked)(streamId, uid))
            throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
        await (0, shared_1.rateLimit)(streamId, uid, 'fun_vote', 6, 10000);
        const option = typeof data.option === 'number' ? data.option : -1;
        const counts = await (0, shared_1.db)().runTransaction(async (tx) => {
            var _a;
            const funSnap = await tx.get(ref);
            const fun = Object.assign(Object.assign({}, (0, fun_logic_1.emptyFun)()), ((_a = funSnap.data()) !== null && _a !== void 0 ? _a : {}));
            if (!(0, fun_logic_1.pollAccepting)(fun.poll, now))
                throw new https_1.HttpsError('failed-precondition', 'This poll is closed.');
            const poll = fun.poll;
            const vRef = (0, shared_1.db)().doc(votePath(streamId, poll.id, uid));
            const vSnap = await tx.get(vRef);
            const prev = vSnap.exists ? vSnap.get('option') : null;
            const next = guard(() => (0, fun_logic_1.applyVote)(poll, prev, option));
            tx.set(ref, { poll: next, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
            tx.set(vRef, { uid, pollId: poll.id, option, at: now });
            return next.counts;
        });
        return { ok: true, option, counts };
    }
    await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
    await (0, shared_1.rateLimit)(streamId, uid, 'fun_ctl', 20, 60000);
    const patch = {};
    switch (op) {
        case 'pollStart':
            patch.poll = guard(() => (0, fun_logic_1.newPoll)(data, `p${now.toString(36)}`, now));
            break;
        case 'pollEnd': {
            const fun = await readFun(streamId);
            if (fun.poll)
                patch.poll = Object.assign(Object.assign({}, fun.poll), { open: false, endsAtMs: Math.min(fun.poll.endsAtMs, now) });
            break;
        }
        case 'timerStart':
            patch.timer = guard(() => (0, fun_logic_1.newTimer)(data, now));
            break;
        case 'timerStop':
            patch.timer = null;
            break;
        case 'spotlight': {
            if (typeof data.commentId === 'string' && data.commentId) {
                const c = await (0, shared_1.db)().doc(`${contracts_1.Paths.comments(streamId)}/${data.commentId}`).get();
                if (!c.exists)
                    throw new https_1.HttpsError('not-found', 'That comment is gone.');
                patch.spotlight = {
                    text: String((_a = c.get('text')) !== null && _a !== void 0 ? _a : '').slice(0, fun_logic_1.FUN_LIMITS.spotlightMax),
                    uid: String((_b = c.get('uid')) !== null && _b !== void 0 ? _b : ''),
                    name: String((_c = c.get('name')) !== null && _c !== void 0 ? _c : ''),
                    avatarUrl: String((_d = c.get('avatarUrl')) !== null && _d !== void 0 ? _d : ''),
                    atMs: now,
                };
            }
            else {
                const host = await (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`).get();
                const m = host.data();
                patch.spotlight = {
                    text: guard(() => (0, fun_logic_1.parseSpotlightText)(data.text)),
                    uid,
                    name: (_e = m === null || m === void 0 ? void 0 : m.displayName) !== null && _e !== void 0 ? _e : '',
                    avatarUrl: (_f = m === null || m === void 0 ? void 0 : m.avatarUrl) !== null && _f !== void 0 ? _f : '',
                    atMs: now,
                };
            }
            break;
        }
        case 'spotlightClear':
            patch.spotlight = null;
            break;
        case 'celebrate':
            patch.celebrate = { kind: (0, fun_logic_1.parseCelebration)(data.kind), atMs: now };
            break;
        case 'raffle': {
            const recent = await (0, shared_1.db)()
                .collection(contracts_1.Paths.comments(streamId))
                .where('ts', '>=', now - fun_logic_1.FUN_LIMITS.raffleWindowMs)
                .orderBy('ts', 'desc')
                .limit(500)
                .get();
            const entrants = (0, fun_logic_1.raffleEntrants)(recent.docs.map((d) => { var _a, _b, _c, _d; return ({
                uid: String((_a = d.get('uid')) !== null && _a !== void 0 ? _a : ''),
                name: String((_b = d.get('name')) !== null && _b !== void 0 ? _b : ''),
                avatarUrl: String((_c = d.get('avatarUrl')) !== null && _c !== void 0 ? _c : ''),
                ts: Number((_d = d.get('ts')) !== null && _d !== void 0 ? _d : 0),
            }); }), now, [state.hostId]);
            const w = (0, fun_logic_1.pickWinner)(entrants, Math.random());
            if (!w)
                throw new https_1.HttpsError('failed-precondition', 'Nobody has commented in the last 10 minutes yet.');
            patch.raffle = { winnerUid: w.uid, winnerName: w.name, winnerAvatarUrl: w.avatarUrl, entrants: entrants.length, atMs: now };
            break;
        }
    }
    await ref.set(Object.assign(Object.assign({}, patch), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    // Instant nudge for celebrations / winners; Firestore stays the source of record.
    await (0, shared_1.broadcast)(streamId, 'studio.fun', { v: 1, type: 'fun', op, ts: now }, { lossy: true });
    return { ok: true, op };
});
//# sourceMappingURL=fun.js.map