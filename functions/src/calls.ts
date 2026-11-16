/**
 * Calling push fan-out.
 *
 * The app writes `calls/{callId}` plus one `participants/{uid}` doc per
 * person. These triggers turn those writes into pushes so a phone rings even
 * when Oneova is killed or the screen is locked:
 *   - Android: FCM high-priority *data* message → app's background handler →
 *     full-screen incoming-call UI (flutter_callkit_incoming).
 *   - iOS: APNs VoIP push (PushKit) → CallKit. Needs the APNS_* secrets below;
 *     without them iOS falls back to a normal alert notification.
 *
 * No server keys live in the app. Secrets (set once, before deploying):
 *   firebase functions:secrets:set APNS_KEY_P8    (contents of AuthKey_XXXX.p8, or "unset")
 *   firebase functions:secrets:set APNS_KEY_ID    (10-char key id, or "unset")
 *   firebase functions:secrets:set APNS_TEAM_ID   (Apple team id, or "unset")
 */
import * as http2 from 'http2';
import * as crypto from 'crypto';
import { onDocumentWritten, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret, defineString, defineBoolean } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';

const apnsKey = defineSecret('APNS_KEY_P8');
const apnsKeyId = defineSecret('APNS_KEY_ID');
const apnsTeamId = defineSecret('APNS_TEAM_ID');
const apnsTopic = defineString('APNS_VOIP_TOPIC', { default: 'com.oneova.app.voip' });
const apnsProduction = defineBoolean('APNS_PRODUCTION', { default: false });

const RING_MS = 45_000;
const FINAL = ['ended', 'missed', 'declined', 'busy'];

interface CallDoc {
  hostId?: string;
  callerName?: string;
  callerAvatar?: string;
  callkitId?: string;
  isVideo?: boolean;
  isGroup?: boolean;
  title?: string;
  status?: string;
  endReason?: string;
  participantIds?: string[];
  startedAt?: Timestamp;
  answeredAt?: Timestamp;
  endedAt?: Timestamp;
}

const db = () => getFirestore();

async function tokensFor(uid: string) {
  const [fcm, voip] = await Promise.all([
    db().collection('users').doc(uid).collection('device_tokens').get(),
    db().collection('users').doc(uid).collection('voip_tokens').get(),
  ]);
  const android: string[] = [];
  const iosFcm: string[] = [];
  for (const d of fcm.docs) {
    const platform = String(d.get('platform') ?? '').toLowerCase();
    (platform === 'ios' ? iosFcm : android).push(d.id);
  }
  return { android, iosFcm, voip: voip.docs.map((d) => d.id) };
}

function callData(callId: string, call: CallDoc, type: string, extra: Record<string, string> = {}) {
  return {
    type,
    callId,
    callkitId: call.callkitId || callId,
    hostId: call.hostId ?? '',
    callerName: (call.isGroup && call.title) ? call.title : (call.callerName ?? ''),
    callerAvatar: call.callerAvatar ?? '',
    isVideo: String(call.isVideo === true),
    isGroup: String(call.isGroup === true),
    sentAt: String(Date.now()),
    ...extra,
  };
}

async function sendFcm(uid: string, tokens: string[], data: Record<string, string>, iosAlert?: { title: string; body: string }) {
  if (tokens.length === 0) return;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    data,
    android: { priority: 'high', ttl: RING_MS },
    apns: iosAlert
      ? {
          headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
          payload: { aps: { alert: iosAlert, sound: 'default' } },
        }
      : undefined,
  });
  // Drop tokens FCM says are dead.
  await Promise.all(
    res.responses.map(async (r, i) => {
      const code = r.error?.code ?? '';
      if (code.includes('registration-token-not-registered') || code.includes('invalid-registration-token')) {
        await db().collection('users').doc(uid).collection('device_tokens').doc(tokens[i]).delete().catch(() => undefined);
      }
    }),
  );
}

// ───────────────────────── APNs VoIP ─────────────────────────

function secretValue(s: ReturnType<typeof defineSecret>): string {
  try {
    const v = s.value();
    return v && v !== 'unset' ? v : '';
  } catch {
    return '';
  }
}

