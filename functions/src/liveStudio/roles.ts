/**
 * LIVE STUDIO v2 — roles, join requests and moderation callables (workstream #4).
 * lsRequestJoin · lsCancelRequest · lsRespondRequest · lsModerate · lsLeaveStage
 * See docs/live-studio/ARCHITECTURE.md §5–§6. Pure logic: roles_logic.ts.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue, Transaction } from 'firebase-admin/firestore';
import { TrackSource } from 'livekit-server-sdk';
import { JoinRequest, JoinRequestStatus, Paths, StageMember, StudioEvent, StudioRole, Topics } from './contracts';
import {
  LIVEKIT_SECRETS,
  broadcast,
  db,
  isBlocked,
  loadState,
  patchState,
  rateLimit,
  requireLive,
  requireRole,
  requireString,
  requireUid,
  roleOf,
  roomName,
  roomService,
} from './shared';
import { PublishSource } from './media_logic';
import { SYSTEM_TEXT, avatarOf, displayNameOf, systemLineId } from './social_logic';
import {
  REQUEST_JOIN_MAX,
  REQUEST_JOIN_WINDOW_MS,
  RolesError,
  allowsGuestRequests,
  assertDecision,
  authorizeModeration,
  cancelDecision,
  guestMemberPatch,
  leaveDecision,
  micTrackSids,
  offStagePatch,
  parseModerateArgs,
  parseRespondArgs,
  permissionForRole,
  pickAccent,
  placeOnStage,
  removeFromLayout,
  requestJoinDecision,
  respondDecision,
} from './roles_logic';
import { recordStudioSignal } from './security';

const SOURCE: Record<PublishSource, TrackSource> = {
  camera: TrackSource.CAMERA,
  microphone: TrackSource.MICROPHONE,
  screen_share: TrackSource.SCREEN_SHARE,
};

/** Maps RolesError to HttpsError; rethrows anything else. */
async function guarded<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof RolesError) throw new HttpsError(e.code, e.message);
    throw e;
  }
}

const streamIdArg = (data: unknown) =>
  requireString((data as { streamId?: unknown } | null)?.streamId, 'streamId', 128);

const memberRef = (streamId: string, uid: string) => db().doc(`${Paths.members(streamId)}/${uid}`);
const requestRef = (streamId: string, uid: string) => db().doc(`${Paths.requests(streamId)}/${uid}`);

async function profileOf(uid: string): Promise<{ name: string; avatarUrl: string }> {
  const snap = await db().doc(`users/${uid}`).get();
  const d = snap.exists ? (snap.data() as Record<string, unknown>) : undefined;
  return { name: displayNameOf(d), avatarUrl: avatarOf(d) };
}

/** Host + co-hosts (identities that receive `stage.req`). */
async function managerUids(streamId: string, hostId: string): Promise<string[]> {
  const q = await db().collection(Paths.members(streamId)).where('role', '==', 'coHost').select().get();
  return [hostId, ...q.docs.map((d) => d.id).filter((u) => u !== hostId)];
}

async function sendSystemLine(
  streamId: string,
  kind: 'requested' | 'onStage',
  who: { uid: string; name: string; avatarUrl: string },
): Promise<void> {
  const ts = Date.now();
  await broadcast(streamId, Topics.chat, {
    v: 1,
    type: 'system',
    id: systemLineId(ts, Math.random()),
    kind,
    uid: who.uid,
    name: who.name,
    avatarUrl: who.avatarUrl,
    text: SYSTEM_TEXT[kind],
    ts,
  });
}

/** `request.new` / `request.update` to [to]. [extra] (e.g. `rejoin`) rides along in the JSON. */
async function sendRequestEvent(
  streamId: string,
  type: 'request.new' | 'request.update',
  r: JoinRequest,
  to: string[],
  extra: Record<string, unknown> = {},
): Promise<void> {
  const event = { v: 1, type, ...r, ...extra, ts: Date.now() } as StudioEvent;
  await broadcast(streamId, Topics.requests, event, { to });
}

/**
 * Updates the participant's LiveKit permission (and `role` attribute) in
 * place. Returns false when they are not in the room or LiveKit refused,
 * so the caller can ask the client to rejoin with a fresh token.
 */
async function setLivePermission(streamId: string, uid: string, role: StudioRole): Promise<boolean> {
  const p = permissionForRole(role);
  try {
    await roomService().updateParticipant(roomName(streamId), uid, {
      attributes: { role },
      permission: { ...p, canPublishSources: p.canPublishSources.map((s) => SOURCE[s]) },
    });
    return true;
  } catch (e) {
    console.warn(`[liveStudio] updateParticipant ${uid} in ${streamId}:`, (e as Error).message);
    return false;
  }
}

/** Mutes every published mic track of [uid] (server-side). Best effort. */
async function muteMic(streamId: string, uid: string): Promise<void> {
  const room = roomName(streamId);
  try {
    const p = await roomService().getParticipant(room, uid);
    const sids = micTrackSids(
      (p.tracks ?? []).map((t) => ({ sid: t.sid, source: t.source as number, name: t.name })),
      TrackSource.MICROPHONE as number,
    );
    await Promise.all(sids.map((sid) => roomService().mutePublishedTrack(room, uid, sid, true)));
  } catch (e) {
    console.warn(`[liveStudio] mute ${uid} in ${streamId}:`, (e as Error).message);
  }
}

