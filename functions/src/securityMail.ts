/**
 * Email side of Ova Guard (security.ts).
 *
 * When Ova Guard records a security event that matters (new device, new
 * country, password / email / phone changed, account secured …) the user
 * gets a designed email from the team's Gmail with:
 *   - what happened, on which device, where and when;
 *   - their previous sign-in, for comparison;
 *   - "Yes, it was me" / "Not me — secure my account" buttons that expire
 *     after LINK_MINUTES and work once.
 *
 * The buttons open `securityLink`. Opening the link (GET) never changes
 * anything, because mail scanners pre-open links; the user has to press the
 * button on that page (POST). Tokens are stored hashed in `security_links`.
 */
import * as crypto from 'crypto';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onRequest } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { secureAccount } from './security';
import { alertEmail, Fact, page } from './mailTemplates';
import { sendMail } from './mailer';
import { readAccountSettings } from './accountSettings';

const db = () => getFirestore();
export const LINK_MINUTES = 60;
const REGION = 'us-central1';

/** Event types worth an email, with the sentence that leads it. */
const EMAIL_LEAD: Record<string, string> = {
  new_device: 'Your Oneova account was just signed in on a device we haven’t seen before.',
  new_country: 'Your Oneova account was just signed in from a country you don’t usually use.',
  impossible_travel: 'Your account was used from two places too far apart to travel between in that time.',
  session_reuse: 'The same sign-in was used from two different devices or places.',
  sign_in: 'Your Oneova account was just signed in.',
  auth_failures: 'Someone tried several times to sign in to your account with the wrong password or code.',
  password_changed: 'The password on your Oneova account was changed.',
  email_changed: 'The email address on your Oneova account was changed.',
  phone_changed: 'The phone number on your Oneova account was changed.',
  biometric_key_added: 'Fingerprint sign-in was turned on for a device.',
  account_secured: 'Your account was secured: every device was signed out and fingerprint sign-in was removed.',
};

const SIGN_IN_TYPES = new Set(['sign_in', 'new_device', 'new_country', 'impossible_travel', 'session_reuse']);

export function linkBase(): string {
  let project = process.env.GCLOUD_PROJECT ?? '';
  if (!project && process.env.FIREBASE_CONFIG) {
    try {
      project = JSON.parse(process.env.FIREBASE_CONFIG).projectId ?? '';
    } catch {
      /* ignore */
    }
  }
  return `https://${REGION}-${project}.cloudfunctions.net/securityLink`;
}

const hash = (t: string) => crypto.createHash('sha256').update(t).digest('hex');