let cachedJwt: { token: string; at: number } | null = null;

function apnsJwt(): string | null {
  const key = secretValue(apnsKey);
  const keyId = secretValue(apnsKeyId);
  const teamId = secretValue(apnsTeamId);
  if (!key || !keyId || !teamId) return null;
  if (cachedJwt && Date.now() - cachedJwt.at < 50 * 60 * 1000) return cachedJwt.token;
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const unsigned = `${b64({ alg: 'ES256', kid: keyId })}.${b64({ iss: teamId, iat: Math.floor(Date.now() / 1000) })}`;
  const sig = crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  cachedJwt = { token: `${unsigned}.${sig}`, at: Date.now() };
  return cachedJwt.token;
}

async function sendVoip(uid: string, tokens: string[], payload: object): Promise<boolean> {
  const jwt = apnsJwt();
  if (!jwt || tokens.length === 0) return false;
  const host = apnsProduction.value() ? 'https://api.push.apple.com' : 'https://api.development.push.apple.com';
  const client = http2.connect(host);
  const body = JSON.stringify(payload);
  let delivered = false;
  try {
    await Promise.all(
      tokens.map(
        (token) =>
          new Promise<void>((resolve) => {
            const req = client.request({
              ':method': 'POST',
              ':path': `/3/device/${token}`,
              authorization: `bearer ${jwt}`,
              'apns-topic': apnsTopic.value(),
              'apns-push-type': 'voip',
              'apns-priority': '10',
              'apns-expiration': String(Math.floor((Date.now() + RING_MS) / 1000)),
            });
            let status = 0;
            req.on('response', (h) => {
              status = Number(h[':status']);
            });
            req.on('data', () => undefined);
            req.on('end', async () => {
              if (status === 200) delivered = true;
              if (status === 410 || status === 400) {
                await db().collection('users').doc(uid).collection('voip_tokens').doc(token).delete().catch(() => undefined);
              }
              resolve();
            });
            req.on('error', (e) => {
              logger.warn('APNs request failed', e);
              resolve();
            });
            req.end(body);
          }),
      ),
    );
  } finally {
    client.close();
  }
  return delivered;
}

// ───────────────────────── Triggers ─────────────────────────

async function isBlockedPair(a: string, b: string): Promise<boolean> {
  if (!a || !b || a === b) return false;
  try {
    const [d1, d2] = await Promise.all([
      db().collection('relationships').doc(`${a}_${b}`).get(),
      db().collection('relationships').doc(`${b}_${a}`).get(),
    ]);
    return d1.get('status') === 'blocked' || d2.get('status') === 'blocked';
  } catch (e) {
    logger.warn('isBlockedPair check skipped', e);
    return false;
  }
}

