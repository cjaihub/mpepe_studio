/**
 * Ova Guard — background content monitor + protected lookups.
 *
 * Triggers (cheap first: heuristics → Web Risk only for links → Vertex
 * Flash-Lite only for texts the heuristics already flagged, cached, with a
 * daily budget; see reputation.ts):
 *   guardScanPostComment / guardScanContentComment   new comments
 *   guardOnProfileWrite                              bio / website / name
 *       changes, profile-change bursts, impersonation of verified names,
 *       contact index + (opt-in) moving email/phone off the public profile.
 *   scanChatMessage()                                called by guardOnMessage
 *       (security.ts) for messages the server can read (not E2E).
 * Callables:
 *   guardCheckLinks      link reputation for the app (E2E chats send only the
 *                        links, never the message).
 *   guardReverseAction   admin undo of any automatic action.
 *   accountLookup        sign-in "is there an account for this number/email"
 *                        without reading other people's profiles.
 *   guardBackfillContacts admin, one-off: fills contact_index (and, when
 *                        GUARD_SPLIT_PRIVATE_FIELDS=true, moves the fields).
 * Schedule:
 *   guardSweep           every 30 min: lifts expired restrictions.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp, DocumentReference } from 'firebase-admin/firestore';
import { analyzeText, analyzeUrl, extractUrls, skeleton } from './linkSafety';
import { TextVerdict, checkLinks, checkText } from './reputation';
import { recentActions, reverseAction, takeAction } from './actions';
import { callerIp, contactKey, limit, requireAccount, requireAdmin, uidForEmail, uidForPhone } from './protect';
import { recordSecurityEvent } from '../security';

const db = () => getFirestore();

/** What the app shows on a message, comment or profile (no message text). */
function safetyField(v: TextVerdict) {
  return {
    verdict: v.verdict,
    reasons: v.reasons.slice(0, 4),
    blockedLinks: v.links.filter((l) => l.verdict === 'dangerous').map((l) => l.url).slice(0, 5),
    categories: v.categories,
    by: 'ova_guard',
    checkedAt: FieldValue.serverTimestamp(),
  };
}

/** Repeat offenders: 3+ dangerous posts in a day → pause + human review. */
async function escalateRepeats(uid: string, scope: 'messaging' | 'comments', source: string, reason: string, targetPath: string) {
  if ((await recentActions(uid, source, 86400000)) < 3) return;
  await takeAction({ uid, action: 'rate_limit', scope, durationMs: 6 * 3600000, reason: `Several dangerous links were blocked: ${reason}`, source });
  await takeAction({ uid, action: 'escalate_admin', reason: `Repeated dangerous links (${scope})`, source, targetPath });
}

// ─────────────── Chat messages (called by guardOnMessage) ───────────────

export async function scanChatMessage(ref: DocumentReference, data: Record<string, unknown>): Promise<void> {
  if (data.isEncrypted === true || data.mediaEncrypted === true) return; // E2E: the app checks links itself
  const text = typeof data.text === 'string' ? data.text : '';
  const senderId = String(data.senderId ?? '');
  if (!text || !senderId) return;
  const quick = analyzeText(text);
  if (!quick.links.length && quick.points < 25) return;
  const v = await checkText(text);
  if (v.verdict === 'safe') return;
  await ref.set({ safety: safetyField(v) }, { merge: true });
  if (v.verdict === 'dangerous') {
    const source = 'scan:chat';
    await takeAction({ uid: senderId, action: 'notify_user', source, reason: `A link you sent was blocked: ${v.reasons[0] ?? 'it is on a list of dangerous sites'}. If you didn’t send it, secure your account.`, notifyTitle: 'Dangerous link blocked' });
    await recordSecurityEvent(senderId, 'phishing_sent', { details: { where: 'chat', reasons: v.reasons } });
    await escalateRepeats(senderId, 'messaging', source, v.reasons[0] ?? '', ref.path);
  }
}

// ─────────────── Comments ───────────────

