/**
 * LIVE STUDIO v2 — "On the table" callables (workstream #5, ARCHITECTURE §9).
 *
 * - `lsSetTable({streamId, mode, ref?})` → `{ok, seq, table}`
 * - `lsPlayback({streamId, state, positionMs})` → `{ok, seq, table}`
 *
 * Both are host/co-host only and write the `table` section through
 * `patchState` (one transaction + one `state.patch` broadcast). Pure
 * validation lives in table_logic.ts.
 *
 * Watch content comes ONLY from the admin-curated `live_watch_catalog`
 * (ARCHITECTURE Q7). No free-form URLs are accepted.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { GoodsRef, Paths, StageMember, StudioRole } from './contracts';
import {
  LIVEKIT_SECRETS,
  db,
  loadState,
  patchState,
  rateLimit,
  requireLive,
  requireRole,
  requireString,
} from './shared';
import {
  ResolvedTable,
  TableError,
  applyPlayback,
  authorizeSetTable,
  normalizeTable,
  parseCatalogEntry,
  parsePlayback,
  parseSetTable,
  pickCatalogEntry,
  resolveScreenPublisher,
  validateCatalogEntry,
  validateGoods,
  nextTable,
} from './table_logic';

const toHttps = (e: unknown): never => {
  if (e instanceof TableError) throw new HttpsError(e.code, e.message);
  throw e;
};

const guard = <T>(fn: () => T): T => {
  try {
    return fn();
  } catch (e) {
    return toHttps(e);
  }
};

async function loadRoles(streamId: string): Promise<Record<string, StudioRole>> {
  const snap = await db().collection(Paths.members(streamId)).get();
  const roles: Record<string, StudioRole> = {};
  snap.forEach((d) => {
    roles[d.id] = (d.data() as StageMember).role ?? 'viewer';
  });
  return roles;
}

/** Goods per decision Q5: the host's Biz products first, then the stream list. */
async function defaultGoods(streamId: string, hostId: string): Promise<GoodsRef | null> {
  const biz = await db().collection('products').where('ownerId', '==', hostId).limit(1).get();
  if (!biz.empty) return { source: 'biz', productId: biz.docs[0].id };
  const own = await db().collection(`${Paths.streams}/${streamId}/products`).orderBy('sortOrder').limit(1).get();
  if (!own.empty) return { source: 'stream', productId: own.docs[0].id };
  return null;
}

async function loadProduct(streamId: string, ref: GoodsRef): Promise<Record<string, unknown> | null> {
  const path = ref.source === 'biz'
    ? `products/${ref.productId}`
    : `${Paths.streams}/${streamId}/products/${ref.productId}`;
  const snap = await db().doc(path).get();
  return snap.exists ? (snap.data() as Record<string, unknown>) : null;
}

export const lsSetTable = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const data = (req.data ?? {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  const request = guard(() => parseSetTable(data));

  const state = await loadState(streamId);
  requireLive(state);
  const role = await requireRole(streamId, uid, ['host', 'coHost'], state);
  guard(() => authorizeSetTable(role));
  await rateLimit(streamId, uid, 'table', 5, 1000);

  const nowMs = Date.now();
  let resolved: ResolvedTable;
  switch (request.mode) {
    case 'goods': {
      if (request.goods) {
        const doc = await loadProduct(streamId, request.goods);
        resolved = { mode: 'goods', goods: guard(() => validateGoods(request.goods!, doc, state.hostId)) };
      } else {
        resolved = { mode: 'goods', goods: await defaultGoods(streamId, state.hostId) };
      }
      break;
    }
    case 'screen': {
      const roles = await loadRoles(streamId);
      const screen = guard(() =>
        resolveScreenPublisher(request.publisherUid, { callerUid: uid, hostId: state.hostId, roles }));
      resolved = { mode: 'screen', screen };
      break;
    }
    default: {
      const mode = request.mode;
      if (request.catalogId) {
        const snap = await db().doc(`${Paths.watchCatalog}/${request.catalogId}`).get();
        const entry = guard(() => validateCatalogEntry(
          parseCatalogEntry(request.catalogId!, snap.exists ? (snap.data() as Record<string, unknown>) : null),
          mode,
          nowMs,
        ));
        resolved = { mode, catalogId: entry.id };
      } else {
        const q = await db().collection(Paths.watchCatalog).where('kind', '==', mode).limit(25).get();
        const entry = pickCatalogEntry(
          q.docs.map((d) => ({ id: d.id, data: d.data() as Record<string, unknown> })),
          mode,
          nowMs,
        );
        resolved = { mode, catalogId: entry?.id ?? null };
      }
    }
  }

  const next = await patchState(streamId, 'table', (s) => nextTable(normalizeTable(s.table), resolved, Date.now()));
  const finalState = next ?? (await loadState(streamId));
  return { ok: true, seq: finalState.seq, table: normalizeTable(finalState.table) };
});

export const lsPlayback = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const data = (req.data ?? {}) as Record<string, unknown>;
  const streamId = requireString(data.streamId, 'streamId', 128);
  const request = guard(() => parsePlayback(data));

  const state = await loadState(streamId);
  requireLive(state);
  await requireRole(streamId, uid, ['host', 'coHost'], state);
  await rateLimit(streamId, uid, 'playback', 5, 1000);

  const next = await patchState(streamId, 'table', (s) =>
    guard(() => applyPlayback(normalizeTable(s.table), request, Date.now())));
  const finalState = next ?? (await loadState(streamId));
  return { ok: true, seq: finalState.seq, table: normalizeTable(finalState.table) };
});
