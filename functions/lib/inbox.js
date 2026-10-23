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
exports.searchMessages = exports.revokeAllSessions = exports.requestSecureAttachmentUpload = exports.markConversationRead = exports.inboxSendMessage = void 0;
/**
 * Unified inbox callables used by the app (control_plane_service.dart,
 * omni_tool_registry.dart, settings_service.dart).
 *
 * Data model (same as the app): conversations/{id} with `participants`,
 * `unreadCount`, `unreadCounts.{uid}`, `latestMessage` (string), `updatedAt`;
 * messages in conversations/{id}/messages.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const auth_1 = require("firebase-admin/auth");
const crypto = __importStar(require("crypto"));
const MAX_TEXT = 10000;
const MAX_UPLOAD_BYTES = 50 * 1024 * 1024;
const ALLOWED_MIME = new Set([
    'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
    'video/mp4', 'video/quicktime', 'video/webm',
    'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/wav', 'audio/webm',
    'application/pdf', 'text/plain',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
]);
function requireMember(request) {
    var _a;
    const auth = request.auth;
    if (!auth || ((_a = auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) === 'anonymous') {
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    }
    return auth.uid;
}
async function loadConversation(conversationId, uid) {
    var _a;
    const id = String(conversationId !== null && conversationId !== void 0 ? conversationId : '');
    if (!/^[A-Za-z0-9_-]{1,200}$/.test(id))
        throw new https_1.HttpsError('invalid-argument', 'Bad conversation.');
    const ref = (0, firestore_1.getFirestore)().collection('conversations').doc(id);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError('not-found', 'Conversation not found.');
    const participants = ((_a = snap.get('participants')) !== null && _a !== void 0 ? _a : []);
    if (!participants.includes(uid))
        throw new https_1.HttpsError('permission-denied', 'Not your conversation.');
    return { ref, snap, participants };
}
/** Sends a message into a conversation, once per clientCommandId. */
exports.inboxSendMessage = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d;
    const uid = requireMember(request);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const content = String((_b = data.content) !== null && _b !== void 0 ? _b : '');
    const attachments = Array.isArray(data.attachments) ? data.attachments.slice(0, 10) : [];
    const commandId = String((_c = data.clientCommandId) !== null && _c !== void 0 ? _c : '');
    if (!/^[A-Za-z0-9_-]{6,100}$/.test(commandId)) {
        throw new https_1.HttpsError('invalid-argument', 'clientCommandId is required.');
    }
    if (!content.trim() && attachments.length === 0)
        throw new https_1.HttpsError('invalid-argument', 'Empty message.');
    if (content.length > MAX_TEXT)
        throw new https_1.HttpsError('invalid-argument', 'Message is too long.');
    const { ref: convRef, snap, participants } = await loadConversation(data.conversationId, uid);
    const connector = (_d = snap.get('connectorId')) !== null && _d !== void 0 ? _d : null;
    if (connector && connector !== 'oneova') {
        // External platforms (WhatsApp, Instagram, …) need their connector
        // credentials, which are not set up yet. Fail honestly instead of
        // pretending the message went out.
        throw new https_1.HttpsError('failed-precondition', `Sending on ${connector} isn't connected yet.`);
    }
    // Idempotent: the same command id always maps to the same message doc.
    const msgRef = convRef.collection('messages').doc(`cmd_${uid}_${commandId}`);
    const result = await (0, firestore_1.getFirestore)().runTransaction(async (tx) => {
        var _a, _b;
        const existing = await tx.get(msgRef);
        if (existing.exists)
            return { messageId: msgRef.id, status: (_a = existing.get('deliveryState')) !== null && _a !== void 0 ? _a : 'sent', duplicate: true };
        tx.set(msgRef, {
            conversationId: convRef.id,
            senderId: uid,
            content,
            attachments,
            status: 'sent',
            deliveryState: 'sent',
            reactions: {},
            isEdited: false,
            isDeleted: false,
            isPinned: false,
            isBookmarked: false,
            timestamp: firestore_1.FieldValue.serverTimestamp(),
            platformId: 'oneova',
            connectorId: connector,
            metadata: {},
            source: 'app',
            clientCommandId: commandId,
            attempt: Number((_b = data.attempt) !== null && _b !== void 0 ? _b : 1),
        });
        const unread = {};
        for (const p of participants)
            if (p !== uid)
                unread[`unreadCounts.${p}`] = firestore_1.FieldValue.increment(1);
        tx.update(convRef, Object.assign({ latestMessage: content.trim() ? content.slice(0, 140) : '📎 Attachment', updatedAt: firestore_1.FieldValue.serverTimestamp(), unreadCount: firestore_1.FieldValue.increment(1), needsReply: true }, unread));
        return { messageId: msgRef.id, status: 'sent', duplicate: false };
    });
    return result;
});
/** Marks a conversation as read for the caller. */
exports.markConversationRead = (0, https_1.onCall)(async (request) => {
    var _a;
    const uid = requireMember(request);
    const { ref } = await loadConversation((_a = request.data) === null || _a === void 0 ? void 0 : _a.conversationId, uid);
    await ref.update({
        [`unreadCounts.${uid}`]: 0,
        unreadCount: 0,
        [`readAt.${uid}`]: firestore_1.FieldValue.serverTimestamp(),
    });
    return { ok: true };
});
/**
 * Short-lived signed URL to upload one attachment into staging/. The file
 * is checked (real file type) by the storage trigger before use.
 * Needs the functions service account to have "Service Account Token
 * Creator" on itself (to sign URLs).
 */
