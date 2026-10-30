/**
 * Each Oneova user's own Gmail, connected in Connected accounts.
 *
 *   gmailConnect({ serverAuthCode })  exchange Google's one-time server code
 *                                     for a refresh token, store it encrypted
 *   gmailStatus()                     connected email + scopes
 *   gmailDisconnect()                 revoke at Google and delete everything
 *   gmailCall({ action, ... })        list / get / send / reply / modify / trash
 *
 * Tokens live in `gmail_tokens/{uid}` (server only; rules deny clients) and
 * are encrypted with AES-256-GCM. The app only sees a public status doc at
 * `users/{uid}/social_connections/gmail`.
 *
 * Setup (once, project mpepe-2b4bd):
 *   - GOOGLE_WEB_CLIENT_ID in functions/.env.mpepe-2b4bd (the Web client from
 *     google-services.json, client_type 3).
 *   - Secrets (optional; Gmail stays off until both exist and are readable,
 *     see optionalSecrets.ts):
 *       GOOGLE_OAUTH_CLIENT_SECRET  that Web client's secret (Cloud Console → Credentials)
 *       GMAIL_TOKEN_KEY             32 random bytes, base64: `openssl rand -base64 32`
 *   - Gmail API enabled, scopes on the OAuth consent screen. Restricted scopes:
 *     up to 100 test users until Google verification + security assessment.
 */
import * as crypto from 'crypto';
import { google, gmail_v1 } from 'googleapis';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineString } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { optionalSecret } from './optionalSecrets';

const webClientId = defineString('GOOGLE_WEB_CLIENT_ID', { default: '' });
const db = () => getFirestore();

export const GMAIL_SCOPES = [
  'https://www.googleapis.com/auth/gmail.readonly',
  'https://www.googleapis.com/auth/gmail.send',
  'https://www.googleapis.com/auth/gmail.modify',
];

// ── encryption ────────────────────────────────────────────────────────────

async function key(): Promise<Buffer> {
  const k = await optionalSecret('GMAIL_TOKEN_KEY');
  const buf = k ? Buffer.from(k, 'base64') : Buffer.alloc(0);
  if (buf.length !== 32) throw new HttpsError('failed-precondition', 'Gmail connection is not set up on the server yet.');
  return buf;
}

async function encrypt(plain: string): Promise<string> {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', await key(), iv);
  const enc = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
  return [iv, c.getAuthTag(), enc].map((b) => b.toString('base64')).join('.');
}

async function decrypt(blob: string): Promise<string> {
  const [iv, tag, enc] = blob.split('.').map((s) => Buffer.from(s, 'base64'));
  const d = crypto.createDecipheriv('aes-256-gcm', await key(), iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(enc), d.final()]).toString('utf8');
}

// ── OAuth client ─────────────────────────────────────────────────────────

async function oauth() {
  const secret = await optionalSecret('GOOGLE_OAUTH_CLIENT_SECRET');
  if (!webClientId.value() || !secret) {
    throw new HttpsError('failed-precondition', 'Gmail connection is not set up on the server yet.');
  }
  // Android/iOS server auth codes are exchanged with an empty redirect URI.
  return new google.auth.OAuth2(webClientId.value(), secret, '');
}

function uidOf(req: { auth?: { uid: string; token: { firebase?: { sign_in_provider?: string } } } }): string {
  const a = req.auth;
  if (!a || a.token.firebase?.sign_in_provider === 'anonymous') throw new HttpsError('unauthenticated', 'Sign in first.');
  return a.uid;
}

async function gmailFor(uid: string): Promise<gmail_v1.Gmail> {
  const snap = await db().collection('gmail_tokens').doc(uid).get();
  const enc = snap.get('refreshToken') as string | undefined;
  if (!enc) throw new HttpsError('failed-precondition', 'Connect Gmail first (Connected accounts → Gmail).');
  const client = await oauth();
  client.setCredentials({ refresh_token: await decrypt(enc) });
  return google.gmail({ version: 'v1', auth: client });
}

