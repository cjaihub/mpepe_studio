/**
 * Signed identity credentials.
 *
 * - The long-lived credential is an SD-JWT VC (every claim is a separate
 *   salted disclosure, so the holder can later reveal only some of them).
 * - A "share" is a short-lived JWT holding only the claims the person chose,
 *   with its own expiry; it is what the QR code on the phone carries.
 * - Anyone can check both with the public key from `idPublic/jwks` and the
 *   revocation status from `idPublic/status` — no account needed.
 *
 * Signing key: ES256 (P-256) private JWK in Secret Manager as
 * IDENTITY_SIGNING_JWK (create it with tools/identity/make_signing_key.cjs).
 */
import * as crypto from 'crypto';
import { defineSecret } from 'firebase-functions/params';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from './common';

export const signingJwk = defineSecret('IDENTITY_SIGNING_JWK');
export const ISSUER = 'https://oneova.web.app';
export const VERIFY_URL = 'https://oneova.web.app/verify';

export type CredentialKind = 'person' | 'business';

const b64u = (b: Buffer | string) => Buffer.from(b).toString('base64url');

function key(): { priv: crypto.KeyObject; pub: Record<string, unknown>; kid: string } {
  const jwk = JSON.parse(signingJwk.value());
  const priv = crypto.createPrivateKey({ key: jwk, format: 'jwk' });
  const pub = { kty: 'EC', crv: 'P-256', x: jwk.x, y: jwk.y };
  // RFC 7638 thumbprint as key id.
  const kid = b64u(crypto.createHash('sha256').update(JSON.stringify({ crv: 'P-256', kty: 'EC', x: jwk.x, y: jwk.y })).digest());
  return { priv, pub, kid };
}

export function publicJwks(): { keys: Record<string, unknown>[] } {
  const { pub, kid } = key();
  return { keys: [{ ...pub, kid, alg: 'ES256', use: 'sig' }] };
}

function sign(header: Record<string, unknown>, payload: Record<string, unknown>): string {
  const { priv, kid } = key();
  const input = `${b64u(JSON.stringify({ ...header, alg: 'ES256', kid }))}.${b64u(JSON.stringify(payload))}`;
  const sig = crypto.sign('sha256', Buffer.from(input), { key: priv, dsaEncoding: 'ieee-p1363' });
  return `${input}.${b64u(sig)}`;
}

/** Issues (or re-issues) the holder's SD-JWT VC and marks it valid. */
export async function issueCredential(uid: string, kind: CredentialKind, claims: Record<string, string | number | boolean>, years: number): Promise<{ id: string; token: string; expiresAt: Date }> {
  const id = crypto.randomUUID();
  const now = Math.floor(Date.now() / 1000);
  const exp = now + Math.round(years * 365.25 * 86400);
  const disclosures: string[] = [];
  const digests: string[] = [];
  for (const [name, value] of Object.entries(claims)) {
    const d = b64u(JSON.stringify([b64u(crypto.randomBytes(16)), name, value]));
    disclosures.push(d);
    digests.push(b64u(crypto.createHash('sha256').update(d).digest()));
  }
  digests.sort();
  const jwt = sign({ typ: 'dc+sd-jwt' }, {
    iss: ISSUER, iat: now, nbf: now, exp, jti: id,
    vct: `${ISSUER}/id/vct/${kind}/v1`,
    _sd_alg: 'sha-256', _sd: digests,
    status: { uri: `${ISSUER}/verify`, id },
  });
  const token = `${jwt}~${disclosures.join('~')}~`;
  const expiresAt = new Date(exp * 1000);
  const refPath = kind === 'person' ? `identity/${uid}` : `business_identity/${uid}`;
  const prev = (await db().doc(refPath).get()).get('credentialId');
  const batch = db().batch();
  if (prev) batch.set(db().doc(`identityStatus/${prev}`), { status: 'replaced', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  batch.set(db().doc(`identityStatus/${id}`), { uid, kind, status: 'valid', issuedAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromDate(expiresAt) });
  batch.set(db().doc(refPath), { credentialId: id, credentialIssuedAt: FieldValue.serverTimestamp(), credentialExpiresAt: Timestamp.fromDate(expiresAt) }, { merge: true });
  await batch.commit();
  return { id, token, expiresAt };
}

export async function revokeCredential(uid: string, kind: CredentialKind): Promise<void> {
  const refPath = kind === 'person' ? `identity/${uid}` : `business_identity/${uid}`;
  const id = (await db().doc(refPath).get()).get('credentialId');
  if (id) await db().doc(`identityStatus/${id}`).set({ status: 'revoked', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const shares = await db().collection(`identity/${uid}/shares`).where('kind', '==', kind).where('revokedAt', '==', null).get();
  const batch = db().batch();
  shares.docs.forEach((d) => batch.update(d.ref, { revokedAt: FieldValue.serverTimestamp() }));
  await batch.commit();
}

/** A short-lived token with only the chosen claims; the QR code carries it. */
export function signShare(shareId: string, credentialId: string, kind: CredentialKind, claims: Record<string, unknown>, ttlSeconds: number): string {
  const now = Math.floor(Date.now() / 1000);
  return sign({ typ: 'oneova-share+jwt' }, {
    iss: ISSUER, iat: now, exp: now + ttlSeconds, jti: shareId, cred: credentialId, kind, claims,
  });
}
