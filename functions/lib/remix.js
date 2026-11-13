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
exports.remixOnDelete = exports.remixOnCreate = void 0;
/**
 * Remixes: a post published from Studio's Remix carries
 * `remixOf: {contentId, authorId, authorName, status: 'pending'}`.
 *
 * remixOnCreate checks the original creator allows remixes (remix_logic):
 * - allowed: writes `remix_links/{remixContentId}` (the earnings split that
 *   sendUserGift applies), marks the remix `active`, bumps the original's
 *   `remixCount` and tells its creator;
 * - not allowed: marks it `rejected`, takes the remix private and tells the
 *   remixer why.
 * remixOnDelete ends the link when a remix is deleted.
 *
 * Only this server writes `remix_links` (no client rules).
 */
const firestore_1 = require("firebase-functions/v2/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const remix_logic_1 = require("./remix_logic");
const db = () => (0, firestore_2.getFirestore)();
const safeId = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);
exports.remixOnCreate = (0, firestore_1.onDocumentCreated)('content/{contentId}', async (e) => {
    var _a;
    var _b, _c;
    const data = (_a = e.data) === null || _a === void 0 ? void 0 : _a.data();
    const remixOf = data === null || data === void 0 ? void 0 : data.remixOf;
    if (!data || !remixOf)
        return;
    const remixId = e.params.contentId;
    const remixAuthorId = String((_b = data.authorId) !== null && _b !== void 0 ? _b : '');
    const ref = e.data.ref;
    const originalId = remixOf.contentId;
    if (!safeId(originalId) || !remixAuthorId) {
        await ref.update({ 'remixOf.status': 'rejected', 'remixOf.reason': 'bad_request' });
        return;
    }
    const original = await db().doc(`content/${originalId}`).get();
    const verdict = (0, remix_logic_1.remixAllowed)(original.data(), remixAuthorId, remixOf.authorId);
    if (!verdict.ok) {
        logger.info('Remix rejected', { remixId, originalId, reason: verdict.reason });
        const update = { 'remixOf.status': 'rejected', 'remixOf.reason': verdict.reason };
        // The creator turned remixes off: the remix does not stay public.
        if (verdict.reason === 'not_allowed' || verdict.reason === 'not_public')
            update.visibility = 'private';
        if (verdict.reason === 'own_post') {
            // Remixing yourself is fine; there is just nothing to split.
            await ref.update({ remixOf: firestore_2.FieldValue.delete(), attribution: firestore_2.FieldValue.delete() });
            return;
        }
        await ref.update(update);
        await db().collection('notifications').doc(`remix_rejected_${remixId}`).set({
            userId: remixAuthorId, recipientId: remixAuthorId, category: 'system', priority: 'normal', type: 'remix_rejected',
            title: 'Your remix is private',
            body: verdict.reason === 'not_allowed'
                ? 'The creator of the original turned off remixes, so only you can see it.'
                : 'The original post is no longer public, so only you can see your remix.',
            deepLink: `/hub/home`, isRead: false, createdAt: firestore_2.FieldValue.serverTimestamp(),
        });
        return;
    }
    const originalAuthorId = String(original.get('authorId'));
    const batch = db().batch();
    batch.set(db().doc(`remix_links/${remixId}`), {
        remixContentId: remixId,
        remixAuthorId,
        originalContentId: originalId,
        originalAuthorId,
        share: remix_logic_1.REMIX_ORIGINAL_SHARE,
        status: 'active',
        giftCoins: 0,
        originalCoins: 0,
        createdAt: firestore_2.FieldValue.serverTimestamp(),
    });
    batch.update(ref, { 'remixOf.status': 'active', 'remixOf.share': remix_logic_1.REMIX_ORIGINAL_SHARE });
    batch.set(original.ref, { remixCount: firestore_2.FieldValue.increment(1) }, { merge: true });
    const me = (_c = (await db().doc(`users/${remixAuthorId}`).get()).data()) !== null && _c !== void 0 ? _c : {};
    const name = String(me.fullName || me.displayName || me.username || 'Someone');
    batch.set(db().collection('notifications').doc(`remix_${remixId}`), {
        userId: originalAuthorId, recipientId: originalAuthorId, actorId: remixAuthorId, category: 'social', priority: 'normal', type: 'remix',
        title: `${name} remixed your post`,
        body: `You get ${Math.round(remix_logic_1.REMIX_ORIGINAL_SHARE * 100)}% of the gift coins their remix earns.`,
        deepLink: `/profile/${remixAuthorId}`, isRead: false, createdAt: firestore_2.FieldValue.serverTimestamp(),
    });
    await batch.commit();
});
exports.remixOnDelete = (0, firestore_1.onDocumentDeleted)('content/{contentId}', async (e) => {
    var _a;
    const remixOf = (_a = e.data) === null || _a === void 0 ? void 0 : _a.get('remixOf');
    if (!remixOf)
        return;
    const link = db().doc(`remix_links/${e.params.contentId}`);
    const snap = await link.get();
    if (!snap.exists)
        return;
    await link.update({ status: 'ended', endedAt: firestore_2.FieldValue.serverTimestamp() });
    const originalId = snap.get('originalContentId');
    if (safeId(originalId))
        await db().doc(`content/${originalId}`).set({ remixCount: firestore_2.FieldValue.increment(-1) }, { merge: true });
});
//# sourceMappingURL=remix.js.map