function str(v: unknown, max = 20000): string {
  return String(v ?? '').slice(0, max);
}

// ── connect / status / disconnect ────────────────────────────────────────

export const gmailConnect = onCall(async (request) => {
  const uid = uidOf(request);
  const code = str((request.data as Record<string, unknown>)?.serverAuthCode, 2048);
  if (!code) throw new HttpsError('invalid-argument', 'Missing Google authorization code.');
  const client = await oauth();
  let tokens;
  try {
    ({ tokens } = await client.getToken(code));
  } catch (e) {
    logger.warn('[gmailConnect] code exchange failed', { error: String(e) });
    throw new HttpsError('permission-denied', 'Google did not accept the sign-in. Please try connecting again.');
  }
  const granted = (tokens.scope ?? '').split(' ');
  const missing = GMAIL_SCOPES.filter((s) => !granted.includes(s));
  if (missing.length) {
    throw new HttpsError('permission-denied', 'Please allow all Gmail permissions on Google’s screen (read, send and organise).');
  }
  if (!tokens.refresh_token) {
    throw new HttpsError('failed-precondition', 'Google didn’t grant offline access. Remove Oneova at myaccount.google.com/permissions and connect again.');
  }
  client.setCredentials(tokens);
  const profile = await google.gmail({ version: 'v1', auth: client }).users.getProfile({ userId: 'me' });
  const email = profile.data.emailAddress ?? '';

  await db().collection('gmail_tokens').doc(uid).set({
    refreshToken: await encrypt(tokens.refresh_token),
    email,
    scopes: granted,
    connectedAt: FieldValue.serverTimestamp(),
  });
  await db().collection('users').doc(uid).collection('social_connections').doc('gmail').set({
    platform: 'gmail',
    accountName: email,
    scopes: GMAIL_SCOPES.map((s) => s.split('/').pop()),
    connectedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true, email };
});

export const gmailStatus = onCall(async (request) => {
  const uid = uidOf(request);
  const snap = await db().collection('gmail_tokens').doc(uid).get();
  return snap.exists ? { connected: true, email: snap.get('email') ?? '' } : { connected: false };
});

export const gmailDisconnect = onCall(async (request) => {
  const uid = uidOf(request);
  const ref = db().collection('gmail_tokens').doc(uid);
  const snap = await ref.get();
  const enc = snap.get('refreshToken') as string | undefined;
  if (enc) {
    try {
      const client = await oauth();
      await client.revokeToken(await decrypt(enc));
    } catch (e) {
      logger.warn('[gmailDisconnect] revoke failed (token may already be gone)', { error: String(e) });
    }
  }
  await ref.delete();
  await db().collection('users').doc(uid).collection('social_connections').doc('gmail').delete();
  return { ok: true };
});

// ── mail actions ─────────────────────────────────────────────────────────

function header(m: gmail_v1.Schema$Message, name: string): string {
  return m.payload?.headers?.find((h) => (h.name ?? '').toLowerCase() === name.toLowerCase())?.value ?? '';
}

function bodyText(p?: gmail_v1.Schema$MessagePart): string {
  if (!p) return '';
  if (p.mimeType === 'text/plain' && p.body?.data) return Buffer.from(p.body.data, 'base64url').toString('utf8');
  for (const c of p.parts ?? []) {
    const t = bodyText(c);
    if (t) return t;
  }
  if (p.mimeType === 'text/html' && p.body?.data) {
    return Buffer.from(p.body.data, 'base64url')
      .toString('utf8')
      .replace(/<style[\s\S]*?<\/style>/g, '')
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }
  return '';
}

function rfc822(to: string, subject: string, body: string, inReplyTo?: string): string {
  const lines = [
    `To: ${to}`,
    `Subject: =?UTF-8?B?${Buffer.from(subject).toString('base64')}?=`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset="UTF-8"',
    'Content-Transfer-Encoding: base64',
  ];
  if (inReplyTo) lines.push(`In-Reply-To: ${inReplyTo}`, `References: ${inReplyTo}`);
  lines.push('', Buffer.from(body).toString('base64'));
  return Buffer.from(lines.join('\r\n')).toString('base64url');
}

function summary(m: gmail_v1.Schema$Message) {
  return {
    id: m.id,
    threadId: m.threadId,
    from: header(m, 'From'),
    to: header(m, 'To'),
    subject: header(m, 'Subject'),
    date: header(m, 'Date'),
    snippet: m.snippet ?? '',
    unread: (m.labelIds ?? []).includes('UNREAD'),
    starred: (m.labelIds ?? []).includes('STARRED'),
  };
}

export const gmailCall = onCall(async (request) => {
  const uid = uidOf(request);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const gmail = await gmailFor(uid);
  try {
    switch (d.action) {
      case 'list': {
        const max = Math.min(Math.max(Number(d.limit ?? 20), 1), 50);
        const res = await gmail.users.messages.list({
          userId: 'me',
          q: str(d.query ?? 'in:inbox', 500),
          maxResults: max,
          pageToken: d.pageToken ? str(d.pageToken, 200) : undefined,
        });
        const msgs = await Promise.all(
          (res.data.messages ?? []).map((m) =>
            gmail.users.messages.get({ userId: 'me', id: m.id!, format: 'metadata', metadataHeaders: ['From', 'To', 'Subject', 'Date'] }),
          ),
        );
        return { messages: msgs.map((r) => summary(r.data)), nextPageToken: res.data.nextPageToken ?? null };
      }
      case 'get': {
        const r = await gmail.users.messages.get({ userId: 'me', id: str(d.id, 64), format: 'full' });
        return { ...summary(r.data), messageId: header(r.data, 'Message-ID'), body: bodyText(r.data.payload).slice(0, 100000) };
      }
      case 'send': {
        const to = str(d.to, 500);
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+/.test(to)) throw new HttpsError('invalid-argument', 'Enter a valid email address.');
        const r = await gmail.users.messages.send({ userId: 'me', requestBody: { raw: rfc822(to, str(d.subject, 500), str(d.body)) } });
        return { ok: true, id: r.data.id };
      }
      case 'reply': {
        const orig = await gmail.users.messages.get({ userId: 'me', id: str(d.id, 64), format: 'metadata', metadataHeaders: ['From', 'Reply-To', 'Subject', 'Message-ID'] });
        const to = header(orig.data, 'Reply-To') || header(orig.data, 'From');
        const subj = header(orig.data, 'Subject');
        const r = await gmail.users.messages.send({
          userId: 'me',
          requestBody: {
            threadId: orig.data.threadId,
            raw: rfc822(to, /^re:/i.test(subj) ? subj : `Re: ${subj}`, str(d.body), header(orig.data, 'Message-ID')),
          },
        });
        return { ok: true, id: r.data.id, to };
      }
      case 'modify': {
        const add = Array.isArray(d.add) ? (d.add as string[]).slice(0, 5) : [];
        const remove = Array.isArray(d.remove) ? (d.remove as string[]).slice(0, 5) : [];
        await gmail.users.messages.modify({ userId: 'me', id: str(d.id, 64), requestBody: { addLabelIds: add, removeLabelIds: remove } });
        return { ok: true };
      }
      case 'trash': {
        await gmail.users.messages.trash({ userId: 'me', id: str(d.id, 64) });
        return { ok: true };
      }
      default:
        throw new HttpsError('invalid-argument', 'Unknown Gmail action.');
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    const msg = String((e as { message?: string }).message ?? e);
    if (/invalid_grant/.test(msg)) {
      // The user removed access in their Google account: clean up.
      await db().collection('gmail_tokens').doc(uid).delete();
      await db().collection('users').doc(uid).collection('social_connections').doc('gmail').delete();
      throw new HttpsError('failed-precondition', 'Gmail access was removed. Connect Gmail again.');
    }
    logger.warn('[gmailCall] failed', { action: d.action, error: msg });
    throw new HttpsError('internal', 'Gmail request failed. Try again.');
  }
});
