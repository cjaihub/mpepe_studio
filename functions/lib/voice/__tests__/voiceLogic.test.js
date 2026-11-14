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
const voiceLogic_1 = require("../voiceLogic");
(0, node_test_1.test)('stream tokens match the Python voice server byte for byte', () => {
    // Made by services/voice/voice/logic.py sign_stream_token(b"k"*32, "user_123456", "call1", ttl_s=60, now=1000)
    const python = 'eyJjYWxsIjoiY2FsbDEiLCJleHAiOjEwNjAsInVpZCI6InVzZXJfMTIzNDU2In0.Jms7REC0ywoNU3z1W5M8FxKudUGlAqMfY4nwwziwA_w';
    assert.equal((0, voiceLogic_1.signStreamToken)(Buffer.from('k'.repeat(32)), 'user_123456', 'call1', 60, 1000), python);
});
(0, node_test_1.test)('only https Cloud Run URLs are called', () => {
    assert.equal((0, voiceLogic_1.validVoiceUrl)('https://oneova-voice-abc-uc.a.run.app/'), 'https://oneova-voice-abc-uc.a.run.app');
    assert.equal((0, voiceLogic_1.validVoiceUrl)('http://oneova-voice-abc-uc.a.run.app'), null);
    assert.equal((0, voiceLogic_1.validVoiceUrl)('https://evil.example.com'), null);
    assert.equal((0, voiceLogic_1.validVoiceUrl)('https://x.run.app?y=1'), null);
});
(0, node_test_1.test)('languages route to cloning or conversion', () => {
    assert.equal((0, voiceLogic_1.engineFor)('sw-KE'), 'clone');
    assert.equal((0, voiceLogic_1.engineFor)('yo'), 'convert');
});
//# sourceMappingURL=voiceLogic.test.js.map