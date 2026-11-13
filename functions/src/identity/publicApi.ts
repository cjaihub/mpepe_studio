/**
 * Public, account-free checks used by oneova.web.app/verify (and anyone):
 *   GET /idPublic/jwks             the issuer's public key
 *   GET /idPublic/status?c=&s=     is this credential / share still valid?
 * Returns no personal data; the claims travel only inside the signed token.
 */
import { onRequest } from 'firebase-functions/v2/https';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { db } from './common';
import { publicJwks, signingJwk } from './credentials';

const ID = /^[0-9a-f-]{36}$/;

export const idPublic = onRequest({ secrets: [signingJwk], cors: true, memory: '256MiB' }, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  const path = req.path.replace(/\/+$/, '');
  if (req.method !== 'GET') { res.status(405).json({ error: 'GET only' }); return; }
  if (path.endsWith('/jwks')) {
    res.set('Cache-Control', 'public, max-age=3600');
    res.json(publicJwks());
    return;
  }
  if (path.endsWith('/status')) {
    const c = String(req.query.c ?? '');
    const s = String(req.query.s ?? '');
    if (!ID.test(c)) { res.status(400).json({ error: 'bad id' }); return; }
    const st = await db().doc(`identityStatus/${c}`).get();
    if (!st.exists) { res.json({ credential: 'unknown' }); return; }
    const exp = (st.get('expiresAt') as Timestamp | undefined)?.toMillis() ?? 0;
    const credential = st.get('status') === 'valid' && exp > Date.now() ? 'valid' : st.get('status') === 'valid' ? 'expired' : String(st.get('status'));
    let share: string | undefined;
    if (ID.test(s)) {
      const ref = db().doc(`identity/${st.get('uid')}/shares/${s}`);
      const sh = await ref.get();
      if (!sh.exists || sh.get('credentialId') !== c) share = 'unknown';
      else if (sh.get('revokedAt')) share = 'revoked';
      else if ((sh.get('expiresAt') as Timestamp).toMillis() < Date.now()) share = 'expired';
      else {
        share = 'valid';
        await ref.update({ views: FieldValue.increment(1), lastViewedAt: FieldValue.serverTimestamp() });
      }
    }
    res.json({ credential, share, kind: st.get('kind') });
    return;
  }
  res.status(404).json({ error: 'not found' });
});
