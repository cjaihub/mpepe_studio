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
exports.MAIL_SECRETS = exports.gmailAppPassword = exports.gmailUser = void 0;
exports.sendMail = sendMail;
/**
 * Sends Oneova's security emails from the team's Gmail account.
 *
 * Setup (once):
 *   1. On the Gmail account, turn on 2-Step Verification and create an
 *      App password (Google Account → Security → App passwords).
 *   2. firebase functions:secrets:set GMAIL_USER          (e.g. security@yourdomain or you@gmail.com)
 *      firebase functions:secrets:set GMAIL_APP_PASSWORD  (the 16-character app password)
 * Gmail limits normal accounts to about 500 emails a day; use a Workspace
 * account (2,000/day) or a transactional provider when Oneova grows.
 */
const nodemailer = __importStar(require("nodemailer"));
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
exports.gmailUser = (0, params_1.defineSecret)('GMAIL_USER');
exports.gmailAppPassword = (0, params_1.defineSecret)('GMAIL_APP_PASSWORD');
exports.MAIL_SECRETS = [exports.gmailUser, exports.gmailAppPassword];
let transport = null;
function getTransport() {
    const user = exports.gmailUser.value();
    const pass = exports.gmailAppPassword.value();
    if (!user || !pass)
        return null;
    transport !== null && transport !== void 0 ? transport : (transport = nodemailer.createTransport({
        host: 'smtp.gmail.com',
        port: 465,
        secure: true,
        auth: { user, pass },
    }));
    return transport;
}
/** Returns true when Gmail accepted the message. Never throws. */
async function sendMail(to, mail) {
    const t = getTransport();
    if (!t) {
        logger.warn('[mailer] GMAIL_USER / GMAIL_APP_PASSWORD not set; email not sent.');
        return false;
    }
    try {
        await t.sendMail({
            from: { name: 'Oneova Security', address: exports.gmailUser.value() },
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