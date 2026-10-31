/**
 * Meta (Facebook Pages, Instagram, WhatsApp Business) login, server side.
 *
 *   metaExchangeCode   callable: OAuth code → long-lived user token → the
 *                      user's Pages. The app secret never leaves Secret Manager.
 *   metaDataDeletion   Meta "Data Deletion Request" callback (required for App
 *                      Review). Verifies the signed_request and deletes the
 *                      Meta connection data Oneova keeps for that person.
 *   metaDeauthorize    Meta "Deauthorize" callback: same clean-up when someone
 *                      removes Oneova from their Facebook settings.
 *   metaDeletionStatus Status page Meta links people to (confirmation code).
 *
 * Setup:
 *   firebase functions:secrets:set META_APP_SECRET --project mpepe-2b4bd
 *   META_APP_ID / META_REDIRECT_URI live in functions/.env.mpepe-2b4bd.
 * Dashboard: Facebook Login → Settings
 *   Deauthorize callback URL   https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDeauthorize
 *   Data deletion request URL  https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDataDeletion
 */
import * as crypto from 'crypto';
import axios from 'axios';
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { page } from './mailTemplates';
import { limit } from './guard/protect';

const metaAppSecret = defineSecret('META_APP_SECRET');
const metaAppId = defineString('META_APP_ID');
const metaRedirectUri = defineString('META_REDIRECT_URI');

const GRAPH = 'https://graph.facebook.com/v22.0';
const db = () => getFirestore();

const APP_FIELDS: Record<string, string> = {
  facebook: 'id,name,category,picture,fan_count,access_token,tasks',
  instagram: 'id,name,category,picture,fan_count,access_token,tasks,instagram_business_account{id,username,profile_picture_url,followers_count}',
  whatsapp: 'id,name,category,picture,fan_count,access_token,tasks',
};

/** appsecret_proof: Meta's recommended guard for server-side Graph calls. */
function proof(token: string): string {
  return crypto.createHmac('sha256', metaAppSecret.value()).update(token).digest('hex');
}

