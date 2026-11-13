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
exports.VERIFY_URL = exports.ISSUER = exports.signingJwk = void 0;
exports.publicJwks = publicJwks;
exports.issueCredential = issueCredential;
exports.revokeCredential = revokeCredential;
exports.signShare = signShare;
/**
 * Signed identity credentials.
 *
 * - The long-lived credential is an SD-JWT VC (every claim is a separate
 *   salted disclosure, so the holder can later reveal only some of them).
 * - A "share" is a short-lived JWT holding only the claims the person chose,
 *   with its own expiry; it is what the QR code on the phone carries.
 * - Anyone can check both with the public key from `idPublic/jwks` and the
 *   revocation status from `idPublic/status` — no account needed.
 *
 * Signing key: ES256 (P-256) private JWK in Secret Manager as
 * IDENTITY_SIGNING_JWK (create it with tools/identity/make_signing_key.cjs).
 */
const crypto = __importStar(require("crypto"));
const params_1 = require("firebase-functions/params");
const firestore_1 = require("firebase-admin/firestore");
const common_1 = require("./common");
exports.signingJwk = (0, params_1.defineSecret)('IDENTITY_SIGNING_JWK');
exports.ISSUER = 'https://oneova.web.app';
exports.VERIFY_URL = 'https://oneova.web.app/verify';
const b64u = (b) => Buffer.from(b).toString('base64url');
function key() {
    const jwk = JSON.parse(exports.signingJwk.value());
    const priv = crypto.createPrivateKey({ key: jwk, format: 'jwk' });
    const pub = { kty: 'EC', crv: 'P-256', x: jwk.x, y: jwk.y };
    // RFC 7638 thumbprint as key id.
    const kid = b64u(crypto.createHash('sha256').update(JSON.stringify({ crv: 'P-256', kty: 'EC', x: jwk.x, y: jwk.y })).digest());
    return { priv, pub, kid };
}
function publicJwks() {
    const { pub, kid } = key();
    return { keys: [Object.assign(Object.assign({}, pub), { kid, alg: 'ES256', use: 'sig' })] };
}
function sign(header, payload) {
    const { priv, kid } = key();
    const input = `${b64u(JSON.stringify(Object.assign(Object.assign({}, header), { alg: 'ES256', kid })))}.${b64u(JSON.stringify(payload))}`;
    const sig = crypto.sign('sha256', Buffer.from(input), { key: priv, dsaEncoding: 'ieee-p1363' });
    return `${input}.${b64u(sig)}`;
}
/** Issues (or re-issues) the holder's SD-JWT VC and marks it valid. */
async function issueCredential(uid, kind, claims, years) {
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + Math.round(years * 365.25 * 86400);
    const disclosures = [];
    const digests = [];
    for (const [name, value] of Object.entries(claims)) {
        const d = b64u(JSON.stringify([b64u(crypto.randomBytes(16)), name, value]));
        disclosures.push(d);
        digests.push(b64u(crypto.createHash('sha256').update(d).digest()));
    }
    digests.sort();
    const jwt = sign({ typ: 'dc+sd-jwt' }, {
        iss: exports.ISSUER, iat: now, nbf: now, exp, jti: id,
        vct: `${exports.ISSUER}/id/vct/${kind}/v1`,
        _sd_alg: 'sha-256', _sd: digests,
        status: { uri: `${exports.ISSUER}/verify`, id },
    });
    const token = `${jwt}~${disclosures.join('~')}~`;
    const expiresAt = new Date(exp * 1000);
    const refPath = kind === 'person' ? `identity/${uid}` : `business_identity/${uid}`;
    const prev = (await (0, common_1.db)().doc(refPath).get()).get('credentialId');
    const batch = (0, common_1.db)().batch();
    if (prev)
        batch.set((0, common_1.db)().doc(`identityStatus/${prev}`), { status: 'replaced', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    batch.set((0, common_1.db)().doc(`identityStatus/${id}`), { uid, kind, status: 'valid', issuedAt: firestore_1.FieldValue.serverTimestamp(), expiresAt: firestore_1.Timestamp.fromDate(expiresAt) });
    batch.set((0, common_1.db)().doc(refPath), { credentialId: id, credentialIssuedAt: firestore_1.FieldValue.serverTimestamp(), credentialExpiresAt: firestore_1.Timestamp.fromDate(expiresAt) }, { merge: true });
    await batch.commit();
    return { id, token, expiresAt };
}
async function revokeCredential(uid, kind) {
    const refPath = kind === 'person' ? `identity/${uid}` : `business_identity/${uid}`;
    const id = (await (0, common_1.db)().doc(refPath).get()).get('credentialId');
    if (id)
        await (0, common_1.db)().doc(`identityStatus/${id}`).set({ status: 'revoked', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    const shares = await (0, common_1.db)().collection(`identity/${uid}/shares`).where('kind', '==', kind).where('revokedAt', '==', null).get();
    const batch = (0, common_1.db)().batch();
    shares.docs.forEach((d) => batch.update(d.ref, { revokedAt: firestore_1.FieldValue.serverTimestamp() }));
    await batch.commit();
}
/** A short-lived token with only the chosen claims; the QR code carries it. */
function signShare(shareId, credentialId, kind, claims, ttlSeconds) {
    const now = Math.floor(Date.now() / 1000);
    return sign({ typ: 'oneova-share+jwt' }, {
        iss: exports.ISSUER, iat: now, exp: now + ttlSeconds, jti: shareId, cred: credentialId, kind, claims,
    });
}
//# sourceMappingURL=credentials.js.map