/**
 * Takes [uid] off the stage: removed from center/wall/overflow (host back to
 * center if they were there), members doc → viewer, join request cleared,
 * LiveKit publish revoked, the user told with `request.update` (cancelled).
 */
async function takeOffStage(streamId: string, uid: string, by: string): Promise<{ wasCoHost: boolean }> {
  let wasCoHost = false;
  await patchState(streamId, 'stage', async (s, tx: Transaction) => {
    const [m, r] = await Promise.all([tx.get(memberRef(streamId, uid)), tx.get(requestRef(streamId, uid))]);
    if (m.exists) {
      wasCoHost = (m.data() as StageMember).role === 'coHost';
      tx.set(memberRef(streamId, uid), offStagePatch(), { merge: true });
    }
    if (r.exists) tx.delete(requestRef(streamId, uid));
    return removeFromLayout(s.stage, uid, s.hostId, Date.now(), by);
  });
  if (wasCoHost) {
    await db().doc(`${Paths.streams}/${streamId}`).set({ coHostIds: FieldValue.arrayRemove(uid) }, { merge: true });
  }
  await setLivePermission(streamId, uid, 'viewer');
  await sendRequestEvent(
    streamId,
    'request.update',
    { uid, displayName: '', avatarUrl: '', status: 'cancelled', requestedAtMs: 0 },
    [uid],
  );
  return { wasCoHost };
}

// ─── Callables ───────────────────────────────────────────────────────────────

/** A viewer asks to join the stage. Returns `{ok, status:'pending'}`. */
export const lsRequestJoin = onCall({ secrets: LIVEKIT_SECRETS }, (req) =>
  guarded(async () => {
    const uid = requireUid(req);
    const streamId = streamIdArg(req.data);
    void recordStudioSignal(streamId, uid, 'join_request');
    const [state, blocked, streamSnap, existing] = await Promise.all([
      loadState(streamId),
      isBlocked(streamId, uid),
      db().doc(`${Paths.streams}/${streamId}`).get(),
      requestRef(streamId, uid).get(),
    ]);
    const role = await roleOf(streamId, uid, state);
    assertDecision(requestJoinDecision({
      role,
      blocked,
      status: state.status,
      allowGuestRequests: allowsGuestRequests(streamSnap.data()),
      existing: existing.exists ? ((existing.data() as JoinRequest).status ?? null) : null,
    }));
    await rateLimit(streamId, uid, 'join', REQUEST_JOIN_MAX, REQUEST_JOIN_WINDOW_MS);

    const p = await profileOf(uid);
    const request: JoinRequest = {
      uid,
      displayName: p.name,
      avatarUrl: p.avatarUrl,
      status: 'pending',
      requestedAtMs: Date.now(),
    };
    await requestRef(streamId, uid).set(request);
    await sendRequestEvent(streamId, 'request.new', request, await managerUids(streamId, state.hostId));
    await sendSystemLine(streamId, 'requested', { uid, name: p.name, avatarUrl: p.avatarUrl });
    return { ok: true, status: 'pending' as JoinRequestStatus };
  }),
);

/** The requester withdraws their pending request. Returns `{ok, status:'cancelled'}`. */
export const lsCancelRequest = onCall({ secrets: LIVEKIT_SECRETS }, (req) =>
  guarded(async () => {
    const uid = requireUid(req);
    const streamId = streamIdArg(req.data);
    const ref = requestRef(streamId, uid);
    const r = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const cur = snap.exists ? (snap.data() as JoinRequest) : null;
      assertDecision(cancelDecision(cur?.status));
      tx.update(ref, { status: 'cancelled' });
      return { ...(cur as JoinRequest), status: 'cancelled' as JoinRequestStatus };
    });
    const state = await loadState(streamId);
    await sendRequestEvent(streamId, 'request.update', r, await managerUids(streamId, state.hostId));
    return { ok: true, status: 'cancelled' };
  }),
);

/**
 * Host/co-host answers a request. Approve → guest with an accent, first free
 * wall index (or overflow), LiveKit publish granted in place.
 * Returns `{ok, status, placement?, rejoin}`; `rejoin` is true when the
 * guest was not in the room and must reconnect with a fresh token.
 */
