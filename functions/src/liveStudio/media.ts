/**
 * LIVE STUDIO v2 — realtime media callables (workstream #1).
 * lsStart · lsToken · lsEnd · lsTime · lsStateFull · lsSetOwnMedia
 * See docs/live-studio/ARCHITECTURE.md §5–§7. Pure logic: media_logic.ts.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { AccessToken, TrackSource } from 'livekit-server-sdk';
import { Paths, StageMember, StudioRole } from './contracts';
import {
  LIVEKIT_SECRETS,
  LIVEKIT_URL,
  LIVEKIT_API_KEY,
  LIVEKIT_API_SECRET,
  db,
  isBlocked,
  loadState,
  requireLive,
  requireRole,
  requireString,
  requireUid,
  roleOf,
  roomName,
  roomService,
} from './shared';
import { normalizeSettings } from './settings_logic';
import { endStudioStream } from './lifecycle';
import { parseStartExtras } from './lifecycle_logic';
import { followDocId, isAcceptedFollow } from './controls_logic';
import { mediaKeyForToken, recordStudioSignal, recordTokenSignal } from './security';
import {
  PublishSource,
  ROOM_EMPTY_TIMEOUT_SECONDS,
  TOKEN_TTL_SECONDS,
  Profile,
  StartValidationError,
  applyStartKind,
  buildHostMember,
  buildInitialState,
  buildStreamDoc,
  canSetOwnMedia,
  grantForRole,
  mergeStartSettings,
  parseOwnMedia,
  parseStartKind,
  profileFrom,
  tokenDecision,
  wireState,
} from './media_logic';

const SOURCE: Record<PublishSource, TrackSource> = {
  camera: TrackSource.CAMERA,
  microphone: TrackSource.MICROPHONE,
  screen_share: TrackSource.SCREEN_SHARE,
};

async function profileOf(uid: string, token?: { name?: unknown; picture?: unknown }): Promise<Profile> {
  const snap = await db().doc(`users/${uid}`).get();
  return profileFrom(snap.exists ? (snap.data() as Record<string, unknown>) : undefined, token);
}

/** Mints a LiveKit token for [uid] with the grants of [role] (identity = Firebase uid). */
async function mintToken(streamId: string, uid: string, role: StudioRole, name: string): Promise<string> {
  const g = grantForRole(role, roomName(streamId));
  const at = new AccessToken(LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value(), {
    identity: uid,
    name,
    ttl: TOKEN_TTL_SECONDS,
    attributes: { role },
  });
  at.addGrant({ ...g, canPublishSources: g.canPublishSources.map((s) => SOURCE[s]) });
  return at.toJwt();
}

function streamIdArg(data: unknown): string {
  return requireString((data as { streamId?: unknown } | null)?.streamId, 'streamId', 128);
}

/** Host starts a v2 live. Returns `{streamId, token, url, role}`. */
export const lsStart = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = (req.data ?? {}) as {
    title?: unknown;
    settings?: unknown;
    kind?: unknown;
    gameTitle?: unknown;
    category?: unknown;
    coverUrl?: unknown;
    audienceMode?: unknown;
    allowGuestRequests?: unknown;
  };
  const title = requireString(data.title, 'title', 200);
  let start;
  try {
    start = parseStartKind(data);
  } catch (e) {
    if (e instanceof StartValidationError) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }
  const { kind, gameTitle } = start;
  const extras = parseStartExtras(data);
  const [profile, savedSnap] = await Promise.all([
    profileOf(uid, req.auth?.token),
    db().doc(Paths.hostSettings(uid)).get(),
  ]);
  const settings = applyStartKind(
    normalizeSettings(mergeStartSettings(savedSnap.exists ? savedSnap.data() : undefined, data.settings)),
    kind,
  );

  const streamRef = db().collection(Paths.streams).doc();
  const streamId = streamRef.id;
  const now = Date.now();

  // Room first: if LiveKit is unreachable nothing is written.
  try {
    await roomService().createRoom({ name: roomName(streamId), emptyTimeout: ROOM_EMPTY_TIMEOUT_SECONDS });
  } catch (e) {
    console.error('[liveStudio] createRoom failed:', (e as Error).message);
    throw new HttpsError('unavailable', 'Could not open the live room. Try again.');
  }

  const batch = db().batch();
  batch.set(streamRef, {
    ...buildStreamDoc({ streamId, hostId: uid, title, profile, kind, gameTitle }),
    audienceMode: extras.audienceMode,
    allowGuestRequests: extras.allowGuestRequests,
    ...(extras.category && kind !== 'gaming' ? { category: extras.category } : {}),
    ...(extras.coverUrl ? { coverUrl: extras.coverUrl, thumbnailUrl: extras.coverUrl } : {}),
    createdAt: FieldValue.serverTimestamp(),
    hostHeartbeatAt: FieldValue.serverTimestamp(),
  });
  batch.set(db().doc(Paths.state(streamId)), {
    ...buildInitialState({ streamId, hostId: uid, title, settings, nowMs: now, gameTitle }),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(db().doc(`${Paths.members(streamId)}/${uid}`), buildHostMember(uid, profile, now));
  await batch.commit();

  const [token, e2ee] = await Promise.all([
    mintToken(streamId, uid, 'host', profile.displayName),
    mediaKeyForToken(streamId),
  ]);
  return { streamId, token, url: LIVEKIT_URL.value(), role: 'host', e2ee };
});

