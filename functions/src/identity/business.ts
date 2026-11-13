/**
 * Verified Business (business identity). One status for the profile, the
 * store portal and the 3D shops: business_identity/{uid}, mirrored to
 * biz_shops/{uid}.verified / verifiedLevel by syncBadges.
 *
 *   app → kybRequirements  what this country usually needs
 *   app → kybStart         opens a check; private folder kyb/{uid}/{sessionId}/
 *   app                    uploads {documentKey}.jpg|png|pdf
 *   app → kybSubmit        details + owners → "review" (+ AI pre-check for the reviewer)
 *   owner → kybOwnerRespond confirms or declines being listed as an owner
 *   admin → kybReview      level 1 (registered) or 2 (verified business) / reject
 *   app → kybDelete        deletes documents and the record, removes the badge
 *   daily kybExpiry        yearly re-check; badge drops when it lapses
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { generateVertexContent } from '../vertexAi';
import { adminAudit, audit, callerUid, cleanUid, db, deleteFolder, notify, requireAdmin, syncBadges } from './common';
import { revokeCredential } from './credentials';
import { BUSINESS_TYPES, BusinessType, CountryRequirements, docsFor, matches, mergeRequirements } from './requirements';

const cc = (v: unknown): string => {
  const s = String(v ?? '').toUpperCase();
  if (!/^[A-Z]{2}$/.test(s)) throw new HttpsError('invalid-argument', 'Choose a country.');
  return s;
};
const btype = (v: unknown): BusinessType => {
  if (!BUSINESS_TYPES.includes(v as BusinessType)) throw new HttpsError('invalid-argument', 'Choose a business type.');
  return v as BusinessType;
};
const text = (v: unknown, max: number) => String(v ?? '').trim().replace(/\s+/g, ' ').slice(0, max);

async function requirementsFor(country: string): Promise<CountryRequirements> {
  const stored = (await db().doc(`kyb_requirements/${country}`).get()).data() as Partial<CountryRequirements> | undefined;
  return mergeRequirements(country, stored);
}

export const kybRequirements = onCall(async (req) => {
  callerUid(req);
  const country = cc(req.data?.country);
  const type = req.data?.businessType ? btype(req.data.businessType) : 'company';
  const r = await requirementsFor(country);
  return { ...r, documents: docsFor(r, type) };
});

export const kybStart = onCall(async (req) => {
  const uid = callerUid(req);
  const country = cc(req.data?.country);
  const businessType = btype(req.data?.businessType);
  const ref = db().doc(`business_identity/${uid}`);
  const cur = (await ref.get()).data();
  if (cur?.status === 'review') return { status: 'review' };
  if (cur?.status === 'verified') return { status: 'verified' };
  const sessionId = cur?.status === 'collecting' && cur.sessionId && cur.country === country ? String(cur.sessionId) : crypto.randomUUID();
  await ref.set({
    uid, status: 'collecting', sessionId, country, businessType, level: 0,
    startedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await audit(uid, 'business.started', 'you', `${country} · ${businessType}`);
  const r = await requirementsFor(country);
  return { status: 'collecting', sessionId, path: `kyb/${uid}/${sessionId}`, requirements: { ...r, documents: docsFor(r, businessType) } };
});

async function uploadedKeys(path: string): Promise<Map<string, string>> {
  const [files] = await getStorage().bucket().getFiles({ prefix: `${path}/` });
  const m = new Map<string, string>();
  for (const f of files) {
    const name = f.name.slice(path.length + 1);
    const stem = name.replace(/\.(jpg|png|pdf)$/, '');
    m.set(stem, name);
  }
  return m;
}

/** Reads the documents for the reviewer. Never decides. Best effort. */
async function aiPreCheck(path: string, files: Map<string, string>, typed: Record<string, string>): Promise<Record<string, unknown> | null> {
  try {
    const bucket = getStorage().bucket();
    const parts: any[] = [{ text: `Typed by the applicant: ${JSON.stringify(typed)}. The files below are business documents, in this order: ${[...files.keys()].join(', ')}.` }];
    for (const [, name] of [...files.entries()].slice(0, 5)) {
      const [buf] = await bucket.file(`${path}/${name}`).download();
      if (buf.length > 7 * 1024 * 1024) continue;
      const mimeType = name.endsWith('.pdf') ? 'application/pdf' : name.endsWith('.png') ? 'image/png' : 'image/jpeg';
      parts.push({ inlineData: { mimeType, data: buf.toString('base64') } });
    }
    const res = await generateVertexContent({
      contents: [{ role: 'user', parts }],
      config: {
        systemInstruction:
          'You help a human reviewer check business registration documents. Reply ONLY with JSON: ' +
          '{"readable":true|false,"legalNameOnDocs":"name as printed or empty","nameMatches":"yes|no|unclear",' +
          '"registrationNumberMatches":"yes|no|unclear","taxIdMatches":"yes|no|unclear","addressRecent":"yes|no|unclear",' +
          '"ownersOnDocs":["names as printed"],"concerns":["short notes, e.g. edited, expired, screenshot, different company"]}. ' +
          'Never guess text you cannot read.',
        responseMimeType: 'application/json',
        temperature: 0,
        maxOutputTokens: 600,
        thinkingConfig: { thinkingBudget: 0 },
      },
    });
    return JSON.parse(res.text ?? '{}');
  } catch (e: any) {
    logger.warn('kyb pre-check failed', e?.message ?? e);
    return null;
  }
}