/** Rings a participant (and stops the ringing on their other devices). */
export const onCallParticipantWritten = onDocumentWritten(
  { document: 'calls/{callId}/participants/{uid}', secrets: [apnsKey, apnsKeyId, apnsTeamId] },
  async (event) => {
    const { callId, uid } = event.params;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const callSnap = await db().collection('calls').doc(callId).get();
    const call = callSnap.data() as CallDoc | undefined;
    if (!call || uid === call.hostId) return;

    const startedRinging = after?.status === 'ringing' && before?.status !== 'ringing';
    const stoppedRinging = before?.status === 'ringing' && after?.status !== 'ringing';

    if (startedRinging) {
      if (call.status && FINAL.includes(call.status)) return;
      const startedMs = call.startedAt?.toMillis?.() ?? Date.now();
      if (Date.now() - startedMs > RING_MS + 15_000) return;
      if (call.hostId && (await isBlockedPair(uid, call.hostId))) {
        await event.data?.after.ref
          .set({ status: 'declined', updatedAt: FieldValue.serverTimestamp() }, { merge: true })
          .catch(() => undefined);
        return;
      }
      const t = await tokensFor(uid);
      const data = callData(callId, call, 'incoming_call');
      const voipSent = await sendVoip(uid, t.voip, {
        aps: {},
        id: data.callkitId,
        nameCaller: data.callerName,
        handle: call.isVideo ? 'Video call' : 'Voice call',
        isVideo: call.isVideo === true,
        avatar: data.callerAvatar,
        extra: { callId, isVideo: call.isVideo === true, isGroup: call.isGroup === true, hostId: call.hostId ?? '' },
      });
      await sendFcm(uid, t.android, data);
      if (!voipSent) {
        await sendFcm(uid, t.iosFcm, data, {
          title: data.callerName || 'Oneova',
          body: `Incoming ${call.isVideo ? 'video' : 'voice'} call`,
        });
      }
      logger.info('Rang participant', { callId, uid, android: t.android.length, voip: voipSent });
      return;
    }

    if (stoppedRinging) {
      const reason = after?.status === 'missed' ? 'missed' : 'stopped';
      const t = await tokensFor(uid);
      await sendFcm(uid, [...t.android, ...t.iosFcm], callData(callId, call, 'call_cancel', { reason }));
      if (reason === 'missed') {
        await db().collection('notifications').add({
          userId: uid,
          actorId: call.hostId ?? null,
          category: 'missedCall',
          priority: 'high',
          title: 'Missed call',
          body: `${call.callerName || 'Someone'} tried to ${call.isVideo ? 'video ' : ''}call you`,
          groupId: `call_${callId}`,
          payload: { callId, hostId: call.hostId ?? '' },
          isRead: false,
          createdAt: FieldValue.serverTimestamp(),
        });
      }
    }
  },
);

/** When a call finishes: per-user history, and anyone still ringing is missed. */
export const onCallFinished = onDocumentUpdated('calls/{callId}', async (event) => {
  const before = event.data?.before.data() as CallDoc | undefined;
  const after = event.data?.after.data() as CallDoc | undefined;
  if (!before || !after) return;
  if (FINAL.includes(before.status ?? '') || !FINAL.includes(after.status ?? '')) return;
  const { callId } = event.params;

  const participants = await event.data!.after.ref.collection('participants').get();
  const batch = db().batch();
  const answered = after.answeredAt?.toMillis();
  const ended = after.endedAt?.toMillis() ?? Date.now();
  const durationSec = answered ? Math.max(0, Math.round((ended - answered) / 1000)) : 0;

  for (const p of participants.docs) {
    const status = String(p.get('status') ?? '');
    if (status === 'ringing') batch.update(p.ref, { status: 'missed', updatedAt: FieldValue.serverTimestamp() });
    const outgoing = p.id === after.hostId;
    const outcome = outgoing
      ? (answered ? 'completed' : after.status)
      : (status === 'joined' || status === 'left' ? 'completed' : status === 'ringing' ? 'missed' : status);
    batch.set(db().collection('users').doc(p.id).collection('call_history').doc(callId), {
      callId,
      direction: outgoing ? 'outgoing' : 'incoming',
      outcome,
      isVideo: after.isVideo === true,
      isGroup: after.isGroup === true,
      hostId: after.hostId ?? '',
      participantIds: after.participantIds ?? [],
      title: after.isGroup ? (after.title ?? null) : (outgoing ? null : (after.callerName ?? null)),
      durationSec,
      startedAt: after.startedAt ?? FieldValue.serverTimestamp(),
      endedAt: after.endedAt ?? FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
});

/** Ends calls left ringing after the caller's app died. */
export const sweepStaleCalls = onSchedule('every 5 minutes', async () => {
  const cutoff = Timestamp.fromMillis(Date.now() - 2 * 60 * 1000);
  const stale = await db()
    .collection('calls')
    .where('status', '==', 'ringing')
    .where('startedAt', '<', cutoff)
    .limit(200)
    .get();
  await Promise.all(
    stale.docs.map((d) =>
      d.ref.update({ status: 'missed', endReason: 'noAnswer', endedAt: FieldValue.serverTimestamp() }),
    ),
  );
  if (!stale.empty) logger.info(`Swept ${stale.size} stale ringing calls`);
});
