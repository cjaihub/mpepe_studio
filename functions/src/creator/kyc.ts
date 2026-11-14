/**
 * Identity verification (KYC) before anyone is paid out: Oneova's own check.
 *
 *   app → kycStart     opens a check; returns the private Storage folder
 *                      `kyc/{uid}/{sessionId}/` for the photos
 *   app                uploads id_front.jpg, id_back.jpg (optional), selfie.jpg
 *                      (only the owner can write there; nobody can read them
 *                      from the app — see storage.rules)
 *   app → kycSubmit    status "review"; an AI pre-check (Vertex AI) reads the
 *                      ID and compares the faces for the reviewer. It never
 *                      approves anyone on its own.
 *   admin → kycReview  verified (with the name on the ID) or rejected
 *   app → kycRefresh   current status
 *
 * `kyc/{uid}` (server-written) keeps the status, the verified name, country
 * and document type, and the pre-check summary for the reviewer.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { generateVertexContent } from '../vertexAi';
import { onPersonalRejected, onPersonalSubmitted, onPersonalVerified } from '../identity/personal';
import { cleanCountrySignals, countryMismatch } from './kycSignals';
import { claimId, idHash, lookupId, normalizeIdNumber } from './kycIdentity';
import { optionalSecret } from '../optionalSecrets';

const db = () => getFirestore();
const DOC_TYPES = ['passport', 'id_card', 'driving_license'];

function me(req: CallableRequest): string {
  const id = req.auth?.uid;
  if (!id) throw new HttpsError('unauthenticated', 'Sign in first.');
  return id;
}

export const kycStart = onCall(async (req) => {
  const uid = me(req);
  const current = (await db().doc(`kyc/${uid}`).get()).data();
  if (current?.status === 'verified') return { status: 'verified' };
  if (current?.status === 'review') return { status: 'review' };
  // Reuse an open check so a second tap continues it.
  const sessionId = current?.status === 'collecting' && current.sessionId ? String(current.sessionId) : crypto.randomUUID();
  await db().doc(`kyc/${uid}`).set({
    uid, provider: 'oneova', sessionId, status: 'collecting',
    startedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { status: 'collecting', sessionId, path: `kyc/${uid}/${sessionId}` };
});

/** Reads the ID and compares the faces for the reviewer. Best effort. */
async function aiPreCheck(path: string, hasBack: boolean, live: string[] = []): Promise<Record<string, unknown> | null> {
  try {
    const bucket = getStorage().bucket();
    const load = async (name: string) => (await bucket.file(`${path}/${name}`).download())[0].toString('base64');
    const [front, selfie, back] = await Promise.all([load('id_front.jpg'), load('selfie.jpg'), hasBack ? load('id_back.jpg') : Promise.resolve(null)]);
    const liveFrames = await Promise.all(live.map(load));
    const res = await generateVertexContent({
      contents: [{
        role: 'user',
        parts: [
          { text: 'Image 1 is the front of an identity document. Image 2 is a selfie from a live camera check.' + (back ? ' Image 3 is the back of the document.' : '') +
              (liveFrames.length ? ` The last ${liveFrames.length} images are frames from the same live check with the head turned.` : '') },
          { inlineData: { mimeType: 'image/jpeg', data: front } },
          { inlineData: { mimeType: 'image/jpeg', data: selfie } },
          ...(back ? [{ inlineData: { mimeType: 'image/jpeg', data: back } }] : []),
          ...liveFrames.map((d) => ({ inlineData: { mimeType: 'image/jpeg', data: d } })),
        ],
      }],
      config: {
        systemInstruction:
          'You help a human reviewer check identity documents. Reply ONLY with JSON: ' +
          '{"documentType":"passport|id_card|driving_license|other|unreadable","fullName":"name as printed or empty",' +
          '"country":"ISO-3166 alpha-2 of the issuing country or empty","expired":true|false|null,' +
          '"documentNumber":"the document number exactly as printed or empty",' +
          '"faceMatch":"likely|unlikely|unclear","liveness":"real|spoof_suspected|unclear",' +
          '"readable":true|false,"concerns":["short notes, e.g. screen photo, printed photo, mask, cropped, edited, different people"]}. ' +
          'liveness: are the selfie and turned-head frames a real 3D person (not a photo of a screen, a print or a mask) and the same person? ' +
          'Never guess a name or number you cannot read.',
        responseMimeType: 'application/json',
        temperature: 0,
        maxOutputTokens: 500,
        thinkingConfig: { thinkingBudget: 0 },
      },
    });
    return JSON.parse(res.text ?? '{}');
  } catch (e: any) {
    logger.warn('kyc pre-check failed', e?.message ?? e);
    return null;
  }
}

