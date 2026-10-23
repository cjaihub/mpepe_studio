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
const controls_logic_1 = require("../controls_logic");
(0, node_test_1.test)('parseChatMode validates and clamps', () => {
    assert.deepEqual((0, controls_logic_1.parseChatMode)({ mode: 'open' }), { ok: true, value: { mode: 'open', slowSeconds: 0 } });
    assert.deepEqual((0, controls_logic_1.parseChatMode)({ mode: 'slow' }), { ok: true, value: { mode: 'slow', slowSeconds: 15 } });
    assert.deepEqual((0, controls_logic_1.parseChatMode)({ mode: 'slow', slowSeconds: 1 }), { ok: true, value: { mode: 'slow', slowSeconds: controls_logic_1.SLOW_MIN_S } });
    assert.deepEqual((0, controls_logic_1.parseChatMode)({ mode: 'slow', slowSeconds: 9999 }), { ok: true, value: { mode: 'slow', slowSeconds: controls_logic_1.SLOW_MAX_S } });
    assert.equal((0, controls_logic_1.parseChatMode)({ mode: 'party' }).ok, false);
    assert.equal((0, controls_logic_1.parseChatMode)({ mode: 'slow', slowSeconds: 'x' }).ok, false);
});
(0, node_test_1.test)('readChatMode falls back to open on bad data', () => {
    assert.equal((0, controls_logic_1.readChatMode)(undefined).mode, 'open');
    assert.equal((0, controls_logic_1.readChatMode)({ mode: 'nope' }).mode, 'open');
    assert.equal((0, controls_logic_1.readChatMode)({ mode: 'followers' }).mode, 'followers');
});
(0, node_test_1.test)('managers are exempt; viewers and guests are limited', () => {
    const slow = { mode: 'slow', slowSeconds: 20 };
    const fol = { mode: 'followers', slowSeconds: 0 };
    assert.deepEqual((0, controls_logic_1.chatModeRequirement)(slow, 'host'), { kind: 'none' });
    assert.deepEqual((0, controls_logic_1.chatModeRequirement)(slow, 'coHost'), { kind: 'none' });
    assert.deepEqual((0, controls_logic_1.chatModeRequirement)(slow, 'viewer'), { kind: 'slow', seconds: 20 });
    assert.deepEqual((0, controls_logic_1.chatModeRequirement)(fol, 'guest'), { kind: 'follower' });
    assert.deepEqual((0, controls_logic_1.chatModeRequirement)({ mode: 'open', slowSeconds: 0 }, 'viewer'), { kind: 'none' });
});
(0, node_test_1.test)('follow doc id matches RelationshipRepository', () => {
    assert.equal((0, controls_logic_1.followDocId)('viewer1', 'host1'), 'viewer1_host1');
    assert.equal((0, controls_logic_1.isAcceptedFollow)('accepted'), true);
    assert.equal((0, controls_logic_1.isAcceptedFollow)('pending'), false);
});
//# sourceMappingURL=controls_logic.test.js.map