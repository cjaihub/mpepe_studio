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
const watch_logic_1 = require("../watch_logic");
const NOW = 1000000;
const VID = 'dQw4w9WgXcQ';
const isWatchError = (code) => (e) => e instanceof watch_logic_1.WatchError && e.code === code;
(0, node_test_1.test)('parseWatchOp: youtube needs an 11-char id and keeps only ytimg thumbs', () => {
    const op = (0, watch_logic_1.parseWatchOp)({ op: 'youtube', videoId: VID, title: ' Song ', thumbUrl: 'https://evil.example/x.jpg' });
    assert.deepEqual(op, { op: 'youtube', video: { videoId: VID, title: 'Song', channel: '', thumbUrl: '' } });
    const ok = (0, watch_logic_1.parseWatchOp)({ op: 'youtube', videoId: VID, thumbUrl: 'https://i.ytimg.com/vi/x/hq.jpg' });
    assert.equal(ok.op === 'youtube' && ok.video.thumbUrl, 'https://i.ytimg.com/vi/x/hq.jpg');
    assert.throws(() => (0, watch_logic_1.parseWatchOp)({ op: 'youtube', videoId: 'short' }), isWatchError('invalid-argument'));
    assert.throws(() => (0, watch_logic_1.parseWatchOp)({ op: 'youtube', videoId: 'aaaaaaaaaa/' }), isWatchError('invalid-argument'));
});
(0, node_test_1.test)('parseWatchOp: positions, rates and unknown ops', () => {
    assert.deepEqual((0, watch_logic_1.parseWatchOp)({ op: 'seek', positionMs: 1500.4 }), { op: 'seek', positionMs: 1500 });
    assert.throws(() => (0, watch_logic_1.parseWatchOp)({ op: 'play', positionMs: -1 }), isWatchError('invalid-argument'));
    assert.throws(() => (0, watch_logic_1.parseWatchOp)({ op: 'play' }), isWatchError('invalid-argument'));
    assert.deepEqual((0, watch_logic_1.parseWatchOp)({ op: 'rate', rate: 1.5 }), { op: 'rate', rate: 1.5 });
    assert.throws(() => (0, watch_logic_1.parseWatchOp)({ op: 'rate', rate: 3 }), isWatchError('invalid-argument'));
    assert.throws(() => (0, watch_logic_1.parseWatchOp)({ op: 'rip' }), isWatchError('invalid-argument'));
});
(0, node_test_1.test)('validateBrowserUrl: https public pages only, no look-alikes', () => {
    assert.equal((0, watch_logic_1.validateBrowserUrl)('https://en.wikipedia.org/wiki/Flutter'), 'https://en.wikipedia.org/wiki/Flutter');
    for (const bad of [
        'http://example.com',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'https://localhost/x',
        'https://192.168.1.1/',
        'https://user:pw@example.com/',
        'https://intranet/',
        'not a url',
        '',
    ]) {
        assert.throws(() => (0, watch_logic_1.validateBrowserUrl)(bad), (e) => e instanceof watch_logic_1.WatchError, bad);
    }
    assert.throws(() => (0, watch_logic_1.validateBrowserUrl)('https://faceb00k.com/'), isWatchError('failed-precondition'));
});
(0, node_test_1.test)('applyWatchOp: youtube starts playing at 0 and the target moves with the clock', () => {
    const w = (0, watch_logic_1.applyWatchOp)(watch_logic_1.EMPTY_WATCH, (0, watch_logic_1.parseWatchOp)({ op: 'youtube', videoId: VID }), 'host', NOW);
    assert.equal(w.kind, 'youtube');
    assert.equal(w.state, 'playing');
    assert.equal(w.rev, 1);
    assert.equal(w.by, 'host');
    assert.equal((0, watch_logic_1.targetPositionMs)(w, NOW + 4000), 4000);
});
(0, node_test_1.test)('applyWatchOp: pause freezes, play re-anchors, rate keeps the position', () => {
    let w = (0, watch_logic_1.applyWatchOp)(watch_logic_1.EMPTY_WATCH, (0, watch_logic_1.parseWatchOp)({ op: 'youtube', videoId: VID }), 'host', NOW);
    w = (0, watch_logic_1.applyWatchOp)(w, { op: 'pause', positionMs: 3000 }, 'host', NOW + 3000);
    assert.equal((0, watch_logic_1.targetPositionMs)(w, NOW + 99000), 3000);
    w = (0, watch_logic_1.applyWatchOp)(w, { op: 'play', positionMs: 3000 }, 'host', NOW + 10000);
    assert.equal((0, watch_logic_1.targetPositionMs)(w, NOW + 12000), 5000);
    w = (0, watch_logic_1.applyWatchOp)(w, { op: 'rate', rate: 2 }, 'host', NOW + 12000);
    assert.equal(w.positionMs, 5000);
    assert.equal((0, watch_logic_1.targetPositionMs)(w, NOW + 13000), 7000);
    w = (0, watch_logic_1.applyWatchOp)(w, { op: 'ended' }, 'host', NOW + 14000);
    assert.equal(w.state, 'ended');
    assert.equal((0, watch_logic_1.targetPositionMs)(w, NOW + 20000), 9000);
});
(0, node_test_1.test)('applyWatchOp: playback ops need a video; browser and stop replace the layer', () => {
    assert.throws(() => (0, watch_logic_1.applyWatchOp)(watch_logic_1.EMPTY_WATCH, { op: 'play', positionMs: 0 }, 'h', NOW), isWatchError('failed-precondition'));
    const b = (0, watch_logic_1.applyWatchOp)(watch_logic_1.EMPTY_WATCH, { op: 'browser', url: 'https://example.com/' }, 'h', NOW);
    assert.equal(b.kind, 'browser');
    assert.equal(b.youtube, null);
    const s = (0, watch_logic_1.applyWatchOp)(b, { op: 'stop' }, 'h', NOW + 1);
    assert.equal(s.kind, null);
    assert.equal(s.browser, null);
    assert.equal(s.rev, 2);
});
(0, node_test_1.test)('normalizeWatch: tolerates missing and malformed docs', () => {
    assert.deepEqual((0, watch_logic_1.normalizeWatch)(null), watch_logic_1.EMPTY_WATCH);
    const n = (0, watch_logic_1.normalizeWatch)({ kind: 'tv', youtube: { videoId: 'x' }, state: 'weird', rate: 'fast' });
    assert.equal(n.kind, null);
    assert.equal(n.youtube, null);
    assert.equal(n.state, 'paused');
    assert.equal(n.rate, 1);
});
(0, node_test_1.test)('fromYouTubeItem: maps search.list items, drops channels and playlists', () => {
    const hit = (0, watch_logic_1.fromYouTubeItem)({
        id: { kind: 'youtube#video', videoId: VID },
        snippet: {
            title: 'Rock &amp; Roll &#39;Live&#39;',
            channelTitle: 'Band',
            liveBroadcastContent: 'live',
            thumbnails: { high: { url: 'https://i.ytimg.com/vi/x/hqdefault.jpg' } },
        },
    });
    assert.deepEqual(hit, {
        videoId: VID,
        title: "Rock & Roll 'Live'",
        channel: 'Band',
        thumbUrl: 'https://i.ytimg.com/vi/x/hqdefault.jpg',
        live: true,
    });
    assert.equal((0, watch_logic_1.fromYouTubeItem)({ id: { kind: 'youtube#channel', channelId: 'UC1' } }), null);
    assert.equal((0, watch_logic_1.fromYouTubeItem)(null), null);
});
//# sourceMappingURL=watch_logic.test.js.map