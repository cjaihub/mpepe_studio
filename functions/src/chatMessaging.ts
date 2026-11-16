/**
 * Chat messaging server pipeline:
 *  1. `onChatMessagePush`: stamps disappearing-message `expiresAt` if needed and
 *     fans out rich / OS push notifications to chat participants while honoring
 *     blocked pairs, per-chat `mutedUsers`, quiet hours, `previewMessageContent`,
 *     and zero-plaintext leaks for E2EE messages.
 *  2. `sweepExpiredChatMessages`: removes expired disappearing messages and
 *     keeps each conversation's `lastMessage` preview accurate after expiry.
 */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { readAccountSettings } from './accountSettings';

const db = () => getFirestore();

interface NotifPrefs {
  pushEnabled?: boolean;
  soundEnabled?: boolean;
  previewMessageContent?: boolean;
  dndEnabled?: boolean;
  quietHoursStart?: number;
  quietHoursEnd?: number;
  timezoneOffsetMinutes?: number;
  categoryOverrides?: Record<string, boolean>;
}

function inQuietHours(p: NotifPrefs): boolean {
  if (!p.dndEnabled) return false;
  const start = p.quietHoursStart ?? 22;
  const end = p.quietHoursEnd ?? 8;
  if (start === end) return false;
  const local = new Date(Date.now() + (p.timezoneOffsetMinutes ?? 0) * 60_000);
  const hour = local.getUTCHours();
  return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}

function safeStr(v: unknown, max = 140): string {
  return typeof v === 'string' ? v.trim().slice(0, max) : '';
}

