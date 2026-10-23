/**
 * Ova Guard: per-account security monitor.
 *
 * Every security event is written here, server-side, to
 * `security_events/{uid}/events/{id}` (clients can read their own, never
 * write). Each event gets a score from the plain rules in `score()` below,
 * so every alert can say exactly why it fired. Gemini is only used on
 * request to summarise an event in friendly words; it never sets the score.
 *
 * Sources:
 *   - guardReportSession (app start / sign-in): new device, new country,
 *     impossible travel, one session used from two devices or countries,
 *     password / email / phone changes (detected from the Auth user record,
 *     not trusted from the client).
 *   - guardReportAuthFailure (signed out): failed passwords / SMS codes as
 *     reported by a device. Rate limited per IP; lower trust than server data.
 *   - checkLegacyPassword: server-side check for old in-profile password
 *     hashes; its failures are server-verified.
 *   - Firestore triggers: message bursts (chats/{id}/messages) and
 *     follow/unfollow bursts (relationships/{a_b}).
 *   - recordSecurityEvent() from biometric.ts: new fingerprint keys.
 *
 * High-risk events create an urgent `notifications` doc (pushed by
 * onNotificationCreated) and stay "open" until the user answers
 * "Yes, it was me" or "Secure my account" (guardRespond), which revokes all
 * sessions and fingerprint keys and forces every device to sign in again.
 *
 * Geo: set GUARD_IPINFO_TOKEN in functions/.env to resolve IPs (country +
 * coordinates via ipinfo.io). Without it, only the device's network country
 * is known and impossible-travel checks are skipped.
 */
import * as crypto from 'crypto';
import axios from 'axios';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp, DocumentReference } from 'firebase-admin/firestore';
import { GoogleGenAI } from '@google/genai';

const geminiSecret = defineSecret('GEMINI_API_KEY');
const db = () => getFirestore();

export type Risk = 'low' | 'medium' | 'high';

export type SecurityEventType =
  | 'new_device'
  | 'sign_in'
  | 'new_country'
  | 'impossible_travel'
  | 'auth_failures'
  | 'password_changed'
  | 'email_changed'
  | 'phone_changed'
  | 'message_spike'
  | 'follow_spike'
  | 'session_reuse'
  | 'biometric_key_added'
  | 'account_secured';

interface Geo {
  country?: string | null;
  city?: string | null;
  lat?: number | null;
  lng?: number | null;
  source?: 'ip' | 'device' | null;
}

interface EventContext {
  deviceId?: string | null;
  deviceLabel?: string | null;
  platform?: string | null;
  ip?: string | null;
  geo?: Geo | null;
  details?: Record<string, unknown>;
}

const HIGH = 70;
const MEDIUM = 40;

// ─────────────────────────── Scoring rules ───────────────────────────

/**
 * Explainable risk rules. Each rule adds points and a reason the user sees.
 * >= 70 is high (push + "Was this you?"), >= 40 medium, otherwise low.
 */
