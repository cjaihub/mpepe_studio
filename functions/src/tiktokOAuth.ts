/**
 * TikTok Login Kit code exchange, server side, so the client secret never
 * ships in the app.
 *
 *   tiktokExchangeCode  callable: { code } → TikTok token response
 *                       (access_token, refresh_token, open_id, expires_in…).
 *
 * Setup:
 *   firebase functions:secrets:set TIKTOK_CLIENT_SECRET --project mpepe-2b4bd
 *   TIKTOK_CLIENT_KEY / TIKTOK_REDIRECT_URI live in functions/.env.mpepe-2b4bd.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';

const tiktokClientSecret = defineSecret('TIKTOK_CLIENT_SECRET');
const tiktokClientKey = defineString('TIKTOK_CLIENT_KEY');
const tiktokRedirectUri = defineString('TIKTOK_REDIRECT_URI');

export const tiktokExchangeCode = onCall({ secrets: [tiktokClientSecret] }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const code = String((request.data as Record<string, unknown> | undefined)?.code ?? '');
  if (!code || code.length > 2048) throw new HttpsError('invalid-argument', 'Missing authorization code.');

  const res = await fetch('https://open.tiktokapis.com/v2/oauth/token/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_key: tiktokClientKey.value(),
      client_secret: tiktokClientSecret.value(),
      code,
      grant_type: 'authorization_code',
      redirect_uri: tiktokRedirectUri.value(),
    }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok || !body.access_token) {
    logger.warn('tiktokExchangeCode failed', { status: res.status, error: body.error });
    throw new HttpsError('failed-precondition', String(body.error_description ?? body.error ?? 'Token exchange failed'));
  }
  return body;
});
