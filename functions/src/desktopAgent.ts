/**
 * Desktop Computer Agent cryptographic bootstrap.
 *
 * Enrolls a workstation-local 256-bit secret as a dedicated, least-privilege
 * Firebase Auth agent principal (`desktop_agent_<32-hex>`, `{ desktopAgent: true }`)
 * without requiring Anonymous Auth, `iam.serviceAccounts.signBlob`, or macOS
 * Data Protection Keychain entitlements.
 *
 * Security model:
 * - A `desktop_agent_*` UID has zero access to user data on its own.
 * - It can only publish a short-lived 6-digit E2EE pairing offer in
 *   `desktop_pairing/{pin}`, and only gains access to a single
 *   `registered_computers/{deviceId}` document AFTER a signed-in mobile owner
 *   explicitly writes `agent_uid` onto their own computer record during E2EE
 *   PIN verification.
 */
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { callerIp, limit } from './guard/protect';

const AGENT_KEYS = 'desktop_agent_keys';
const KEY_TTL_DAYS = 180;

function sha256(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

export const desktopAgentBootstrap = onCall(async (request) => {
  await limit(callerIp(request), 'desktop_agent_boot', 30, 15 * 60000);

  const data = (request.data ?? {}) as Record<string, unknown>;
  const secret = String(data.secret ?? '').trim();
  const computerName = String(data.computerName ?? '').trim().slice(0, 120);
  const os = String(data.os ?? '').trim().slice(0, 40);

  if (!/^[0-9a-f]{64}$/i.test(secret)) {
    throw new HttpsError(
      'invalid-argument',
      'A 256-bit hex workstation secret is required.',
    );
  }

  const agentUid = `desktop_agent_${crypto.randomBytes(16).toString('hex')}`;
  const agentEmail = `${agentUid}@agent.oneova.internal`;
  const auth = getAuth();

  await auth.createUser({
    uid: agentUid,
    email: agentEmail,
    password: secret,
    displayName: computerName || 'Oneova Desktop Agent',
  });
  await auth.setCustomUserClaims(agentUid, { desktopAgent: true });

  await getFirestore().collection(AGENT_KEYS).doc(agentUid).set({
    secretHash: sha256(secret),
    agentEmail,
    computerName: computerName || 'Workstation',
    os: os || 'desktop',
    createdAt: FieldValue.serverTimestamp(),
    lastUsedAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + KEY_TTL_DAYS * 86400000),
  });

  return { agentUid, agentEmail };
});
