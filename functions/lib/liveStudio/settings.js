"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsSetSettings = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const settings_logic_1 = require("./settings_logic");
/** 10 settings calls per 2 s per host per stream (the client throttles sliders to 4/s). */
const RATE_MAX = 10;
const RATE_WINDOW_MS = 2000;
function asInvalidArgument(fn) {
    try {
        return fn();
    }
    catch (e) {
        if (e instanceof settings_logic_1.SettingsValidationError)
            throw new https_1.HttpsError('invalid-argument', e.message);
        throw e;
    }
}
async function saveHostDefaults(uid, settings) {
    await (0, shared_1.db)().doc(contracts_1.Paths.hostSettings(uid)).set(Object.assign(Object.assign({}, settings), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
}
exports.lsSetSettings = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const data = ((_a = req.data) !== null && _a !== void 0 ? _a : {});
    const streamId = asInvalidArgument(() => (0, settings_logic_1.parseStreamId)(data.streamId));
    const partial = data.partial;
    if (streamId === null) {
        const ref = (0, shared_1.db)().doc(contracts_1.Paths.hostSettings(uid));
        const settings = await (0, shared_1.db)().runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const { next, changed } = asInvalidArgument(() => (0, settings_logic_1.applySettingsPatch)((0, settings_logic_1.normalizeSettings)(snap.exists ? snap.data() : undefined), partial));
            tx.set(ref, Object.assign(Object.assign({}, next), { updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
            return { next, changed };
        });
        return { settings: settings.next, changed: settings.changed };
    }
    const state = await (0, shared_1.loadState)(streamId);
    await (0, shared_1.requireRole)(streamId, uid, ['host'], state);
    (0, shared_1.requireLive)(state);
    // Fail fast with a clear error before taking the transaction.
    asInvalidArgument(() => (0, settings_logic_1.applySettingsPatch)((0, settings_logic_1.normalizeSettings)(state.settings), partial));
    await (0, shared_1.rateLimit)(streamId, uid, 'settings', RATE_MAX, RATE_WINDOW_MS);
    let changed = [];
    let applied = (0, settings_logic_1.normalizeSettings)(state.settings);
    const result = await (0, shared_1.patchState)(streamId, 'settings', (s) => {
        const r = asInvalidArgument(() => (0, settings_logic_1.applySettingsPatch)((0, settings_logic_1.normalizeSettings)(s.settings), partial));
        changed = r.changed;
        applied = r.next;
        return r.changed.length ? r.next : undefined;
    });
    if (result)
        applied = result.settings;
    await saveHostDefaults(uid, applied);
    return { settings: applied, changed };
});
//# sourceMappingURL=settings.js.map