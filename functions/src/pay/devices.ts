/**
 * Trusted payment devices (build log D1).
 *
 *   payDeviceChallenge({ purpose: 'register' | 'verify' })  -> { challengeId, challenge, expiresAt }
 *   payDeviceRegister({ challengeId, publicKey, attestation[], label, signature }) -> { deviceId, trusted }
 *   payDeviceTrust({ deviceId })            after a fresh email code (purpose sensitive_action)
 *   payDeviceVerify({ challengeId, deviceId, signature }) -> { ok, trusted, coolDownUntil }
 *   payDeviceList()                         -> { devices }
 *   payDeviceRevoke({ deviceId })
 *
 * Collections (deny-all to clients): pay_devices/{deviceId}, pay_device_challenges/{id}.
 * The private key never leaves the phone and only signs after a fingerprint or
 * face check. `verifyDeviceApproval()` is what payment approvals (D2) call.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { recordSecurityEvent } from '../security';
import { callerIp, limit } from '../guard/protect';
import {
  CHALLENGE_TTL_MS, MAX_ACTIVE_DEVICES, NEW_DEVICE_COOL_DOWN_MS, b64, deviceCanApprove, p256Key,
  proofPayload, stepUpUsable, verifyAndroidAttestation, verifySignature,
} from './devicesLogic';

const db = () => getFirestore();
const DEVICES = 'pay_devices';
const CHALLENGES = 'pay_device_challenges';

const GOOGLE_ROOTS_URL = 'https://android.googleapis.com/attestation/root';
const GOOGLE_STATUS_URL = 'https://android.googleapis.com/attestation/status';
const CACHE_MS = 3600_000;
let rootsCache: { at: number; pems: string[] } | null = null;
let statusCache: { at: number; revoked: Set<string> } | null = null;

async function googleRoots(): Promise<string[]> {
  if (rootsCache && Date.now() - rootsCache.at < CACHE_MS) return rootsCache.pems;
  const r = await fetch(GOOGLE_ROOTS_URL, { signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`roots ${r.status}`);
  const pems = (await r.json()) as unknown;
  if (!Array.isArray(pems) || pems.length === 0 || !pems.every((p) => typeof p === 'string')) throw new Error('roots format');
  rootsCache = { at: Date.now(), pems: pems as string[] };
  return rootsCache.pems;
}

async function revokedSerials(): Promise<Set<string>> {
  if (statusCache && Date.now() - statusCache.at < CACHE_MS) return statusCache.revoked;
  const r = await fetch(GOOGLE_STATUS_URL, { signal: AbortSignal.timeout(8000) });
  if (!r.ok) throw new Error(`status ${r.status}`);
  const body = (await r.json()) as { entries?: Record<string, { status?: string }> };
  if (!body || typeof body.entries !== 'object') throw new Error('status format');
  const revoked = new Set<string>();
  for (const [serial, e] of Object.entries(body.entries)) {
    if (e?.status === 'REVOKED') revoked.add(serial.toLowerCase().replace(/^0+(?=.)/, ''));
  }
  statusCache = { at: Date.now(), revoked };
  return revoked;
}

function uidOf(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function dataOf(request: CallableRequest<unknown>): Record<string, unknown> {
  const d = request.data;
  return d && typeof d === 'object' ? (d as Record<string, unknown>) : {};
}

function idOf(v: unknown, what: string): string {
  if (typeof v !== 'string' || !/^[A-Za-z0-9_-]{16,64}$/.test(v)) throw new HttpsError('invalid-argument', `Missing ${what}.`);
  return v;
}

const ms = (v: unknown): number | null => (v instanceof Timestamp ? v.toMillis() : typeof v === 'number' ? v : null);

/** Takes a challenge once: right owner, right purpose, not expired, not used. */
async function consumeChallenge(uid: string, challengeId: string, purpose: 'register' | 'verify'): Promise<string> {
  const ref = db().collection(CHALLENGES).doc(challengeId);
  const out = await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists || s.get('uid') !== uid || s.get('purpose') !== purpose) return null;
    if (s.get('usedAt') || (ms(s.get('expiresAt')) ?? 0) < Date.now()) return null;
    tx.update(ref, { usedAt: FieldValue.serverTimestamp() });
    return String(s.get('challenge'));
  });
  if (!out) throw new HttpsError('deadline-exceeded', 'This check expired. Try again.');
  return out;
}

export const payDeviceChallenge = onCall(async (request) => {
  const uid = uidOf(request);
  const purpose = dataOf(request).purpose === 'register' ? 'register' : 'verify';
  await limit(uid, 'pay_device_challenge', 30, 3600_000);
  const challenge = crypto.randomBytes(32).toString('base64url');
  const ref = db().collection(CHALLENGES).doc();
  const expiresAt = Date.now() + CHALLENGE_TTL_MS;
  await ref.set({ uid, purpose, challenge, expiresAt: Timestamp.fromMillis(expiresAt), createdAt: FieldValue.serverTimestamp() });
  return { challengeId: ref.id, challenge, expiresAt };
});