export const kycSubmit = onCall({ timeoutSeconds: 120, memory: '512MiB' }, async (req) => {
  const uid = me(req);
  const current = (await db().doc(`kyc/${uid}`).get()).data();
  const sessionId = String(req.data?.sessionId ?? '');
  if (!current || current.status !== 'collecting' || current.sessionId !== sessionId) {
    throw new HttpsError('failed-precondition', 'Start the identity check again.');
  }
  const documentType = DOC_TYPES.includes(String(req.data?.documentType)) ? String(req.data.documentType) : null;
  const country = typeof req.data?.country === 'string' && /^[A-Za-z]{2}$/.test(req.data.country) ? req.data.country.toUpperCase() : null;
  const fullName = String(req.data?.fullName ?? '').trim().replace(/\s+/g, ' ').slice(0, 120);
  if (!documentType || !country || fullName.length < 3) throw new HttpsError('invalid-argument', 'Fill in your name, country and ID type.');

  const path = `kyc/${uid}/${sessionId}`;
  const bucket = getStorage().bucket();
  const [[front], [selfie], [back]] = await Promise.all([
    bucket.file(`${path}/id_front.jpg`).exists(), bucket.file(`${path}/selfie.jpg`).exists(), bucket.file(`${path}/id_back.jpg`).exists(),
  ]);
  if (!front || !selfie) throw new HttpsError('failed-precondition', 'Add a photo of your ID and a selfie.');
  const [[left], [right]] = await Promise.all([bucket.file(`${path}/live_left.jpg`).exists(), bucket.file(`${path}/live_right.jpg`).exists()]);
  const live = [...(left ? ['live_left.jpg'] : []), ...(right ? ['live_right.jpg'] : [])];

  // What the phone's live check saw (a hint for the reviewer; the AI and the
  // reviewer check the frames themselves).
  const lv = req.data?.liveness;
  const liveness = lv && typeof lv === 'object' ? {
    passed: lv.passed === true,
    actions: Array.isArray(lv.actions) ? lv.actions.filter((a: unknown) => typeof a === 'string' && /^[a-z_]{2,20}$/.test(a)).slice(0, 6) : [],
    ms: typeof lv.ms === 'number' && lv.ms > 0 && lv.ms < 600000 ? Math.round(lv.ms) : null,
    biometric: lv.biometric === true,
  } : null;

  const countrySignals = cleanCountrySignals(req.data?.countrySignals);
  await db().doc(`kyc/${uid}`).set({
    status: 'review', documentType, country, submittedName: fullName, hasBack: back,
    countrySignals, countryMismatch: countryMismatch(country, countrySignals),
    liveness, liveFrames: live.length,
    submittedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await onPersonalSubmitted(uid);
  const ai = await aiPreCheck(path, back, live);
  if (ai) {
    // One ID, one person: keep only a keyed hash of the number, never the number.
    const number = normalizeIdNumber(ai.documentNumber);
    delete ai.documentNumber;
    let identity: Record<string, unknown> = {};
    const pepper = number ? await optionalSecret('KYC_ID_PEPPER') : null;
    if (number && pepper) {
      const hash = idHash(pepper, country, documentType, number);
      const found = await lookupId(hash, uid);
      identity = {
        idHash: hash,
        idStatus: found.status,
        duplicateOf: found.status === 'duplicate' ? found.primaryUid ?? null : null,
      };
    }
    await db().doc(`kyc/${uid}`).set({ aiCheck: ai, aiCheckedAt: FieldValue.serverTimestamp(), ...identity }, { merge: true });
    if (identity.idStatus === 'duplicate') {
      return { status: 'review', duplicate: true, message: 'This ID is already verified on another Oneova account. Sign in there and link this account (Oneova ID → Linked accounts), then try again.' };
    }
  }
  return { status: 'review' };
});

export const kycRefresh = onCall(async (req) => {
  const uid = me(req);
  const k = (await db().doc(`kyc/${uid}`).get()).data();
  return { status: k?.status ?? 'none', reason: k?.rejectReason ?? null, verifiedName: k?.verifiedName ?? null };
});

/** Admin decision (from the admin dashboard). */
export const kycReview = onCall(async (req) => {
  const admin = me(req);
  if ((await db().doc(`users/${admin}`).get()).get('role') !== 'admin') throw new HttpsError('permission-denied', 'Admins only.');
  const uid = String(req.data?.uid ?? '');
  if (!uid || uid.includes('/')) throw new HttpsError('invalid-argument', 'Missing user.');
  const k = (await db().doc(`kyc/${uid}`).get()).data();
  if (!k || k.status !== 'review') throw new HttpsError('failed-precondition', 'Nothing to review for this user.');
  if (req.data?.approve === true) {
    const name = String(req.data?.verifiedName ?? k.submittedName ?? '').trim().slice(0, 120);
    if (name.length < 3) throw new HttpsError('invalid-argument', 'Enter the name exactly as on the ID.');
    // One ID, one person: a duplicate can't be approved unless the owner linked this account.
    if (typeof k.idHash === 'string') await claimId(k.idHash, uid);
    await db().doc(`kyc/${uid}`).set({
      status: 'verified', verifiedName: name, country: String(req.data?.country ?? k.country), documentType: k.documentType,
      reviewedBy: admin, verifiedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await db().collection('notifications').doc(`kyc_ok_${uid}`).set({
      userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
      title: 'You’re verified ✅', body: 'You can now withdraw your earnings.', deepLink: '/wallet/withdraw',
      isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
    await onPersonalVerified(uid, admin);
  } else {
    const reason = String(req.data?.reason ?? 'We couldn’t confirm your ID. Please try again with clear photos.').slice(0, 200);
    await db().doc(`kyc/${uid}`).set({
      status: 'rejected', rejectReason: reason, reviewedBy: admin, updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    await db().collection('notifications').doc(`kyc_no_${uid}_${Date.now()}`).set({
      userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'payout',
      title: 'Identity check needs another try', body: reason, deepLink: '/wallet/verify',
      isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
    await onPersonalRejected(uid, reason);
  }
  return { ok: true };
});
