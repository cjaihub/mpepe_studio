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
exports.MAIL_SECRETS = void 0;
exports.sendMail = sendMail;
/**
 * Sends Oneova's security emails from the team's Gmail account.
 *
 * Setup (once):
 *   1. On the Gmail account, turn on 2-Step Verification and create an
 *      App password (Google Account → Security → App passwords).
 *   2. firebase functions:secrets:set GMAIL_USER          (e.g. security@yourdomain or you@gmail.com)
 *      firebase functions:secrets:set GMAIL_APP_PASSWORD  (the 16-character app password)
 *   3. Give the functions' service account Secret Accessor on both (see
 *      optionalSecrets.ts). Until then security emails are skipped, nothing fails.
 * This is ONLY Oneova's own sender. Users' Gmail is per-user (gmailUser.ts).
 * Gmail limits normal accounts to about 500 emails a day; use a Workspace
 * account (2,000/day) or a transactional provider when Oneova grows.
 */
const nodemailer = __importStar(require("nodemailer"));
const logger = __importStar(require("firebase-functions/logger"));
const optionalSecrets_1 = require("./optionalSecrets");
/**
 * Kept for call sites that used to bind the secrets. Empty on purpose: the
 * sender secrets are optional and read at run time (optionalSecrets.ts), so a
 * missing GMAIL_USER / GMAIL_APP_PASSWORD never blocks `firebase deploy`.
 */
exports.MAIL_SECRETS = [];
let transport = null;
let sender = '';
async function getTransport() {
    if (transport)
        return transport;
    const user = await (0, optionalSecrets_1.optionalSecret)('GMAIL_USER');
    const pass = await (0, optionalSecrets_1.optionalSecret)('GMAIL_APP_PASSWORD');
    if (!user || !pass)
        return null;
    sender = user;
    transport = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 465,
        secure: true,
        auth: { user, pass },
    });
    return transport;
}
/** Returns true when Gmail accepted the message. Never throws. */
async function sendMail(to, mail) {
    const t = await getTransport();
    if (!t) {
        logger.warn('[mailer] GMAIL_USER / GMAIL_APP_PASSWORD not set; security email skipped.');
        return false;
    }
    try {
        await t.sendMail({
            from: { name: 'Oneova Security', address: sender },
            to,
            subject: mail.subject,
            text: mail.text,
            html: mail.html,
            headers: { 'X-Entity-Ref-ID': `${Date.now()}` }, // stops Gmail threading separate alerts
        });
        return true;
    }
    catch (e) {
        logger.error('[mailer] send failed', { error: String(e) });
        return false;
    }
}
//# sourceMappingURL=mailer.js.map