/**
 * LiveKit join token for the caller. Returns `{token, url, role, e2ee}`;
 * `e2ee` is `{key, keyIndex}` (the stream's shared media key, base64) or
 * null when LIVE_STUDIO_E2EE is off. See security.ts / security_logic.ts.
 */
export const lsToken = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const streamId = streamIdArg(req.data);
  const state = await loadState(streamId);
  const blocked = await isBlocked(streamId, uid);
  const decision = tokenDecision({ status: state.status, blocked });
  if (!decision.ok) {
    if (blocked) await recordStudioSignal(streamId, uid, 'blocked_token');
    throw new HttpsError(decision.code, decision.message);
  }

  const role = await roleOf(streamId, uid, state);
  if (role === 'viewer' && uid !== state.hostId) {
    // Followers-only lives (setup wizard → audienceMode): viewers must follow the host.
    const stream = await db().doc(`${Paths.streams}/${streamId}`).get();
    if (stream.get('audienceMode') === 'followers') {
      const rel = await db().doc(`relationships/${followDocId(uid, state.hostId)}`).get();
      if (!rel.exists || !isAcceptedFollow(rel.get('status'))) {
        throw new HttpsError('permission-denied', 'This live is for followers only. Follow the host to watch.');
      }
    }
  }
  const member = await db().doc(`${Paths.members(streamId)}/${uid}`).get();
  const name = member.exists
    ? (member.data() as StageMember).displayName
    : (await profileOf(uid, req.auth?.token)).displayName;
  const [token, e2ee] = await Promise.all([
    mintToken(streamId, uid, role, name),
    mediaKeyForToken(streamId),
    recordTokenSignal(streamId, uid, req),
  ]);
  return { token, url: LIVEKIT_URL.value(), role, e2ee };
});

/** Host ends the live: status ended (stream doc + studio/state), room deleted. */
export const lsEnd = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const streamId = streamIdArg(req.data);
  await requireRole(streamId, uid, ['host']);
  await endStudioStream(streamId, 'host');
  return { ok: true };
});

/** Server clock, for the client's offset estimate. Returns `{serverMs}`. */
export const lsTime = onCall(async (req) => {
  requireUid(req);
  return { serverMs: Date.now() };
});

/** Full StudioState for resync (late join, reconnect, seq gap). Returns `{state}`. */
export const lsStateFull = onCall(async (req) => {
  const uid = requireUid(req);
  const streamId = streamIdArg(req.data);
  if (await isBlocked(streamId, uid)) throw new HttpsError('permission-denied', 'You are blocked from this live.');
  const snap = await db().doc(Paths.state(streamId)).get();
  if (!snap.exists) throw new HttpsError('not-found', 'This live does not exist.');
  return { state: wireState(snap.data() as Record<string, unknown>) };
});

/** A publisher syncs their own mic / cam flags to their members doc. */
export const lsSetOwnMedia = onCall(async (req) => {
  const uid = requireUid(req);
  const streamId = streamIdArg(req.data);
  const media = parseOwnMedia(req.data);
  if (!media) throw new HttpsError('invalid-argument', 'micOn and camOn must be booleans.');
  const state = await loadState(streamId);
  requireLive(state);
  const role = await requireRole(streamId, uid, ['host', 'coHost', 'guest'], state);
  if (!canSetOwnMedia(role, uid, state)) throw new HttpsError('failed-precondition', 'You are not on stage.');
  await db().doc(`${Paths.members(streamId)}/${uid}`).set(media, { merge: true });
  return { ok: true, ...media };
});