function buildMessagePreview(data: FirebaseFirestore.DocumentData, hideUserContent: boolean): string {
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
  if (text) return text;

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
      return (data.location as Record<string, unknown> | undefined)?.live === true
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

async function isBlockedPair(a: string, b: string): Promise<boolean> {
  if (!a || !b) return false;
  const [ab, ba] = await Promise.all([
    db().collection('relationships').doc(`${a}_${b}`).get().catch(() => null),
    db().collection('relationships').doc(`${b}_${a}`).get().catch(() => null),
  ]);
  return ab?.data()?.status === 'blocked' || ba?.data()?.status === 'blocked';
}

export const onChatMessagePush = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
  const data = event.data?.data();
  if (!data) return;

  const { chatId } = event.params;
  const senderId = safeStr(data.senderId, 128);
  if (!senderId || senderId === 'guest') return;

  const chatSnap = await db().collection('chats').doc(chatId).get().catch(() => null);
  if (!chatSnap?.exists) return;
  const chat = chatSnap.data() ?? {};

  // Guarantee disappearing messages always carry an explicit expiresAt timestamp.
  const disappearingSec = typeof chat.disappearingDuration === 'number' ? chat.disappearingDuration : 0;
  if (disappearingSec > 0 && !data.expiresAt) {
    const baseMs =
      data.timestamp && typeof (data.timestamp as Timestamp).toMillis === 'function'
        ? (data.timestamp as Timestamp).toMillis()
        : Date.now();
    await event.data!.ref
      .set({ expiresAt: Timestamp.fromMillis(baseMs + disappearingSec * 1000) }, { merge: true })
      .catch(() => undefined);
  }

  const participants = Array.isArray(chat.participants) ? (chat.participants as string[]) : [];
  if (participants.length === 0) return;

  const muted = new Set<string>([
    ...(Array.isArray(chat.mutedUsers) ? (chat.mutedUsers as string[]) : []),
    ...(Array.isArray(chat.mutedBy) ? (chat.mutedBy as string[]) : []),
  ]);

  const category = safeStr(chat.category, 32);
  // Avoid hammering pushes on massive broadcast channels from an edge trigger.
  if (category === 'channel' && participants.length > 200) return;

  const recipients = participants
    .filter((uid) => uid && uid !== senderId && !muted.has(uid))
    .slice(0, 100);
  if (recipients.length === 0) return;

  const senderDoc = await db().collection('users').doc(senderId).get().catch(() => null);
  const u = senderDoc?.data() ?? {};
  const senderName =
    [u.fullName, u.displayName, u.username].find((v) => typeof v === 'string' && v.trim().length > 0)?.trim() ??
    'Oneova';
  const senderAvatar = [u.profilePhotoUrl, u.photoUrl, u.avatarUrl].find(
    (v) => typeof v === 'string' && v.startsWith('http'),
  ) as string | undefined;

  const isGroup =
    category === 'group' || category === 'room' || category === 'vip_room' || participants.length > 2;
  const chatTitle = safeStr(chat.title ?? chat.name ?? chat.groupName, 80);
  const title = isGroup && chatTitle ? `${senderName} · ${chatTitle}` : senderName;
  const route = `/hub/messages/${chatId}`;
  const groupKey = `chat_${chatId}`;
  const isDirectPair = participants.length === 2 && !isGroup;

  await Promise.all(
    recipients.map(async (uid) => {
      try {
        if (isDirectPair && (await isBlockedPair(uid, senderId))) return;

        const prefs = (await readAccountSettings(uid, 'notifications', 'settings/notifications')) as NotifPrefs;
        if (prefs.pushEnabled === false) return;
        if (prefs.categoryOverrides?.newMessage === false) return;
        if (inQuietHours(prefs)) return;

        const tokensSnap = await db().collection('users').doc(uid).collection('device_tokens').get();
        if (tokensSnap.empty) return;

        const hideContent = prefs.previewMessageContent === false;
        const sound = prefs.soundEnabled !== false;
        const body = buildMessagePreview(data, hideContent);
        const isPrivate = hideContent || data.isEncrypted === true;

        const richDocs = tokensSnap.docs.filter((d) => d.get('richPush') === true);
        const plainDocs = tokensSnap.docs.filter((d) => d.get('richPush') !== true);
        const sends: Promise<{
          docs: typeof tokensSnap.docs;
          res: import('firebase-admin/messaging').BatchResponse;
        }>[] = [];

        if (richDocs.length > 0) {
          const payload: Record<string, string> = {
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
          if (senderAvatar && !hideContent) payload.avatarUrl = senderAvatar;
          sends.push(
            getMessaging()
              .sendEachForMulticast({
                tokens: richDocs.map((d) => d.id),
                data: payload,
                android: { priority: 'high', collapseKey: groupKey, ttl: 24 * 3600 * 1000 },
              })
              .then((res) => ({ docs: richDocs, res })),
          );
        }

        if (plainDocs.length > 0) {
          sends.push(
            getMessaging()
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
              .then((res) => ({ docs: plainDocs, res })),
          );
        }

        const results = await Promise.all(sends);
        const stale: Promise<unknown>[] = [];
        for (const { docs, res } of results) {
          res.responses.forEach((r, idx) => {
            const code = r.error?.code ?? '';
            if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
              stale.push(docs[idx].ref.delete().catch(() => undefined));
            }
          });
        }
        await Promise.all(stale);
      } catch (err) {
        logger.warn('chat message push skipped for recipient', { chatId, uid, err: String(err) });
      }
    }),
  );
});

export const sweepExpiredChatMessages = onSchedule('every 15 minutes', async () => {
  const now = Timestamp.now();
  const snap = await db()
    .collectionGroup('messages')
    .where('expiresAt', '<=', now)
    .limit(300)
    .get()
    .catch((err) => {
      logger.warn('sweepExpiredChatMessages query skipped (missing index or transient):', String(err));
      return null;
    });

  if (!snap || snap.empty) return;

  const affectedChats = new Set<string>();
  const batch = db().batch();
  for (const doc of snap.docs) {
    const chatRef = doc.ref.parent.parent;
    if (chatRef) affectedChats.add(chatRef.id);
    batch.delete(doc.ref);
  }
  await batch.commit();

  // Refresh each affected chat's snippet to reflect remaining messages.
  await Promise.all(
    Array.from(affectedChats).map(async (chatId) => {
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
          lastMessageTime: m.timestamp ?? Timestamp.now(),
          lastMessageSenderId: m.senderId ?? null,
          lastMessageType: m.mediaType ?? 'text',
        });
      } catch (err) {
        logger.warn('refresh chat snippet after expiry failed', { chatId, err: String(err) });
      }
    }),
  );
});
