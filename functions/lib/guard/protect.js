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
exports.contactKey = void 0;
exports.requireAccount = requireAccount;
exports.callerIp = callerIp;
exports.limit = limit;
exports.isAdmin = isAdmin;
exports.requireAdmin = requireAdmin;
exports.uidForPhone = uidForPhone;
exports.uidForEmail = uidForEmail;
/**
 * Shared endpoint protection: who is calling, per-user / per-IP limits,
 * admin checks and the private contact index used instead of public
 * users.phoneNumber / users.email queries.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const auth_1 = require("firebase-admin/auth");
const firestore_1 = require("firebase-admin/firestore");
const db = () => (0, firestore_1.getFirestore)();
const sha = (v) => crypto.createHash('sha256').update(v).digest('hex');
function requireAccount(request) {
    var _a;
    const auth = request.auth;
    if (!auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    if (((_a = auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) === 'anonymous')
        throw new https_1.HttpsError('permission-denied', 'Sign in to your account first.');
    return auth.uid;
}
function callerIp(request) {
    var _a, _b, _c;
    var _d;
    const fwd = String((_d = (_b = (_a = request.rawRequest) === null || _a === void 0 ? void 0 : _a.headers) === null || _b === void 0 ? void 0 : _b['x-forwarded-for']) !== null && _d !== void 0 ? _d : '');
    return fwd.split(',')[0].trim() || ((_c = request.rawRequest) === null || _c === void 0 ? void 0 : _c.ip) || null;
}
/**
 * Fixed-window limiter in `security_rate/{bucket}_{hash(key)}` (deny-all to
 * clients; TTL field `expiresAt`). Throws resource-exhausted when over.
 */
async function limit(key, bucket, max, windowMs) {
    if (!key)
        return;
    const ref = db().collection('security_rate').doc(`${bucket}_${sha(key).slice(0, 32)}`);
    const ok = await db().runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(ref);
        const start = Number((_a = snap.get('start')) !== null && _a !== void 0 ? _a : 0);
        const count = Date.now() - start < windowMs ? Number((_b = snap.get('count')) !== null && _b !== void 0 ? _b : 0) : 0;
        if (count >= max)
            return false;
        tx.set(ref, {
            start: count === 0 ? Date.now() : start,
            count: count + 1,
            expiresAt: firestore_1.Timestamp.fromMillis(Date.now() + Math.max(windowMs, 3600000)),
        });
        return true;
    });
    if (!ok)
        throw new https_1.HttpsError('resource-exhausted', 'Too many requests. Please wait a little and try again.');
}
/** Same rule as firestore.rules isAdmin(), plus an `admin` custom claim. */
async function isAdmin(uid, claims) {
    if ((claims === null || claims === void 0 ? void 0 : claims.admin) === true)
        return true;
    return (await db().collection('users').doc(uid).get()).get('role') === 'admin';
}
async function requireAdmin(request) {
    var _a;
    const uid = requireAccount(request);
    if (!(await isAdmin(uid, (_a = request.auth) === null || _a === void 0 ? void 0 : _a.token)))
        throw new https_1.HttpsError('permission-denied', 'Admins only.');
    return uid;
}
// ─────────────── Private contact index ───────────────
// `contact_index/{p:+E164 | e:email}` → { uid }. Deny-all to clients, so a
// phone number or e-mail can be matched to an account without making every
// profile's contact details readable.
exports.contactKey = {
    phone: (e164) => `p:${e164}`,
    email: (email) => `e:${email.trim().toLowerCase()}`,
};
async function uidForPhone(phone) {
    try {
        return (await (0, auth_1.getAuth)().getUserByPhoneNumber(phone)).uid;
    }
    catch (_a) {
        // not an Auth phone; try the index, then legacy profile fields
    }
    const idx = await db().collection('contact_index').doc(exports.contactKey.phone(phone)).get();
    if (idx.exists)
        return String(idx.get('uid'));
    // Older profiles stored local formats (07…, 254…).
    const variants = [phone, phone.slice(1), ...(phone.startsWith('+254') ? [`0${phone.slice(4)}`] : [])];
    for (const v of variants) {
        for (const field of ['phoneNumber', 'phone']) {
            const q = await db().collection('users').where(field, '==', v).limit(1).get();
            if (!q.empty)
                return q.docs[0].id;
        }
    }
    return null;
}
async function uidForEmail(email) {
    const e = email.trim().toLowerCase();
    try {
        return (await (0, auth_1.getAuth)().getUserByEmail(e)).uid;
    }
    catch (_a) {
        // fall through
    }
    const idx = await db().collection('contact_index').doc(exports.contactKey.email(e)).get();
    if (idx.exists)
        return String(idx.get('uid'));
    for (const [field, op] of [['email', '=='], ['linkedEmails', 'array-contains']]) {
        const q = await db().collection('users').where(field, op, e).limit(1).get();
        if (!q.empty)
            return q.docs[0].id;
    }
    return null;
}
//# sourceMappingURL=protect.js.map