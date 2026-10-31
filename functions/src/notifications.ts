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
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as logger from 'firebase-functions/logger';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { readAccountSettings } from './accountSettings';

const db = () => getFirestore();

// Calls ring through calls.ts; chat pushes are sent by the messaging pipeline.
const SKIP = new Set(['call', 'missedCall', 'newMessage']);

interface Prefs {
  pushEnabled?: boolean;
  soundEnabled?: boolean;
  previewMessageContent?: boolean;
  dndEnabled?: boolean;
  quietHoursStart?: number;
  quietHoursEnd?: number;
  timezoneOffsetMinutes?: number;
  categoryOverrides?: Record<string, boolean>;
}

function inQuietHours(p: Prefs): boolean {
  if (!p.dndEnabled) return false;
  const start = p.quietHoursStart ?? 22;
  const end = p.quietHoursEnd ?? 8;
  if (start === end) return false;
  const local = new Date(Date.now() + (p.timezoneOffsetMinutes ?? 0) * 60_000);
  const hour = local.getUTCHours();
  return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}

interface Actor { id: string; name: string; avatar?: string }

async function resolveActor(n: FirebaseFirestore.DocumentData): Promise<Actor | null> {
  const p = n.payload || {};
  const id: string | undefined = n.actorId || p.actorId || p.followerId || p.userId || p.authorId || p.senderId || p.hostId;
  if (!id || id === (n.userId || n.recipientId)) return null;
  const snap = await db().collection('users').doc(id).get().catch(() => null);
  const u = snap?.data() || {};
  const name = [u.fullName, u.displayName, u.username, p.actorName, p.senderName, p.hostName]
    .find((v) => typeof v === 'string' && v.trim().length > 0);
  const avatar = [u.avatarUrl, u.photoUrl, u.photoURL, p.avatarUrl, p.actorAvatar, p.senderAvatar]
    .find((v) => typeof v === 'string' && v.startsWith('http'));
  return { id, name: name ? String(name).trim() : 'Someone', avatar };
}

async function postPreview(postId?: string): Promise<string | undefined> {
  if (!postId) return undefined;
  for (const col of ['posts', 'content']) {
    const d = (await db().collection(col).doc(postId).get().catch(() => null))?.data();
    const url = d && [d.thumbnailUrl, d.coverUrl, d.thumbnail, d.imageUrl].find((v) => typeof v === 'string' && v.startsWith('http'));
    if (url) return String(url);
  }
  return undefined;
}

/** Old terse defaults we replace with plain, friendly copy. */
const GENERIC_TITLES = new Set(['new like', 'new comment', 'new reply', 'new follower', 'new mention', 'oneova', '']);

interface Copy { title: string; body: string; actions: string[]; group: string }

function friendlyCopy(category: string, actor: Actor | null, n: FirebaseFirestore.DocumentData): Copy {
  const who = actor?.name || 'Someone';
  const title = String(n.title || '');
  const body = String(n.body || n.message || '');
  const generic = GENERIC_TITLES.has(title.trim().toLowerCase()) || body.startsWith('Someone ');
  const quoted = (body.match(/"(.+)"/) || [])[1];
  const keep = (t: string, b: string): [string, string] => (generic ? [t, b] : [title || t, body || b]);
  let t: string; let b: string; let actions: string[] = ['open']; let group = category;
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
      if (n.payload?.sharedWithYou) {
        [t, b] = keep(`${who} shared a post with you`, 'Tap to watch it.');
        actions = ['like', 'watch'];
        group = 'shared';
      } else {
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

export const onNotificationCreated = onDocumentCreated('notifications/{id}', async (event) => {
  const n = event.data?.data();
  if (!n) return;
  const uid: string = n.userId || n.recipientId;
  const category: string = n.category || 'system';
  if (!uid || SKIP.has(category) || n.isRead === true) return;

  const actor = await resolveActor(n).catch(() => null);
  const copy = friendlyCopy(category, actor, n);
  const p = n.payload || {};
  const postId: string | undefined = p.postId || p.contentId || p.videoId;
  const image = p.thumbnailUrl || p.mediaUrl || (await postPreview(postId));

  // Save the friendly copy so the in-app centre reads the same as the push.
  const patch: Record<string, unknown> = {};
  if (copy.title !== n.title) patch.title = copy.title;
  if (copy.body !== (n.body || n.message)) { patch.body = copy.body; patch.message = copy.body; }
  if (actor && !n.actorId) patch.actorId = actor.id;
  if (actor && !p.actorName) patch['payload.actorName'] = actor.name;
  if (actor?.avatar && !p.avatarUrl) patch['payload.avatarUrl'] = actor.avatar;
  if (image && !p.thumbnailUrl) patch['payload.thumbnailUrl'] = image;
  if (Object.keys(patch).length > 0) await event.data!.ref.update(patch).catch(() => undefined);

  const prefs = (await readAccountSettings(uid, 'notifications', 'settings/notifications')) as Prefs;
  const urgent = n.priority === 'urgent';
  if (prefs.pushEnabled === false && !urgent) return;
  if (prefs.categoryOverrides?.[category] === false && !urgent) return;
  if (inQuietHours(prefs) && !urgent) return;

  const tokens = await db().collection('users').doc(uid).collection('device_tokens').get();
  if (tokens.empty) return;

  const sound = prefs.soundEnabled !== false;
  const hidePreview = prefs.previewMessageContent === false;
  const title = copy.title;
  const body = hidePreview ? 'Open Oneova to see it.' : copy.body;
  const route = String(n.deepLink || p.route || '/notifications');
  const live = category === 'live';
  const groupId: string | undefined = n.groupId || undefined;

  const baseData: Record<string, string> = {
    notificationId: event.params.id,
    category,
    route,
    priority: String(n.priority || 'normal'),
  };

  const rich = tokens.docs.filter((d) => d.get('richPush') === true);
  const plain = tokens.docs.filter((d) => d.get('richPush') !== true);
  const sends: Promise<{ docs: typeof tokens.docs; res: import('firebase-admin/messaging').BatchResponse }>[] = [];

  if (rich.length > 0) {
    const data: Record<string, string> = {
      ...baseData,
      render: 'rich',
      title,
      body,
      group: copy.group,
      actions: copy.actions.join(','),
      sound: sound ? 'on' : 'off',
      private: hidePreview ? 'true' : 'false',
      sentAt: String(Date.now()),
    };
    if (actor) data.actorId = actor.id;
    if (actor?.avatar && !hidePreview) data.avatarUrl = actor.avatar;
    if (image && !hidePreview) data.imageUrl = String(image);
    if (postId) data.postId = String(postId);
    if (p.commentId) data.commentId = String(p.commentId);
    sends.push(getMessaging().sendEachForMulticast({
      tokens: rich.map((d) => d.id),
      data,
      android: { priority: 'high', collapseKey: groupId, ttl: 24 * 3600 * 1000 },
    }).then((res) => ({ docs: rich, res })));
  }

  if (plain.length > 0) {
    sends.push(getMessaging().sendEachForMulticast({
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
  const stale: Promise<unknown>[] = [];
  let failed = 0;
  for (const { docs, res } of await Promise.all(sends)) {
    failed += res.failureCount;
    res.responses.forEach((r, i) => {
      const code = r.error?.code ?? '';
      if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
        stale.push(docs[i].ref.delete());
      }
    });
  }
  await Promise.all(stale);
  if (failed > 0) logger.info('notification push partial failure', { id: event.params.id, failed });
});
