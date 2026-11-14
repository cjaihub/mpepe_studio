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
exports.ENROLL_PROMPTS = exports.MAX_SPEAK_CHARS = exports.CONSENT_VERSION = exports.CLONE_LANGUAGES = void 0;
exports.baseLang = baseLang;
exports.engineFor = engineFor;
exports.validVoiceUrl = validVoiceUrl;
exports.signStreamToken = signStreamToken;
/**
 * Pure helpers for "My voice" (testable without Firebase).
 * Stream tokens must match services/voice/voice/logic.py byte for byte.
 */
const crypto = __importStar(require("crypto"));
/** Chatterbox speaks these directly in the person's voice; others are converted. */
exports.CLONE_LANGUAGES = new Set('ar da de el en es fi fr he hi it ja ko ms nl no pl pt ru sv sw tr zh'.split(' '));
exports.CONSENT_VERSION = 1;
exports.MAX_SPEAK_CHARS = 400;
function baseLang(code) {
    return String(code !== null && code !== void 0 ? code : '').trim().toLowerCase().split(/[-_]/)[0];
}
function engineFor(language) {
    return exports.CLONE_LANGUAGES.has(baseLang(language)) ? 'clone' : 'convert';
}
/** Only an https Cloud Run URL is ever called. */
function validVoiceUrl(v) {
    if (typeof v !== 'string')
        return null;
    try {
        const u = new URL(v.trim());
        return u.protocol === 'https:' && u.hostname.endsWith('.run.app') && !u.search && !u.hash ? u.origin : null;
    }
    catch (_a) {
        return null;
    }
}
const b64url = (b) => b.toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
/** {"call":…,"exp":…,"uid":…}.HMAC — same as Python's json.dumps(sort_keys=True, separators=(",", ":")). */
function signStreamToken(key, uid, callId, ttlS = 900, nowS = Math.floor(Date.now() / 1000)) {
    const body = JSON.stringify({ call: callId, exp: Math.floor(nowS + ttlS), uid });
    const sig = crypto.createHmac('sha256', key).update(body).digest();
    return `${b64url(Buffer.from(body))}.${b64url(sig)}`;
}
/** Practical phrases to read, about a minute in all (also shown in the app). */
exports.ENROLL_PROMPTS = [
    'Hi, it’s me. I’m on my way, I’ll call you when I get there.',
    'Can you send me the price and the delivery time, please?',
    'Thank you so much for watching, see you in the next video!',
    'That sounds great. Let’s meet tomorrow at ten in the morning.',
    'I’m a bit busy right now, can I call you back in five minutes?',
    'Welcome to my shop. This one is my favourite, let me show you.',
];
//# sourceMappingURL=voiceLogic.js.map