export function score(type: SecurityEventType, d: Record<string, unknown> = {}): { score: number; risk: Risk; reasons: string[] } {
  let s = 0;
  const reasons: string[] = [];
  const add = (points: number, reason: string) => {
    s += points;
    reasons.push(reason);
  };
  switch (type) {
    case 'sign_in':
      add(0, 'Sign-in from a device you have used before');
      break;
    case 'new_device':
      if (d.firstDevice) {
        add(5, 'First device on this account');
      } else {
        add(40, 'Sign-in from a device we have not seen on your account');
      }
      if (d.newCountry) add(30, `First sign-in from ${d.country ?? 'a new country'}`);
      if (d.recentFailures && Number(d.recentFailures) >= 5) add(20, `${d.recentFailures} failed attempts shortly before`);
      break;
    case 'new_country':
      add(45, `First sign-in from ${d.country ?? 'a new country'}`);
      if (d.recentFailures && Number(d.recentFailures) >= 5) add(20, `${d.recentFailures} failed attempts shortly before`);
      break;
    case 'impossible_travel':
      add(75, `Signed in ${Math.round(Number(d.km ?? 0))} km away ${Math.round(Number(d.minutes ?? 0))} min after the previous sign-in (faster than a plane)`);
      break;
    case 'auth_failures': {
      const n = Number(d.count ?? 0);
      if (n >= 10) add(70, `${n} wrong ${d.kind === 'otp' ? 'SMS codes' : 'passwords'} in 15 minutes`);
      else add(45, `${n} wrong ${d.kind === 'otp' ? 'SMS codes' : 'passwords'} in 15 minutes`);
      if (d.verified) add(5, 'Checked by Oneova servers');
      break;
    }
    case 'password_changed':
      add(50, 'Your password was changed');
      if (d.newDevice) add(30, 'Changed from a device added in the last 24 hours');
      break;
    case 'email_changed':
      add(70, 'The email on your account was changed');
      if (d.newDevice) add(20, 'Changed from a device added in the last 24 hours');
      break;
    case 'phone_changed':
      add(70, 'The phone number on your account was changed');
      if (d.newDevice) add(20, 'Changed from a device added in the last 24 hours');
      break;
    case 'message_spike': {
      const n = Number(d.count ?? 0);
      const chats = Number(d.chats ?? 0);
      if (n >= 200 || chats >= 60) add(75, `${n} messages to ${chats} chats in a few minutes`);
      else add(50, `${n} messages to ${chats} chats in a few minutes`);
      break;
    }
    case 'follow_spike': {
      const n = Number(d.count ?? 0);
      if (n >= 150) add(75, `${n} follows/unfollows in 10 minutes`);
      else add(50, `${n} follows/unfollows in 10 minutes`);
      break;
    }
    case 'session_reuse':
      add(85, String(d.why ?? 'The same sign-in session was used from two places'));
      break;
    case 'biometric_key_added':
      add(25, 'Fingerprint sign-in was turned on for a device');
      if (d.newDevice) add(30, 'The device was added in the last 24 hours');
      break;
    case 'account_secured':
      add(0, 'You secured your account: other sessions and fingerprint keys were removed');
      break;
  }
  const value = Math.min(100, s);
  return { score: value, risk: value >= HIGH ? 'high' : value >= MEDIUM ? 'medium' : 'low', reasons };
}

const TITLES: Record<SecurityEventType, string> = {
  sign_in: 'Signed in',
  new_device: 'New device signed in',
  new_country: 'Sign-in from a new country',
  impossible_travel: 'Impossible-travel sign-in',
  auth_failures: 'Failed sign-in attempts',
  password_changed: 'Password changed',
  email_changed: 'Email changed',
  phone_changed: 'Phone number changed',
  message_spike: 'Unusual messaging activity',
  follow_spike: 'Unusual follow activity',
  session_reuse: 'Session used from two places',
  biometric_key_added: 'Fingerprint sign-in turned on',
  account_secured: 'Account secured',
};

// ─────────────────────────── Recording ───────────────────────────

