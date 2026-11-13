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
exports.escapeHtml = exports.validShareCode = exports.SHARE_TYPES = void 0;
exports.newShareCode = newShareCode;
exports.validShareTarget = validShareTarget;
exports.sharePlatform = sharePlatform;
exports.shareRoute = shareRoute;
/** Pure rules for tracked share links. Tested in __tests__/models3d.test.ts. */
const crypto = __importStar(require("crypto"));
exports.SHARE_TYPES = ['product', 'shop'];
const ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789';
function newShareCode() {
    let out = '';
    for (const b of crypto.randomBytes(10))
        out += ALPHABET[b % ALPHABET.length];
    return out;
}
const validShareCode = (code) => typeof code === 'string' && /^[a-z0-9]{10}$/.test(code);
exports.validShareCode = validShareCode;
function validShareTarget(type, id) {
    return exports.SHARE_TYPES.includes(type) && typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
}
function sharePlatform(userAgent) {
    const ua = userAgent.toLowerCase();
    if (/bot|crawler|spider|facebookexternalhit|whatsapp|telegram|slack|discord|preview|twitter/.test(ua))
        return 'bot';
    if (ua.includes('android'))
        return 'android';
    if (/iphone|ipad|ipod/.test(ua))
        return 'ios';
    return 'desktop';
}
/** App route a link opens. */
function shareRoute(type, targetId, code) {
    return type === 'product' ? `/shops/p/${targetId}?ref=${code}` : `/shops/${targetId}/stage?ref=${code}`;
}
const escapeHtml = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
exports.escapeHtml = escapeHtml;
//# sourceMappingURL=shareLogic.js.map