export const kybSubmit = onCall({ timeoutSeconds: 120, memory: '512MiB' }, async (req) => {
  const uid = callerUid(req);
  const ref = db().doc(`business_identity/${uid}`);
  const cur = (await ref.get()).data();
  const sessionId = String(req.data?.sessionId ?? '');
  if (!cur || cur.status !== 'collecting' || cur.sessionId !== sessionId) throw new HttpsError('failed-precondition', 'Start the business check again.');
  if ((await db().doc(`kyc/${uid}`).get()).get('status') !== 'verified') {
    throw new HttpsError('failed-precondition', 'Verify your own identity first. A business is verified through its owner.');
  }
  const r = await requirementsFor(cur.country);
  const type = cur.businessType as BusinessType;
  const legalName = text(req.data?.legalName, 140);
  const registrationNumber = text(req.data?.registrationNumber, 40).toUpperCase();
  const taxId = text(req.data?.taxId, 40).toUpperCase();
  const address = text(req.data?.address, 240);
  if (legalName.length < 2) throw new HttpsError('invalid-argument', 'Enter the registered business name.');
  if (!matches(r.registrationNumber, registrationNumber)) throw new HttpsError('invalid-argument', `Check the ${r.registrationNumber.label}.`);
  if (!matches(r.taxId, taxId)) throw new HttpsError('invalid-argument', `Check the ${r.taxId.label}.`);
  if (address.length < 5) throw new HttpsError('invalid-argument', 'Enter the registered address.');

  const path = `kyb/${uid}/${sessionId}`;
  const files = await uploadedKeys(path);
  const missing = docsFor(r, type).filter((d) => d.required && !files.has(d.key)).map((d) => d.label);
  if (missing.length) throw new HttpsError('failed-precondition', `Still needed: ${missing.join(', ')}.`);

  // Owners: Oneova usernames + share. Each one confirms and verifies themselves.
  const rawOwners: any[] = Array.isArray(req.data?.owners) ? req.data.owners.slice(0, 10) : [];
  const owners: { uid: string; username: string; share: number }[] = [];
  for (const o of rawOwners) {
    const username = text(o?.username, 40).replace(/^@/, '').toLowerCase();
    const share = Math.min(Math.max(Number(o?.share) || 0, 0), 100);
    if (!username) continue;
    const q = await db().collection('users').where('username', '==', username).limit(1).get();
    if (q.empty) throw new HttpsError('not-found', `No Oneova account @${username}.`);
    const ownerUid = q.docs[0].id;
    if (!owners.some((x) => x.uid === ownerUid)) owners.push({ uid: ownerUid, username, share });
  }

  const batch = db().batch();
  const existing = await ref.collection('owners').get();
  existing.docs.forEach((d) => batch.delete(d.ref));
  for (const o of owners) {
    const self = o.uid === uid;
    batch.set(ref.collection('owners').doc(o.uid), {
      ownerUid: o.uid, username: o.username, share: o.share, status: self ? 'confirmed' : 'pending', idVerified: self, updatedAt: FieldValue.serverTimestamp(),
    });
    if (!self) {
      batch.set(db().doc(`identity/${o.uid}/ownerInvites/${uid}`), {
        bizUid: uid, legalName, country: cur.country, share: o.share, status: 'pending', createdAt: FieldValue.serverTimestamp(),
      });
    }
  }
  batch.set(ref, {
    status: 'review', legalName, registrationNumber, taxIdLast4: taxId.slice(-4), taxId, address,
    files: [...files.values()], ownerCount: owners.length, submittedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await batch.commit();
  for (const o of owners.filter((x) => x.uid !== uid)) {
    await notify(o.uid, `kyb_owner_${uid}_${o.uid}`, 'Confirm business ownership', `${legalName} listed you as an owner. Confirm it in Oneova ID.`, '/id');
  }
  await audit(uid, 'business.submitted', 'you', `${files.size} documents, ${owners.length} owners`);
  const ai = await aiPreCheck(path, files, { legalName, registrationNumber, taxId, address });
  if (ai) await ref.set({ aiCheck: ai, aiCheckedAt: FieldValue.serverTimestamp() }, { merge: true });
  return { status: 'review' };
});

export const kybOwnerRespond = onCall(async (req) => {
  const uid = callerUid(req);
  const bizUid = cleanUid(req.data?.bizUid);
  const accept = req.data?.accept === true;
  const invite = db().doc(`identity/${uid}/ownerInvites/${bizUid}`);
  if (!(await invite.get()).exists) throw new HttpsError('not-found', 'No such request.');
  const idVerified = (await db().doc(`kyc/${uid}`).get()).get('status') === 'verified';
  await invite.update({ status: accept ? 'confirmed' : 'declined', respondedAt: FieldValue.serverTimestamp() });
  await db().doc(`business_identity/${bizUid}/owners/${uid}`).set({
    status: accept ? 'confirmed' : 'declined', idVerified: accept && idVerified, updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  await audit(uid, accept ? 'business.owner_confirmed' : 'business.owner_declined', 'you');
  return { ok: true, idVerified };
});

export const kybReview = onCall(async (req) => {
  const admin = await requireAdmin(req);
  const uid = cleanUid(req.data?.uid);
  const ref = db().doc(`business_identity/${uid}`);
  const b = (await ref.get()).data();
  if (!b || b.status !== 'review') throw new HttpsError('failed-precondition', 'Nothing to review for this business.');
  if (req.data?.approve === true) {
    const level = Number(req.data?.level) === 2 ? 2 : 1;
    if (level === 2) {
      // Refresh each owner's ID status, then require all confirmed + verified.
      const owners = await ref.collection('owners').get();
      for (const o of owners.docs) {
        const v = (await db().doc(`kyc/${o.id}`).get()).get('status') === 'verified';
        if (o.get('status') === 'confirmed' && o.get('idVerified') !== v) await o.ref.update({ idVerified: v });
        if (o.get('status') !== 'confirmed' || !v) throw new HttpsError('failed-precondition', `@${o.get('username')} hasn’t confirmed or isn’t ID-verified yet. Approve as level 1, or wait.`);
      }
    }
    const legalName = text(req.data?.legalName ?? b.legalName, 140);
    const expiresAt = Timestamp.fromDate(new Date(Date.now() + 365 * 86400000));
    await ref.set({
      status: 'verified', level, legalName, reviewedBy: admin, verifiedAt: FieldValue.serverTimestamp(), expiresAt,
      updatedAt: FieldValue.serverTimestamp(), rejectReason: FieldValue.delete(),
    }, { merge: true });
    await syncBadges(uid);
    await audit(uid, 'business.verified', 'reviewer', level === 2 ? 'Verified Business' : 'Registered business');
    await adminAudit(admin, 'business.approve', uid, '', { level });
    await notify(uid, `kyb_ok_${uid}`, level === 2 ? 'Your business is verified ✅' : 'Your business is registered ✅',
      'The badge now shows on your profile and your store.', '/id/business');
  } else {
    const reason = text(req.data?.reason ?? 'We couldn’t confirm your business documents.', 240);
    await ref.set({ status: 'rejected', rejectReason: reason, reviewedBy: admin, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await syncBadges(uid);
    await audit(uid, 'business.rejected', 'reviewer', reason);
    await adminAudit(admin, 'business.reject', uid, reason);
    await notify(uid, `kyb_no_${uid}_${Date.now()}`, 'Business check needs another try', reason, '/id/business');
  }
  return { ok: true };
});

export const kybDelete = onCall({ timeoutSeconds: 120 }, async (req) => {
  const uid = callerUid(req);
  if (req.data?.confirm !== true) throw new HttpsError('failed-precondition', 'Confirm first.');
  const removed = await deleteFolder(`kyb/${uid}/`);
  await revokeCredential(uid, 'business');
  const ref = db().doc(`business_identity/${uid}`);
  const owners = await ref.collection('owners').get();
  const batch = db().batch();
  owners.docs.forEach((o) => {
    batch.delete(o.ref);
    if (o.id !== uid) batch.delete(db().doc(`identity/${o.id}/ownerInvites/${uid}`));
  });
  batch.delete(ref);
  await batch.commit();
  await syncBadges(uid);
  await audit(uid, 'business.deleted', 'you', `Business data deleted (${removed} documents)`);
  return { ok: true, documentsDeleted: removed };
});

/** Admin: save a country's requirements (merged over the built-in ones). */
export const kybRequirementsSave = onCall(async (req) => {
  const admin = await requireAdmin(req);
  const country = req.data?.country === 'default' ? 'default' : cc(req.data?.country);
  const r = req.data?.requirements;
  if (!r || typeof r !== 'object') throw new HttpsError('invalid-argument', 'Missing requirements.');
  for (const f of [r.registrationNumber, r.taxId].filter(Boolean)) {
    try { new RegExp(String(f.pattern)); } catch { throw new HttpsError('invalid-argument', `Bad pattern: ${f.pattern}`); }
  }
  await db().doc(`kyb_requirements/${country}`).set({ ...r, updatedBy: admin, updatedAt: FieldValue.serverTimestamp() });
  await adminAudit(admin, 'kyb_requirements.save', country);
  return { ok: true };
});

/** Yearly re-check: the badge drops when a verification lapses. */
export const kybExpiry = onSchedule({ schedule: 'every day 03:10', timeZone: 'Africa/Nairobi' }, async () => {
  const due = await db().collection('business_identity').where('expiresAt', '<', Timestamp.now()).limit(300).get();
  for (const d of due.docs.filter((x) => x.get('status') === 'verified')) {
    await d.ref.set({ status: 'expired', expiredReason: 'Yearly re-check due.', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    await revokeCredential(d.id, 'business');
    await syncBadges(d.id);
    await audit(d.id, 'business.expired', 'system', 'Yearly re-check due');
    await notify(d.id, `kyb_exp_${d.id}_${Date.now()}`, 'Renew your business verification', 'It’s been a year. Upload fresh documents to keep the badge.', '/id/business');
  }
});

/** Retention: ID photos and business documents are deleted 30 days after a decision. */
export const idRetention = onSchedule({ schedule: 'every day 03:40', timeZone: 'Africa/Nairobi', timeoutSeconds: 540 }, async () => {
  const cutoff = Date.now() - 30 * 86400000;
  for (const [col, folder] of [['kyc', 'kyc'], ['business_identity', 'kyb']] as const) {
    for (const status of ['verified', 'rejected']) {
      const snap = await db().collection(col).where('status', '==', status).limit(300).get();
      for (const d of snap.docs) {
        if (d.get('filesPurgedAt')) continue;
        const decided = (d.get('updatedAt') as Timestamp | undefined)?.toMillis() ?? Date.now();
        if (decided > cutoff) continue;
        const n = await deleteFolder(`${folder}/${d.id}/`);
        await d.ref.set({ filesPurgedAt: FieldValue.serverTimestamp() }, { merge: true });
        if (n) await audit(d.id, `${col === 'kyc' ? 'id' : 'business'}.files_deleted`, 'system', `${n} files deleted after 30 days`);
      }
    }
  }
});

/** Admin: lists, then fetches, the files of a check for review. Every view is logged. */
export const idReviewFiles = onCall({ memory: '512MiB' }, async (req) => {
  const admin = await requireAdmin(req);
  const uid = cleanUid(req.data?.uid);
  const kind = req.data?.kind === 'business' ? 'business' : 'person';
  const doc = (await db().doc(kind === 'person' ? `kyc/${uid}` : `business_identity/${uid}`).get()).data();
  if (!doc?.sessionId) throw new HttpsError('not-found', 'No files.');
  const path = `${kind === 'person' ? 'kyc' : 'kyb'}/${uid}/${doc.sessionId}`;
  const name = req.data?.name ? String(req.data.name) : null;
  if (!name) {
    const [files] = await getStorage().bucket().getFiles({ prefix: `${path}/` });
    return { files: files.map((f) => f.name.slice(path.length + 1)) };
  }
  if (!/^[a-z0-9_]{2,40}\.(jpg|png|pdf)$/.test(name)) throw new HttpsError('invalid-argument', 'Bad file.');
  const [buf] = await getStorage().bucket().file(`${path}/${name}`).download();
  await adminAudit(admin, `${kind === 'person' ? 'kyc' : 'business'}.view_file`, uid, '', { name });
  const mime = name.endsWith('.pdf') ? 'application/pdf' : name.endsWith('.png') ? 'image/png' : 'image/jpeg';
  return { name, mime, b64: buf.toString('base64') };
});