async function scanComment(ref: DocumentReference, data: Record<string, unknown> | undefined) {
  if (!data || data.type === 'gif') return;
  const text = typeof data.content === 'string' ? data.content : '';
  const authorId = String(data.authorId ?? '');
  if (!text || !authorId) return;
  const quick = analyzeText(text);
  if (!quick.links.length && quick.points < 25) return;
  const v = await checkText(text);
  if (v.verdict === 'safe') return;
  await ref.set({ safety: safetyField(v) }, { merge: true });
  if (v.verdict === 'dangerous') {
    const source = 'scan:comment';
    const reason = v.reasons[0] ?? 'It contains a dangerous link';
    await takeAction({ uid: authorId, action: 'hide_content', targetPath: ref.path, source, reason: `Comment hidden until reviewed: ${reason}` });
    await recordSecurityEvent(authorId, 'phishing_sent', { details: { where: 'comment', reasons: v.reasons } });
    await escalateRepeats(authorId, 'comments', source, reason, ref.path);
  }
}

export const guardScanPostComment = onDocumentCreated('posts/{postId}/comments/{commentId}', (e) =>
  e.data ? scanComment(e.data.ref, e.data.data()) : Promise.resolve(),
);
export const guardScanContentComment = onDocumentCreated('content/{postId}/comments/{commentId}', (e) =>
  e.data ? scanComment(e.data.ref, e.data.data()) : Promise.resolve(),
);

// ─────────────── Profiles ───────────────

const PRIVATE_FIELDS = ['email', 'phoneNumber', 'phone', 'recoveryEmail', 'linkedEmails', 'dateOfBirth', 'birthday'];
const WATCHED = ['displayName', 'username', 'bio', 'website', 'photoUrl', 'avatarUrl'];
const splitOn = () => process.env.GUARD_SPLIT_PRIVATE_FIELDS === 'true';

async function indexContacts(uid: string, d: Record<string, unknown>) {
  const batch = db().batch();
  let n = 0;
  for (const p of [d.phoneNumber, d.phone]) {
    if (typeof p === 'string' && /^\+[1-9]\d{6,14}$/.test(p)) {
      batch.set(db().collection('contact_index').doc(contactKey.phone(p)), { uid, kind: 'phone' }, { merge: true });
      n++;
    }
  }
  const emails = [d.email, d.recoveryEmail, ...(Array.isArray(d.linkedEmails) ? d.linkedEmails : [])];
  for (const e of emails) {
    if (typeof e === 'string' && e.includes('@') && e.length < 200) {
      batch.set(db().collection('contact_index').doc(contactKey.email(e)), { uid, kind: 'email' }, { merge: true });
      n++;
    }
  }
  if (n) await batch.commit();
}

/** Copies contact fields to users/{uid}/private/contact and removes them from the public profile. */
async function movePrivateFields(uid: string, d: Record<string, unknown>) {
  const present = PRIVATE_FIELDS.filter((f) => d[f] !== undefined);
  if (!present.length) return;
  const copy = Object.fromEntries(present.map((f) => [f, d[f]]));
  await db().doc(`users/${uid}/private/contact`).set({ ...copy, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await db().doc(`users/${uid}`).update(Object.fromEntries(present.map((f) => [f, FieldValue.delete()])));
}

async function bumpProfileChanges(uid: string): Promise<number> {
  const ref = db().collection('security_counters').doc(uid);
  return db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    const start = Number(s.get('profStart') ?? 0);
    const fresh = Date.now() - start > 3600000;
    const n = (fresh ? 0 : Number(s.get('profCount') ?? 0)) + 1;
    tx.set(ref, { profStart: fresh ? Date.now() : start, profCount: n }, { merge: true });
    return n;
  });
}

