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
import * as nodemailer from 'nodemailer';
import { defineSecret } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { Mail } from './mailTemplates';

export const gmailUser = defineSecret('GMAIL_USER');
export const gmailAppPassword = defineSecret('GMAIL_APP_PASSWORD');
export const MAIL_SECRETS = [gmailUser, gmailAppPassword];

let transport: nodemailer.Transporter | null = null;

function getTransport(): nodemailer.Transporter | null {
  const user = gmailUser.value();
  const pass = gmailAppPassword.value();
  if (!user || !pass) return null;
  transport ??= nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: { user, pass },
  });
  return transport;
}

/** Returns true when Gmail accepted the message. Never throws. */
export async function sendMail(to: string, mail: Mail): Promise<boolean> {
  const t = getTransport();
  if (!t) {
    logger.warn('[mailer] GMAIL_USER / GMAIL_APP_PASSWORD not set; email not sent.');
    return false;
  }
  try {
    await t.sendMail({
      from: { name: 'Oneova Security', address: gmailUser.value() },
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
