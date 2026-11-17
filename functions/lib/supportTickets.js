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
exports.lookupSupportTicket = exports.submitSupportTicket = void 0;
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("./guard/protect");
const db = () => (0, firestore_1.getFirestore)();
const ALLOWED_CATEGORIES = new Set([
    'account',
    'live',
    'interaction',
    'desktop',
    'post',
    'monetization',
    'feed',
    'privacy',
    'other',
]);
function sha256Hex(value) {
    return crypto.createHash('sha256').update(value).digest('hex');
}
function generateTrackingCode() {
    const num = crypto.randomInt(100000, 999999);
    return `OVA-${num}`;
}
function generateAccessPin() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let out = '';
    for (let i = 0; i < 6; i++) {
        out += alphabet[crypto.randomInt(0, alphabet.length)];
    }
    return out;
}
exports.submitSupportTicket = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    var _c, _d, _e, _f, _g;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_ticket_ip', 8, 60 * 60000);
    const authUid = request.auth && ((_b = (_a = request.auth.token) === null || _a === void 0 ? void 0 : _a.firebase) === null || _b === void 0 ? void 0 : _b.sign_in_provider) !== 'anonymous'
        ? request.auth.uid
        : '';
    if (authUid) {
        await (0, protect_1.limit)(authUid, 'support_ticket_uid', 15, 24 * 3600000);
    }
    const raw = ((_c = request.data) !== null && _c !== void 0 ? _c : {});
    const categoryRaw = String((_d = raw.category) !== null && _d !== void 0 ? _d : 'other').trim().toLowerCase();
    const category = ALLOWED_CATEGORIES.has(categoryRaw) ? categoryRaw : 'other';
    const subject = String((_e = raw.subject) !== null && _e !== void 0 ? _e : '').trim();
    const message = String((_f = raw.message) !== null && _f !== void 0 ? _f : '').trim();
    const contactEmail = String((_g = raw.contactEmail) !== null && _g !== void 0 ? _g : '').trim().slice(0, 120);
    if (subject.length < 3 || subject.length > 140) {
        throw new https_1.HttpsError('invalid-argument', 'Subject must be between 3 and 140 characters.');
    }
    if (message.length < 10 || message.length > 2000) {
        throw new https_1.HttpsError('invalid-argument', 'Message must be between 10 and 2000 characters.');
    }
    if (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
        throw new https_1.HttpsError('invalid-argument', 'Please provide a valid email address.');
    }
    const trackingCode = generateTrackingCode();
    const accessPin = generateAccessPin();
    const ref = db().collection('support_tickets').doc();
    await ref.set({
        uid: authUid,
        trackingCode,
        pinHash: sha256Hex(`${trackingCode}:${accessPin}`),
        category,
        subject,
        message,
        contactEmail,
        status: 'open',
        adminReply: '',
        repliedByUid: '',
        repliedByName: '',
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    return {
        ok: true,
        ticketId: ref.id,
        trackingCode,
        accessPin,
        status: 'open',
    };
});
exports.lookupSupportTicket = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_lookup_ip', 20, 10 * 60000);
    const raw = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const trackingCode = String((_b = raw.trackingCode) !== null && _b !== void 0 ? _b : '')
        .trim()
        .toUpperCase();
    const accessPin = String((_c = raw.accessPin) !== null && _c !== void 0 ? _c : '')
        .trim()
        .toUpperCase();
    if (!/^OVA-\d{6}$/.test(trackingCode) || !/^[A-Z0-9]{6}$/.test(accessPin)) {
        throw new https_1.HttpsError('invalid-argument', 'Enter a valid tracking code and 6-character PIN.');
    }
    const snap = await db()
        .collection('support_tickets')
        .where('trackingCode', '==', trackingCode)
        .limit(1)
        .get();
    if (snap.empty) {
        throw new https_1.HttpsError('not-found', 'Ticket not found or PIN mismatch.');
    }
    const data = snap.docs[0].data();
    const expectedHash = String((_d = data.pinHash) !== null && _d !== void 0 ? _d : '');
    const providedHash = sha256Hex(`${trackingCode}:${accessPin}`);
    if (expectedHash.length !== providedHash.length ||
        !crypto.timingSafeEqual(Buffer.from(expectedHash), Buffer.from(providedHash))) {
        throw new https_1.HttpsError('not-found', 'Ticket not found or PIN mismatch.');
    }
    const updatedAt = data.updatedAt && typeof data.updatedAt.toDate === 'function'
        ? data.updatedAt.toDate().toISOString()
        : null;
    return {
        ok: true,
        trackingCode: data.trackingCode,
        category: data.category,
        subject: data.subject,
        status: data.status,
        adminReply: data.adminReply || '',
        updatedAt,
    };
});
//# sourceMappingURL=supportTickets.js.map