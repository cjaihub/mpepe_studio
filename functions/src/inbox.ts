/**
 * Unified inbox callables used by the app (control_plane_service.dart,
 * omni_tool_registry.dart, settings_service.dart).
 *
 * Data model (same as the app): conversations/{id} with `participants`,
 * `unreadCount`, `unreadCounts.{uid}`, `latestMessage` (string), `updatedAt`;
 * messages in conversations/{id}/messages.
 */
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { getAuth } from 'firebase-admin/auth';
import * as crypto from 'crypto';

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

function requireMember(request: CallableRequest<unknown>): string {
  const auth = request.auth;
  if (!auth || auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Sign in first.');
  }
  return auth.uid;
}

async function loadConversation(conversationId: unknown, uid: string) {
  const id = String(conversationId ?? '');
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) throw new HttpsError('invalid-argument', 'Bad conversation.');
  const ref = getFirestore().collection('conversations').doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Conversation not found.');
  const participants = (snap.get('participants') ?? []) as string[];
  if (!participants.includes(uid)) throw new HttpsError('permission-denied', 'Not your conversation.');
  return { ref, snap, participants };
}

/** Sends a message into a conversation, once per clientCommandId. */
export const inboxSendMessage = onCall(async (request) => {
  const uid = requireMember(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const content = String(data.content ?? '');
  const attachments = Array.isArray(data.attachments) ? data.attachments.slice(0, 10) : [];
  const commandId = String(data.clientCommandId ?? '');
  if (!/^[A-Za-z0-9_-]{6,100}$/.test(commandId)) {
    throw new HttpsError('invalid-argument', 'clientCommandId is required.');
  }
  if (!content.trim() && attachments.length === 0) throw new HttpsError('invalid-argument', 'Empty message.');
  if (content.length > MAX_TEXT) throw new HttpsError('invalid-argument', 'Message is too long.');

  const { ref: convRef, snap, participants } = await loadConversation(data.conversationId, uid);
  const connector = (snap.get('connectorId') as string | undefined) ?? null;
  if (connector && connector !== 'oneova') {
    // External platforms (WhatsApp, Instagram, …) need their connector
    // credentials, which are not set up yet. Fail honestly instead of
    // pretending the message went out.
    throw new HttpsError('failed-precondition', `Sending on ${connector} isn't connected yet.`);
  }

  // Idempotent: the same command id always maps to the same message doc.
  const msgRef = convRef.collection('messages').doc(`cmd_${uid}_${commandId}`);
  const result = await getFirestore().runTransaction(async (tx) => {
    const existing = await tx.get(msgRef);
    if (existing.exists) return { messageId: msgRef.id, status: existing.get('deliveryState') ?? 'sent', duplicate: true };
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
      timestamp: FieldValue.serverTimestamp(),
      platformId: 'oneova',
      connectorId: connector,
      metadata: {},
      source: 'app',
      clientCommandId: commandId,
      attempt: Number(data.attempt ?? 1),
    });
    const unread: Record<string, FieldValue> = {};
    for (const p of participants) if (p !== uid) unread[`unreadCounts.${p}`] = FieldValue.increment(1);
    tx.update(convRef, {
      latestMessage: content.trim() ? content.slice(0, 140) : '📎 Attachment',
      updatedAt: FieldValue.serverTimestamp(),
      unreadCount: FieldValue.increment(1),
      needsReply: true,
      ...unread,
    });
    return { messageId: msgRef.id, status: 'sent', duplicate: false };
  });
  return result;
});

