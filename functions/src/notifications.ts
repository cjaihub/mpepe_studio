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

export const onNotificationCreated = onDocumentCreated('notifications/{id}', async (event) => {
  const n = event.data?.data();
  if (!n) return;
  const uid: string = n.userId || n.recipientId;
  const category: string = n.category || 'system';
  if (!uid || SKIP.has(category) || n.isRead === true) return;

  const prefs = (await readAccountSettings(uid, 'notifications', 'settings/notifications')) as Prefs;
  const urgent = n.priority === 'urgent';
  if (prefs.pushEnabled === false && !urgent) return;
  if (prefs.categoryOverrides?.[category] === false && !urgent) return;
  if (inQuietHours(prefs) && !urgent) return;

  const tokens = await db().collection('users').doc(uid).collection('device_tokens').get();
  if (tokens.empty) return;

  const sound = prefs.soundEnabled !== false;
  const title = String(n.title || 'Oneova');
  const body = prefs.previewMessageContent === false ? 'Open Oneova to see it.' : String(n.body || n.message || '');
  const route = String(n.deepLink || n.payload?.route || '/notifications');
  const live = category === 'live';

  const res = await getMessaging().sendEachForMulticast({
    tokens: tokens.docs.map((d) => d.id),
    notification: { title, body },
    data: { notificationId: event.params.id, category, route, priority: String(n.priority || 'normal') },
    android: {
      priority: 'high',
      collapseKey: n.groupId || undefined,
      notification: {
        channelId: live ? 'oneova_live_channel' : 'oneova_high_importance_channel',
        sound: sound ? 'oneova_notification' : undefined,
        color: live ? '#FF2D87' : '#0C4FA8',
        tag: n.groupId || undefined,
        defaultVibrateTimings: true,
      },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          sound: sound ? 'oneova_notification.wav' : undefined,
          'thread-id': n.groupId || category,
          'interruption-level': live || urgent ? 'time-sensitive' : 'active',
        },
      },
    },
  });

  // Drop tokens FCM reports as gone so the next fan-out is cheaper.
  const stale: Promise<unknown>[] = [];
  res.responses.forEach((r, i) => {
    const code = r.error?.code ?? '';
    if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
      stale.push(tokens.docs[i].ref.delete());
    }
  });
  await Promise.all(stale);
  if (res.failureCount > 0) logger.info('notification push partial failure', { id: event.params.id, failed: res.failureCount });
});
