/**
 * Google services a person keeps linked to their Oneova profile
 * (Profile → Google services). This is separate from signing in to Oneova:
 * a person adds a Google account once, then switches on only the services
 * they use. Each service asks Google for its own scopes (incremental
 * authorization), so turning on Calendar never asks for Gmail.
 *
 *   googleLinkService({ service | services, serverAuthCode })  add services (and the account, first time)
 *   googleUnlinkService({ sub, service })           stop using one service
 *   googleRemoveAccount({ sub })                    revoke at Google, delete everything
 *   googleAccessToken({ sub, service })             short-lived access token for on-device API calls
 *
 * One refresh token per Google account, AES-256-GCM encrypted (uid-bound) in
 * `users/{uid}/secure_tokens/google_{sub}` (server only, same key as Gmail).
 * The app reads `users/{uid}/google_accounts/{sub}`, also server-written:
 * email, name, photo, granted scopes and `services.{id}.status`.
 *
 * Gmail keeps using gmailUser.ts: linking Gmail here writes the same token to
 * `secure_tokens/gmail` (tagged with `googleSub`) and the usual
 * `social_connections/gmail` status doc, so Ova and the inbox work unchanged.
 * Linking YouTube writes `youtube_accounts/{sub}` with the person's channels.
 *
 * Google has no per-scope revoke: turning one service off means Oneova stops
 * using it; only removing the account cuts Google's permission.
 */
import { google } from 'googleapis';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { GMAIL_SCOPES, encrypt, decrypt, oauth, uidOf, gmailTokenRef, gmailStatusRef, clearToken as clearGmail } from './gmailUser';

const db = () => getFirestore();
type OAuth2Client = InstanceType<typeof google.auth.OAuth2>;

/** Asked with every service so the account can be named on its card. */
export const GOOGLE_IDENTITY_SCOPES = [
  'openid',
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
];

type ServiceDef = { label: string; scopes: string[]; deviceToken: boolean };

/** Must match `GoogleService` in lib/backend/connections/google_services.dart. */
export const GOOGLE_SERVICES: Record<string, ServiceDef> = {
  // Gmail stays server-only: mail is read and sent through gmailCall.
  gmail: { label: 'Gmail', scopes: GMAIL_SCOPES, deviceToken: false },
  youtube: {
    label: 'YouTube',
    scopes: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube.force-ssl',
      'https://www.googleapis.com/auth/yt-analytics.readonly',
      'https://www.googleapis.com/auth/yt-analytics-monetary.readonly',
    ],
    deviceToken: true,
  },
  drive: { label: 'Google Drive', scopes: ['https://www.googleapis.com/auth/drive.file'], deviceToken: true },
  calendar: { label: 'Google Calendar', scopes: ['https://www.googleapis.com/auth/calendar.events'], deviceToken: true },
  contacts: { label: 'Google Contacts', scopes: ['https://www.googleapis.com/auth/contacts.readonly'], deviceToken: true },
  tasks: { label: 'Google Tasks', scopes: ['https://www.googleapis.com/auth/tasks'], deviceToken: true },
};

const user = (uid: string) => db().collection('users').doc(uid);
const tokenRef = (uid: string, sub: string) => user(uid).collection('secure_tokens').doc(`google_${sub}`);
const accountRef = (uid: string, sub: string) => user(uid).collection('google_accounts').doc(sub);
const youtubeRef = (uid: string, sub: string) => user(uid).collection('youtube_accounts').doc(sub);

function str(v: unknown, max: number): string {
  return String(v ?? '').slice(0, max);
}

function serviceOf(v: unknown): [string, ServiceDef] {
  const id = str(v, 32);
  const def = GOOGLE_SERVICES[id];
  if (!def) throw new HttpsError('invalid-argument', 'Unknown Google service.');
  return [id, def];
}

function subOf(v: unknown): string {
  const sub = str(v, 64);
  if (!/^[A-Za-z0-9_-]{1,64}$/.test(sub)) throw new HttpsError('invalid-argument', 'Unknown Google account.');
  return sub;
}

async function client(): Promise<OAuth2Client> {
  try {
    return await oauth();
  } catch (e) {
    if (e instanceof HttpsError) throw new HttpsError('failed-precondition', 'Google services are not set up on the server yet.');
    throw e;
  }
}

/** Decrypted refresh token for [sub], or null when the account isn't linked. */
async function refreshTokenFor(uid: string, sub: string): Promise<{ token: string; scopes: string[] } | null> {
  const snap = await tokenRef(uid, sub).get();
  const enc = snap.get('refreshToken') as string | undefined;
  if (!enc) return null;
  return { token: await decrypt(enc, uid), scopes: (snap.get('scopes') as string[] | undefined) ?? [] };
}

