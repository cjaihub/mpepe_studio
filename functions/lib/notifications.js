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
exports.onNotificationCreated = void 0;
/**
 * Activity push fan-out.
 *
 * Every in-app alert is a `notifications/{id}` doc (likes, comments, follows,
 * "X posted", "X is LIVE", ...). This trigger mirrors each new doc to the
 * recipient's devices as a ringing push so it arrives while Oneova is in the
 * background or closed. While the app is open the in-app banner rings instead
 * (the foreground handler skips pushes that carry `notificationId`).
 *
 * Honours the recipient's notification settings (`user_settings/{uid}.notifications`,
 * falling back to `users/{uid}/settings/notifications`): push on/off,
 * per-category switches, quiet hours (urgent bypasses), sound and preview.
 *
 * Friendly copy: writers often store terse text ("New Like" / "Someone liked
 * your video"). The trigger looks up who did it and rewrites the title/body
 * in plain language ("Amina liked your video"), saving it back on the doc so
 * the in-app notification centre reads the same.
 *
 * Rich pushes: Android devices that registered with `richPush: true` get a
 * data-only message (`render: 'rich'`) that the app draws itself with the
 * person's photo, a post preview, grouping and action buttons (Reply, Like,
 * Follow back, Watch, Update). Older builds and iOS keep the plain
 * notification payload.
 */
