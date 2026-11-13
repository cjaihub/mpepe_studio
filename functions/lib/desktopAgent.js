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
exports.desktopAgentBootstrap = void 0;
/**
 * Desktop Computer Agent cryptographic bootstrap.
 *
 * Enrolls a workstation-local 256-bit secret as a dedicated, least-privilege
 * Firebase Auth agent principal (`desktop_agent_<32-hex>`, `{ desktopAgent: true }`)
 * without requiring Anonymous Auth, `iam.serviceAccounts.signBlob`, or macOS
 * Data Protection Keychain entitlements.
 *
 * Security model:
 * - A `desktop_agent_*` UID has zero access to user data on its own.
 * - It can only publish a short-lived 6-digit E2EE pairing offer in
 *   `desktop_pairing/{pin}`, and only gains access to a single
 *   `registered_computers/{deviceId}` document AFTER a signed-in mobile owner
 *   explicitly writes `agent_uid` onto their own computer record during E2EE
 *   PIN verification.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("./guard/protect");
const AGENT_KEYS = 'desktop_agent_keys';
const KEY_TTL_DAYS = 180;
function sha256(value) {
    return crypto.createHash('sha256').update(value).digest('hex');
}
exports.desktopAgentBootstrap = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d;
    await (0, protect_1.limit)((0, protect_1.callerIp)(request), 'desktop_agent_boot', 30, 15 * 60000);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const secret = String((_b = data.secret) !== null && _b !== void 0 ? _b : '').trim();
    const computerName = String((_c = data.computerName) !== null && _c !== void 0 ? _c : '').trim().slice(0, 120);
    const os = String((_d = data.os) !== null && _d !== void 0 ? _d : '').trim().slice(0, 40);
    if (!/^[0-9a-f]{64}$/i.test(secret)) {
        throw new https_1.HttpsError('invalid-argument', 'A 256-bit hex workstation secret is required.');
    }
    const agentUid = `desktop_agent_${crypto.randomBytes(16).toString('hex')}`;
    const agentEmail = `${agentUid}@agent.oneova.internal`;
    const auth = (0, auth_1.getAuth)();
    await auth.createUser({
        uid: agentUid,
        email: agentEmail,
        password: secret,
        displayName: computerName || 'Oneova Desktop Agent',
    });
    await auth.setCustomUserClaims(agentUid, { desktopAgent: true });
    await (0, firestore_1.getFirestore)().collection(AGENT_KEYS).doc(agentUid).set({
        secretHash: sha256(secret),
        agentEmail,
        computerName: computerName || 'Workstation',
        os: os || 'desktop',
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        lastUsedAt: firestore_1.FieldValue.serverTimestamp(),
        expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + KEY_TTL_DAYS * 86400000),
    });
    return { agentUid, agentEmail };
});
//# sourceMappingURL=desktopAgent.js.map