/** Marks a conversation as read for the caller. */
export const markConversationRead = onCall(async (request) => {
  const uid = requireMember(request);
  const { ref } = await loadConversation((request.data as { conversationId?: unknown })?.conversationId, uid);
  await ref.update({
    [`unreadCounts.${uid}`]: 0,
    unreadCount: 0,
    [`readAt.${uid}`]: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/**
 * Short-lived signed URL to upload one attachment into staging/. The file
 * is checked (real file type) by the storage trigger before use.
 * Needs the functions service account to have "Service Account Token
 * Creator" on itself (to sign URLs).
 */
export const requestSecureAttachmentUpload = onCall(async (request) => {
  const uid = requireMember(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const mimeType = String(data.mimeType ?? '').toLowerCase();
  const fileSize = Number(data.fileSize ?? 0);
  const rawName = String(data.fileName ?? 'file');
  if (!ALLOWED_MIME.has(mimeType)) throw new HttpsError('invalid-argument', 'This file type is not allowed.');
  if (!(fileSize > 0) || fileSize > MAX_UPLOAD_BYTES) throw new HttpsError('invalid-argument', 'File is too large (max 50 MB).');

  let folder = 'inbox';
  if (data.conversationId) folder = (await loadConversation(data.conversationId, uid)).ref.id;
  const safeName = rawName.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'file';
  const path = `staging/${folder}/${uid}/${crypto.randomUUID()}_${safeName}`;
  const expires = Date.now() + 15 * 60 * 1000;
  const [uploadUrl] = await getStorage().bucket().file(path).getSignedUrl({
    version: 'v4',
    action: 'write',
    expires,
    contentType: mimeType,
    extensionHeaders: { 'x-goog-content-length-range': `0,${MAX_UPLOAD_BYTES}` },
  });
  return { uploadUrl, storagePath: path, expiresAt: expires };
});

/** Signs the account out everywhere: phones, PCs, fingerprint keys. */
export const revokeAllSessions = onCall(async (request) => {
  const uid = requireMember(request);
  const db = getFirestore();
  const auth = getAuth();
  const user = await auth.getUser(uid);
  const claims = { ...(user.customClaims ?? {}) } as Record<string, unknown>;
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
    at: FieldValue.serverTimestamp(),
  });
  return { ok: true, devicesRemoved: devices.size };
});

/**
 * Text search over the caller's own conversations. Firestore has no
 * full-text index, so this scans recent messages (newest first) and matches
 * words case-insensitively; good for personal inboxes, not a global index.
 */
export const searchMessages = onCall(async (request) => {
  const uid = requireMember(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const query = String(data.query ?? '').trim().toLowerCase();
  const senderName = String(data.senderName ?? '').trim().toLowerCase();
  const limit = Math.min(Math.max(Number(data.limit ?? 20), 1), 50);
  if (!query && !senderName) throw new HttpsError('invalid-argument', 'Type something to search for.');

  const now = Date.now();
  const day = 86400000;
  const since = ({ today: now - day, yesterday: now - 2 * day, last_week: now - 7 * day } as Record<string, number>)[
    String(data.timeRange ?? '')
  ];

  const db = getFirestore();
  let convIds: string[];
  if (data.conversationId) {
    convIds = [(await loadConversation(data.conversationId, uid)).ref.id];
  } else {
    const convs = await db.collection('conversations')
      .where('participants', 'array-contains', uid)
      .orderBy('updatedAt', 'desc')
      .limit(30)
      .get();
    convIds = convs.docs.map((d) => d.id);
  }

  const words = query.split(/\s+/).filter(Boolean);
  const results: Record<string, unknown>[] = [];
  for (const convId of convIds) {
    let q = db.collection('conversations').doc(convId).collection('messages').orderBy('timestamp', 'desc');
    if (since) q = q.where('timestamp', '>=', Timestamp.fromMillis(since));
    const snap = await q.limit(200).get();
    for (const doc of snap.docs) {
      const m = doc.data();
      if (m.isDeleted) continue;
      const text = String(m.content ?? m.text ?? '').toLowerCase();
      const sender = String(m.senderName ?? '').toLowerCase();
      if (words.length && !words.every((w) => text.includes(w))) continue;
      if (senderName && !sender.includes(senderName)) continue;
      results.push({
        messageId: doc.id,
        conversationId: convId,
        senderId: m.senderId ?? null,
        senderName: m.senderName ?? null,
        content: String(m.content ?? m.text ?? '').slice(0, 300),
        timestamp: (m.timestamp as Timestamp | undefined)?.toMillis() ?? null,
      });
      if (results.length >= limit) return { results };
    }
  }
  return { results };
});
