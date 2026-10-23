/**
 * LIVE STUDIO v2 — `lsSetSettings` (workstream #6, stage customization).
 *
 * Args:   { streamId: string | null, partial: Partial<StudioSettings> }
 * Result: { settings: StudioSettings, changed: string[] }
 *
 * - streamId null: validates and saves the caller's own defaults at
 *   users/{uid}/live_studio/settings (used by Go Live / lsStart).
 * - streamId set: host only. Applies the patch to studio/state.settings via
 *   patchState (seq bump + `state.patch` broadcast to every viewer) and
 *   mirrors the applied settings into the host's saved defaults.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { Paths, StudioSettings } from './contracts';
import { LIVEKIT_SECRETS, db, loadState, patchState, rateLimit, requireLive, requireRole, requireUid } from './shared';
import { SettingsValidationError, applySettingsPatch, normalizeSettings, parseStreamId } from './settings_logic';

/** 10 settings calls per 2 s per host per stream (the client throttles sliders to 4/s). */
const RATE_MAX = 10;
const RATE_WINDOW_MS = 2000;

function asInvalidArgument<T>(fn: () => T): T {
  try {
    return fn();
  } catch (e) {
    if (e instanceof SettingsValidationError) throw new HttpsError('invalid-argument', e.message);
    throw e;
  }
}

async function saveHostDefaults(uid: string, settings: StudioSettings) {
  await db().doc(Paths.hostSettings(uid)).set({ ...settings, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

export const lsSetSettings = onCall({ secrets: LIVEKIT_SECRETS }, async (req) => {
  const uid = requireUid(req);
  const data = (req.data ?? {}) as { streamId?: unknown; partial?: unknown };
  const streamId = asInvalidArgument(() => parseStreamId(data.streamId));
  const partial = data.partial;

  if (streamId === null) {
    const ref = db().doc(Paths.hostSettings(uid));
    const settings = await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const { next, changed } = asInvalidArgument(() =>
        applySettingsPatch(normalizeSettings(snap.exists ? snap.data() : undefined), partial),
      );
      tx.set(ref, { ...next, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return { next, changed };
    });
    return { settings: settings.next, changed: settings.changed };
  }

  const state = await loadState(streamId);
  await requireRole(streamId, uid, ['host'], state);
  requireLive(state);
  // Fail fast with a clear error before taking the transaction.
  asInvalidArgument(() => applySettingsPatch(normalizeSettings(state.settings), partial));
  await rateLimit(streamId, uid, 'settings', RATE_MAX, RATE_WINDOW_MS);

  let changed: (keyof StudioSettings)[] = [];
  let applied: StudioSettings = normalizeSettings(state.settings);
  const result = await patchState(streamId, 'settings', (s) => {
    const r = asInvalidArgument(() => applySettingsPatch(normalizeSettings(s.settings), partial));
    changed = r.changed;
    applied = r.next;
    return r.changed.length ? r.next : undefined;
  });
  if (result) applied = result.settings;

  await saveHostDefaults(uid, applied);
  return { settings: applied, changed };
});