export const lsRespondRequest = onCall({ secrets: LIVEKIT_SECRETS }, (req) =>
  guarded(async () => {
    const actor = requireUid(req);
    const streamId = streamIdArg(req.data);
    const { uid, approve } = parseRespondArgs(req.data);
    const state = await loadState(streamId);
    requireLive(state);
    const actorRole = await requireRole(streamId, actor, ['host', 'coHost'], state);
    const targetBlocked = await isBlocked(streamId, uid);
    const ref = requestRef(streamId, uid);

    if (!approve) {
      const r = await db().runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const cur = snap.exists ? (snap.data() as JoinRequest) : null;
        assertDecision(respondDecision({ actorRole, requestStatus: cur?.status, targetRole: 'viewer', targetBlocked: false }));
        tx.update(ref, { status: 'declined', respondedBy: actor, respondedAtMs: Date.now() });
        return { ...(cur as JoinRequest), status: 'declined' as JoinRequestStatus };
      });
      await sendRequestEvent(streamId, 'request.update', r, [uid]);
      return { ok: true, status: 'declined', rejoin: false };
    }

    let request: JoinRequest | null = null;
    let placement: ReturnType<typeof placeOnStage>['placement'] = { kind: 'already' };
    await patchState(streamId, 'stage', async (s, tx) => {
      const [reqSnap, membersSnap] = await Promise.all([tx.get(ref), tx.get(db().collection(Paths.members(streamId)))]);
      const cur = reqSnap.exists ? (reqSnap.data() as JoinRequest) : null;
      const members = membersSnap.docs.map((d) => ({ ...(d.data() as StageMember), uid: d.id }));
      const target = members.find((m) => m.uid === uid);
      const targetRole: StudioRole = uid === s.hostId ? 'host' : (target?.role ?? 'viewer');
      assertDecision(respondDecision({ actorRole, requestStatus: cur?.status, targetRole, targetBlocked }));

      const now = Date.now();
      const placed = placeOnStage(s.stage, uid, now, actor);
      placement = placed.placement;
      tx.set(
        memberRef(streamId, uid),
        guestMemberPatch({
          uid,
          displayName: cur!.displayName,
          avatarUrl: cur!.avatarUrl,
          accent: pickAccent(members, uid),
          nowMs: now,
        }),
        { merge: true },
      );
      tx.update(ref, { status: 'approved', respondedBy: actor, respondedAtMs: now, rejoin: false });
      request = { ...cur!, status: 'approved' };
      return placed.placement.kind === 'already' ? undefined : placed.stage;
    });

    const inPlace = await setLivePermission(streamId, uid, 'guest');
    if (!inPlace) await ref.update({ rejoin: true });
    const approved = request as unknown as JoinRequest;
    await sendRequestEvent(streamId, 'request.update', approved, [uid], { rejoin: !inPlace });
    await sendSystemLine(streamId, 'onStage', { uid, name: approved.displayName, avatarUrl: approved.avatarUrl });
    return { ok: true, status: 'approved', placement, rejoin: !inPlace };
  }),
);

/**
 * Host/co-host moderation: `mute` | `removeFromStage` | `block`, plus the
 * host-only `promoteCoHost` | `demoteCoHost` (local type until the contract
 * enum gains them). Returns `{ok, action}`.
 */
export const lsModerate = onCall({ secrets: LIVEKIT_SECRETS }, (req) =>
  guarded(async () => {
    const actor = requireUid(req);
    const streamId = streamIdArg(req.data);
    const { uid, action } = parseModerateArgs(req.data);
    const state = await loadState(streamId);
    const actorRole = await requireRole(streamId, actor, ['host', 'coHost'], state);
    const targetRole = await roleOf(streamId, uid, state);
    const st = state.stage;
    const targetOnStage = st.centerUid === uid || st.wall.includes(uid) || st.overflow.includes(uid);
    assertDecision(authorizeModeration({ action, actorUid: actor, actorRole, targetUid: uid, targetRole, targetOnStage }));

    switch (action) {
      case 'mute':
        await muteMic(streamId, uid);
        await memberRef(streamId, uid).set({ micOn: false }, { merge: true });
        break;
      case 'removeFromStage':
        await takeOffStage(streamId, uid, actor);
        break;
      case 'block': {
        if (targetOnStage || targetRole !== 'viewer') await takeOffStage(streamId, uid, actor);
        await db().doc(`${Paths.blocks(streamId)}/${uid}`).set({ uid, by: actor, atMs: Date.now() });
        await requestRef(streamId, uid).delete();
        try {
          await roomService().removeParticipant(roomName(streamId), uid);
        } catch (e) {
          console.warn(`[liveStudio] removeParticipant ${uid}:`, (e as Error).message);
        }
        break;
      }
      case 'promoteCoHost':
      case 'demoteCoHost': {
        const role: StudioRole = action === 'promoteCoHost' ? 'coHost' : 'guest';
        await memberRef(streamId, uid).set({ role }, { merge: true });
        await db().doc(`${Paths.streams}/${streamId}`).set(
          { coHostIds: action === 'promoteCoHost' ? FieldValue.arrayUnion(uid) : FieldValue.arrayRemove(uid) },
          { merge: true },
        );
        await setLivePermission(streamId, uid, role);
        break;
      }
    }
    return { ok: true, action };
  }),
);

/** A guest or co-host leaves the stage. Returns `{ok}`. */
export const lsLeaveStage = onCall({ secrets: LIVEKIT_SECRETS }, (req) =>
  guarded(async () => {
    const uid = requireUid(req);
    const streamId = streamIdArg(req.data);
    const state = await loadState(streamId);
    const role = await roleOf(streamId, uid, state);
    assertDecision(leaveDecision(role));
    await takeOffStage(streamId, uid, uid);
    return { ok: true };
  }),
);