const firestore_1 = require("firebase-functions/v2/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const accountSettings_1 = require("./accountSettings");
const db = () => (0, firestore_2.getFirestore)();
// Calls ring through calls.ts; chat pushes are sent by the messaging pipeline.
const SKIP = new Set(['call', 'missedCall', 'newMessage']);
function inQuietHours(p) {
    var _a, _b, _c;
    if (!p.dndEnabled)
        return false;
    const start = (_a = p.quietHoursStart) !== null && _a !== void 0 ? _a : 22;
    const end = (_b = p.quietHoursEnd) !== null && _b !== void 0 ? _b : 8;
    if (start === end)
        return false;
    const local = new Date(Date.now() + ((_c = p.timezoneOffsetMinutes) !== null && _c !== void 0 ? _c : 0) * 60000);
    const hour = local.getUTCHours();
    return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}
async function resolveActor(n) {
    const p = n.payload || {};
    const id = n.actorId || p.actorId || p.followerId || p.userId || p.authorId || p.senderId || p.hostId;
    if (!id || id === (n.userId || n.recipientId))
        return null;
    const snap = await db().collection('users').doc(id).get().catch(() => null);
    const u = (snap === null || snap === void 0 ? void 0 : snap.data()) || {};
    const name = [u.fullName, u.displayName, u.username, p.actorName, p.senderName, p.hostName]
        .find((v) => typeof v === 'string' && v.trim().length > 0);
    const avatar = [u.avatarUrl, u.photoUrl, u.photoURL, p.avatarUrl, p.actorAvatar, p.senderAvatar]
        .find((v) => typeof v === 'string' && v.startsWith('http'));
    return { id, name: name ? String(name).trim() : 'Someone', avatar };
}
async function postPreview(postId) {
    var _a;
    if (!postId)
        return undefined;
    for (const col of ['posts', 'content']) {
        const d = (_a = (await db().collection(col).doc(postId).get().catch(() => null))) === null || _a === void 0 ? void 0 : _a.data();
        const url = d && [d.thumbnailUrl, d.coverUrl, d.thumbnail, d.imageUrl].find((v) => typeof v === 'string' && v.startsWith('http'));
        if (url)
            return String(url);
    }
    return undefined;
}
/** Old terse defaults we replace with plain, friendly copy. */
const GENERIC_TITLES = new Set(['new like', 'new comment', 'new reply', 'new follower', 'new mention', 'oneova', '']);
function friendlyCopy(category, actor, n) {
    var _a;
    const who = (actor === null || actor === void 0 ? void 0 : actor.name) || 'Someone';
    const title = String(n.title || '');
    const body = String(n.body || n.message || '');
    const generic = GENERIC_TITLES.has(title.trim().toLowerCase()) || body.startsWith('Someone ');
    const quoted = (body.match(/"(.+)"/) || [])[1];
    const keep = (t, b) => (generic ? [t, b] : [title || t, body || b]);
    let t;
    let b;
    let actions = ['open'];
    let group = category;
    switch (category) {
        case 'like':
        case 'reaction':
            [t, b] = keep(`${who} liked your post`, 'Your post is getting some love. Tap to see it.');
            group = 'like';
            break;
        case 'comment':
            [t, b] = keep(`${who} commented on your post`, quoted ? `“${quoted}”` : 'Tap to read it and reply.');
            actions = ['reply', 'open'];
            group = 'comment';
            break;
        case 'reply':
            [t, b] = keep(`${who} replied to your comment`, quoted ? `“${quoted}”` : 'Tap to keep the conversation going.');
            actions = ['reply', 'open'];
            group = 'comment';
            break;
        case 'mention':
            [t, b] = keep(`${who} mentioned you`, quoted ? `“${quoted}”` : 'Tap to see what they said.');
            actions = ['reply', 'open'];
            group = 'comment';
            break;
        case 'newFollower':
            [t, b] = keep(`${who} started following you`, 'Say hi or follow them back.');
            actions = ['follow_back', 'view_profile'];
            group = 'follow';
            break;
        case 'followRequest':
            [t, b] = keep(`${who} wants to follow you`, 'Tap to accept or decline.');
            actions = ['view_profile'];
            group = 'follow';
            break;
        case 'share':
        case 'repost':
            if ((_a = n.payload) === null || _a === void 0 ? void 0 : _a.sharedWithYou) {
                [t, b] = keep(`${who} shared a post with you`, 'Tap to watch it.');
                actions = ['like', 'watch'];
                group = 'shared';
            }
            else {
                [t, b] = keep(`${who} shared your post`, 'More people are seeing your work.');
            }
            break;
        case 'newPost':
            [t, b] = keep(`${who} just posted`, body || 'Be one of the first to see it.');
            actions = ['like', 'watch'];
            break;
        case 'live':
            [t, b] = keep(`${who} is live now`, body || 'Join in before it ends.');
            actions = ['watch'];
            break;
        case 'appUpdate':
            [t, b] = [title || 'A new version of Oneova is ready', body || 'Update to get the latest features and fixes.'];
            actions = ['update'];
            group = 'updates';
            break;
        case 'recommendation':
            [t, b] = [title || 'Your For You feed just got smarter', body || 'We tuned what you see based on what you enjoy.'];
            group = 'updates';
            break;
        case 'profileTip':
            [t, b] = [title || 'Make your profile shine', body || 'A couple of quick details help people find you.'];
            actions = ['complete'];
            group = 'updates';
            break;
        default:
            [t, b] = [title || 'Oneova', body];
    }
    return { title: t, body: b, actions, group };
}
exports.onNotificationCreated = (0, firestore_1.onDocumentCreated)('notifications/{id}', async (event) => {
    var _a, _b;
    const n = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!n)
        return;
    const uid = n.userId || n.recipientId;
    const category = n.category || 'system';
    if (!uid || SKIP.has(category) || n.isRead === true)
        return;
    const actor = await resolveActor(n).catch(() => null);
    const copy = friendlyCopy(category, actor, n);
    const p = n.payload || {};
    const postId = p.postId || p.contentId || p.videoId;
    const image = p.thumbnailUrl || p.mediaUrl || (await postPreview(postId));
    // Save the friendly copy so the in-app centre reads the same as the push.
    const patch = {};
    if (copy.title !== n.title)
        patch.title = copy.title;
    if (copy.body !== (n.body || n.message)) {
        patch.body = copy.body;
        patch.message = copy.body;
    }
    if (actor && !n.actorId)
        patch.actorId = actor.id;
    if (actor && !p.actorName)
        patch['payload.actorName'] = actor.name;
    if ((actor === null || actor === void 0 ? void 0 : actor.avatar) && !p.avatarUrl)
        patch['payload.avatarUrl'] = actor.avatar;
    if (image && !p.thumbnailUrl)
        patch['payload.thumbnailUrl'] = image;
    if (Object.keys(patch).length > 0)
        await event.data.ref.update(patch).catch(() => undefined);
    const prefs = (await (0, accountSettings_1.readAccountSettings)(uid, 'notifications', 'settings/notifications'));
    const urgent = n.priority === 'urgent';
    if (prefs.pushEnabled === false && !urgent)
        return;
    if (((_b = prefs.categoryOverrides) === null || _b === void 0 ? void 0 : _b[category]) === false && !urgent)
        return;
    if (inQuietHours(prefs) && !urgent)
        return;
    const tokens = await db().collection('users').doc(uid).collection('device_tokens').get();
    if (tokens.empty)
        return;
    const sound = prefs.soundEnabled !== false;
    const hidePreview = prefs.previewMessageContent === false;
    const title = copy.title;
    const body = hidePreview ? 'Open Oneova to see it.' : copy.body;
    const route = String(n.deepLink || p.route || '/notifications');
    const live = category === 'live';
    const groupId = n.groupId || undefined;
    const baseData = {
        notificationId: event.params.id,
        category,
        route,
        priority: String(n.priority || 'normal'),
    };
    const rich = tokens.docs.filter((d) => d.get('richPush') === true);
    const plain = tokens.docs.filter((d) => d.get('richPush') !== true);
    const sends = [];
    if (rich.length > 0) {
        const data = Object.assign(Object.assign({}, baseData), { render: 'rich', title,
            body, group: copy.group, actions: copy.actions.join(','), sound: sound ? 'on' : 'off', private: hidePreview ? 'true' : 'false', sentAt: String(Date.now()) });
        if (actor)
            data.actorId = actor.id;
        if ((actor === null || actor === void 0 ? void 0 : actor.avatar) && !hidePreview)
            data.avatarUrl = actor.avatar;
        if (image && !hidePreview)
            data.imageUrl = String(image);
        if (postId)
            data.postId = String(postId);
        if (p.commentId)
            data.commentId = String(p.commentId);
        sends.push((0, messaging_1.getMessaging)().sendEachForMulticast({
            tokens: rich.map((d) => d.id),
            data,
            android: { priority: 'high', collapseKey: groupId, ttl: 24 * 3600 * 1000 },
        }).then((res) => ({ docs: rich, res })));
    }
    if (plain.length > 0) {
        sends.push((0, messaging_1.getMessaging)().sendEachForMulticast({
            tokens: plain.map((d) => d.id),
            notification: { title, body, imageUrl: image && !hidePreview ? String(image) : undefined },
            data: baseData,
            android: {
                priority: 'high',
                collapseKey: groupId,
                notification: {
                    channelId: live ? 'oneova_live_channel' : 'oneova_high_importance_channel',
                    sound: sound ? 'oneova_notification' : undefined,
                    color: live ? '#FF2D87' : '#0C4FA8',
                    tag: groupId,
                    defaultVibrateTimings: true,
                    visibility: hidePreview ? 'private' : 'public',
                },
            },
            apns: {
                headers: { 'apns-priority': '10' },
                payload: {
                    aps: {
                        sound: sound ? 'oneova_notification.wav' : undefined,
                        'thread-id': groupId || copy.group,
                        'interruption-level': live || urgent ? 'time-sensitive' : 'active',
                        'mutable-content': 1,
                    },
                },
                fcmOptions: image && !hidePreview ? { imageUrl: String(image) } : undefined,
            },
        }).then((res) => ({ docs: plain, res })));
    }
    // Drop tokens FCM reports as gone so the next fan-out is cheaper.
    const stale = [];
    let failed = 0;
    for (const { docs, res } of await Promise.all(sends)) {
        failed += res.failureCount;
        res.responses.forEach((r, i) => {
            var _a;
            var _b;
            const code = (_b = (_a = r.error) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : '';
            if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
                stale.push(docs[i].ref.delete());
            }
        });
    }
    await Promise.all(stale);
    if (failed > 0)
        logger.info('notification push partial failure', { id: event.params.id, failed });
});
//# sourceMappingURL=notifications.js.map