/** Creates a single-use link token for [action] and returns its URL. */
export async function createSecurityLink(uid: string, eventId: string | null, action: 'confirm' | 'secure'): Promise<string> {
  const token = crypto.randomBytes(24).toString('base64url');
  await db().collection('security_links').doc(hash(token)).set({
    uid,
    eventId,
    action,
    expiresAt: Timestamp.fromMillis(Date.now() + LINK_MINUTES * 60_000),
    usedAt: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  return `${linkBase()}?t=${encodeURIComponent(token)}`;
}

function when(ts: unknown): string {
  const d = ts instanceof Timestamp ? ts.toDate() : typeof ts === 'number' ? new Date(ts) : new Date();
  return d.toLocaleString('en-GB', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'UTC' }) + ' UTC';
}

function place(geo: Record<string, unknown> | null | undefined): string {
  if (!geo) return '';
  return [geo.city, geo.region, geo.country].filter((x) => typeof x === 'string' && x).join(', ');
}

export const guardEmailOnEvent = onDocumentCreated(
  'security_events/{uid}/events/{eventId}',
  async (event) => {
    const e = event.data?.data();
    if (!e) return;
    const { uid, eventId } = event.params;
    const type = String(e.type ?? '');
    const lead = EMAIL_LEAD[type];
    if (!lead) return;
    const risk = (e.risk ?? 'low') as 'low' | 'medium' | 'high';
    // An ordinary sign-in on a known device does not need an email.
    if (type === 'sign_in' && risk === 'low') return;

    const prefs = await readAccountSettings(uid, 'notifications', 'settings/notifications');
    if (prefs.emailSecurityAlerts === false && risk !== 'high') return;

    let email: string | undefined;
    try {
      email = (await getAuth().getUser(uid)).email ?? undefined;
    } catch {
      return;
    }
    if (!email) return;

    const details: Fact[] = [
      { label: 'What', value: String(e.title ?? type) },
      { label: 'When', value: when(e.at) },
      { label: 'Device', value: [e.deviceLabel, e.platform].filter(Boolean).join(' · ') },
      { label: 'Where', value: place(e.geo) },
      { label: 'IP address', value: String(e.ipMasked ?? '') },
      { label: 'Why we flagged it', value: Array.isArray(e.reasons) && risk !== 'low' ? String(e.reasons[0] ?? '') : '' },
    ];

    // Previous sign-in, for comparison.
    let lastSignIn: Fact[] | undefined;
    if (SIGN_IN_TYPES.has(type)) {
      const recent = await db().collection('security_events').doc(uid).collection('events').orderBy('at', 'desc').limit(12).get();
      const prev = recent.docs.find((d) => d.id !== eventId && SIGN_IN_TYPES.has(String(d.get('type'))));
      if (prev) {
        lastSignIn = [
          { label: 'When', value: when(prev.get('at')) },
          { label: 'Device', value: [prev.get('deviceLabel'), prev.get('platform')].filter(Boolean).join(' · ') },
          { label: 'Where', value: place(prev.get('geo')) },
        ];
      }
    }

    const wantsAnswer = type !== 'account_secured' && (risk !== 'low' || SIGN_IN_TYPES.has(type) || type.endsWith('_changed'));
    const confirmUrl = wantsAnswer && SIGN_IN_TYPES.has(type) ? await createSecurityLink(uid, eventId, 'confirm') : null;
    const secureUrl = wantsAnswer ? await createSecurityLink(uid, eventId, 'secure') : null;

    const ok = await sendMail(
      email,
      alertEmail({
        title: type === 'account_secured' ? 'Your account is secured' : String(e.title ?? 'Security alert'),
        lead,
        risk,
        details,
        lastSignIn,
        confirmUrl,
        secureUrl,
        linkMinutes: LINK_MINUTES,
      }),
    );
    await event.data?.ref.set({ emailedAt: ok ? FieldValue.serverTimestamp() : null, emailFailed: !ok }, { merge: true });
  },
);

// ── Link handler ───────────────────────────────────────────────────────────

export const securityLink = onRequest({ cors: false }, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.set('X-Robots-Tag', 'noindex');
  const token = String((req.method === 'POST' ? req.body?.t : req.query.t) ?? '').slice(0, 100);
  const expired = () =>
    res.status(410).send(
      page({
        title: 'This link has expired',
        message: 'Security links work once and expire after ' + LINK_MINUTES + ' minutes. Open the Oneova app and go to <b>Profile → Security</b> to review recent activity or secure your account.',
        tone: 'warn',
      }),
    );
  if (!token) return void expired();

  const ref = db().collection('security_links').doc(hash(token));
  const snap = await ref.get();
  if (!snap.exists) return void expired();
  const link = snap.data() as { uid: string; eventId: string | null; action: 'confirm' | 'secure'; expiresAt: Timestamp; usedAt: Timestamp | null };
  if (link.usedAt || link.expiresAt.toMillis() < Date.now()) return void expired();

  if (req.method !== 'POST') {
    // Showing the page changes nothing; the user must press the button.
    res.status(200).send(
      link.action === 'secure'
        ? page({
            title: 'Secure your Oneova account?',
            message: 'This signs out <b>every device</b>, removes fingerprint sign-in, and asks for your password and a code next time. Use it if you don’t recognise this activity.',
            tone: 'warn',
            form: { action: linkBase(), button: 'Secure my account now', danger: true, hidden: { t: token } },
          })
        : page({
            title: 'Was this you?',
            message: 'Confirm that you made this sign-in. We’ll remember this device and place.',
            form: { action: linkBase(), button: 'Yes, it was me', hidden: { t: token } },
          }),
    );
    return;
  }

  // Single use: claim the token first.
  const claimed = await db().runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    if (!cur.exists || cur.get('usedAt')) return false;
    tx.update(ref, { usedAt: FieldValue.serverTimestamp() });
    return true;
  });
  if (!claimed) return void expired();

  try {
    if (link.action === 'confirm') {
      if (link.eventId) {
        await db().collection('security_events').doc(link.uid).collection('events').doc(link.eventId)
          .set({ status: 'confirmed', answeredAt: FieldValue.serverTimestamp(), answeredVia: 'email' }, { merge: true });
      }
      res.status(200).send(page({ title: 'Thanks — marked as you', message: 'Nothing else to do. You can close this page.', tone: 'ok' }));
      return;
    }
    await secureAccount(link.uid, link.eventId);
    res.status(200).send(
      page({
        title: 'Your account is secured',
        message: 'Every device has been signed out and fingerprint sign-in was removed. Sign in again on your phone, then <b>change your password</b> in Profile → Security.',
        tone: 'ok',
      }),
    );
  } catch (e) {
    logger.error('[securityLink] action failed', { error: String(e) });
    res.status(500).send(page({ title: 'Something went wrong', message: 'Please open the Oneova app → Profile → Security.', tone: 'warn' }));
  }
});