function graphError(e: unknown): string {
  const d = (e as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error;
  return d?.message ?? String(e);
}

export const metaExchangeCode = onCall({ secrets: [metaAppSecret] }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  await limit(uid, 'oauth_meta', 10, 10 * 60000);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const code = String(data.code ?? '');
  const app = String(data.app ?? 'facebook');
  if (!code || code.length > 2048) throw new HttpsError('invalid-argument', 'Missing authorization code.');
  if (!APP_FIELDS[app]) throw new HttpsError('invalid-argument', 'Unknown Meta app.');
  // The redirect URI must match the one used for the dialog; only ours is accepted.
  const redirectUri = metaRedirectUri.value();

  try {
    const short = await axios.get(`${GRAPH}/oauth/access_token`, {
      params: { client_id: metaAppId.value(), client_secret: metaAppSecret.value(), redirect_uri: redirectUri, code },
      timeout: 15000,
    });
    const shortToken = short.data?.access_token as string | undefined;
    if (!shortToken) throw new Error('No access token from Meta.');

    const long = await axios.get(`${GRAPH}/oauth/access_token`, {
      params: { grant_type: 'fb_exchange_token', client_id: metaAppId.value(), client_secret: metaAppSecret.value(), fb_exchange_token: shortToken },
      timeout: 15000,
    });
    const userToken = (long.data?.access_token as string | undefined) ?? shortToken;
    const expiresIn = Number(long.data?.expires_in ?? 5_184_000);

    const me = await axios.get(`${GRAPH}/me`, { params: { fields: 'id,name', access_token: userToken, appsecret_proof: proof(userToken) }, timeout: 15000 });
    const metaUserId = String(me.data?.id ?? '');

    const perms = await axios.get(`${GRAPH}/me/permissions`, { params: { access_token: userToken, appsecret_proof: proof(userToken) }, timeout: 15000 });
    const granted = ((perms.data?.data ?? []) as Array<{ permission: string; status: string }>)
      .filter((p) => p.status === 'granted')
      .map((p) => p.permission);

    const accounts = await axios.get(`${GRAPH}/me/accounts`, {
      params: { fields: APP_FIELDS[app], limit: 50, access_token: userToken, appsecret_proof: proof(userToken) },
      timeout: 15000,
    });
    let pages = (accounts.data?.data ?? []) as Array<Record<string, unknown>>;
    if (app === 'instagram') pages = pages.filter((p) => p.instagram_business_account);

    // Remember which Oneova account this Meta person belongs to, so a
    // deletion / deauthorize callback from Meta can find their data.
    if (metaUserId) {
      await db().collection('meta_users').doc(metaUserId).set(
        { uids: FieldValue.arrayUnion(uid), apps: FieldValue.arrayUnion(app), updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      await db().collection('users').doc(uid).collection('private').doc('meta').set(
        { metaUserId, granted, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
    }

    return { userToken, expiresIn, metaUserId, metaUserName: me.data?.name ?? null, granted, pages };
  } catch (e) {
    logger.warn('[metaExchangeCode] failed', { error: graphError(e) });
    throw new HttpsError('failed-precondition', `Meta sign-in failed: ${graphError(e)}`);
  }
});

// ── Signed requests (deletion / deauthorize) ─────────────────────────────

function parseSignedRequest(signed: string): { user_id?: string } | null {
  const [sig, payload] = signed.split('.', 2);
  if (!sig || !payload) return null;
  const expected = crypto.createHmac('sha256', metaAppSecret.value()).update(payload).digest();
  const given = Buffer.from(sig.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  try {
    const json = JSON.parse(Buffer.from(payload.replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
    return json?.algorithm === 'HMAC-SHA256' ? json : null;
  } catch {
    return null;
  }
}

/** Deletes everything Oneova stores about this Meta person. Returns uids touched. */
async function purgeMetaUser(metaUserId: string, reason: 'deletion' | 'deauthorize'): Promise<number> {
  const ref = db().collection('meta_users').doc(metaUserId);
  const snap = await ref.get();
  const uids = (snap.get('uids') as string[] | undefined) ?? [];
  for (const uid of uids) {
    const batch = db().batch();
    for (const app of ['facebook', 'instagram', 'whatsapp']) {
      batch.delete(db().collection('users').doc(uid).collection('social_connections').doc(app));
    }
    batch.delete(db().collection('users').doc(uid).collection('private').doc('meta'));
    // The phone drops its stored tokens when it sees the connection is gone.
    batch.set(db().collection('users').doc(uid), { metaDisconnectedAt: FieldValue.serverTimestamp(), metaDisconnectReason: reason }, { merge: true });
    await batch.commit();
  }
  await ref.delete();
  return uids.length;
}

function statusUrl(code: string): string {
  const project = process.env.GCLOUD_PROJECT ?? 'mpepe-2b4bd';
  return `https://us-central1-${project}.cloudfunctions.net/metaDeletionStatus?code=${encodeURIComponent(code)}`;
}

export const metaDataDeletion = onRequest({ secrets: [metaAppSecret] }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'POST signed_request' });
    return;
  }
  const parsed = parseSignedRequest(String(req.body?.signed_request ?? ''));
  if (!parsed?.user_id) {
    res.status(400).json({ error: 'Invalid signed_request' });
    return;
  }
  const code = crypto.randomBytes(9).toString('base64url');
  const count = await purgeMetaUser(String(parsed.user_id), 'deletion');
  await db().collection('meta_deletions').doc(code).set({
    metaUserIdHash: crypto.createHash('sha256').update(String(parsed.user_id)).digest('hex'),
    accounts: count,
    status: 'completed',
    requestedAt: FieldValue.serverTimestamp(),
    completedAt: FieldValue.serverTimestamp(),
  });
  res.json({ url: statusUrl(code), confirmation_code: code });
});

export const metaDeauthorize = onRequest({ secrets: [metaAppSecret] }, async (req, res) => {
  const parsed = parseSignedRequest(String(req.body?.signed_request ?? ''));
  if (!parsed?.user_id) {
    res.status(400).send('Invalid signed_request');
    return;
  }
  await purgeMetaUser(String(parsed.user_id), 'deauthorize');
  res.status(200).send('ok');
});

export const metaDeletionStatus = onRequest(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  const code = String(req.query.code ?? '').slice(0, 40);
  const snap = code ? await db().collection('meta_deletions').doc(code).get() : null;
  if (!snap?.exists) {
    res.status(404).send(page({ title: 'Request not found', message: 'We couldn’t find a deletion request with this code. Check the link from Facebook, or email privacy@oneova.app.', tone: 'warn' }));
    return;
  }
  const at = snap.get('completedAt')?.toDate?.() as Date | undefined;
  res.status(200).send(
    page({
      title: 'Your data was deleted',
      message:
        `Confirmation code <b>${code}</b>. Oneova removed your Facebook, Instagram and WhatsApp connection data` +
        (at ? ` on ${at.toUTCString()}` : '') +
        '. Your Oneova account itself is not deleted; to delete it, email <b>privacy@oneova.app</b> (see oneova.web.app/deletion).',
      tone: 'ok',
    }),
  );
});
