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
exports.shareToAudience = void 0;
/**
 * "Share to all": sends one post to everyone who follows you (or everyone you
 * follow) as a friendly notification ("Amina shared a post with you"),
 * instead of flooding chats. Done on the server because it has to respect
 * each recipient's own privacy settings, which the sender cannot read:
 *
 *  - `user_settings/{rid}.privacy.messagePermissions == 'none'` → skipped;
 *    'contactsOnly' → only when the recipient follows the sender.
 *  - `user_settings/{rid}.privacy.allowShares === false` → skipped (opt-out).
 *  - Anyone who blocked the sender (relationships/{rid}_{sender} blocked) → skipped.
 *  - Posts the sender may not share (private, or another creator's post with
 *    sharing off) → refused.
 *
 * Rate limits: 3 bulk shares per rolling hour, 10 per day, 500 people each.
 * The same post reaches the same person at most once (deterministic ids).
 */
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const db = () => (0, firestore_1.getFirestore)();
const MAX_RECIPIENTS = 500;
const PER_HOUR = 3;
const PER_DAY = 10;
async function takeRateSlot(uid) {
    const ref = db().collection('share_limits').doc(uid);
    return db().runTransaction(async (tx) => {
        var _a;
        const now = Date.now();
        const recent = ((_a = (await tx.get(ref)).get('bulk')) !== null && _a !== void 0 ? _a : [])
            .filter((t) => now - t < 24 * 3600000);
        if (recent.length >= PER_DAY || recent.filter((t) => now - t < 3600000).length >= PER_HOUR)
            return false;
        tx.set(ref, { bulk: [...recent, now], updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    });
}
async function audienceIds(uid, audience) {
    const field = audience === 'following' ? 'followerId' : 'followingId';
    const other = audience === 'following' ? 'followingId' : 'followerId';
    const snap = await db().collection('relationships')
        .where(field, '==', uid).where('status', '==', 'accepted').limit(MAX_RECIPIENTS).get();
    return [...new Set(snap.docs.map((d) => String(d.get(other) || '')).filter((id) => id && id !== uid))];
}
exports.shareToAudience = (0, https_1.onCall)({ timeoutSeconds: 120, memory: '256MiB' }, async (request) => {
    var _a;
    var _b;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to share.');
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const postId = typeof data.postId === 'string' ? data.postId.trim() : '';
    const audience = data.audience === 'following' ? 'following' : 'followers';
    const note = typeof data.message === 'string' ? data.message.trim().slice(0, 140) : '';
    if (!postId || postId.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Pick a post to share.');
    // The post must exist and be shareable by this person.
    let post;
    for (const col of ['content', 'posts']) {
        post = (await db().collection(col).doc(postId).get()).data();
        if (post)
            break;
    }
    if (!post)
        throw new https_1.HttpsError('not-found', 'This post is no longer available.');
    const authorId = String(post.authorId || '');
    const isPrivate = post.isPrivate === true || post.visibility === 'private' || post.privacy === 'private';
    if (isPrivate && authorId !== uid)
        throw new https_1.HttpsError('permission-denied', 'This post is private, so it can’t be shared.');
    if (post.allowShare === false && authorId !== uid)
        throw new https_1.HttpsError('permission-denied', 'The creator turned off sharing for this post.');
    if (!(await takeRateSlot(uid))) {
        throw new https_1.HttpsError('resource-exhausted', 'You’ve shared to everyone a few times already. Try again a bit later.');
    }
    const me = (await db().collection('users').doc(uid).get()).data() || {};
    const myName = String(me.fullName || me.displayName || me.username || 'Someone').trim();
    const myAvatar = [me.avatarUrl, me.photoUrl, me.photoURL].find((v) => typeof v === 'string' && v.startsWith('http'));
    const ids = await audienceIds(uid, audience);
    let sent = 0;
    let skipped = 0;
    for (let i = 0; i < ids.length; i += 100) {
        const chunk = ids.slice(i, i + 100);
        const settings = await db().getAll(...chunk.map((id) => db().collection('user_settings').doc(id)));
        // relationships/{rid}_{me}: blocked, or (accepted) they follow me.
        const blocks = await db().getAll(...chunk.map((id) => db().collection('relationships').doc(`${id}_${uid}`)));
        const notes = await db().getAll(...chunk.map((id) => db().collection('notifications').doc(`share_${postId}_${uid}_${id}`)));
        const batch = db().batch();
        chunk.forEach((rid, j) => {
            const privacy = (settings[j].get('privacy') || {});
            const rel = blocks[j].get('status');
            const perm = String(privacy.messagePermissions || 'everyone');
            const follows = audience === 'followers' || rel === 'accepted';
            if (rel === 'blocked' || privacy.allowShares === false || perm === 'none' ||
                (perm === 'contactsOnly' && !follows) || notes[j].exists) {
                skipped++;
                return;
            }
            batch.set(notes[j].ref, {
                userId: rid,
                recipientId: rid,
                actorId: uid,
                category: 'share',
                priority: 'normal',
                type: 'social',
                title: `${myName} shared a post with you`,
                body: note ? `“${note}”` : 'Tap to watch it.',
                message: note ? `“${note}”` : 'Tap to watch it.',
                deepLink: `/hub/home?v=${postId}`,
                groupId: `share_${uid}`,
                payload: Object.assign(Object.assign({ postId, sharedWithYou: true, actorName: myName }, (myAvatar ? { avatarUrl: myAvatar } : {})), (typeof post.thumbnailUrl === 'string' ? { thumbnailUrl: post.thumbnailUrl } : {})),
                isRead: false,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                timestamp: firestore_1.FieldValue.serverTimestamp(),
            });
            sent++;
        });
        await batch.commit();
    }
    await db().collection('share_logs').add({
        uid, postId, audience, sent, skipped, createdAt: firestore_1.Timestamp.now(),
    }).catch(() => undefined);
    logger.info('shareToAudience', { uid, postId, audience, sent, skipped });
    return { sent, skipped, total: ids.length };
});
//# sourceMappingURL=shareAudience.js.map