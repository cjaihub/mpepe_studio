"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert/strict"));
const security_logic_1 = require("../security_logic");
const spec = (id) => security_logic_1.DETECTORS.find((d) => d.id === id);
/** Feeds [n] hits spaced [stepMs] apart through a detector's sliding log. */
function feed(id, n, stepMs, values) {
    const s = spec(id);
    let log = [];
    const cap = Math.min(200, s.distinct ? s.criticalAt * 8 : s.criticalAt + 1);
    for (let i = 0; i < n; i++) {
        log = (0, security_logic_1.slideLog)(log, values ? { t: 1000000 + i * stepMs, v: values(i) } : { t: 1000000 + i * stepMs }, s.windowMs, cap);
    }
    return (0, security_logic_1.countLog)(log, !!s.distinct);
}
// ─── Detectors ──────────────────────────────────────────────────────────────
(0, node_test_1.test)('every detector has warn < critical and a positive window', () => {
    for (const d of security_logic_1.DETECTORS) {
        assert.ok(d.warnAt < d.criticalAt, d.id);
        assert.ok(d.windowMs > 0, d.id);
        assert.ok(d.reason(3, d.windowMs).length > 0);
    }
});
(0, node_test_1.test)('severity thresholds', () => {
    const s = spec('comment_flood_user');
    assert.equal((0, security_logic_1.severityFor)(s, s.warnAt - 1), null);
    assert.equal((0, security_logic_1.severityFor)(s, s.warnAt), 'warn');
    assert.equal((0, security_logic_1.severityFor)(s, s.criticalAt - 1), 'warn');
    assert.equal((0, security_logic_1.severityFor)(s, s.criticalAt), 'critical');
});
(0, node_test_1.test)('comment flood per user: inside the window escalates, spread out does not', () => {
    const s = spec('comment_flood_user');
    assert.equal((0, security_logic_1.severityFor)(s, feed('comment_flood_user', s.warnAt, 1000)), 'warn'); // 25 in 25 s
    assert.equal((0, security_logic_1.severityFor)(s, feed('comment_flood_user', s.criticalAt, 500)), 'critical'); // 60 in 30 s
    // One every 3 s: only ~20 are ever inside 60 s.
    assert.equal((0, security_logic_1.severityFor)(s, feed('comment_flood_user', 300, 3000)), null);
});
(0, node_test_1.test)('sliding log drops expired hits and is capped', () => {
    let log = [];
    for (let i = 0; i < 10; i++)
        log = (0, security_logic_1.slideLog)(log, { t: i * 1000 }, 3000, 100);
    assert.deepEqual(log.map((h) => h.t), [7000, 8000, 9000]);
    for (let i = 0; i < 50; i++)
        log = (0, security_logic_1.slideLog)(log, { t: 10000 + i }, 60000, 5);
    assert.equal(log.length, 5);
    assert.equal((0, security_logic_1.slideLog)(undefined, { t: 1 }, 10, 3).length, 1);
    // garbage from the doc is ignored
    assert.equal((0, security_logic_1.slideLog)([{ t: 'x' }, { t: 5 }], { t: 6 }, 10, 5).length, 2);
});
(0, node_test_1.test)('distinct counting: duplicate identity and token sweeps', () => {
    const dup = spec('duplicate_identity_user');
    assert.equal((0, security_logic_1.severityFor)(dup, feed('duplicate_identity_user', 10, 1000, () => 'same')), null);
    assert.equal((0, security_logic_1.severityFor)(dup, feed('duplicate_identity_user', 2, 1000, (i) => `fp${i}`)), 'warn');
    assert.equal((0, security_logic_1.severityFor)(dup, feed('duplicate_identity_user', 4, 1000, (i) => `fp${i}`)), 'critical');
    const sweep = spec('token_sweep_user');
    assert.equal((0, security_logic_1.severityFor)(sweep, feed('token_sweep_user', 40, 1000, () => 'one-stream')), null);
    assert.equal((0, security_logic_1.severityFor)(sweep, feed('token_sweep_user', 25, 1000, (i) => `s${i}`)), 'critical');
    // 25 streams but spread over > 5 min: not a sweep
    assert.equal((0, security_logic_1.severityFor)(sweep, feed('token_sweep_user', 25, 60000, (i) => `s${i}`)), null);
});
(0, node_test_1.test)('detector routing by signal and detail', () => {
    const ids = (k, d = {}) => (0, security_logic_1.detectorsFor)(k, d).map((x) => x.id).sort();
    assert.deepEqual(ids('comment'), ['comment_flood_stream', 'comment_flood_user']);
    assert.deepEqual(ids('join_request'), ['join_request_flood_stream', 'join_request_flood_user']);
    assert.deepEqual(ids('exhausted', { bucket: 'react' }), ['error_storm_user', 'reaction_flood_user']);
    assert.deepEqual(ids('exhausted', { bucket: 'cmt_min' }), ['error_storm_user']);
    assert.deepEqual(ids('denied'), ['error_storm_user']);
    assert.deepEqual(ids('blocked_token'), ['blocked_retry_user']);
    assert.deepEqual(ids('token', { newAccount: false }), ['token_sweep_user']);
    assert.deepEqual(ids('token', { newAccount: true, fingerprint: 'f' }), ['duplicate_identity_user', 'raid_stream', 'token_sweep_user']);
});
(0, node_test_1.test)('reaction flood beyond the rate limit and blocked retries', () => {
    const r = spec('reaction_flood_user');
    assert.equal((0, security_logic_1.severityFor)(r, feed('reaction_flood_user', 20, 200)), 'warn');
    assert.equal((0, security_logic_1.severityFor)(r, feed('reaction_flood_user', 60, 100)), 'critical');
    const b = spec('blocked_retry_user');
    assert.equal((0, security_logic_1.severityFor)(b, feed('blocked_retry_user', 3, 60000)), 'warn');
    assert.equal((0, security_logic_1.severityFor)(b, feed('blocked_retry_user', 10, 30000)), 'critical');
});
(0, node_test_1.test)('stream buckets: raid over sharded counters', () => {
    const now = 1000000123;
    const raid = spec('raid_stream');
    const buckets = (0, security_logic_1.bucketsFor)(now, raid.windowMs);
    assert.equal(buckets.length, 13); // 60 s / 5 s, unaligned → one partial bucket more
    assert.ok(buckets[buckets.length - 1] <= now);
    const rows = buckets.flatMap((b) => [0, 1, 2, 3].map(() => ({ bucket: b, count: 3 }))); // 13×4×3 = 156
    rows.push({ bucket: buckets[0] - 5000, count: 999 }); // outside the window
    const n = (0, security_logic_1.sumBuckets)(rows, now, raid.windowMs);
    assert.equal(n, 156);
    assert.equal((0, security_logic_1.severityFor)(raid, n), 'critical');
    assert.equal((0, security_logic_1.severityFor)(raid, (0, security_logic_1.sumBuckets)(rows.slice(0, 10), now, raid.windowMs)), 'warn');
});
(0, node_test_1.test)('incident ids dedupe within the cooldown slot and allow escalation', () => {
    const t = 10 * security_logic_1.INCIDENT_COOLDOWN_MS.warn;
    const a = (0, security_logic_1.incidentId)('comment_flood_user', 'u/1', 'warn', t);
    assert.equal(a, (0, security_logic_1.incidentId)('comment_flood_user', 'u/1', 'warn', t + 1000));
    assert.notEqual(a, (0, security_logic_1.incidentId)('comment_flood_user', 'u/1', 'warn', t + security_logic_1.INCIDENT_COOLDOWN_MS.warn));
    assert.notEqual(a, (0, security_logic_1.incidentId)('comment_flood_user', 'u/1', 'critical', t));
    assert.ok(!a.includes('/'));
});
(0, node_test_1.test)('buildIncident: below threshold null; stream scope has no uid', () => {
    assert.equal((0, security_logic_1.buildIncident)({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 3, now: 1 }), null);
    const i = (0, security_logic_1.buildIncident)({ spec: spec('raid_stream'), streamId: 's', uid: 'u', count: 150, now: 5 });
    assert.equal(i.uid, null);
    assert.equal(i.severity, 'critical');
    assert.equal(i.threshold, spec('raid_stream').criticalAt);
    const u = (0, security_logic_1.buildIncident)({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 30, now: 5 });
    assert.equal(u.uid, 'u');
    assert.equal(u.severity, 'warn');
});
(0, node_test_1.test)('failures map to signals', () => {
    assert.deepEqual((0, security_logic_1.signalForFailure)('resource-exhausted', 'react'), { kind: 'exhausted', detail: { bucket: 'react' } });
    assert.deepEqual((0, security_logic_1.signalForFailure)('permission-denied'), { kind: 'denied', detail: { bucket: '' } });
    assert.equal((0, security_logic_1.signalForFailure)('not-found'), null);
});
(0, node_test_1.test)('only critical per-account incidents go to the guard', () => {
    const crit = (0, security_logic_1.buildIncident)({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 99, now: 1 });
    assert.equal((0, security_logic_1.guardMapping)(crit).type, 'message_spike');
    const dup = (0, security_logic_1.buildIncident)({ spec: spec('duplicate_identity_user'), streamId: 's', uid: 'u', count: 5, now: 1 });
    assert.equal((0, security_logic_1.guardMapping)(dup).type, 'session_reuse');
    assert.ok(String((0, security_logic_1.guardMapping)(dup).details.why).length > 0);
    const warn = (0, security_logic_1.buildIncident)({ spec: spec('comment_flood_user'), streamId: 's', uid: 'u', count: 30, now: 1 });
    assert.equal((0, security_logic_1.guardMapping)(warn), null);
    const raid = (0, security_logic_1.buildIncident)({ spec: spec('raid_stream'), streamId: 's', uid: null, count: 500, now: 1 });
    assert.equal((0, security_logic_1.guardMapping)(raid), null);
});
// ─── Monitor ────────────────────────────────────────────────────────────────
const inc = (id, uid, count, atMs) => (0, security_logic_1.buildIncident)({ spec: spec(id), streamId: 's1', uid, count, now: atMs });
(0, node_test_1.test)('monitor throttle: once per 60 s', () => {
    assert.equal((0, security_logic_1.monitorShouldRun)(undefined, 1), true);
    assert.equal((0, security_logic_1.monitorShouldRun)(1000, 50000), false);
    assert.equal((0, security_logic_1.monitorShouldRun)(1000, 61000), true);
});
(0, node_test_1.test)('summary is PII-minimal: aliases, no uids, sanitized short samples', () => {
    const now = 10000000;
    const { summary, aliases } = (0, security_logic_1.buildHealthSummary)({
        incidents: [inc('comment_flood_user', 'uid_secret_1', 70, now - 1000), inc('raid_stream', null, 40, now - 2000),
            inc('comment_flood_user', 'old', 70, now - 20 * 60000)],
        metrics: { viewers: 120.4, participants: 3, chatPerMin: 88 },
        now,
        people: { uid_secret_1: { onStage: false, role: 'viewer' } },
        samples: { uid_secret_1: ['Visit https://spam.example now!!! mail me a@b.co @bob +1 555 123 4567 ' + 'x'.repeat(200), 'two', 'three', 'four'] },
    });
    const json = JSON.stringify(summary);
    assert.ok(!json.includes('uid_secret_1'));
    assert.ok(!json.includes('spam.example'));
    assert.ok(!json.includes('a@b.co'));
    assert.ok(!json.includes('@bob'));
    assert.ok(!json.includes('555'));
    assert.equal(summary.incidents.length, 2); // the 20-min-old one is dropped
    assert.equal(aliases.a1, 'uid_secret_1');
    assert.ok(summary.samples.length <= 3);
    for (const s of summary.samples)
        assert.ok(s.text.length <= security_logic_1.SAMPLE_MAX_CHARS);
    assert.equal(summary.metrics.viewers, 120);
    assert.deepEqual(summary.allowedActions, security_logic_1.ACTION_ALLOW_LIST);
    assert.equal((0, security_logic_1.sanitizeSample)(42), '');
    assert.equal((0, security_logic_1.sanitizeSample)('a\u0000b\nc'), 'a b c');
});
function ctx() {
    const now = 10000000;
    return (0, security_logic_1.buildHealthSummary)({
        incidents: [inc('comment_flood_user', 'u1', 30, now), inc('duplicate_identity_user', 'u2', 2, now)],
        metrics: { viewers: 10, participants: 2, chatPerMin: 5 },
        now,
        people: { u1: { onStage: false, role: 'viewer' }, u2: { onStage: true, role: 'guest' } },
    });
}
(0, node_test_1.test)('model output: valid answer maps aliases back to uids', () => {
    const c = ctx();
    const r = (0, security_logic_1.validateModelOutput)('```json\n{"assessment":"Spam from one viewer.","actions":[{"type":"mute_user","account":"a1"},{"type":"remove_from_stage","account":"a2"},{"type":"slow_mode"}]}\n```', c);
    assert.equal(r.assessment, 'Spam from one viewer.');
    assert.deepEqual(r.actions, [
        { type: 'mute_user', targetUid: 'u1' },
        { type: 'remove_from_stage', targetUid: 'u2' },
        { type: 'slow_mode' },
    ]);
});
(0, node_test_1.test)('model output: strict validation drops anything off-list', () => {
    const c = ctx();
    const r = (0, security_logic_1.validateModelOutput)({
        assessment: 'x'.repeat(1000),
        actions: [
            { type: 'delete_account', account: 'a1' }, // not allow-listed
            { type: 'block_user', account: 'a9' }, // unknown alias
            { type: 'block_user', account: 'u1' }, // raw uid is not an alias
            { type: 'remove_from_stage', account: 'a1' }, // a1 is not on stage
            { type: 'slow_mode', account: 'a1' }, // stream action with an account
            { type: 'end_live' }, // no critical incident
            { type: 'mute_user', account: 'a1' },
            { type: 'mute_user', account: 'a1' }, // duplicate
            { type: 'followers_only' },
            { type: 'pause_join_requests' },
            { type: 'slow_mode' }, // over 3
        ],
    }, c);
    assert.ok(r.assessment.length <= 280);
    assert.deepEqual(r.actions.map((a) => a.type), ['mute_user', 'followers_only', 'pause_join_requests']);
});
(0, node_test_1.test)('model output: unusable answers return null (→ fallback)', () => {
    const c = ctx();
    assert.equal((0, security_logic_1.validateModelOutput)('not json', c), null);
    assert.equal((0, security_logic_1.validateModelOutput)('[]', c), null);
    assert.equal((0, security_logic_1.validateModelOutput)({ assessment: '', actions: [{ type: 'slow_mode' }] }, c), null);
    assert.equal((0, security_logic_1.validateModelOutput)({ assessment: 'ok', actions: [] }, c), null);
    assert.equal((0, security_logic_1.validateModelOutput)({ assessment: 'ok', actions: [{ type: 'ban_everyone' }] }, c), null);
    assert.equal((0, security_logic_1.validateModelOutput)(null, c), null);
});
(0, node_test_1.test)('end_live allowed only with a critical incident', () => {
    const now = 1000;
    const c = (0, security_logic_1.buildHealthSummary)({ incidents: [inc('raid_stream', null, 500, now)], metrics: { viewers: 1, participants: 1, chatPerMin: 0 }, now });
    assert.deepEqual((0, security_logic_1.validateModelOutput)({ assessment: 'Raid.', actions: [{ type: 'end_live' }] }, c).actions, [{ type: 'end_live' }]);
});
(0, node_test_1.test)('fallback rules pick allow-listed actions', () => {
    const now = 5000;
    const raid = (0, security_logic_1.fallbackAdvice)([inc('raid_stream', null, 40, now)]);
    assert.deepEqual(raid.actions.map((a) => a.type), ['followers_only', 'pause_join_requests']);
    const spam = (0, security_logic_1.fallbackAdvice)([inc('comment_flood_user', 'u1', 99, now), inc('comment_flood_stream', null, 500, now - 1)]);
    assert.deepEqual(spam.actions[0], { type: 'block_user', targetUid: 'u1' });
    assert.ok(spam.actions.some((a) => a.type === 'slow_mode'));
    const dupStage = (0, security_logic_1.fallbackAdvice)([inc('duplicate_identity_user', 'u2', 2, now)], { u2: { onStage: true } });
    assert.deepEqual(dupStage.actions, [{ type: 'remove_from_stage', targetUid: 'u2' }]);
    for (const a of [...raid.actions, ...spam.actions])
        assert.ok(security_logic_1.ACTION_ALLOW_LIST.includes(a.type));
    assert.ok(spam.actions.length <= 3);
    assert.ok(spam.assessment.length > 0);
    assert.equal((0, security_logic_1.fallbackAdvice)([]).actions.length, 0);
});
(0, node_test_1.test)('advisory severity is the worst incident', () => {
    const now = 7;
    const a = (0, security_logic_1.buildAdvisory)({
        streamId: 's1', now, source: 'rules', assessment: 'x', actions: [],
        incidents: [inc('comment_flood_user', 'u', 30, now), inc('raid_stream', null, 500, now)],
    });
    assert.equal(a.severity, 'critical');
    assert.equal(a.id, 'adv_7');
    assert.equal(a.incidentIds.length, 2);
});
// ─── E2EE keys ──────────────────────────────────────────────────────────────
let counter = 0;
const rnd = (n) => new Uint8Array(n).fill(++counter);
(0, node_test_1.test)('env switch defaults to on', () => {
    assert.equal((0, security_logic_1.e2eeEnabled)(undefined), true);
    assert.equal((0, security_logic_1.e2eeEnabled)('true'), true);
    assert.equal((0, security_logic_1.e2eeEnabled)(''), true);
    for (const off of ['false', 'FALSE', '0', 'off', 'no'])
        assert.equal((0, security_logic_1.e2eeEnabled)(off), false, off);
});
(0, node_test_1.test)('new key: 32 random bytes, index 0', () => {
    const k = (0, security_logic_1.newMediaKey)(rnd, 100);
    assert.equal(Buffer.from(k.key, 'base64').length, security_logic_1.MEDIA_KEY_BYTES);
    assert.equal(k.keyIndex, 0);
    assert.ok((0, security_logic_1.isValidKeyDoc)(k));
    assert.deepEqual((0, security_logic_1.keyPayload)(k), { key: k.key, keyIndex: 0 });
    assert.throws(() => (0, security_logic_1.newMediaKey)(() => new Uint8Array(16), 1));
});
(0, node_test_1.test)('rotation: new bytes, next index, wraps around the ring', () => {
    const a = (0, security_logic_1.newMediaKey)(rnd, 1);
    const b = (0, security_logic_1.rotateMediaKey)(a, rnd, 2, 'blocked');
    assert.notEqual(a.key, b.key);
    assert.equal(b.keyIndex, 1);
    assert.equal(b.reason, 'blocked');
    let k = a;
    for (let i = 0; i < security_logic_1.KEY_RING_SIZE; i++)
        k = (0, security_logic_1.rotateMediaKey)(k, rnd, 3, 'x');
    assert.equal(k.keyIndex, 0);
    assert.equal((0, security_logic_1.rotateMediaKey)(null, rnd, 1, 'x').keyIndex, 0);
    assert.equal((0, security_logic_1.isValidKeyDoc)({ key: 'AAAA', keyIndex: 0 }), false);
    assert.equal((0, security_logic_1.isValidKeyDoc)(Object.assign(Object.assign({}, a), { keyIndex: security_logic_1.KEY_RING_SIZE })), false);
});
(0, node_test_1.test)('rotation triggers: losing publish rights only', () => {
    assert.equal((0, security_logic_1.memberChangeNeedsRotation)({ role: 'guest' }, { role: 'viewer' }), true);
    assert.equal((0, security_logic_1.memberChangeNeedsRotation)({ role: 'coHost' }, undefined), true);
    assert.equal((0, security_logic_1.memberChangeNeedsRotation)({ role: 'coHost' }, { role: 'guest' }), false);
    assert.equal((0, security_logic_1.memberChangeNeedsRotation)({ role: 'viewer' }, { role: 'guest' }), false);
    assert.equal((0, security_logic_1.memberChangeNeedsRotation)(undefined, { role: 'guest' }), false);
    assert.equal((0, security_logic_1.memberChangeNeedsRotation)({ role: 'guest' }, { role: 'guest', micOn: false }), false);
});
(0, node_test_1.test)('key.update event never carries the key', () => {
    const e = (0, security_logic_1.keyUpdateEvent)(3, 9);
    assert.deepEqual(e, { v: 1, type: 'key.update', keyIndex: 3, ts: 9 });
    assert.ok(!('key' in e));
});
//# sourceMappingURL=security_logic.test.js.map