/** Marks every service on the account as needing a reconnect (Google said invalid_grant). */
async function markNeedsReconnect(uid: string, sub: string): Promise<void> {
  const acc = await accountRef(uid, sub).get();
  const services = (acc.get('services') ?? {}) as Record<string, unknown>;
  const patch: Record<string, unknown> = {};
  for (const id of Object.keys(services)) patch[id] = { status: 'needsReconnect' };
  await accountRef(uid, sub).set({ services: patch, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
}

// ── service-specific setup ───────────────────────────────────────────────

/** Gmail is one address per Oneova user: point gmailUser.ts at this account. */
async function linkGmail(uid: string, sub: string, email: string, refreshEnc: string, granted: string[]): Promise<void> {
  const prev = await gmailTokenRef(uid).get();
  const prevSub = prev.get('googleSub') as string | undefined;
  const batch = db().batch();
  if (prevSub && prevSub !== sub) {
    batch.set(accountRef(uid, prevSub), { services: { gmail: FieldValue.delete() } }, { merge: true });
  }
  batch.set(gmailTokenRef(uid), {
    refreshToken: refreshEnc,
    email,
    scopes: granted,
    googleSub: sub,
    connectedAt: FieldValue.serverTimestamp(),
  });
  batch.set(gmailStatusRef(uid), {
    platform: 'gmail',
    accountName: email,
    email,
    grantedScopes: GMAIL_SCOPES,
    scopes: GMAIL_SCOPES.map((s) => s.split('/').pop()),
    tokenStore: 'server',
    googleSub: sub,
    connectedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

/** Writes `youtube_accounts/{sub}` in the shape YtAccountStore reads. */
async function syncYoutube(uid: string, sub: string, me: { name?: string | null; email?: string | null; picture?: string | null }, auth: OAuth2Client): Promise<void> {
  const res = await google.youtube({ version: 'v3', auth }).channels.list({ part: ['snippet', 'statistics'], mine: true });
  const prev = await youtubeRef(uid, sub).get();
  const prevActive = new Set(
    ((prev.get('channels') as Array<{ id?: string; isActive?: boolean }> | undefined) ?? []).filter((c) => c.isActive).map((c) => c.id),
  );
  // First YouTube account: make its first channel the active one.
  const anyActive =
    prevActive.size > 0 ||
    (await user(uid).collection('youtube_accounts').get()).docs.some(
      (d) => d.id !== sub && ((d.get('channels') as Array<{ isActive?: boolean }> | undefined) ?? []).some((c) => c.isActive),
    );
  const channels = (res.data.items ?? []).map((ch, i) => ({
    id: ch.id ?? '',
    title: ch.snippet?.title ?? 'Unknown Channel',
    thumbnailUrl: ch.snippet?.thumbnails?.medium?.url ?? ch.snippet?.thumbnails?.default?.url ?? '',
    subscriberCount: Number(ch.statistics?.subscriberCount ?? 0),
    videoCount: Number(ch.statistics?.videoCount ?? 0),
    viewCount: Number(ch.statistics?.viewCount ?? 0),
    isActive: prevActive.size > 0 ? prevActive.has(ch.id ?? '') : !anyActive && i === 0,
  }));
  await youtubeRef(uid, sub).set(
    {
      googleId: sub,
      accountName: me.name ?? me.email ?? '',
      email: me.email ?? '',
      profilePictureUrl: me.picture ?? '',
      channels,
      connectedAt: prev.exists ? prev.get('connectedAt') : FieldValue.serverTimestamp(),
      lastRefreshed: FieldValue.serverTimestamp(),
      tokenStore: 'server',
    },
    { merge: true },
  );
}

// ── callables ────────────────────────────────────────────────────────────

export const googleLinkService = onCall(async (request) => {
  const uid = uidOf(request);
  const d = (request.data ?? {}) as Record<string, unknown>;
  // One service, or several picked together (one Google consent screen).
  const picked = (Array.isArray(d.services) ? (d.services as unknown[]).slice(0, 10) : [d.service]).map(serviceOf);
  const code = str(d.serverAuthCode, 2048);
  if (!code) throw new HttpsError('invalid-argument', 'Missing Google authorization code.');

  const auth = await client();
  let tokens;
  try {
    ({ tokens } = await auth.getToken(code));
  } catch (e) {
    logger.warn('[googleLinkService] code exchange failed', { error: String(e) });
    throw new HttpsError('permission-denied', 'Google did not accept the sign-in. Please try again.');
  }
  const granted = (tokens.scope ?? '').split(' ').filter(Boolean);
  // A service counts only when every one of its scopes was ticked.
  const linked = picked.filter(([, def]) => def.scopes.every((s) => granted.includes(s)));
  if (!linked.length) {
    const label = picked.length === 1 ? picked[0][1].label : 'the services you picked';
    throw new HttpsError('permission-denied', `Please tick every permission for ${label} on Google’s screen.`);
  }
  const ids = linked.map(([id]) => id);
  auth.setCredentials(tokens);
  const me = (await google.oauth2({ version: 'v2', auth }).userinfo.get()).data;
  const sub = me.id ?? '';
  if (!sub) throw new HttpsError('failed-precondition', 'Google didn’t say which account this is. Please try again.');
  const email = me.email ?? '';

  const prev = await tokenRef(uid, sub).get();
  const refreshEnc = tokens.refresh_token
    ? await encrypt(tokens.refresh_token, uid)
    : (prev.get('refreshToken') as string | undefined);
  if (!refreshEnc) {
    throw new HttpsError('failed-precondition', 'Google didn’t grant offline access. Remove Oneova at myaccount.google.com/permissions and try again.');
  }
  const scopes = Array.from(new Set([...((prev.get('scopes') as string[] | undefined) ?? []), ...granted]));
  await tokenRef(uid, sub).set({ refreshToken: refreshEnc, email, scopes, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  // Gmail holds a copy of this account's token: keep it current.
  const gmail = await gmailTokenRef(uid).get();
  if (ids.includes('gmail')) {
    await linkGmail(uid, sub, email, refreshEnc, granted);
  } else if (gmail.get('googleSub') === sub && tokens.refresh_token) {
    await gmailTokenRef(uid).set({ refreshToken: refreshEnc }, { merge: true });
  }
  if (ids.includes('youtube')) {
    try {
      await syncYoutube(uid, sub, me, auth);
    } catch (e) {
      logger.warn('[googleLinkService] YouTube channel sync failed', { error: String(e) });
    }
  }

  const acc = await accountRef(uid, sub).get();
  await accountRef(uid, sub).set(
    {
      sub,
      email,
      name: me.name ?? '',
      photoUrl: me.picture ?? '',
      grantedScopes: scopes,
      tokenStore: 'server',
      services: Object.fromEntries(ids.map((id) => [id, { status: 'connected', linkedAt: FieldValue.serverTimestamp() }])),
      updatedAt: FieldValue.serverTimestamp(),
      ...(acc.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
    },
    { merge: true },
  );
  return { ok: true, sub, email, linked: ids, skipped: picked.map(([id]) => id).filter((id) => !ids.includes(id)) };
});

export const googleUnlinkService = onCall(async (request) => {
  const uid = uidOf(request);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const sub = subOf(d.sub);
  const [service] = serviceOf(d.service);
  // Older on-phone YouTube links have no Google services account: nothing to do.
  if (!(await accountRef(uid, sub).get()).exists) return { ok: true };
  if (service === 'gmail' && (await gmailTokenRef(uid).get()).get('googleSub') === sub) {
    await clearGmail(uid);
  }
  if (service === 'youtube') await youtubeRef(uid, sub).delete();
  await accountRef(uid, sub).set(
    { services: { [service]: FieldValue.delete() }, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return { ok: true };
});

export const googleRemoveAccount = onCall(async (request) => {
  const uid = uidOf(request);
  const sub = subOf((request.data as Record<string, unknown> | null)?.sub);
  const stored = await refreshTokenFor(uid, sub).catch(() => null);
  if (stored) {
    try {
      await (await client()).revokeToken(stored.token);
    } catch (e) {
      logger.warn('[googleRemoveAccount] revoke failed (token may already be gone)', { error: String(e) });
    }
  }
  if ((await gmailTokenRef(uid).get()).get('googleSub') === sub) await clearGmail(uid);
  const batch = db().batch();
  batch.delete(tokenRef(uid, sub));
  batch.delete(accountRef(uid, sub));
  batch.delete(youtubeRef(uid, sub));
  await batch.commit();
  return { ok: true };
});

export const googleAccessToken = onCall(async (request) => {
  const uid = uidOf(request);
  const d = (request.data ?? {}) as Record<string, unknown>;
  const sub = subOf(d.sub);
  const [service, def] = serviceOf(d.service);
  if (!def.deviceToken) throw new HttpsError('permission-denied', `${def.label} is used through Oneova’s server only.`);
  const acc = await accountRef(uid, sub).get();
  if (acc.get(`services.${service}.status`) !== 'connected') {
    throw new HttpsError('failed-precondition', `Turn on ${def.label} in Profile → Google services first.`);
  }
  const stored = await refreshTokenFor(uid, sub);
  if (!stored) throw new HttpsError('failed-precondition', `Turn on ${def.label} in Profile → Google services first.`);
  const auth = await client();
  auth.setCredentials({ refresh_token: stored.token });
  try {
    const { token } = await auth.getAccessToken();
    if (!token) throw new Error('no access token');
    return { accessToken: token, expiresAt: auth.credentials.expiry_date ?? Date.now() + 50 * 60 * 1000, scopes: def.scopes };
  } catch (e) {
    const msg = String((e as { message?: string }).message ?? e);
    if (/invalid_grant/.test(msg)) {
      await markNeedsReconnect(uid, sub);
      throw new HttpsError('failed-precondition', `Google access was removed. Reconnect ${def.label} in Profile → Google services.`);
    }
    logger.warn('[googleAccessToken] refresh failed', { service, error: msg });
    throw new HttpsError('internal', 'Couldn’t reach Google. Try again.');
  }
});
