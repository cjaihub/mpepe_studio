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
const contracts_1 = require("../contracts");
const social_logic_1 = require("../social_logic");
(0, node_test_1.describe)('comment normalization', () => {
    (0, node_test_1.test)('trims and collapses whitespace', () => {
        assert.deepEqual((0, social_logic_1.normalizeCommentText)('  hello \n\n  world\t! '), { ok: true, text: 'hello world !' });
    });
    (0, node_test_1.test)('strips zero-width and control chars', () => {
        assert.deepEqual((0, social_logic_1.normalizeCommentText)('hi​\u0007 there'), { ok: true, text: 'hi there' });
    });
    (0, node_test_1.test)('rejects empty, whitespace-only and non-strings', () => {
        assert.equal((0, social_logic_1.normalizeCommentText)('   \n ').ok, false);
        assert.equal((0, social_logic_1.normalizeCommentText)(42).ok, false);
        assert.equal((0, social_logic_1.normalizeCommentText)(undefined).ok, false);
    });
    (0, node_test_1.test)('enforces the length cap after collapsing', () => {
        assert.equal((0, social_logic_1.normalizeCommentText)('a'.repeat(contracts_1.Limits.commentMaxLength)).ok, true);
        assert.equal((0, social_logic_1.normalizeCommentText)('a'.repeat(contracts_1.Limits.commentMaxLength + 1)).ok, false);
        // 300 raw chars that collapse to ≤ 200 are fine.
        assert.equal((0, social_logic_1.normalizeCommentText)('a' + ' '.repeat(298) + 'b').ok, true);
    });
    (0, node_test_1.test)('counts emoji as one character each', () => {
        assert.equal((0, social_logic_1.normalizeCommentText)('😀'.repeat(contracts_1.Limits.commentMaxLength)).ok, true);
    });
    (0, node_test_1.test)('clientId validation and deterministic ids', () => {
        assert.equal((0, social_logic_1.isValidClientId)('abcDEF12'), true);
        assert.equal((0, social_logic_1.isValidClientId)('short'), false);
        assert.equal((0, social_logic_1.isValidClientId)('has/slash12'), false);
        assert.equal((0, social_logic_1.commentDocId)('u1', 'abcDEF12'), 'u1_abcDEF12');
    });
});
(0, node_test_1.describe)('moderation hook', () => {
    (0, node_test_1.test)('block list rejects whole phrases, case/leet-insensitive', async () => {
        const m = (0, social_logic_1.blockListModerator)({ blocked: ['bad phrase', 'spam'] });
        assert.equal((await m('this is a BAD   phrase ok', 'u')).allow, false);
        assert.equal((await m('5p4m', 'u')).allow, false);
        assert.equal((await m('spammer', 'u')).allow, true, 'no partial-word match');
        assert.equal((await m('all good', 'u')).allow, true);
    });
    (0, node_test_1.test)('masked terms are replaced, comment allowed', async () => {
        const m = (0, social_logic_1.blockListModerator)({ blocked: [], masked: ['darn'] });
        const v = await m('oh Darn it', 'u');
        assert.equal(v.allow, true);
        assert.equal(v.text, 'oh •••• it');
    });
    (0, node_test_1.test)('fold strips diacritics', () => {
        assert.equal((0, social_logic_1.foldForMatching)('Ñoño Spä'), 'nono spa');
    });
    (0, node_test_1.test)('compose: first rejection wins, masks accumulate', async () => {
        const mask = (0, social_logic_1.blockListModerator)({ blocked: [], masked: ['x'] });
        const reject = async (t) => ({ allow: !t.includes('no'), reason: 'nope', text: t });
        const c = (0, social_logic_1.composeModerators)(mask, reject);
        assert.deepEqual(await c('a x b', 'u'), { allow: true, text: 'a • b' });
        assert.equal((await c('no x', 'u')).allow, false);
    });
    (0, node_test_1.test)('setCommentModerator replaces the active hook', async () => {
        (0, social_logic_1.setCommentModerator)((t) => ({ allow: t !== 'blocked', text: t.toUpperCase() }));
        assert.deepEqual(await (0, social_logic_1.moderateComment)('hi', 'u'), { allow: true, text: 'HI' });
        assert.equal((await (0, social_logic_1.moderateComment)('blocked', 'u')).allow, false);
        (0, social_logic_1.setCommentModerator)((0, social_logic_1.blockListModerator)());
        assert.equal((await (0, social_logic_1.moderateComment)('kys', 'u')).allow, false, 'default list is active again');
    });
});
(0, node_test_1.describe)('mute and permissions', () => {
    (0, node_test_1.test)('mute minutes parsing', () => {
        assert.equal((0, social_logic_1.parseMuteMinutes)(5), 5);
        assert.equal((0, social_logic_1.parseMuteMinutes)(0), 0);
        assert.equal((0, social_logic_1.parseMuteMinutes)(2.9), 2);
        assert.equal((0, social_logic_1.parseMuteMinutes)(-1), null);
        assert.equal((0, social_logic_1.parseMuteMinutes)(1441), null);
        assert.equal((0, social_logic_1.parseMuteMinutes)('5'), null);
    });
    (0, node_test_1.test)('mute expiry', () => {
        const until = (0, social_logic_1.muteUntil)(1000, 2);
        assert.equal(until, 121000);
        assert.equal((0, social_logic_1.isChatMuted)(false, until, 120999), true);
        assert.equal((0, social_logic_1.isChatMuted)(false, until, 121000), false);
        assert.equal((0, social_logic_1.isChatMuted)(true, undefined, 0), true);
        assert.equal((0, social_logic_1.isChatMuted)(undefined, undefined, 0), false);
    });
    (0, node_test_1.test)('delete: author or manager', () => {
        assert.equal((0, social_logic_1.canDeleteComment)('viewer', 'a', 'a'), true);
        assert.equal((0, social_logic_1.canDeleteComment)('viewer', 'a', 'b'), false);
        assert.equal((0, social_logic_1.canDeleteComment)('guest', 'a', 'b'), false);
        assert.equal((0, social_logic_1.canDeleteComment)('coHost', 'a', 'b'), true);
        assert.equal((0, social_logic_1.canDeleteComment)('host', 'a', 'b'), true);
        assert.equal((0, social_logic_1.canDeleteComment)('viewer', '', ''), false);
    });
    (0, node_test_1.test)('mute chat: managers only, co-host cannot mute host, no self-mute', () => {
        assert.equal((0, social_logic_1.canMuteChat)('host', 'h', 'viewer', 'v'), true);
        assert.equal((0, social_logic_1.canMuteChat)('coHost', 'c', 'viewer', 'v'), true);
        assert.equal((0, social_logic_1.canMuteChat)('coHost', 'c', 'coHost', 'c2'), true);
        assert.equal((0, social_logic_1.canMuteChat)('coHost', 'c', 'host', 'h'), false);
        assert.equal((0, social_logic_1.canMuteChat)('guest', 'g', 'viewer', 'v'), false);
        assert.equal((0, social_logic_1.canMuteChat)('viewer', 'v', 'viewer', 'v2'), false);
        assert.equal((0, social_logic_1.canMuteChat)('host', 'h', 'host', 'h'), false);
    });
});
(0, node_test_1.describe)('comment broadcast sampler', () => {
    (0, node_test_1.test)('second window counter resets each second, per key', () => {
        const c = new social_logic_1.SecondWindowCounter();
        assert.equal(c.hit('s', 1000), 1);
        assert.equal(c.hit('s', 1500), 2);
        assert.equal(c.hit('t', 1500), 1);
        assert.equal(c.count('s', 1999), 2);
        assert.equal(c.hit('s', 2000), 1);
        assert.equal(c.count('s', 3000), 0);
    });
    (0, node_test_1.test)('counter prunes when too many keys', () => {
        const c = new social_logic_1.SecondWindowCounter(3);
        c.hit('a', 0);
        c.hit('b', 0);
        c.hit('c', 0);
        c.hit('d', 1000);
        assert.equal(c.count('a', 1000), 0);
        assert.equal(c.count('d', 1000), 1);
    });
    (0, node_test_1.test)('gateStep enforces the per-second budget and resets', () => {
        let doc;
        let allowed = 0;
        for (let i = 0; i < 20; i++) {
            const s = (0, social_logic_1.gateStep)(doc, 5000 + i * 10, 5);
            if (s.next)
                doc = s.next;
            if (s.allow)
                allowed++;
        }
        assert.equal(allowed, 5);
        assert.equal((0, social_logic_1.gateStep)(doc, 6000, 5).allow, true, 'next second resets');
    });
    (0, node_test_1.test)('shard budgets cover the global budget', () => {
        assert.ok((0, social_logic_1.shardBudget)() * social_logic_1.COMMENT_GATE_SHARDS >= contracts_1.Limits.commentBroadcastPerSecond);
        assert.equal((0, social_logic_1.shardBudget)(25, 5), 5);
        assert.equal((0, social_logic_1.shardBudget)(1, 5), 1);
    });
    (0, node_test_1.test)('managers always broadcast; others need local and global budget', () => {
        assert.equal((0, social_logic_1.shouldBroadcastComment)({ role: 'host', localCountThisSecond: 999, globalAllow: false }), true);
        assert.equal((0, social_logic_1.shouldBroadcastComment)({ role: 'coHost', localCountThisSecond: 999, globalAllow: null }), true);
        assert.equal((0, social_logic_1.shouldBroadcastComment)({ role: 'viewer', localCountThisSecond: 1, globalAllow: true }), true);
        assert.equal((0, social_logic_1.shouldBroadcastComment)({ role: 'viewer', localCountThisSecond: 1, globalAllow: false }), false);
        assert.equal((0, social_logic_1.shouldBroadcastComment)({ role: 'viewer', localCountThisSecond: 1, globalAllow: null }), false, 'fail closed');
        assert.equal((0, social_logic_1.shouldBroadcastComment)({ role: 'guest', localCountThisSecond: 26, globalAllow: true }), false);
    });
    (0, node_test_1.test)('a 1000-comment burst in one second broadcasts ≤ 25 viewer comments + all host ones', () => {
        const local = new social_logic_1.SecondWindowCounter();
        const docs = Array(social_logic_1.COMMENT_GATE_SHARDS).fill(undefined);
        let sent = 0;
        let hostSent = 0;
        for (let i = 0; i < 1000; i++) {
            const now = 10000 + i;
            const role = i % 100 === 0 ? 'host' : 'viewer';
            const n = local.hit('s', now);
            const k = (0, social_logic_1.pickShard)((i * 7919 % 1000) / 1000, social_logic_1.COMMENT_GATE_SHARDS);
            const step = (0, social_logic_1.gateStep)(docs[k], now, (0, social_logic_1.shardBudget)());
            if (role !== 'host' && step.next)
                docs[k] = step.next;
            const ok = (0, social_logic_1.shouldBroadcastComment)({ role, localCountThisSecond: n, globalAllow: role === 'host' ? null : step.allow });
            if (ok && role === 'host')
                hostSent++;
            else if (ok)
                sent++;
        }
        assert.ok(sent <= contracts_1.Limits.commentBroadcastPerSecond, `sent ${sent}`);
        assert.ok(sent > 0);
        assert.equal(hostSent, 10);
    });
});
(0, node_test_1.describe)('throttles and leases', () => {
    (0, node_test_1.test)('throttleDue', () => {
        assert.equal((0, social_logic_1.throttleDue)(undefined, 0, 1000), true);
        assert.equal((0, social_logic_1.throttleDue)(1000, 1999, 1000), false);
        assert.equal((0, social_logic_1.throttleDue)(1000, 2000, 1000), true);
        assert.equal((0, social_logic_1.throttleDue)(10000, 1000, 1000), true, 'clock went back by more than one interval');
        assert.equal((0, social_logic_1.throttleDue)(1500, 1000, 1000), false, 'small skew keeps the lease');
    });
    (0, node_test_1.test)('per-user 10 s system-line throttle', () => {
        let last;
        const emitted = [];
        for (let t = 0; t <= 30000; t += 700) {
            if ((0, social_logic_1.throttleDue)(last, t, 10000)) {
                last = t;
                emitted.push(t);
            }
        }
        assert.deepEqual(emitted, [0, 10500, 21000]);
    });
    (0, node_test_1.test)('lease memo', () => {
        const m = new social_logic_1.LeaseMemo();
        assert.equal(m.blocked('k', 0), false);
        m.hold('k', 500);
        assert.equal(m.blocked('k', 499), true);
        assert.equal(m.blocked('k', 500), false);
    });
});
(0, node_test_1.describe)('reactions', () => {
    (0, node_test_1.test)('parseReaction', () => {
        assert.deepEqual((0, social_logic_1.parseReaction)('love', 3), { ok: true, kind: 'love', n: 3 });
        assert.equal((0, social_logic_1.parseReaction)('sparkles', contracts_1.Limits.reactionMaxPerCall).ok, true);
        assert.equal((0, social_logic_1.parseReaction)('love', contracts_1.Limits.reactionMaxPerCall + 1).ok, false);
        assert.equal((0, social_logic_1.parseReaction)('love', 0).ok, false);
        assert.equal((0, social_logic_1.parseReaction)('love', 1.5).ok, false);
        assert.equal((0, social_logic_1.parseReaction)('fire', 1).ok, false);
        assert.equal((0, social_logic_1.reactionField)('love'), 'loves');
        assert.equal((0, social_logic_1.reactionField)('sparkles'), 'sparkles');
    });
    (0, node_test_1.test)('pickShard stays in range', () => {
        assert.equal((0, social_logic_1.pickShard)(0), 0);
        assert.equal((0, social_logic_1.pickShard)(0.999999), 9);
        assert.equal((0, social_logic_1.pickShard)(1), 9);
        assert.equal((0, social_logic_1.pickShard)(-1), 0);
    });
    (0, node_test_1.test)('sumShards ignores missing docs and bad fields', () => {
        assert.deepEqual((0, social_logic_1.sumShards)([{ loves: 2, sparkles: 1 }, undefined, { loves: 3, shares: 1, viewers: -1, x: 'y' }, { loves: 'NaN' }]), {
            loves: 5, sparkles: 1, shares: 1, viewers: -1,
        });
    });
    (0, node_test_1.test)('deltas are against the last flushed totals and never negative', () => {
        assert.deepEqual((0, social_logic_1.reactionDeltas)({ loves: 10, sparkles: 4 }, undefined), { loves: 10, sparkles: 4 });
        assert.deepEqual((0, social_logic_1.reactionDeltas)({ loves: 10, sparkles: 4 }, { loves: 7, sparkles: 4 }), { loves: 3, sparkles: 0 });
        assert.deepEqual((0, social_logic_1.reactionDeltas)({ loves: 5, sparkles: 0 }, { loves: 7 }), { loves: 0, sparkles: 0 });
    });
    (0, node_test_1.test)('late increments roll into the next window (never lost)', () => {
        let flushed;
        let shard = 0;
        const deltas = [];
        shard += 5; // window 1
        const d1 = (0, social_logic_1.reactionDeltas)({ loves: shard, sparkles: 0 }, flushed);
        flushed = { loves: shard, sparkles: 0 };
        deltas.push(d1.loves);
        shard += 2; // landed after flush 1 read
        shard += 1; // window 2
        deltas.push((0, social_logic_1.reactionDeltas)({ loves: shard, sparkles: 0 }, flushed).loves);
        assert.deepEqual(deltas, [5, 3]);
    });
    (0, node_test_1.test)('flush delay waits for the window end plus grace', () => {
        assert.equal((0, social_logic_1.flushDelayMs)(1000, 1000, 500), 500 + social_logic_1.FLUSH_GRACE_MS);
        assert.equal((0, social_logic_1.flushDelayMs)(1000, 1400, 500), 100 + social_logic_1.FLUSH_GRACE_MS);
        assert.equal((0, social_logic_1.flushDelayMs)(1000, 9999, 500), 0);
    });
    (0, node_test_1.test)('100k calls spread over 10 s produce ≤ 20 flushes (one per 500 ms window)', () => {
        const calls = Array.from({ length: 100000 }, (_, i) => Math.floor((i * 10000) / 100000));
        const flushes = (0, social_logic_1.simulateAggregation)(calls, contracts_1.Limits.reactionAggregateWindowMs);
        assert.equal(flushes.length, 20);
        for (let i = 1; i < flushes.length; i++)
            assert.ok(flushes[i] - flushes[i - 1] >= contracts_1.Limits.reactionAggregateWindowMs);
    });
    (0, node_test_1.test)('idle windows produce no flush', () => {
        assert.deepEqual((0, social_logic_1.simulateAggregation)([0, 100, 5000]), [500, 5500]);
        assert.deepEqual((0, social_logic_1.simulateAggregation)([]), []);
    });
});
(0, node_test_1.describe)('presence and counts', () => {
    (0, node_test_1.test)('room name → stream id', () => {
        assert.equal((0, social_logic_1.streamIdFromRoom)('studio_abc123'), 'abc123');
        assert.equal((0, social_logic_1.streamIdFromRoom)('call_abc'), null);
        assert.equal((0, social_logic_1.streamIdFromRoom)('studio_'), null);
        assert.equal((0, social_logic_1.streamIdFromRoom)('studio_a/b'), null);
        assert.equal((0, social_logic_1.streamIdFromRoom)(undefined), null);
    });
    (0, node_test_1.test)('viewers prefer the room count, fall back to the clamped counter', () => {
        assert.equal((0, social_logic_1.resolveViewers)(1200, 3), 1200);
        assert.equal((0, social_logic_1.resolveViewers)(0, 7), 7);
        assert.equal((0, social_logic_1.resolveViewers)(undefined, -4), 0);
    });
    (0, node_test_1.test)('participants = stage + co-hosts + pending (deduped)', () => {
        const stage = (0, social_logic_1.stagePublishers)({ centerUid: 'h', wall: ['a', null, 'b', null, null, null], overflow: ['c'] });
        assert.deepEqual(stage, ['h', 'a', 'b', 'c']);
        assert.equal((0, social_logic_1.computeParticipants)(stage, ['a', 'co'], 3), 5 + 3);
        assert.equal((0, social_logic_1.computeParticipants)([], [], 0), 0);
        assert.deepEqual((0, social_logic_1.stagePublishers)(undefined), []);
    });
    (0, node_test_1.test)('counts change detection', () => {
        assert.equal((0, social_logic_1.countsChanged)(undefined, { viewers: 1, participants: 1 }), true);
        assert.equal((0, social_logic_1.countsChanged)({ viewers: 1, participants: 1 }, { viewers: 1, participants: 1 }), false);
        assert.equal((0, social_logic_1.countsChanged)({ viewers: 1, participants: 1 }, { viewers: 2, participants: 1 }), true);
    });
    (0, node_test_1.test)('joined lines: always in small rooms, sampled ≤ 1/s in large rooms', () => {
        assert.equal((0, social_logic_1.joinLineMode)(10), 'always');
        assert.equal((0, social_logic_1.joinLineMode)(100), 'always');
        assert.equal((0, social_logic_1.joinLineMode)(101), 'sampled');
        let last;
        let lines = 0;
        for (let t = 0; t < 5000; t += 5) {
            if ((0, social_logic_1.joinLineMode)(200000) === 'always' || (0, social_logic_1.throttleDue)(last, t, 1000)) {
                last = t;
                lines++;
            }
        }
        assert.equal(lines, 5);
    });
    (0, node_test_1.test)('counts broadcast at most every countsIntervalMs', () => {
        let last;
        let sent = 0;
        for (let t = 0; t < 10000; t += 50) {
            if ((0, social_logic_1.throttleDue)(last, t, contracts_1.Limits.countsIntervalMs)) {
                last = t;
                sent++;
            }
        }
        assert.equal(sent, 5);
    });
});
(0, node_test_1.describe)('misc', () => {
    (0, node_test_1.test)('system line ids are prefixed and unique-ish', () => {
        const a = (0, social_logic_1.systemLineId)(1000, 0.1);
        const b = (0, social_logic_1.systemLineId)(1000, 0.2);
        assert.match(a, /^sys_/);
        assert.notEqual(a, b);
    });
    (0, node_test_1.test)('profile name/avatar resolution', () => {
        assert.equal((0, social_logic_1.displayNameOf)({ displayName: '  Ada ' }), 'Ada');
        assert.equal((0, social_logic_1.displayNameOf)({ fullName: 'Grace', displayName: 'x' }), 'Grace');
        assert.equal((0, social_logic_1.displayNameOf)(undefined), 'Someone');
        assert.equal((0, social_logic_1.avatarOf)({ photoUrl: 'p' }), 'p');
        assert.equal((0, social_logic_1.avatarOf)({}), '');
    });
});
//# sourceMappingURL=social_logic.test.js.map