/** Writes one scored event and raises an alert when it is high risk. */
export async function recordSecurityEvent(
  uid: string,
  type: SecurityEventType,
  ctx: EventContext = {},
): Promise<string> {
  const details = ctx.details ?? {};
  const scored = score(type, { ...details, country: ctx.geo?.country });
  const ref = db().collection('security_events').doc(uid).collection('events').doc();
  const needsAnswer = scored.risk === 'high' && type !== 'account_secured';
  await ref.set({
    type,
    title: TITLES[type],
    score: scored.score,
    risk: scored.risk,
    reasons: scored.reasons,
    status: needsAnswer ? 'open' : 'closed',
    deviceId: ctx.deviceId ?? null,
    deviceLabel: ctx.deviceLabel ?? null,
    platform: ctx.platform ?? null,
    ipMasked: maskIp(ctx.ip),
    geo: ctx.geo ?? null,
    details,
    at: FieldValue.serverTimestamp(),
  });

  const stateRef = db().collection('security_state').doc(uid);
  await stateRef.set(
    {
      lastEventAt: FieldValue.serverTimestamp(),
      lastEventType: type,
      ...(needsAnswer ? { openHighRisk: FieldValue.increment(1) } : {}),
    },
    { merge: true },
  );
  await refreshRiskLevel(uid);

  if (needsAnswer) {
    await db().collection('notifications').add({
      userId: uid,
      category: 'security',
      type: 'security_alert',
      priority: 'urgent',
      title: `Ova Guard: ${TITLES[type]}`,
      body: `${scored.reasons[0] ?? 'Unusual activity'}. Was this you?`,
      deepLink: '/profile/security',
      payload: { route: '/profile/security', eventId: ref.id },
      isRead: false,
      timestamp: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  return ref.id;
}

/** Account risk = worst open event, else the worst event in the last 7 days. */
async function refreshRiskLevel(uid: string) {
  const events = db().collection('security_events').doc(uid).collection('events');
  const open = await events.where('status', '==', 'open').limit(20).get();
  let level: Risk = 'low';
  let reason = 'No unusual activity';
  if (!open.empty) {
    level = 'high';
    reason = `${open.size} alert${open.size === 1 ? '' : 's'} need your answer`;
  } else {
    const week = await events
      .where('at', '>=', Timestamp.fromMillis(Date.now() - 7 * 86400000))
      .orderBy('at', 'desc')
      .limit(50)
      .get();
    const medium = week.docs.filter((d) => d.get('risk') === 'medium').length;
    if (medium > 0) {
      level = 'medium';
      reason = `${medium} event${medium === 1 ? '' : 's'} worth a look this week`;
    }
  }
  await db().collection('security_state').doc(uid).set(
    { riskLevel: level, riskReason: reason, openHighRisk: open.size, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

// ─────────────────────────── Helpers ───────────────────────────

function sha256(v: string): string {
  return crypto.createHash('sha256').update(v).digest('hex');
}

function safeEqualStr(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && crypto.timingSafeEqual(ab, bb);
}

function maskIp(ip?: string | null): string | null {
  if (!ip) return null;
  if (ip.includes(':')) return ip.split(':').slice(0, 3).join(':') + ':…';
  const p = ip.split('.');
  return p.length === 4 ? `${p[0]}.${p[1]}.${p[2]}.x` : null;
}

function clientIp(request: CallableRequest<unknown>): string | null {
  const fwd = String(request.rawRequest?.headers?.['x-forwarded-for'] ?? '');
  const ip = fwd.split(',')[0].trim() || request.rawRequest?.ip || '';
  return ip || null;
}

function str(v: unknown, max = 80): string | null {
  if (v === undefined || v === null) return null;
  const s = String(v).trim();
  return s ? s.slice(0, max) : null;
}

function deviceIdFrom(v: unknown): string {
  const id = String(v ?? '');
  if (!/^[0-9a-f]{32}$/.test(id)) throw new HttpsError('invalid-argument', 'Bad device.');
  return id;
}

async function geoFor(request: CallableRequest<unknown>, ip: string | null, deviceCountry: string | null): Promise<Geo> {
  const token = process.env.GUARD_IPINFO_TOKEN;
  if (token && ip) {
    try {
      const res = await axios.get(`https://ipinfo.io/${encodeURIComponent(ip)}/json`, {
        params: { token },
        timeout: 2500,
      });
      const [lat, lng] = String(res.data?.loc ?? '').split(',').map(Number);
      return {
        country: str(res.data?.country, 2),
        city: str(res.data?.city, 60),
        lat: Number.isFinite(lat) ? lat : null,
        lng: Number.isFinite(lng) ? lng : null,
        source: 'ip',
      };
    } catch (e) {
      logger.warn('ipinfo lookup failed', { error: String(e) });
    }
  }
  const header = str(request.rawRequest?.headers?.['x-appengine-country'], 2);
  if (header && header !== 'ZZ') return { country: header.toUpperCase(), source: 'ip' };
  return { country: deviceCountry ? deviceCountry.toUpperCase().slice(0, 2) : null, source: deviceCountry ? 'device' : null };
}

function km(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const r = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

function requireUser(request: CallableRequest<unknown>) {
  const auth = request.auth;
  if (!auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  if (auth.token.firebase?.sign_in_provider === 'anonymous') {
    throw new HttpsError('permission-denied', 'Guests have no account to protect.');
  }
  return auth;
}

// Devices seen by Ova Guard (server-written). Separate from the login gate's
// `users/{uid}/trusted_devices`, which only an SMS check may fill.
const devicesCol = (uid: string) => db().collection('security_state').doc(uid).collection('devices');
const trustedCol = (uid: string) => db().collection('users').doc(uid).collection('trusted_devices');

async function recentFailures(uid: string): Promise<number> {
  const c = await db().collection('security_counters').doc(uid).get();
  const since = Number(c.get('failWindowStart') ?? 0);
  return Date.now() - since < 15 * 60000 ? Number(c.get('failCount') ?? 0) : 0;
}

// ─────────────────────────── Callables ───────────────────────────

/**
 * Called by the app on start and after each sign-in. Updates this device's
 * entry and records new-device / location / session / account-change events.
 * Returns whether this device was logged out remotely.
 */
/**
 * Network context for the app's login history row: masked IP and the IP's
 * region. Read-only; writes nothing.
 */
export const loginContext = onCall(async (request) => {
  requireUser(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ip = clientIp(request);
  const geo = await geoFor(request, ip, str(data.networkCountry, 2));
  return {
    ipMasked: maskIp(ip),
    country: geo.source === 'ip' ? geo.country ?? null : null,
    city: geo.source === 'ip' ? geo.city ?? null : null,
    region: null,
  };
});

export const guardReportSession = onCall(async (request) => {
  const auth = requireUser(request);
  const uid = auth.uid;
  const data = (request.data ?? {}) as Record<string, unknown>;
  const deviceId = deviceIdFrom(data.deviceId);
  const label = str(data.deviceLabel) ?? 'Unknown device';
  const platform = str(data.platform, 20);
  const appVersion = str(data.appVersion, 20);
  const ip = clientIp(request);
  const geo = await geoFor(request, ip, str(data.networkCountry, 2));
  const authTime = Number(auth.token.auth_time ?? 0);
  const provider = String(auth.token.firebase?.sign_in_provider ?? '');
  const now = Date.now();

  const stateRef = db().collection('security_state').doc(uid);
  const deviceRef = devicesCol(uid).doc(deviceId);
  const [state, device, otherDevices, user] = await Promise.all([
    stateRef.get(),
    deviceRef.get(),
    devicesCol(uid).limit(1).get(),
    getAuth().getUser(uid),
  ]);

  // Logged out remotely, or signed in before "Secure my account".
  const revokedAt = (state.get('sessionsRevokedAt') as Timestamp | undefined)?.toMillis() ?? 0;
  if (device.exists && device.get('revoked') === true && (device.get('revokedAt')?.toMillis?.() ?? 0) > authTime * 1000) {
    return { loggedOut: true };
  }
  if (revokedAt > authTime * 1000) return { loggedOut: true };

  const ctx: EventContext = { deviceId, deviceLabel: label, platform, ip, geo };
  const known = device.exists && device.get('revoked') !== true;
  const sessions = (state.get('sessions') ?? {}) as Record<string, { d: string; c?: string | null; t: number }>;
  const isNewSession = authTime > 0 && !sessions[String(authTime)];
  const failures = isNewSession ? await recentFailures(uid) : 0;

  // 1) The same sign-in (auth_time) showing up on another device or country.
  const prev = sessions[String(authTime)];
  if (prev && prev.d !== deviceId) {
    await recordSecurityEvent(uid, 'session_reuse', {
      ...ctx,
      details: { why: 'The same sign-in session was used from a second device' },
    });
  } else if (prev && prev.c && geo.country && prev.c !== geo.country && now - prev.t < 3600000) {
    await recordSecurityEvent(uid, 'session_reuse', {
      ...ctx,
      details: { why: `The same session was used from ${prev.c} and ${geo.country} within an hour` },
    });
  }

  // 2) New sign-in: device, country, impossible travel.
  const knownCountries: string[] = (state.get('knownCountries') as string[] | undefined) ?? [];
  const newCountry = !!geo.country && knownCountries.length > 0 && !knownCountries.includes(geo.country);
  if (isNewSession) {
    if (!known) {
      await recordSecurityEvent(uid, 'new_device', {
        ...ctx,
        details: { firstDevice: otherDevices.empty, newCountry, recentFailures: failures, provider },
      });
    } else if (newCountry) {
      await recordSecurityEvent(uid, 'new_country', { ...ctx, details: { recentFailures: failures, provider } });
    } else {
      await recordSecurityEvent(uid, 'sign_in', { ...ctx, details: { provider } });
    }
    const last = state.get('lastLogin') as { at?: number; lat?: number; lng?: number } | undefined;
    if (last?.lat != null && last?.lng != null && geo.lat != null && geo.lng != null && last.at) {
      const distance = km({ lat: last.lat, lng: last.lng }, { lat: geo.lat, lng: geo.lng });
      const minutes = Math.max(1, (now - last.at) / 60000);
      if (distance > 500 && distance / (minutes / 60) > 900) {
        await recordSecurityEvent(uid, 'impossible_travel', { ...ctx, details: { km: distance, minutes } });
      }
    }
  }

  // 3) Account changes, read from the Auth record (cannot be faked by a client).
  const snap = state.get('authSnapshot') as { email?: string | null; phone?: string | null; validAfter?: string | null } | undefined;
  const deviceAgeMs = device.exists ? now - (device.get('firstSeenAt')?.toMillis?.() ?? now) : 0;
  const newDevice = !known || deviceAgeMs < 86400000;
  if (snap) {
    if ((snap.email ?? null) !== (user.email ?? null)) {
      await recordSecurityEvent(uid, 'email_changed', { ...ctx, details: { newDevice } });
    }
    if ((snap.phone ?? null) !== (user.phoneNumber ?? null)) {
      await recordSecurityEvent(uid, 'phone_changed', { ...ctx, details: { newDevice } });
    }
    // tokensValidAfterTime moves when the password changes (or sessions are revoked).
    if (snap.validAfter && user.tokensValidAfterTime && snap.validAfter !== user.tokensValidAfterTime &&
        new Date(user.tokensValidAfterTime).getTime() > revokedAt + 5000) {
      await recordSecurityEvent(uid, 'password_changed', { ...ctx, details: { newDevice } });
    }
  }

  // Remember this session and device.
  const keep = Object.entries(sessions)
    .filter(([, v]) => now - v.t < 30 * 86400000)
    .sort((a, b) => b[1].t - a[1].t)
    .slice(0, 20);
  const nextSessions: Record<string, unknown> = Object.fromEntries(keep);
  if (authTime > 0) nextSessions[String(authTime)] = { d: deviceId, c: geo.country ?? null, t: now };

  await Promise.all([
    deviceRef.set(
      {
        label,
        platform,
        appVersion,
        lastSeenAt: FieldValue.serverTimestamp(),
        lastCountry: geo.country ?? null,
        lastCity: geo.city ?? null,
        lastIpMasked: maskIp(ip),
        lastProvider: provider,
        revoked: false,
        ...(device.exists ? {} : { firstSeenAt: FieldValue.serverTimestamp() }),
      },
      { merge: true },
    ),
    stateRef.set(
      {
        sessions: nextSessions,
        knownCountries: geo.country ? FieldValue.arrayUnion(geo.country) : knownCountries,
        authSnapshot: {
          email: user.email ?? null,
          phone: user.phoneNumber ?? null,
          validAfter: user.tokensValidAfterTime ?? null,
        },
        ...(isNewSession ? { lastLogin: { at: now, lat: geo.lat ?? null, lng: geo.lng ?? null, country: geo.country ?? null } } : {}),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    ),
  ]);

  // Once the password lives in Firebase Auth, the old hash is not needed.
  if (user.providerData.some((p) => p.providerId === 'password')) {
    await db().collection('legacy_password_hashes').doc(uid).delete().catch(() => undefined);
  }
  return { loggedOut: false };
});

/**
 * Failed password / SMS code, reported by a signed-out device. Rate limited
 * per IP so it can't be used to flood someone with alerts.
 */
export const guardReportAuthFailure = onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const phone = String(data.phone ?? '');
  const kind = data.kind === 'otp' ? 'otp' : 'password';
  if (!/^\+[1-9]\d{6,14}$/.test(phone)) throw new HttpsError('invalid-argument', 'Bad number.');
  const ip = clientIp(request);
  if (!(await allowFromIp(ip, 'fail', 30))) return { ok: true };
  const user = await db().collection('users').where('phoneNumber', '==', phone).limit(1).get();
  if (user.empty) return { ok: true };
  await countFailure(user.docs[0].id, kind, false, ip, str(data.deviceLabel));
  return { ok: true };
});

/** Simple fixed-window limiter per IP (30 calls / 15 min by default). */
async function allowFromIp(ip: string | null, bucket: string, max: number): Promise<boolean> {
  if (!ip) return true;
  const ref = db().collection('security_rate').doc(`${bucket}_${sha256(ip).slice(0, 32)}`);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const start = Number(snap.get('start') ?? 0);
    const count = Date.now() - start < 15 * 60000 ? Number(snap.get('count') ?? 0) : 0;
    if (count >= max) return false;
    tx.set(ref, {
      start: count === 0 ? Date.now() : start,
      count: count + 1,
      expiresAt: Timestamp.fromMillis(Date.now() + 86400000),
    });
    return true;
  });
}

/** Counts failures in a 15-minute window and records an event at 5 and 10. */
async function countFailure(uid: string, kind: 'password' | 'otp', verified: boolean, ip: string | null, deviceLabel: string | null) {
  const ref = db().collection('security_counters').doc(uid);
  const count = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const start = Number(snap.get('failWindowStart') ?? 0);
    const fresh = Date.now() - start >= 15 * 60000;
    const n = (fresh ? 0 : Number(snap.get('failCount') ?? 0)) + 1;
    tx.set(ref, { failWindowStart: fresh ? Date.now() : start, failCount: n }, { merge: true });
    return n;
  });
  if (count === 5 || count === 10) {
    await recordSecurityEvent(uid, 'auth_failures', {
      ip,
      deviceLabel,
      details: { count, kind, verified },
    });
  }
}

/**
 * Checks a password against an old in-profile hash on the server, so clients
 * never need to read password hashes. Works signed out (by phone) or signed
 * in (own account).
 */
export const checkLegacyPassword = onCall(async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const password = String(data.password ?? '');
  const phone = String(data.phone ?? '');
  if (!password || password.length > 256) throw new HttpsError('invalid-argument', 'Bad password.');
  const ip = clientIp(request);
  if (!(await allowFromIp(ip, 'legacy', 20))) {
    throw new HttpsError('resource-exhausted', 'Too many attempts. Try again in 15 minutes.');
  }

  let uid: string | null = null;
  if (/^\+[1-9]\d{6,14}$/.test(phone)) {
    const q = await db().collection('users').where('phoneNumber', '==', phone).limit(1).get();
    uid = q.empty ? null : q.docs[0].id;
  }
  if (!uid && request.auth && request.auth.token.firebase?.sign_in_provider !== 'anonymous') uid = request.auth.uid;
  if (!uid) return { match: false };

  if ((await recentFailures(uid)) >= 10) {
    throw new HttpsError('resource-exhausted', 'Too many attempts. Try again in 15 minutes.');
  }

  const [legacy, profile] = await Promise.all([
    db().collection('legacy_password_hashes').doc(uid).get(),
    db().collection('users').doc(uid).get(),
  ]);
  const hash = String(legacy.get('passwordHash') ?? profile.get('passwordHash') ?? '');
  const plain = String(legacy.get('password') ?? profile.get('password') ?? '');
  let match = false;
  if (hash) match = safeEqualStr(hash, sha256(password));
  else if (plain) match = safeEqualStr(plain, password);
  if (!match) await countFailure(uid, 'password', true, ip, null);
  return { match };
});

/**
 * Secure my account: end every session, drop every fingerprint key and every
 * remembered device, so each phone must pass the two checks again. Shared by
 * guardRespond and the e-mail "Secure my account" link (securityMail.ts).
 */
export async function secureAccount(
  uid: string,
  eventId?: string | null,
): Promise<{ biometricKeysRemoved: number; devicesSignedOut: number }> {
  const keys = await db().collection('biometric_keys').where('uid', '==', uid).get();
  const devices = await devicesCol(uid).get();
  const trusted = await trustedCol(uid).get();
  const events = db().collection('security_events').doc(uid).collection('events');
  const open = await events.where('status', '==', 'open').get();
  const batch = db().batch();
  keys.docs.forEach((d) => batch.delete(d.ref));
  [...devices.docs, ...trusted.docs].forEach((d) =>
    batch.set(d.ref, { revoked: true, revokedAt: FieldValue.serverTimestamp() }, { merge: true }),
  );
  open.docs.forEach((d) => batch.update(d.ref, { status: 'secured', answeredAt: FieldValue.serverTimestamp() }));
  batch.set(
    db().collection('security_state').doc(uid),
    { sessionsRevokedAt: FieldValue.serverTimestamp(), sessions: {}, openHighRisk: 0 },
    { merge: true },
  );
  await batch.commit();

  const user = await getAuth().getUser(uid);
  const claims = { ...(user.customClaims ?? {}) } as Record<string, unknown>;
  delete claims.mfaSessions;
  await getAuth().setCustomUserClaims(uid, claims);
  await getAuth().revokeRefreshTokens(uid);
  // Keep the snapshot in step so the revoke isn't reported as a password change.
  const after = await getAuth().getUser(uid);
  await db().collection('security_state').doc(uid).set(
    { authSnapshot: { email: after.email ?? null, phone: after.phoneNumber ?? null, validAfter: after.tokensValidAfterTime ?? null } },
    { merge: true },
  );

  await recordSecurityEvent(uid, 'account_secured', {
    details: { biometricKeysRemoved: keys.size, devicesSignedOut: devices.size, eventId: eventId ?? null },
  });
  return { biometricKeysRemoved: keys.size, devicesSignedOut: devices.size };
}

/** Answers an alert: "Yes, it was me" or "Secure my account". */
export const guardRespond = onCall(async (request) => {
  const auth = requireUser(request);
  const uid = auth.uid;
  const data = (request.data ?? {}) as Record<string, unknown>;
  const eventId = str(data.eventId, 40);
  const action = data.action === 'secure' ? 'secure' : 'confirm';
  const events = db().collection('security_events').doc(uid).collection('events');

  if (action === 'confirm') {
    if (!eventId) throw new HttpsError('invalid-argument', 'Missing event.');
    const ref = events.doc(eventId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError('not-found', 'Event not found.');
    await ref.update({ status: 'confirmed', answeredAt: FieldValue.serverTimestamp() });
    // A confirmed new device or country becomes known.
    const country = snap.get('geo.country');
    if (country) {
      await db().collection('security_state').doc(uid).set({ knownCountries: FieldValue.arrayUnion(country) }, { merge: true });
    }
    await refreshRiskLevel(uid);
    return { ok: true };
  }

  return { ok: true, ...(await secureAccount(uid, eventId)) };
});

/**
 * "Log out" one device. Its fingerprint keys are deleted at once; the device
 * signs itself out when it next reaches Oneova (it watches its own entry).
 */
export const guardRevokeDevice = onCall(async (request) => {
  const auth = requireUser(request);
  const deviceId = deviceIdFrom((request.data as Record<string, unknown>)?.deviceId);
  const keys = await db().collection('biometric_keys').where('uid', '==', auth.uid).where('deviceId', '==', deviceId).get();
  const batch = db().batch();
  keys.docs.forEach((d) => batch.delete(d.ref));
  for (const ref of [devicesCol(auth.uid).doc(deviceId), trustedCol(auth.uid).doc(deviceId)]) {
    batch.set(ref, { revoked: true, revokedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  await batch.commit();
  return { ok: true };
});

/**
 * Plain-language explanation of one event by Gemini. The model only sees the
 * event's type, rule reasons, device and country (never messages), and its
 * text is advisory: risk and alerts come from the rules above.
 */
export const guardExplainEvent = onCall({ secrets: [geminiSecret] }, async (request) => {
  const auth = requireUser(request);
  const eventId = str((request.data as Record<string, unknown>)?.eventId, 40);
  if (!eventId) throw new HttpsError('invalid-argument', 'Missing event.');
  const ref = db().collection('security_events').doc(auth.uid).collection('events').doc(eventId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Event not found.');
  const cached = snap.get('aiSummary');
  if (cached) return { summary: cached };

  const apiKey = geminiSecret.value();
  if (!apiKey) throw new HttpsError('failed-precondition', 'AI is not configured.');
  const e = snap.data() ?? {};
  const facts = {
    event: e.title,
    risk: e.risk,
    score: e.score,
    reasons: e.reasons,
    device: e.deviceLabel,
    platform: e.platform,
    country: e.geo?.country ?? null,
    city: e.geo?.city ?? null,
    status: e.status,
  };
  const ai = new GoogleGenAI({ apiKey });
  const res = await ai.models.generateContent({
    model: 'gemini-2.5-flash',
    contents: [{ role: 'user', parts: [{ text: JSON.stringify(facts) }] }],
    config: {
      systemInstruction:
        'You are Ova Guard, the security helper in the Oneova app. Explain this account security event to the account owner ' +
        'in 2-3 short, calm sentences, then one sentence on what to do if it was not them (tap "Secure my account"). ' +
        'Use only the facts given. Do not change the risk level, do not guess causes, no markdown.',
      maxOutputTokens: 200,
      temperature: 0.2,
    },
  });
  const summary = String(res.text ?? '').trim().slice(0, 800);
  if (summary) await ref.update({ aiSummary: summary });
  return { summary };
});

// ─────────────────────────── Activity triggers ───────────────────────────

/** Bumps a windowed counter; returns the new count and distinct targets. */
async function bumpWindow(
  ref: DocumentReference,
  prefix: string,
  windowMs: number,
  target: string | null,
): Promise<{ count: number; targets: number; alertedAt: number }> {
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const start = Number(snap.get(`${prefix}Start`) ?? 0);
    const fresh = Date.now() - start >= windowMs;
    const count = (fresh ? 0 : Number(snap.get(`${prefix}Count`) ?? 0)) + 1;
    const targets = new Set<string>(fresh ? [] : ((snap.get(`${prefix}Targets`) as string[] | undefined) ?? []));
    if (target && targets.size < 200) targets.add(target);
    tx.set(
      ref,
      {
        [`${prefix}Start`]: fresh ? Date.now() : start,
        [`${prefix}Count`]: count,
        [`${prefix}Targets`]: [...targets],
      },
      { merge: true },
    );
    return { count, targets: targets.size, alertedAt: Number(snap.get(`${prefix}AlertedAt`) ?? 0) };
  });
}

async function markAlerted(ref: DocumentReference, prefix: string) {
  await ref.set({ [`${prefix}AlertedAt`]: Date.now() }, { merge: true });
}

/** Message bursts: 80+ messages in 5 minutes, or 25+ different chats in 10. */
export const guardOnMessage = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
  const senderId = String(event.data?.get('senderId') ?? '');
  if (!senderId || senderId === 'guest') return;
  const ref = db().collection('security_counters').doc(senderId);
  const w = await bumpWindow(ref, 'msg', 10 * 60000, event.params.chatId);
  const spike = w.count >= 80 || w.targets >= 25;
  if (!spike || Date.now() - w.alertedAt < 30 * 60000) return;
  await markAlerted(ref, 'msg');
  await recordSecurityEvent(senderId, 'message_spike', { details: { count: w.count, chats: w.targets } });
});

/** Follow / unfollow bursts: 60+ changes in 10 minutes. */
export const guardOnRelationship = onDocumentWritten('relationships/{relId}', async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  const wasFollow = before?.status === 'accepted' || before?.status === 'pending';
  const isFollow = after?.status === 'accepted' || after?.status === 'pending';
  if (wasFollow === isFollow) return;
  const relId = event.params.relId;
  const cut = relId.indexOf('_');
  if (cut <= 0) return;
  const actor = relId.slice(0, cut);
  const ref = db().collection('security_counters').doc(actor);
  const w = await bumpWindow(ref, 'follow', 10 * 60000, relId.slice(cut + 1));
  if (w.count < 60 || Date.now() - w.alertedAt < 30 * 60000) return;
  await markAlerted(ref, 'follow');
  await recordSecurityEvent(actor, 'follow_spike', { details: { count: w.count } });
});

// ─────────────────────────── Legacy password hashes ───────────────────────────

/**
 * Moves old password hashes out of the public `users` docs into
 * `legacy_password_hashes/{uid}` (no client access). The profile keeps only
 * `legacyPasswordPending: true` so the login screen knows to ask the server.
 */
async function moveLegacyPasswordHashes(): Promise<number> {
  let moved = 0;
  for (const field of ['passwordHash', 'password']) {
    const snap = await db().collection('users').where(field, '!=', null).limit(2000).get();
    const writer = db().bulkWriter();
    for (const doc of snap.docs) {
      const d = doc.data();
      writer.set(
        db().collection('legacy_password_hashes').doc(doc.id),
        {
          ...(d.passwordHash ? { passwordHash: String(d.passwordHash) } : {}),
          ...(d.password ? { password: String(d.password) } : {}),
          movedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      writer.update(doc.ref, {
        passwordHash: FieldValue.delete(),
        password: FieldValue.delete(),
        legacyPasswordPending: true,
      });
      moved++;
    }
    await writer.close();
  }
  return moved;
}

export const moveLegacyPasswordHashesDaily = onSchedule('every 24 hours', async () => {
  const moved = await moveLegacyPasswordHashes();
  logger.info('legacy password hashes moved', { moved });
});

/** Admin-only: run the move right after deploying. */
export const moveLegacyPasswordHashesNow = onCall(async (request) => {
  const auth = requireUser(request);
  const me = await db().collection('users').doc(auth.uid).get();
  if (me.get('role') !== 'admin') throw new HttpsError('permission-denied', 'Admins only.');
  return { moved: await moveLegacyPasswordHashes() };
});
