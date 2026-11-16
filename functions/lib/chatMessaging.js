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
exports.sweepExpiredChatMessages = exports.onChatMessagePush = void 0;
/**
 * Chat messaging server pipeline:
 *  1. `onChatMessagePush`: stamps disappearing-message `expiresAt` if needed and
 *     fans out rich / OS push notifications to chat participants while honoring
 *     blocked pairs, per-chat `mutedUsers`, quiet hours, `previewMessageContent`,
 *     and zero-plaintext leaks for E2EE messages.
 *  2. `sweepExpiredChatMessages`: removes expired disappearing messages and
 *     keeps each conversation's `lastMessage` preview accurate after expiry.
 */
const firestore_1 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const accountSettings_1 = require("./accountSettings");
const db = () => (0, firestore_2.getFirestore)();
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
function safeStr(v, max = 140) {
    return typeof v === 'string' ? v.trim().slice(0, max) : '';
}
function buildMessagePreview(data, hideUserContent) {
    var _a;
    const mediaType = safeStr(data.mediaType, 32);
    const encrypted = data.isEncrypted === true || data.mediaEncrypted === true;
    if (hideUserContent) {
        return 'Open Oneova to read it.';
    }
    if (encrypted) {
        switch (mediaType) {
            case 'audio':
                return '🔒 Encrypted voice note';
            case 'image':
                return '🔒 Encrypted photo';
            case 'video':
                return '🔒 Encrypted video';
            case 'video_note':
                return '🔒 Encrypted video message';
            case 'location':
                return '📍 Shared location';
            default:
                return mediaType ? '🔒 Encrypted attachment' : '🔒 New encrypted message';
        }
    }
    const text = safeStr(data.text, 160);
    if (text)
        return text;
    switch (mediaType) {
        case 'audio':
            return data.voiceDuration ? `🎙️ Voice note (${String(data.voiceDuration)})` : '🎙️ Voice note';
        case 'image':
            return '📷 Photo';
        case 'video':
            return '🎥 Video';
        case 'video_note':
            return data.voiceDuration ? `📹 Video message (${String(data.voiceDuration)})` : '📹 Video message';
        case 'gif':
            return 'GIF';
        case 'location':
            return ((_a = data.location) === null || _a === void 0 ? void 0 : _a.live) === true
                ? '📍 Live location'
                : '📍 Location';
        case 'document':
        case 'file':
        case 'archive':
        case 'code': {
            const fn = safeStr(data.fileName, 64);
            return fn ? `📄 ${fn}` : '📄 Document';
        }
        default:
            return 'Sent a message';
    }
}
async function isBlockedPair(a, b) {
    var _a, _b;
    if (!a || !b)
        return false;
    const [ab, ba] = await Promise.all([
        db().collection('relationships').doc(`${a}_${b}`).get().catch(() => null),
        db().collection('relationships').doc(`${b}_${a}`).get().catch(() => null),
    ]);
    return ((_a = ab === null || ab === void 0 ? void 0 : ab.data()) === null || _a === void 0 ? void 0 : _a.status) === 'blocked' || ((_b = ba === null || ba === void 0 ? void 0 : ba.data()) === null || _b === void 0 ? void 0 : _b.status) === 'blocked';
}
exports.onChatMessagePush = (0, firestore_1.onDocumentCreated)('chats/{chatId}/messages/{messageId}', async (event) => {
    var _a, _b;
    var _c, _d, _e, _f, _g;
    const data = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!data)
        return;
    const { chatId } = event.params;
    const senderId = safeStr(data.senderId, 128);
    if (!senderId || senderId === 'guest')
        return;
    const chatSnap = await db().collection('chats').doc(chatId).get().catch(() => null);
    if (!(chatSnap === null || chatSnap === void 0 ? void 0 : chatSnap.exists))
        return;
    const chat = (_c = chatSnap.data()) !== null && _c !== void 0 ? _c : {};
    // Guarantee disappearing messages always carry an explicit expiresAt timestamp.
    const disappearingSec = typeof chat.disappearingDuration === 'number' ? chat.disappearingDuration : 0;
    if (disappearingSec > 0 && !data.expiresAt) {
        const baseMs = data.timestamp && typeof data.timestamp.toMillis === 'function'
            ? data.timestamp.toMillis()
            : Date.now();
        await event.data.ref
            .set({ expiresAt: firestore_2.Timestamp.fromMillis(baseMs + disappearingSec * 1000) }, { merge: true })
            .catch(() => undefined);
    }
    const participants = Array.isArray(chat.participants) ? chat.participants : [];
    if (participants.length === 0)
        return;
    const muted = new Set([
        ...(Array.isArray(chat.mutedUsers) ? chat.mutedUsers : []),
        ...(Array.isArray(chat.mutedBy) ? chat.mutedBy : []),
    ]);
    const category = safeStr(chat.category, 32);
    // Avoid hammering pushes on massive broadcast channels from an edge trigger.
    if (category === 'channel' && participants.length > 200)
        return;
    const recipients = participants
        .filter((uid) => uid && uid !== senderId && !muted.has(uid))
        .slice(0, 100);
    if (recipients.length === 0)
        return;
    const senderDoc = await db().collection('users').doc(senderId).get().catch(() => null);
    const u = (_d = senderDoc === null || senderDoc === void 0 ? void 0 : senderDoc.data()) !== null && _d !== void 0 ? _d : {};
    const senderName = (_e = (_b = [u.fullName, u.displayName, u.username].find((v) => typeof v === 'string' && v.trim().length > 0)) === null || _b === void 0 ? void 0 : _b.trim()) !== null && _e !== void 0 ? _e : 'Oneova';
    const senderAvatar = [u.profilePhotoUrl, u.photoUrl, u.avatarUrl].find((v) => typeof v === 'string' && v.startsWith('http'));
    const isGroup = category === 'group' || category === 'room' || category === 'vip_room' || participants.length > 2;
    const chatTitle = safeStr((_g = (_f = chat.title) !== null && _f !== void 0 ? _f : chat.name) !== null && _g !== void 0 ? _g : chat.groupName, 80);
    const title = isGroup && chatTitle ? `${senderName} · ${chatTitle}` : senderName;
    const route = `/hub/messages/${chatId}`;
    const groupKey = `chat_${chatId}`;
    const isDirectPair = participants.length === 2 && !isGroup;
    await Promise.all(recipients.map(async (uid) => {
        var _a;
        try {
            if (isDirectPair && (await isBlockedPair(uid, senderId)))
                return;
            const prefs = (await (0, accountSettings_1.readAccountSettings)(uid, 'notifications', 'settings/notifications'));
            if (prefs.pushEnabled === false)
                return;
            if (((_a = prefs.categoryOverrides) === null || _a === void 0 ? void 0 : _a.newMessage) === false)
                return;
            if (inQuietHours(prefs))
                return;
            const tokensSnap = await db().collection('users').doc(uid).collection('device_tokens').get();
            if (tokensSnap.empty)
                return;
            const hideContent = prefs.previewMessageContent === false;
            const sound = prefs.soundEnabled !== false;
            const body = buildMessagePreview(data, hideContent);
            const isPrivate = hideContent || data.isEncrypted === true;
            const richDocs = tokensSnap.docs.filter((d) => d.get('richPush') === true);
            const plainDocs = tokensSnap.docs.filter((d) => d.get('richPush') !== true);
            const sends = [];
            if (richDocs.length > 0) {
                const payload = {
                    render: 'rich',
                    category: 'newMessage',
                    chatId,
                    actorId: senderId,
                    title,
                    body,
                    route,
                    group: groupKey,
                    actions: 'open',
                    sound: sound ? 'on' : 'off',
                    private: isPrivate ? 'true' : 'false',
                    sentAt: String(Date.now()),
                };
                if (senderAvatar && !hideContent)
                    payload.avatarUrl = senderAvatar;
                sends.push((0, messaging_1.getMessaging)()
                    .sendEachForMulticast({
                    tokens: richDocs.map((d) => d.id),
                    data: payload,
                    android: { priority: 'high', collapseKey: groupKey, ttl: 24 * 3600 * 1000 },
                })
                    .then((res) => ({ docs: richDocs, res })));
            }
            if (plainDocs.length > 0) {
                sends.push((0, messaging_1.getMessaging)()
                    .sendEachForMulticast({
                    tokens: plainDocs.map((d) => d.id),
                    notification: { title, body },
                    data: {
                        category: 'newMessage',
                        chatId,
                        actorId: senderId,
                        route,
                    },
                    android: {
                        priority: 'high',
                        collapseKey: groupKey,
                        notification: {
                            channelId: 'oneova_high_importance_channel',
                            sound: sound ? 'oneova_notification' : undefined,
                            color: '#0C4FA8',
                            tag: groupKey,
                            visibility: isPrivate ? 'private' : 'public',
                        },
                    },
                    apns: {
                        headers: { 'apns-priority': '10' },
                        payload: {
                            aps: {
                                sound: sound ? 'oneova_notification.wav' : undefined,
                                'thread-id': groupKey,
                                'mutable-content': 1,
                            },
                        },
                    },
                })
                    .then((res) => ({ docs: plainDocs, res })));
            }
            const results = await Promise.all(sends);
            const stale = [];
            for (const { docs, res } of results) {
                res.responses.forEach((r, idx) => {
                    var _a;
                    var _b;
                    const code = (_b = (_a = r.error) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : '';
                    if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
                        stale.push(docs[idx].ref.delete().catch(() => undefined));
                    }
                });
            }
            await Promise.all(stale);
        }
        catch (err) {
            logger.warn('chat message push skipped for recipient', { chatId, uid, err: String(err) });
        }
    }));
});
exports.sweepExpiredChatMessages = (0, scheduler_1.onSchedule)('every 15 minutes', async () => {
    const now = firestore_2.Timestamp.now();
    const snap = await db()
        .collectionGroup('messages')
        .where('expiresAt', '<=', now)
        .limit(300)
        .get()
        .catch((err) => {
        logger.warn('sweepExpiredChatMessages query skipped (missing index or transient):', String(err));
        return null;
    });
    if (!snap || snap.empty)
        return;
    const affectedChats = new Set();
    const batch = db().batch();
    for (const doc of snap.docs) {
        const chatRef = doc.ref.parent.parent;
        if (chatRef)
            affectedChats.add(chatRef.id);
        batch.delete(doc.ref);
    }
    await batch.commit();
    // Refresh each affected chat's snippet to reflect remaining messages.
    await Promise.all(Array.from(affectedChats).map(async (chatId) => {
        var _a, _b, _c;
        try {
            const chatRef = db().collection('chats').doc(chatId);
            const latest = await chatRef.collection('messages').orderBy('timestamp', 'desc').limit(1).get();
            if (latest.empty) {
                await chatRef.update({
                    lastMessage: '',
                    lastMessageType: 'text',
                });
                return;
            }
            const m = latest.docs[0].data();
            const preview = buildMessagePreview(m, false);
            await chatRef.update({
                lastMessage: preview,
                lastMessageTime: (_a = m.timestamp) !== null && _a !== void 0 ? _a : firestore_2.Timestamp.now(),
                lastMessageSenderId: (_b = m.senderId) !== null && _b !== void 0 ? _b : null,
                lastMessageType: (_c = m.mediaType) !== null && _c !== void 0 ? _c : 'text',
            });
        }
        catch (err) {
            logger.warn('refresh chat snippet after expiry failed', { chatId, err: String(err) });
        }
    }));
});
//# sourceMappingURL=chatMessaging.js.map