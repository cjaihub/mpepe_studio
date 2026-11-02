/**
 * Each Oneova user's own Gmail, connected in Connected accounts.
 *
 *   gmailConnect({ serverAuthCode })  exchange Google's one-time server code
 *                                     for a refresh token, store it encrypted
 *   gmailStatus()                     connected email + scopes
 *   gmailDisconnect()                 revoke at Google and delete everything
 *   gmailCall({ action, ... })        list / get / send / reply / modify / trash
 *
 * The refresh token lives under the user's own document at
 * `users/{uid}/secure_tokens/gmail` (server only; rules deny every client,
 * owner and admin included). It is encrypted with AES-256-GCM and the uid is
 * bound in as associated data, so a blob copied to another user's doc won't
 * decrypt. The app only sees a status doc at
 * `users/{uid}/social_connections/gmail`, also server-written.
 * Tokens from the old top-level `gmail_tokens/{uid}` location are moved on
 * first use.
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

/** `v2.iv.tag.data`, base64 parts; [uid] is the GCM associated data. */
export function encryptWith(k: Buffer, plain: string, uid: string): string {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', k, iv);
  c.setAAD(Buffer.from(uid, 'utf8'));
  const enc = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
  return ['v2', ...[iv, c.getAuthTag(), enc].map((b) => b.toString('base64'))].join('.');
}

/** Reads `v2.` blobs (uid-bound) and the original `iv.tag.data` format. */
export function decryptWith(k: Buffer, blob: string, uid: string): string {
  const parts = blob.split('.');
  const v2 = parts[0] === 'v2';
  const [iv, tag, enc] = (v2 ? parts.slice(1) : parts).map((s) => Buffer.from(s, 'base64'));
  const d = crypto.createDecipheriv('aes-256-gcm', k, iv);
  if (v2) d.setAAD(Buffer.from(uid, 'utf8'));
  d.setAuthTag(tag);
  return Buffer.concat([d.update(enc), d.final()]).toString('utf8');
}

async function encrypt(plain: string, uid: string): Promise<string> {
  return encryptWith(await key(), plain, uid);
}

async function decrypt(blob: string, uid: string): Promise<string> {
  return decryptWith(await key(), blob, uid);
}

// ── token storage ────────────────────────────────────────────────────────

const tokenRef = (uid: string) => db().collection('users').doc(uid).collection('secure_tokens').doc('gmail');
const legacyTokenRef = (uid: string) => db().collection('gmail_tokens').doc(uid);
const statusRef = (uid: string) => db().collection('users').doc(uid).collection('social_connections').doc('gmail');

type StoredToken = { refreshToken: string; email: string };

/** The user's stored token; moves one from the old top-level location if needed. */
async function loadToken(uid: string): Promise<StoredToken | null> {
  const snap = await tokenRef(uid).get();
  if (snap.exists && snap.get('refreshToken')) {
    return { refreshToken: snap.get('refreshToken'), email: snap.get('email') ?? '' };
  }
  const legacy = await legacyTokenRef(uid).get();
  const enc = legacy.get('refreshToken') as string | undefined;
  if (!enc) return null;
  const refreshToken = await encrypt(await decrypt(enc, uid), uid);
  const batch = db().batch();
  batch.set(tokenRef(uid), {
    refreshToken,
    email: legacy.get('email') ?? '',
    scopes: legacy.get('scopes') ?? [],
    connectedAt: legacy.get('connectedAt') ?? FieldValue.serverTimestamp(),
    movedAt: FieldValue.serverTimestamp(),
  });
  batch.delete(legacyTokenRef(uid));
  await batch.commit();
  return { refreshToken, email: legacy.get('email') ?? '' };
}

/** Removes the token (both locations) and the public status doc. */
async function clearToken(uid: string): Promise<void> {
  const batch = db().batch();
  batch.delete(tokenRef(uid));
  batch.delete(legacyTokenRef(uid));
  batch.delete(statusRef(uid));
  await batch.commit();
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
  const stored = await loadToken(uid);
  if (!stored) {
    // A status doc without a token (e.g. written by an older app build) would
    // show Gmail as connected when it can't work: remove it.
    await statusRef(uid).delete().catch(() => undefined);
    throw new HttpsError('failed-precondition', 'Connect Gmail first (Connected accounts → Gmail).');
  }
  const client = await oauth();
  client.setCredentials({ refresh_token: await decrypt(stored.refreshToken, uid) });
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

  const batch = db().batch();
  batch.set(tokenRef(uid), {
    refreshToken: await encrypt(tokens.refresh_token, uid),
    email,
    scopes: granted,
    connectedAt: FieldValue.serverTimestamp(),
  });
  batch.delete(legacyTokenRef(uid));
  batch.set(statusRef(uid), {
    platform: 'gmail',
    accountName: email,
    email,
    grantedScopes: GMAIL_SCOPES,
    scopes: GMAIL_SCOPES.map((s) => s.split('/').pop()),
    // The refresh token is held server-side (secure_tokens/gmail).
    tokenStore: 'server',
    connectedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { ok: true, email };
});

export const gmailStatus = onCall(async (request) => {
  const uid = uidOf(request);
  const stored = await loadToken(uid);
  return stored ? { connected: true, email: stored.email } : { connected: false };
});

export const gmailDisconnect = onCall(async (request) => {
  const uid = uidOf(request);
  const stored = await loadToken(uid).catch(() => null);
  if (stored) {
    try {
      const client = await oauth();
      await client.revokeToken(await decrypt(stored.refreshToken, uid));
    } catch (e) {
      logger.warn('[gmailDisconnect] revoke failed (token may already be gone)', { error: String(e) });
    }
  }
  await clearToken(uid);
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
    internalDate: m.internalDate ?? null,
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
      await clearToken(uid);
      throw new HttpsError('failed-precondition', 'Gmail access was removed. Connect Gmail again.');
    }
    logger.warn('[gmailCall] failed', { action: d.action, error: msg });
    throw new HttpsError('internal', 'Gmail request failed. Try again.');
  }
});