export const guardOnProfileWrite = onDocumentWritten('users/{uid}', async (event) => {
  const uid = event.params.uid;
  const before = event.data?.before?.data() ?? {};
  const after = event.data?.after?.data();
  if (!after) return;

  const contactChanged = PRIVATE_FIELDS.some((f) => after[f] !== undefined && JSON.stringify(after[f]) !== JSON.stringify(before[f]));
  if (contactChanged) await indexContacts(uid, after);
  if (splitOn() && PRIVATE_FIELDS.some((f) => after[f] !== undefined)) await movePrivateFields(uid, after);

  const changed = WATCHED.filter((f) => after[f] !== before[f]);
  if (!changed.length || !event.data?.before?.exists) return;

  // Names of accounts an admin verified (verifiedBy is admin-only in the
  // rules; the signup isVerified flag is self-chosen, so it is not trusted).
  const nameKeys = [after.displayName, after.username].filter((x): x is string => typeof x === 'string' && x.length >= 4).map((x) => skeleton(x.normalize('NFKD').replace(/[^\p{L}\p{N}]/gu, '')));
  if (after.isVerified === true && typeof after.verifiedBy === 'string') {
    await Promise.all(nameKeys.map((k) => db().collection('guard_verified_names').doc(k.slice(0, 120)).set({ uid }, { merge: true })));
  } else if (changed.includes('displayName') || changed.includes('username')) {
    for (const k of nameKeys) {
      const hit = await db().collection('guard_verified_names').doc(k.slice(0, 120)).get();
      if (hit.exists && hit.get('uid') !== uid) {
        await takeAction({ uid, action: 'escalate_admin', source: 'scan:impersonation', targetPath: `users/${uid}`, reason: `Profile name copies a verified account (${hit.get('uid')})` });
        await db().doc(`users/${uid}`).set({ safety: { impersonationOf: hit.get('uid'), by: 'ova_guard' } }, { merge: true });
        break;
      }
    }
  }

  // Bio / website links.
  if (changed.includes('bio') || changed.includes('website')) {
    const text = `${after.bio ?? ''} ${after.website ?? ''}`.trim();
    if (text && (extractUrls(text).length || analyzeText(text).points >= 25)) {
      const v = await checkText(text);
      if (v.verdict !== 'safe') await db().doc(`users/${uid}`).set({ safety: { bio: safetyField(v) } }, { merge: true });
      if (v.verdict === 'dangerous') {
        await takeAction({ uid, action: 'notify_user', source: 'scan:bio', notifyTitle: 'Link in your bio blocked', reason: `A link in your bio was blocked: ${v.reasons[0] ?? ''}` });
      }
    }
  }

  // Many profile changes in an hour is a classic takeover sign.
  if ((await bumpProfileChanges(uid)) === 6) {
    await recordSecurityEvent(uid, 'profile_change_spike', { details: { count: 6, fields: changed } });
  }
});

// ─────────────── Callables ───────────────

/** Link reputation for links the app is about to show (E2E chats) or send. */
export const guardCheckLinks = onCall(async (request) => {
  const uid = requireAccount(request);
  const raw = (request.data as { urls?: unknown })?.urls;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 10) throw new HttpsError('invalid-argument', 'Send 1 to 10 links.');
  await limit(uid, 'links', 120, 10 * 60000);
  // One answer per link sent, in the same order.
  const out = await Promise.all(
    raw.map(async (u) => {
      const input = String(u).slice(0, 500);
      const finding = analyzeUrl(extractUrls(input, 1)[0] ?? input);
      if (!finding) return { url: input, host: null, verdict: 'safe', reasons: [] as string[] };
      const [rep] = await checkLinks({ links: [finding], points: 0, reasons: [], categories: [] });
      return { url: input, host: rep.host, verdict: rep.verdict, reasons: rep.reasons.slice(0, 3) };
    }),
  );
  return { links: out };
});

export const guardReverseAction = onCall(async (request) => {
  const admin = await requireAdmin(request);
  const d = (request.data ?? {}) as { actionId?: unknown; reason?: unknown };
  const id = String(d.actionId ?? '');
  if (!/^[A-Za-z0-9]{10,40}$/.test(id)) throw new HttpsError('invalid-argument', 'Missing action.');
  const ok = await reverseAction(id, admin, String(d.reason ?? '').slice(0, 300));
  if (!ok) throw new HttpsError('failed-precondition', 'That action is not active.');
  return { ok };
});

