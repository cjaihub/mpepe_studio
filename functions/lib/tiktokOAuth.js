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
exports.tiktokExchangeCode = void 0;
/**
 * TikTok Login Kit code exchange, server side, so the client secret never
 * ships in the app.
 *
 *   tiktokExchangeCode  callable: { code } → TikTok token response
 *                       (access_token, refresh_token, open_id, expires_in…).
 *
 * Setup:
 *   firebase functions:secrets:set TIKTOK_CLIENT_SECRET --project mpepe-2b4bd
 *   TIKTOK_CLIENT_KEY / TIKTOK_REDIRECT_URI live in functions/.env.mpepe-2b4bd.
 */
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const tiktokClientSecret = (0, params_1.defineSecret)('TIKTOK_CLIENT_SECRET');
const tiktokClientKey = (0, params_1.defineString)('TIKTOK_CLIENT_KEY');
const tiktokRedirectUri = (0, params_1.defineString)('TIKTOK_REDIRECT_URI');
exports.tiktokExchangeCode = (0, https_1.onCall)({ secrets: [tiktokClientSecret] }, async (request) => {
    var _a, _b;
    var _c, _d, _e;
    if (!((_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid))
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    const code = String((_c = (_b = request.data) === null || _b === void 0 ? void 0 : _b.code) !== null && _c !== void 0 ? _c : '');
    if (!code || code.length > 2048)
        throw new https_1.HttpsError('invalid-argument', 'Missing authorization code.');
    const res = await fetch('https://open.tiktokapis.com/v2/oauth/token/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            client_key: tiktokClientKey.value(),
            client_secret: tiktokClientSecret.value(),
            code,
            grant_type: 'authorization_code',
            redirect_uri: tiktokRedirectUri.value(),
        }),
    });
    const body = (await res.json().catch(() => ({})));
    if (!res.ok || !body.access_token) {
        logger.warn('tiktokExchangeCode failed', { status: res.status, error: body.error });
        throw new https_1.HttpsError('failed-precondition', String((_e = (_d = body.error_description) !== null && _d !== void 0 ? _d : body.error) !== null && _e !== void 0 ? _e : 'Token exchange failed'));
    }
    return body;
});
//# sourceMappingURL=tiktokOAuth.js.map