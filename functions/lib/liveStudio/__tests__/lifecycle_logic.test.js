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
const lifecycle_logic_1 = require("../lifecycle_logic");
const now = 10000000000;
const live = (o) => (Object.assign({ status: 'live', createdMs: now - 60 * 60 * 1000, heartbeatMs: null, hostLeftMs: null }, o));
(0, node_test_1.test)('ended lives are never swept', () => {
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ status: 'ended', heartbeatMs: 0 }), now), null);
});
(0, node_test_1.test)('fresh heartbeat keeps the live open', () => {
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ heartbeatMs: now - 10000 }), now), null);
});
(0, node_test_1.test)('stale heartbeat ends the live', () => {
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ heartbeatMs: now - lifecycle_logic_1.HEARTBEAT_STALE_MS }), now), 'timeout');
});
(0, node_test_1.test)('host left the room past the grace', () => {
    const left = now - lifecycle_logic_1.HOST_LEFT_GRACE_MS;
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ heartbeatMs: left - 5000, hostLeftMs: left }), now), 'host_left');
    // Back within the grace or heartbeating again afterwards: keep it.
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ heartbeatMs: now - 5000, hostLeftMs: now - 30000 }), now), null);
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ heartbeatMs: now - 1000, hostLeftMs: left }), now), null);
});
(0, node_test_1.test)('lives from builds without heartbeat get a long timeout only', () => {
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ createdMs: now - 60000 }), now), null);
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ createdMs: now - lifecycle_logic_1.NO_HEARTBEAT_MAX_MS }), now), 'timeout');
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ createdMs: now - lifecycle_logic_1.FIRST_HEARTBEAT_GRACE_MS - lifecycle_logic_1.HOST_LEFT_GRACE_MS, hostLeftMs: now - lifecycle_logic_1.HOST_LEFT_GRACE_MS }), now), 'host_left');
    assert.equal((0, lifecycle_logic_1.orphanReason)(live({ createdMs: now - 30000, hostLeftMs: now - lifecycle_logic_1.HOST_LEFT_GRACE_MS }), now), null);
});
(0, node_test_1.test)('start extras are optional and sanitized', () => {
    assert.deepEqual((0, lifecycle_logic_1.parseStartExtras)(undefined), {
        category: null,
        coverUrl: null,
        audienceMode: 'public',
        allowGuestRequests: true,
    });
    assert.deepEqual((0, lifecycle_logic_1.parseStartExtras)({ category: ' Music ', coverUrl: 'https://x/y.jpg', audienceMode: 'followers', allowGuestRequests: false }), { category: 'Music', coverUrl: 'https://x/y.jpg', audienceMode: 'followers', allowGuestRequests: false });
    const bad = (0, lifecycle_logic_1.parseStartExtras)({ category: 'a\nb', coverUrl: 'http://x', audienceMode: 'vip', allowGuestRequests: 'no' });
    assert.equal(bad.category, null);
    assert.equal(bad.coverUrl, null);
    assert.equal(bad.audienceMode, 'public');
    assert.equal(bad.allowGuestRequests, true);
});
(0, node_test_1.test)('toMs reads numbers, dates and timestamps', () => {
    assert.equal((0, lifecycle_logic_1.toMs)(5), 5);
    assert.equal((0, lifecycle_logic_1.toMs)(new Date(7)), 7);
    assert.equal((0, lifecycle_logic_1.toMs)({ toMillis: () => 9 }), 9);
    assert.equal((0, lifecycle_logic_1.toMs)('x'), null);
});
//# sourceMappingURL=lifecycle_logic.test.js.map