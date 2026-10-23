/**
 * LIVE STUDIO v2 — host chat / join controls.
 *   lsSetChatMode({streamId, mode: 'open'|'slow'|'followers', slowSeconds?})
 *   lsSetJoinRequests({streamId, open})
 * Host / co-host only. State lives on the stream doc (studioChatMode,
 * allowGuestRequests) and is enforced server-side in lsComment / lsRequestJoin.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { Paths, StudioRole } from './contracts';
import { LIVEKIT_SECRETS, broadcast, db, loadState, rateLimit, requireLive, requireRole, requireString, requireUid } from './shared';
import {
  ChatModeState,
  chatModeRequirement,
  followDocId,
  isAcceptedFollow,
  parseChatMode,
  readChatMode,
} from './controls_logic';

const asData = (d: unknown): Record<string, unknown> => (d && typeof d === 'object' ? (d as Record<string, unknown>) : {});

export const lsSetChatMode = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireString(data.streamId, 'streamId', 128);
  const parsed = parseChatMode(data);
  if (!parsed.ok) throw new HttpsError('invalid-argument', parsed.reason);
  const state = await loadState(streamId);
  requireLive(state);
  await requireRole(streamId, uid, ['host', 'coHost'], state);
  await rateLimit(streamId, uid, 'chatmode', 10, 60_000);
  await db().doc(`${Paths.streams}/${streamId}`).set(
    { studioChatMode: parsed.value, studioChatModeAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await broadcast(streamId, 'chat', {
    v: 1,
    type: 'system',
    id: `chatmode_${Date.now()}`,
    uid,
    name: '',
    avatarUrl: '',
    text:
      parsed.value.mode === 'slow'
        ? `Slow mode on: one comment every ${parsed.value.slowSeconds}s`
        : parsed.value.mode === 'followers'
          ? 'Followers-only chat is on'
          : 'Chat is open to everyone',
    kind: 'shared',
    ts: Date.now(),
  });
  return { ok: true, chatMode: parsed.value };
});

export const lsSetJoinRequests = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = asData(req.data);
  const streamId = requireString(data.streamId, 'streamId', 128);
  if (typeof data.open !== 'boolean') throw new HttpsError('invalid-argument', 'open must be true or false.');
  const state = await loadState(streamId);
  requireLive(state);
  await requireRole(streamId, uid, ['host', 'coHost'], state);
  await rateLimit(streamId, uid, 'joinreq_ctl', 10, 60_000);
  await db().doc(`${Paths.streams}/${streamId}`).set({ allowGuestRequests: data.open }, { merge: true });
  return { ok: true, open: data.open };
});

/**
 * Called by lsComment for every comment: enforces slow mode and
 * followers-only chat for non-managers. Throws HttpsError when refused.
 */
export async function enforceChatMode(streamId: string, uid: string, role: StudioRole, hostId: string): Promise<void> {
  const streamSnap = await db().doc(`${Paths.streams}/${streamId}`).get();
  const mode: ChatModeState = readChatMode(streamSnap.get('studioChatMode'));
  const need = chatModeRequirement(mode, role);
  if (need.kind === 'slow') {
    await rateLimit(streamId, uid, 'cmt_slow', 1, need.seconds * 1000);
  } else if (need.kind === 'follower') {
    const rel = await db().doc(`relationships/${followDocId(uid, hostId)}`).get();
    if (!rel.exists || !isAcceptedFollow(rel.get('status'))) {
      throw new HttpsError('permission-denied', 'Only followers can comment right now. Follow the host to join the chat.');
    }
  }
}
