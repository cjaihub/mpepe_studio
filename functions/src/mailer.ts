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
import * as nodemailer from 'nodemailer';
import * as logger from 'firebase-functions/logger';
import { Mail } from './mailTemplates';
import { optionalSecret } from './optionalSecrets';

/**
 * Kept for call sites that used to bind the secrets. Empty on purpose: the
 * sender secrets are optional and read at run time (optionalSecrets.ts), so a
 * missing GMAIL_USER / GMAIL_APP_PASSWORD never blocks `firebase deploy`.
 */
export const MAIL_SECRETS: never[] = [];

let transport: nodemailer.Transporter | null = null;
let sender = '';

async function getTransport(): Promise<nodemailer.Transporter | null> {
  if (transport) return transport;
  const user = await optionalSecret('GMAIL_USER');
  const pass = await optionalSecret('GMAIL_APP_PASSWORD');
  if (!user || !pass) return null;
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
export async function sendMail(to: string, mail: Mail): Promise<boolean> {
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
  } catch (e) {
    logger.error('[mailer] send failed', { error: String(e) });
    return false;
  }
}
