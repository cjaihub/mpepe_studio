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
exports.ACTIONS = void 0;
exports.takeAction = takeAction;
exports.reverseAction = reverseAction;
exports.recentActions = recentActions;
exports.applyEventPolicy = applyEventPolicy;
/**
 * Ova Guard — automatic action-taker.
 *
 * The only things it can do are in ACTIONS below (a fixed allow-list). There
 * is no ban, delete or suspend action: the strongest steps are temporary and
 * every one is
 *   - recorded in `security_actions/{id}` (admin-readable) with a plain
 *     reason and an expiry,
 *   - shown to the affected user as an event in
 *     `security_events/{uid}/events` (type `guard_action`),
 *   - reversible by an admin with `guardReverseAction`.
 * Anything that needs more than this is escalated to a human
 * (`moderation_cases`, source "ova_guard").
 *
 * Enforcement:
 *   rate_limit          security_state/{uid}.restrictions.{scope} = until;
 *                       firestore.rules refuse new chat messages / comments /
 *                       follows while it is in the future.
 *   hide_content        sets isModerated / safety.hidden on the doc, which the
 *                       app already filters out, "pending review".
 *   force_reauth        revokeRefreshTokens + sessionsRevokedAt, which every
 *                       signed-in device watches and signs out on.
 *   freeze_withdrawals  security_state/{uid}.withdrawalsFrozenUntil. Only taken
 *                       when GUARD_WITHDRAWAL_FREEZE=true, which is set once
 *                       requestWithdrawal checks that field (it does not yet).
 *   notify_user         an in-app + push notification.
 *   escalate_admin      a moderation case for a human reviewer.
 */
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const db = () => (0, firestore_1.getFirestore)();
exports.ACTIONS = ['rate_limit', 'hide_content', 'force_reauth', 'freeze_withdrawals', 'notify_user', 'escalate_admin'];
const MAX_MS = {
    rate_limit: 24 * 3600000,
    hide_content: 0,
    force_reauth: 0,
    freeze_withdrawals: 72 * 3600000,
    notify_user: 0,
    escalate_admin: 0,
};
const LABEL = {
    rate_limit: 'Sending paused for a while',
    hide_content: 'Content hidden until reviewed',
    force_reauth: 'Signed out everywhere for safety',
    freeze_withdrawals: 'Withdrawals paused for safety',
    notify_user: 'Safety notice sent',
    escalate_admin: 'Sent to the Oneova safety team',
};
function untilFor(req) {
    var _a;
    const max = MAX_MS[req.action];
    if (!max)
        return null;
    return firestore_1.Timestamp.fromMillis(Date.now() + Math.min(max, Math.max(60000, (_a = req.durationMs) !== null && _a !== void 0 ? _a : max)));
}
/** Runs one allow-listed action. Never throws: guard work must not break the app. */
async function takeAction(req) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (!exports.ACTIONS.includes(req.action) || !req.uid)
        return null;
    // Never show a freeze that the withdrawal flow does not enforce.
    if (req.action === 'freeze_withdrawals' && process.env.GUARD_WITHDRAWAL_FREEZE !== 'true')
        return null;
    try {
        const until = untilFor(req);
        const ref = db().collection('security_actions').doc();
        const state = db().collection('security_state').doc(req.uid);
        switch (req.action) {
            case 'rate_limit':
                await state.set({ restrictions: { [(_a = req.scope) !== null && _a !== void 0 ? _a : 'messaging']: until } }, { merge: true });
                break;
            case 'freeze_withdrawals':
                await state.set({ withdrawalsFrozenUntil: until, withdrawalsFrozenReason: req.reason }, { merge: true });
                break;
            case 'hide_content':
                if (!req.targetPath)
                    return null;
                await db().doc(req.targetPath).set({
                    isModerated: true,
                    safety: { hidden: true, state: 'pending_review', by: 'ova_guard', reason: req.reason, actionId: ref.id },
                }, { merge: true });
                break;
            case 'force_reauth':
                await (0, auth_1.getAuth)().revokeRefreshTokens(req.uid);
                await state.set({ sessionsRevokedAt: firestore_1.FieldValue.serverTimestamp(), sessions: {} }, { merge: true });
                // Keep the snapshot in step so the revoke isn't reported as a password change.
                {
                    const after = await (0, auth_1.getAuth)().getUser(req.uid);
                    await state.set({ authSnapshot: { email: (_b = after.email) !== null && _b !== void 0 ? _b : null, phone: (_c = after.phoneNumber) !== null && _c !== void 0 ? _c : null, validAfter: (_d = after.tokensValidAfterTime) !== null && _d !== void 0 ? _d : null } }, { merge: true });
                }
                break;
            case 'notify_user':
                await db().collection('notifications').add({
                    userId: req.uid,
                    category: 'security',
                    type: 'security_notice',
                    priority: 'high',
                    title: (_e = req.notifyTitle) !== null && _e !== void 0 ? _e : 'Ova Guard',
                    body: req.reason.slice(0, 240),
                    deepLink: '/profile/security',
                    payload: { route: '/profile/security', actionId: ref.id },
                    isRead: false,
                    timestamp: firestore_1.FieldValue.serverTimestamp(),
                    createdAt: firestore_1.FieldValue.serverTimestamp(),
                });
                break;
            case 'escalate_admin':
                await db().collection('moderation_cases').add({
                    source: 'ova_guard',
                    subjectUid: req.uid,
                    targetPath: (_f = req.targetPath) !== null && _f !== void 0 ? _f : null,
                    reason: req.reason,
                    trigger: req.source,
                    state: 'open',
                    createdAt: firestore_1.FieldValue.serverTimestamp(),
                });
                break;
        }
        await ref.set({
            uid: req.uid,
            action: req.action,
            label: LABEL[req.action],
            reason: req.reason,
            source: req.source,
            scope: (_g = req.scope) !== null && _g !== void 0 ? _g : null,
            targetPath: (_h = req.targetPath) !== null && _h !== void 0 ? _h : null,
            eventId: (_j = req.eventId) !== null && _j !== void 0 ? _j : null,
            status: until ? 'active' : 'done',
            expiresAt: until,
            reversible: req.action !== 'notify_user',
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        if (req.action !== 'notify_user') {
            await db().collection('security_events').doc(req.uid).collection('events').add({
                type: 'guard_action',
                title: LABEL[req.action],
                score: 0,
                risk: 'low',
                reasons: [req.reason],
                status: 'closed',
                actionId: ref.id,
                action: req.action,
                expiresAt: until,
                details: { source: req.source },
                at: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        return ref.id;
    }
    catch (e) {
        logger.error('guard action failed', { action: req.action, uid: req.uid, error: String(e) });
        return null;
    }
}
/** Undoes one action (admin), or lets it lapse (sweep). */
async function reverseAction(actionId, by, why, status = 'reversed') {
    var _a, _b;
    const ref = db().collection('security_actions').doc(actionId);
    const snap = await ref.get();
    if (!snap.exists || !['active', 'done'].includes(String(snap.get('status'))))
        return false;
    const a = snap.data();
    const state = db().collection('security_state').doc(a.uid);
    switch (a.action) {
        case 'rate_limit':
            await state.set({ restrictions: { [(_a = a.scope) !== null && _a !== void 0 ? _a : 'messaging']: firestore_1.FieldValue.delete() } }, { merge: true });
            break;
        case 'freeze_withdrawals':
            await state.set({ withdrawalsFrozenUntil: firestore_1.FieldValue.delete(), withdrawalsFrozenReason: firestore_1.FieldValue.delete() }, { merge: true });
            break;
        case 'hide_content':
            if (a.targetPath && status === 'reversed') {
                await db().doc(a.targetPath).set({ isModerated: false, safety: { hidden: false, state: 'restored', reviewedBy: by } }, { merge: true }).catch(() => undefined);
            }
            break;
        default:
            break; // force_reauth / escalate / notify have nothing to undo
    }
    await ref.update({ status, reversedBy: by, reversedReason: why.slice(0, 300), reversedAt: firestore_1.FieldValue.serverTimestamp() });
    if (status === 'reversed') {
        await db().collection('security_events').doc(a.uid).collection('events').add({
            type: 'guard_action_reversed',
            title: 'Safety step removed',
            score: 0,
            risk: 'low',
            reasons: [`The Oneova team removed “${(_b = a.label) !== null && _b !== void 0 ? _b : a.action}”${why ? `: ${why.slice(0, 160)}` : ''}`],
            status: 'closed',
            actionId,
            at: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    return true;
}
/** How many actions of this kind this user got in the last `ms`. */
async function recentActions(uid, source, ms) {
    const q = await db()
        .collection('security_actions')
        .where('uid', '==', uid)
        .where('createdAt', '>=', firestore_1.Timestamp.fromMillis(Date.now() - ms))
        .limit(50)
        .get();
    return q.docs.filter((d) => d.get('source') === source).length;
}
// ─────────────── Policy: which events lead to which actions ───────────────
/**
 * Called by recordSecurityEvent for every new account event. Fixed rules;
 * the AI never picks actions.
 */
async function applyEventPolicy(uid, type, score, reasons, eventId, details) {
    var _a;
    const reason = (_a = reasons[0]) !== null && _a !== void 0 ? _a : 'Unusual activity on your account';
    const run = (action, extra = {}) => takeAction(Object.assign({ uid, action, reason, source: `event:${type}`, eventId }, extra));
    switch (type) {
        case 'session_reuse':
            // A copied sign-in token: end every session and protect the money.
            await run('force_reauth');
            await run('freeze_withdrawals', { durationMs: 48 * 3600000 });
            break;
        case 'impossible_travel':
            await run('freeze_withdrawals', { durationMs: 48 * 3600000 });
            if (score >= 90)
                await run('escalate_admin');
            break;
        case 'email_changed':
        case 'phone_changed':
        case 'password_changed':
            if (details.newDevice)
                await run('freeze_withdrawals', { durationMs: 48 * 3600000 });
            break;
        case 'profile_change_spike':
            await run('freeze_withdrawals', { durationMs: 24 * 3600000 });
            break;
        case 'message_spike':
            if (score >= 70) {
                await run('rate_limit', { scope: 'messaging', durationMs: 3600000 });
                await run('notify_user', { notifyTitle: 'Messaging paused for 1 hour', reason: `${reason}. If this wasn’t you, open Security and tap “Secure my account”.` });
            }
            break;
        case 'follow_spike':
            if (score >= 70)
                await run('rate_limit', { scope: 'follows', durationMs: 3600000 });
            break;
        case 'auth_failures':
            // Only server-checked failures: signed-out reports could be forged to freeze someone else.
            if (score >= 70 && details.verified)
                await run('freeze_withdrawals', { durationMs: 24 * 3600000 });
            break;
        default:
            break;
    }
}
//# sourceMappingURL=actions.js.map