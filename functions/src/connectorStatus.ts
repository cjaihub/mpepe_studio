/**
 * Which platform connections can actually work right now, so the app shows
 * "Waiting for setup" instead of starting a sign-in that is bound to fail.
 *
 * A platform is ready when the server has what its connect flow needs:
 *  - Facebook / Instagram / WhatsApp: META_APP_ID + META_REDIRECT_URI params and
 *    the META_APP_SECRET secret (metaExchangeCode).
 *  - TikTok: TIKTOK_CLIENT_KEY + TIKTOK_REDIRECT_URI params and the
 *    TIKTOK_CLIENT_SECRET secret (tiktokExchangeCode).
 *  - Gmail (server-kept connection): GOOGLE_WEB_CLIENT_ID, and the optional
 *    secrets GOOGLE_OAUTH_CLIENT_SECRET and GMAIL_TOKEN_KEY (gmailConnect).
 *  - YouTube: Google sign-in on the phone; nothing server-side.
 *
 * An admin can also hold a platform back (e.g. while it waits for the
 * platform's app review, or when a secret is known to be stale) with
 * `app_config/connectors.{platform} = { ready: false, note: '...' }`.
 * Only booleans and plain notes are returned; never secret values.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getFirestore } from 'firebase-admin/firestore';
import { optionalSecret } from './optionalSecrets';

type Status = { ready: boolean; note?: string };

const has = (name: string) => (process.env[name] ?? '').trim().length > 0;

export const connectorStatus = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');

  const [metaSecret, tiktokSecret, googleSecret, gmailKey, overrides] = await Promise.all([
    optionalSecret('META_APP_SECRET'),
    optionalSecret('TIKTOK_CLIENT_SECRET'),
    optionalSecret('GOOGLE_OAUTH_CLIENT_SECRET'),
    optionalSecret('GMAIL_TOKEN_KEY'),
    getFirestore().collection('app_config').doc('connectors').get().then((d) => d.data() ?? {}).catch(() => ({})),
  ]);

  const waiting = 'This connection is being set up. Check back soon.';
  const meta: Status = has('META_APP_ID') && has('META_REDIRECT_URI') && metaSecret
    ? { ready: true }
    : { ready: false, note: waiting };
  const status: Record<string, Status> = {
    facebook: meta,
    instagram: meta,
    whatsapp: meta,
    tiktok: has('TIKTOK_CLIENT_KEY') && has('TIKTOK_REDIRECT_URI') && tiktokSecret ? { ready: true } : { ready: false, note: waiting },
    gmail: has('GOOGLE_WEB_CLIENT_ID') && googleSecret && gmailKey ? { ready: true } : { ready: false, note: waiting },
    youtube: { ready: true },
  };

  for (const [platform, o] of Object.entries(overrides as Record<string, unknown>)) {
    const v = o as { ready?: unknown; note?: unknown };
    if (status[platform] && v && v.ready === false) {
      status[platform] = { ready: false, note: typeof v.note === 'string' && v.note ? v.note.slice(0, 160) : waiting };
    }
  }
  return { platforms: status };
});