exports.requestSecureAttachmentUpload = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d;
    const uid = requireMember(request);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const mimeType = String((_b = data.mimeType) !== null && _b !== void 0 ? _b : '').toLowerCase();
    const fileSize = Number((_c = data.fileSize) !== null && _c !== void 0 ? _c : 0);
    const rawName = String((_d = data.fileName) !== null && _d !== void 0 ? _d : 'file');
    if (!ALLOWED_MIME.has(mimeType))
        throw new https_1.HttpsError('invalid-argument', 'This file type is not allowed.');
    if (!(fileSize > 0) || fileSize > MAX_UPLOAD_BYTES)
        throw new https_1.HttpsError('invalid-argument', 'File is too large (max 50 MB).');
    let folder = 'inbox';
    if (data.conversationId)
        folder = (await loadConversation(data.conversationId, uid)).ref.id;
    const safeName = rawName.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'file';
    const path = `staging/${folder}/${uid}/${crypto.randomUUID()}_${safeName}`;
    const expires = Date.now() + 15 * 60 * 1000;
    const [uploadUrl] = await (0, storage_1.getStorage)().bucket().file(path).getSignedUrl({
        version: 'v4',
        action: 'write',
        expires,
        contentType: mimeType,
        extensionHeaders: { 'x-goog-content-length-range': `0,${MAX_UPLOAD_BYTES}` },
    });
    return { uploadUrl, storagePath: path, expiresAt: expires };
});
/** Signs the account out everywhere: phones, PCs, fingerprint keys. */
exports.revokeAllSessions = (0, https_1.onCall)(async (request) => {
    var _a;
    const uid = requireMember(request);
    const db = (0, firestore_1.getFirestore)();
    const auth = (0, auth_1.getAuth)();
    const user = await auth.getUser(uid);
    const claims = Object.assign({}, ((_a = user.customClaims) !== null && _a !== void 0 ? _a : {}));
    delete claims.mfaSessions;
    await auth.setCustomUserClaims(uid, claims);
    await auth.revokeRefreshTokens(uid);
    const writer = db.bulkWriter();
    const [devices, keys] = await Promise.all([
        db.collection('users').doc(uid).collection('trusted_devices').get(),
        db.collection('biometric_keys').where('uid', '==', uid).get(),
    ]);
    devices.docs.forEach((d) => writer.delete(d.ref));
    keys.docs.forEach((d) => writer.delete(d.ref));
    await writer.close();
    await db.collection('users').doc(uid).collection('security_events').add({
        type: 'signed_out_everywhere',
        devicesRemoved: devices.size,
        at: firestore_1.FieldValue.serverTimestamp(),
    });
    return { ok: true, devicesRemoved: devices.size };
});
/**
 * Text search over the caller's own conversations. Firestore has no
 * full-text index, so this scans recent messages (newest first) and matches
 * words case-insensitively; good for personal inboxes, not a global index.
 */
exports.searchMessages = (0, https_1.onCall)(async (request) => {
    var _a;
    var _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const uid = requireMember(request);
    const data = ((_b = request.data) !== null && _b !== void 0 ? _b : {});
    const query = String((_c = data.query) !== null && _c !== void 0 ? _c : '').trim().toLowerCase();
    const senderName = String((_d = data.senderName) !== null && _d !== void 0 ? _d : '').trim().toLowerCase();
    const limit = Math.min(Math.max(Number((_e = data.limit) !== null && _e !== void 0 ? _e : 20), 1), 50);
    if (!query && !senderName)
        throw new https_1.HttpsError('invalid-argument', 'Type something to search for.');
    const now = Date.now();
    const day = 86400000;
    const since = { today: now - day, yesterday: now - 2 * day, last_week: now - 7 * day }[String((_f = data.timeRange) !== null && _f !== void 0 ? _f : '')];
    const db = (0, firestore_1.getFirestore)();
    let convIds;
    if (data.conversationId) {
        convIds = [(await loadConversation(data.conversationId, uid)).ref.id];
    }
    else {
        const convs = await db.collection('conversations')
            .where('participants', 'array-contains', uid)
            .orderBy('updatedAt', 'desc')
            .limit(30)
            .get();
        convIds = convs.docs.map((d) => d.id);
    }
    const words = query.split(/\s+/).filter(Boolean);
    const results = [];
    for (const convId of convIds) {
        let q = db.collection('conversations').doc(convId).collection('messages').orderBy('timestamp', 'desc');
        if (since)
            q = q.where('timestamp', '>=', firestore_1.Timestamp.fromMillis(since));
        const snap = await q.limit(200).get();
        for (const doc of snap.docs) {
            const m = doc.data();
            if (m.isDeleted)
                continue;
            const text = String((_h = (_g = m.content) !== null && _g !== void 0 ? _g : m.text) !== null && _h !== void 0 ? _h : '').toLowerCase();
            const sender = String((_j = m.senderName) !== null && _j !== void 0 ? _j : '').toLowerCase();
            if (words.length && !words.every((w) => text.includes(w)))
                continue;
            if (senderName && !sender.includes(senderName))
                continue;
            results.push({
                messageId: doc.id,
                conversationId: convId,
                senderId: (_k = m.senderId) !== null && _k !== void 0 ? _k : null,
                senderName: (_l = m.senderName) !== null && _l !== void 0 ? _l : null,
                content: String((_o = (_m = m.content) !== null && _m !== void 0 ? _m : m.text) !== null && _o !== void 0 ? _o : '').slice(0, 300),
                timestamp: (_p = (_a = m.timestamp) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _p !== void 0 ? _p : null,
            });
            if (results.length >= limit)
                return { results };
        }
    }
    return { results };
});
//# sourceMappingURL=inbox.js.map