export const guardSweep = onSchedule('every 30 minutes', async () => {
  const due = await db()
    .collection('security_actions')
    .where('status', '==', 'active')
    .where('expiresAt', '<=', Timestamp.now())
    .limit(300)
    .get();
  for (const d of due.docs) await reverseAction(d.id, 'ova_guard', 'Time limit ended', 'expired');
  if (due.size) logger.info('guard sweep lifted actions', { count: due.size });
});

/**
 * Sign-in lookup. Returns only what the sign-in header shows. The phone or
 * e-mail itself comes back only to someone already signed in with it.
 */
export const accountLookup = onCall(async (request) => {
  const d = (request.data ?? {}) as { phone?: unknown; email?: unknown };
  const phone = typeof d.phone === 'string' ? d.phone.trim() : '';
  const email = typeof d.email === 'string' ? d.email.trim().toLowerCase() : '';
  if (phone && !/^\+[1-9]\d{6,14}$/.test(phone)) throw new HttpsError('invalid-argument', 'Bad number.');
  if (email && !/^[^@\s]{1,64}@[^@\s]{1,190}$/.test(email)) throw new HttpsError('invalid-argument', 'Bad e-mail.');
  if (!phone && !email) throw new HttpsError('invalid-argument', 'Send a phone or e-mail.');
  await limit(callerIp(request), 'lookup_ip', 60, 15 * 60000);
  await limit(request.auth?.uid ?? null, 'lookup_uid', 40, 15 * 60000);

  const uid = phone ? await uidForPhone(phone) : await uidForEmail(email);
  if (!uid) return { found: false };
  const p = (await db().doc(`users/${uid}`).get()).data();
  if (!p) return { found: false };
  const token = request.auth?.token as Record<string, unknown> | undefined;
  const ownsEmail = !!email && token?.email === email && token?.email_verified === true;
  const ownsPhone = !!phone && token?.phone_number === phone;
  let accountPhone: string | null = null;
  if (ownsEmail || ownsPhone) {
    const priv = (await db().doc(`users/${uid}/private/contact`).get()).data();
    accountPhone = (priv?.phoneNumber ?? p.phoneNumber ?? p.phone ?? null) as string | null;
    if (!accountPhone) accountPhone = (await getAuth().getUser(uid).catch(() => null))?.phoneNumber ?? null;
  }
  return {
    found: true,
    uid,
    displayName: p.displayName ?? p.name ?? null,
    username: p.username ?? null,
    photoUrl: p.photoUrl ?? p.avatarUrl ?? null,
    authPasswordLinked: p.authPasswordLinked === true,
    legacyPasswordPending: p.legacyPasswordPending === true || !!p.passwordHash || !!p.password,
    phoneNumber: phone || accountPhone,
  };
});

export const guardBackfillContacts = onCall({ timeoutSeconds: 540 }, async (request) => {
  await requireAdmin(request);
  let after: string | null = (request.data as { after?: string })?.after ?? null;
  let indexed = 0;
  let moved = 0;
  for (let page = 0; page < 10; page++) {
    let q = db().collection('users').orderBy('__name__').limit(300);
    if (after) q = q.startAfter(after);
    const snap = await q.get();
    if (snap.empty) return { indexed, moved, done: true };
    for (const doc of snap.docs) {
      const d = doc.data();
      if (PRIVATE_FIELDS.some((f) => d[f] !== undefined)) {
        await indexContacts(doc.id, d);
        indexed++;
        if (splitOn()) {
          await movePrivateFields(doc.id, d);
          moved++;
        }
      }
    }
    after = snap.docs[snap.docs.length - 1].id;
  }
  return { indexed, moved, done: false, after };
});

/** Restriction check for server-written content (live comments etc.). */
export async function restrictedUntil(uid: string, scope: 'messaging' | 'comments' | 'follows'): Promise<number> {
  const s = await db().collection('security_state').doc(uid).get();
  return (s.get(`restrictions.${scope}`) as Timestamp | undefined)?.toMillis() ?? 0;
}
