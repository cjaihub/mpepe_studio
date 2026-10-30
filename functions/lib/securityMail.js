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
exports.securityLink = exports.guardEmailOnEvent = exports.LINK_MINUTES = void 0;
exports.linkBase = linkBase;
exports.createSecurityLink = createSecurityLink;
/**
 * Email side of Ova Guard (security.ts).
 *
 * When Ova Guard records a security event that matters (new device, new
 * country, password / email / phone changed, account secured …) the user
 * gets a designed email from the team's Gmail with:
 *   - what happened, on which device, where and when;
 *   - their previous sign-in, for comparison;
 *   - "Yes, it was me" / "Not me — secure my account" buttons that expire
 *     after LINK_MINUTES and work once.
 *
 * The buttons open `securityLink`. Opening the link (GET) never changes
 * anything, because mail scanners pre-open links; the user has to press the
 * button on that page (POST). Tokens are stored hashed in `security_links`.
 */
const crypto = __importStar(require("crypto"));
const firestore_1 = require("firebase-functions/v2/firestore");
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const auth_1 = require("firebase-admin/auth");
const firestore_2 = require("firebase-admin/firestore");
const security_1 = require("./security");
const mailTemplates_1 = require("./mailTemplates");
const mailer_1 = require("./mailer");
const accountSettings_1 = require("./accountSettings");
const db = () => (0, firestore_2.getFirestore)();
exports.LINK_MINUTES = 60;
const REGION = 'us-central1';
/** Event types worth an email, with the sentence that leads it. */
const EMAIL_LEAD = {
    new_device: 'Your Oneova account was just signed in on a device we haven’t seen before.',
    new_country: 'Your Oneova account was just signed in from a country you don’t usually use.',
    impossible_travel: 'Your account was used from two places too far apart to travel between in that time.',
    session_reuse: 'The same sign-in was used from two different devices or places.',
    sign_in: 'Your Oneova account was just signed in.',
    auth_failures: 'Someone tried several times to sign in to your account with the wrong password or code.',
    password_changed: 'The password on your Oneova account was changed.',
    email_changed: 'The email address on your Oneova account was changed.',
    phone_changed: 'The phone number on your Oneova account was changed.',
    biometric_key_added: 'Fingerprint sign-in was turned on for a device.',
    account_secured: 'Your account was secured: every device was signed out and fingerprint sign-in was removed.',
};
const SIGN_IN_TYPES = new Set(['sign_in', 'new_device', 'new_country', 'impossible_travel', 'session_reuse']);
function linkBase() {
    var _a, _b;
    let project = (_a = process.env.GCLOUD_PROJECT) !== null && _a !== void 0 ? _a : '';
    if (!project && process.env.FIREBASE_CONFIG) {
        try {
            project = (_b = JSON.parse(process.env.FIREBASE_CONFIG).projectId) !== null && _b !== void 0 ? _b : '';
        }
        catch (_c) {
            /* ignore */
        }
    }
    return `https://${REGION}-${project}.cloudfunctions.net/securityLink`;
}
const hash = (t) => crypto.createHash('sha256').update(t).digest('hex');
/** Creates a single-use link token for [action] and returns its URL. */
async function createSecurityLink(uid, eventId, action) {
    const token = crypto.randomBytes(24).toString('base64url');
    await db().collection('security_links').doc(hash(token)).set({
        uid,
        eventId,
        action,
        expiresAt: firestore_2.Timestamp.fromMillis(Date.now() + exports.LINK_MINUTES * 60000),
        usedAt: null,
        createdAt: firestore_2.FieldValue.serverTimestamp(),
    });
    return `${linkBase()}?t=${encodeURIComponent(token)}`;
}
function when(ts) {
    const d = ts instanceof firestore_2.Timestamp ? ts.toDate() : typeof ts === 'number' ? new Date(ts) : new Date();
    return d.toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }) + ' UTC';
}
function place(geo) {
    if (!geo)
        return '';
    return [geo.city, geo.region, geo.country].filter((x) => typeof x === 'string' && x).join(', ');
}
exports.guardEmailOnEvent = (0, firestore_1.onDocumentCreated)('security_events/{uid}/events/{eventId}', async (event) => {
    var _a, _b;
    var _c, _d, _e, _f, _g, _h, _j;
    const e = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!e)
        return;
    const { uid, eventId } = event.params;
    const type = String((_c = e.type) !== null && _c !== void 0 ? _c : '');
    const lead = EMAIL_LEAD[type];
    if (!lead)
        return;
    const risk = ((_d = e.risk) !== null && _d !== void 0 ? _d : 'low');
    // An ordinary sign-in on a known device does not need an email.
    if (type === 'sign_in' && risk === 'low')
        return;
    const prefs = await (0, accountSettings_1.readAccountSettings)(uid, 'notifications', 'settings/notifications');
    if (prefs.emailSecurityAlerts === false && risk !== 'high')
        return;
    let email;
    try {
        email = (_e = (await (0, auth_1.getAuth)().getUser(uid)).email) !== null && _e !== void 0 ? _e : undefined;
    }
    catch (_k) {
        return;
    }
    if (!email)
        return;
    const details = [
        { label: 'What', value: String((_f = e.title) !== null && _f !== void 0 ? _f : type) },
        { label: 'When', value: when(e.at) },
        { label: 'Device', value: [e.deviceLabel, e.platform].filter(Boolean).join(' · ') },
        { label: 'Where', value: place(e.geo) },
        { label: 'IP address', value: String((_g = e.ipMasked) !== null && _g !== void 0 ? _g : '') },
        { label: 'Why we flagged it', value: Array.isArray(e.reasons) && risk !== 'low' ? String((_h = e.reasons[0]) !== null && _h !== void 0 ? _h : '') : '' },
    ];
    // Previous sign-in, for comparison.
    let lastSignIn;
    if (SIGN_IN_TYPES.has(type)) {
        const recent = await db().collection('security_events').doc(uid).collection('events').orderBy('at', 'desc').limit(12).get();
        const prev = recent.docs.find((d) => d.id !== eventId && SIGN_IN_TYPES.has(String(d.get('type'))));
        if (prev) {
            lastSignIn = [
                { label: 'When', value: when(prev.get('at')) },
                { label: 'Device', value: [prev.get('deviceLabel'), prev.get('platform')].filter(Boolean).join(' · ') },
                { label: 'Where', value: place(prev.get('geo')) },
            ];
        }
    }
    const wantsAnswer = type !== 'account_secured' && (risk !== 'low' || SIGN_IN_TYPES.has(type) || type.endsWith('_changed'));
    const confirmUrl = wantsAnswer && SIGN_IN_TYPES.has(type) ? await createSecurityLink(uid, eventId, 'confirm') : null;
    const secureUrl = wantsAnswer ? await createSecurityLink(uid, eventId, 'secure') : null;
    const ok = await (0, mailer_1.sendMail)(email, (0, mailTemplates_1.alertEmail)({
        title: type === 'account_secured' ? 'Your account is secured' : String((_j = e.title) !== null && _j !== void 0 ? _j : 'Security alert'),
        lead,
        risk,
        details,
        lastSignIn,
        confirmUrl,
        secureUrl,
        linkMinutes: exports.LINK_MINUTES,
    }));
    await ((_b = event.data) === null || _b === void 0 ? void 0 : _b.ref.set({ emailedAt: ok ? firestore_2.FieldValue.serverTimestamp() : null, emailFailed: !ok }, { merge: true }));
});
// ── Link handler ───────────────────────────────────────────────────────────
exports.securityLink = (0, https_1.onRequest)({ cors: false }, async (req, res) => {
    var _a;
    var _b;
    res.set('Cache-Control', 'no-store');
    res.set('X-Robots-Tag', 'noindex');
    const token = String((_b = (req.method === 'POST' ? (_a = req.body) === null || _a === void 0 ? void 0 : _a.t : req.query.t)) !== null && _b !== void 0 ? _b : '').slice(0, 100);
    const expired = () => res.status(410).send((0, mailTemplates_1.page)({
        title: 'This link has expired',
        message: 'Security links work once and expire after ' + exports.LINK_MINUTES + ' minutes. Open the Oneova app and go to <b>Profile → Security</b> to review recent activity or secure your account.',
        tone: 'warn',
    }));
    if (!token)
        return void expired();
    const ref = db().collection('security_links').doc(hash(token));
    const snap = await ref.get();
    if (!snap.exists)
        return void expired();
    const link = snap.data();
    if (link.usedAt || link.expiresAt.toMillis() < Date.now())
        return void expired();
    if (req.method !== 'POST') {
        // Showing the page changes nothing; the user must press the button.
        res.status(200).send(link.action === 'secure'
            ? (0, mailTemplates_1.page)({
                title: 'Secure your Oneova account?',
                message: 'This signs out <b>every device</b>, removes fingerprint sign-in, and asks for your password and a code next time. Use it if you don’t recognise this activity.',
                tone: 'warn',
                form: { action: linkBase(), button: 'Secure my account now', danger: true, hidden: { t: token } },
            })
            : (0, mailTemplates_1.page)({
                title: 'Was this you?',
                message: 'Confirm that you made this sign-in. We’ll remember this device and place.',
                form: { action: linkBase(), button: 'Yes, it was me', hidden: { t: token } },
            }));
        return;
    }
    // Single use: claim the token first.
    const claimed = await db().runTransaction(async (tx) => {
        const cur = await tx.get(ref);
        if (!cur.exists || cur.get('usedAt'))
            return false;
        tx.update(ref, { usedAt: firestore_2.FieldValue.serverTimestamp() });
        return true;
    });
    if (!claimed)
        return void expired();
    try {
        if (link.action === 'confirm') {
            if (link.eventId) {
                await db().collection('security_events').doc(link.uid).collection('events').doc(link.eventId)
                    .set({ status: 'confirmed', answeredAt: firestore_2.FieldValue.serverTimestamp(), answeredVia: 'email' }, { merge: true });
            }
            res.status(200).send((0, mailTemplates_1.page)({ title: 'Thanks — marked as you', message: 'Nothing else to do. You can close this page.', tone: 'ok' }));
            return;
        }
        await (0, security_1.secureAccount)(link.uid, link.eventId);
        res.status(200).send((0, mailTemplates_1.page)({
            title: 'Your account is secured',
            message: 'Every device has been signed out and fingerprint sign-in was removed. Sign in again on your phone, then <b>change your password</b> in Profile → Security.',
            tone: 'ok',
        }));
    }
    catch (e) {
        logger.error('[securityLink] action failed', { error: String(e) });
        res.status(500).send((0, mailTemplates_1.page)({ title: 'Something went wrong', message: 'Please open the Oneova app → Profile → Security.', tone: 'warn' }));
    }
});
//# sourceMappingURL=securityMail.js.map