export const payDeviceRegister = onCall(async (request) => {
  const uid = uidOf(request);
  const data = dataOf(request);
  await limit(uid, 'pay_device_register', 10, 24 * 3600_000);
  await limit(callerIp(request), 'pay_device_register_ip', 30, 3600_000);

  const challengeId = idOf(data.challengeId, 'check');
  const publicKey = b64(data.publicKey, 512);
  const signature = b64(data.signature, 128);
  if (!publicKey || !p256Key(publicKey) || !signature) throw new HttpsError('invalid-argument', 'This phone’s security key isn’t supported.');
  const chainIn = Array.isArray(data.attestation) ? data.attestation : [];
  const chain = chainIn.map((c) => b64(c, 8192));
  if (chain.length === 0 || chain.some((c) => !c)) {
    throw new HttpsError('failed-precondition', 'This phone can’t prove its security chip. Payments need a phone with a hardware security key.');
  }
  const label = typeof data.label === 'string' ? data.label.replace(/[^\p{L}\p{N} ._()'-]/gu, '').slice(0, 60) : '';

  const challenge = await consumeChallenge(uid, challengeId, 'register');

  // Proof the user passed a biometric: the key only signs after one.
  if (!verifySignature(publicKey, proofPayload({ purpose: 'register', uid, challengeId, challenge }), signature)) {
    throw new HttpsError('permission-denied', 'We couldn’t confirm it’s you on this phone. Try again.');
  }

  let roots: string[];
  let revoked: Set<string>;
  try {
    [roots, revoked] = await Promise.all([googleRoots(), revokedSerials()]);
  } catch {
    throw new HttpsError('unavailable', 'We couldn’t check this phone right now. Try again in a minute.');
  }
  const att = verifyAndroidAttestation({ chain: chain as Buffer[], publicKey, challenge: Buffer.from(challenge, 'base64url'), rootPems: roots, revokedSerials: revoked });
  if (!att.ok) {
    console.warn('[payDeviceRegister] attestation refused', { uid, reason: att.reason });
    throw new HttpsError('failed-precondition', 'This phone’s security chip couldn’t be verified, so it can’t be used for payments.');
  }

  const keyHash = crypto.createHash('sha256').update(publicKey).digest('hex');
  const active = await db().collection(DEVICES).where('uid', '==', uid).where('revokedAt', '==', null).get();
  if (active.docs.some((d) => d.get('keyHash') === keyHash)) throw new HttpsError('already-exists', 'This phone is already registered.');
  if (active.size >= MAX_ACTIVE_DEVICES) throw new HttpsError('resource-exhausted', `You can have ${MAX_ACTIVE_DEVICES} payment phones. Remove one first.`);

  const ref = db().collection(DEVICES).doc();
  await ref.set({
    uid,
    publicKey: publicKey.toString('base64'),
    keyHash,
    platform: 'android',
    hardware: att.hardware,
    label,
    trustedAt: null,
    coolDownUntil: null,
    revokedAt: null,
    lastUsedAt: null,
    createdAt: FieldValue.serverTimestamp(),
  });
  await recordSecurityEvent(uid, 'pay_device_added', { deviceId: ref.id, deviceLabel: label, platform: 'android', ip: callerIp(request), details: { hardware: att.hardware } });
  return { deviceId: ref.id, trusted: false, hardware: att.hardware };
});

/** After a fresh email code: the device may approve money. Extra phones wait 24 h for large amounts. */
export const payDeviceTrust = onCall(async (request) => {
  const uid = uidOf(request);
  const deviceId = idOf(dataOf(request).deviceId, 'device');
  const devRef = db().collection(DEVICES).doc(deviceId);
  const stateRef = db().collection('security_state').doc(uid);
  const others = await db().collection(DEVICES).where('uid', '==', uid).where('revokedAt', '==', null).get();
  const hasOtherTrusted = others.docs.some((d) => d.id !== deviceId && d.get('trustedAt'));

  const result = await db().runTransaction(async (tx) => {
    const [dev, state] = await Promise.all([tx.get(devRef), tx.get(stateRef)]);
    if (!dev.exists || dev.get('uid') !== uid || dev.get('revokedAt')) return { error: 'missing' as const };
    if (dev.get('trustedAt')) return { error: null, coolDownUntil: ms(dev.get('coolDownUntil')) };
    const now = Date.now();
    if (!stepUpUsable(ms(state.get('stepUpAt')), ms(state.get('payDeviceStepUpUsedAt')), now)) return { error: 'step_up' as const };
    const coolDownUntil = hasOtherTrusted ? now + NEW_DEVICE_COOL_DOWN_MS : null;
    tx.update(devRef, { trustedAt: Timestamp.fromMillis(now), coolDownUntil: coolDownUntil ? Timestamp.fromMillis(coolDownUntil) : null });
    tx.set(stateRef, { payDeviceStepUpUsedAt: Timestamp.fromMillis(now) }, { merge: true });
    return { error: null, coolDownUntil };
  });
  if (result.error === 'missing') throw new HttpsError('not-found', 'This phone isn’t registered.');
  if (result.error === 'step_up') throw new HttpsError('failed-precondition', 'Confirm with the code we email you first.');
  await recordSecurityEvent(uid, 'pay_device_trusted', { deviceId, ip: callerIp(request), details: { otherDevices: hasOtherTrusted } });
  return { trusted: true, coolDownUntil: result.coolDownUntil };
});

export interface ApprovalCheck { ok: boolean; reason?: string; coolDownUntil?: number | null }

/**
 * For payment approvals: the payload must be signed by an active device of [uid].
 * [large] amounts also need the new-device cool-down to be over.
 */
export async function verifyDeviceApproval(uid: string, deviceId: string, payload: Buffer, signature: Buffer, large: boolean): Promise<ApprovalCheck> {
  const snap = await db().collection(DEVICES).doc(deviceId).get();
  if (!snap.exists || snap.get('uid') !== uid) return { ok: false, reason: 'unknown_device' };
  const can = deviceCanApprove({ revokedAt: ms(snap.get('revokedAt')), trustedAt: ms(snap.get('trustedAt')), coolDownUntil: ms(snap.get('coolDownUntil')) }, Date.now(), large);
  if (!can.ok) return { ok: false, reason: can.reason, coolDownUntil: ms(snap.get('coolDownUntil')) };
  const key = Buffer.from(String(snap.get('publicKey')), 'base64');
  if (!verifySignature(key, payload, signature)) return { ok: false, reason: 'bad_signature' };
  await snap.ref.update({ lastUsedAt: FieldValue.serverTimestamp() });
  return { ok: true, coolDownUntil: ms(snap.get('coolDownUntil')) };
}

/** "Check it's me": a full round trip with the device key, used by the face card. */
export const payDeviceVerify = onCall(async (request) => {
  const uid = uidOf(request);
  const data = dataOf(request);
  await limit(uid, 'pay_device_verify', 60, 3600_000);
  const challengeId = idOf(data.challengeId, 'check');
  const deviceId = idOf(data.deviceId, 'device');
  const signature = b64(data.signature, 128);
  if (!signature) throw new HttpsError('invalid-argument', 'Missing signature.');
  const challenge = await consumeChallenge(uid, challengeId, 'verify');
  const snap = await db().collection(DEVICES).doc(deviceId).get();
  if (!snap.exists || snap.get('uid') !== uid || snap.get('revokedAt')) return { ok: false, registered: false };
  const key = Buffer.from(String(snap.get('publicKey')), 'base64');
  const ok = verifySignature(key, proofPayload({ purpose: 'verify', uid, challengeId, challenge, deviceId }), signature);
  if (ok) await snap.ref.update({ lastUsedAt: FieldValue.serverTimestamp() });
  return { ok, registered: true, trusted: !!snap.get('trustedAt'), coolDownUntil: ms(snap.get('coolDownUntil')) };
});

export const payDeviceList = onCall(async (request) => {
  const uid = uidOf(request);
  const q = await db().collection(DEVICES).where('uid', '==', uid).where('revokedAt', '==', null).get();
  const devices = q.docs.map((d) => ({
    id: d.id,
    label: String(d.get('label') ?? ''),
    platform: String(d.get('platform') ?? ''),
    hardware: String(d.get('hardware') ?? ''),
    trusted: !!d.get('trustedAt'),
    coolDownUntil: ms(d.get('coolDownUntil')),
    createdAt: ms(d.get('createdAt')),
    lastUsedAt: ms(d.get('lastUsedAt')),
  }));
  devices.sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0));
  return { devices };
});

export const payDeviceRevoke = onCall(async (request) => {
  const uid = uidOf(request);
  const deviceId = idOf(dataOf(request).deviceId, 'device');
  const ref = db().collection(DEVICES).doc(deviceId);
  const done = await db().runTransaction(async (tx) => {
    const s = await tx.get(ref);
    if (!s.exists || s.get('uid') !== uid) return false;
    if (!s.get('revokedAt')) tx.update(ref, { revokedAt: FieldValue.serverTimestamp() });
    return true;
  });
  if (!done) throw new HttpsError('not-found', 'This phone isn’t registered.');
  await recordSecurityEvent(uid, 'pay_device_revoked', { deviceId, ip: callerIp(request) });
  return { ok: true };
});
