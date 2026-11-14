/**
 * Pure checks for trusted payment devices (no Firebase), so they can be tested.
 *
 * A payment device is a P-256 key pair made inside the phone's secure hardware
 * (Android Keystore, StrongBox where present) that can only sign after a
 * fingerprint or face check. The server keeps the public key. On Android the
 * key comes with Google's key attestation certificate chain, which proves:
 *   - the key lives in secure hardware (TEE or StrongBox), not in software;
 *   - it was made for our challenge (no replay of an old registration);
 *   - it needs user authentication to sign;
 *   - it belongs to our app package;
 *   - the chain ends at a Google attestation root and no certificate in it is revoked.
 * See docs/payments/platform/SECURITY_MODEL.md.
 */
import * as crypto from 'crypto';

export const APP_PACKAGE = 'com.oneova.app';
export const CHALLENGE_TTL_MS = 5 * 60_000;
export const STEP_UP_WINDOW_MS = 10 * 60_000;
export const NEW_DEVICE_COOL_DOWN_MS = 24 * 3600_000;
export const MAX_ACTIVE_DEVICES = 5;

export type Hardware = 'strongbox' | 'tee';

/** Sorted keys, no spaces: the exact bytes a device signs. */
export function canonicalJson(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return `[${v.map(canonicalJson).join(',')}]`;
  const o = v as Record<string, unknown>;
  return `{${Object.keys(o).filter((k) => o[k] !== undefined).sort().map((k) => `${JSON.stringify(k)}:${canonicalJson(o[k])}`).join(',')}}`;
}

export function b64(v: unknown, maxBytes = 16_384): Buffer | null {
  if (typeof v !== 'string' || v.length === 0 || v.length > maxBytes * 2) return null;
  const s = v.replace(/-/g, '+').replace(/_/g, '/');
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(s)) return null;
  const buf = Buffer.from(s, 'base64');
  return buf.length > 0 && buf.length <= maxBytes ? buf : null;
}

/** A P-256 public key in SubjectPublicKeyInfo DER, or null. */
export function p256Key(spki: Buffer): crypto.KeyObject | null {
  try {
    const k = crypto.createPublicKey({ key: spki, format: 'der', type: 'spki' });
    if (k.asymmetricKeyType !== 'ec' || k.asymmetricKeyDetails?.namedCurve !== 'prime256v1') return null;
    return k;
  } catch {
    return null;
  }
}

/** ECDSA P-256 / SHA-256 signature (DER, as Android's Signature returns it). */
export function verifySignature(spki: Buffer, data: Buffer, signature: Buffer): boolean {
  const key = p256Key(spki);
  if (!key || signature.length < 8 || signature.length > 80) return false;
  try {
    return crypto.verify('sha256', data, { key, dsaEncoding: 'der' }, signature);
  } catch {
    return false;
  }
}

// ── Minimal DER reader (enough for X.509 extensions and Android KeyDescription) ──

interface Tlv { cls: number; constructed: boolean; tag: number; start: number; body: Buffer; end: number }

function readTlv(buf: Buffer, pos: number): Tlv {
  if (pos >= buf.length) throw new Error('der: out of data');
  const start = pos;
  const first = buf[pos++];
  const cls = first >> 6;
  const constructed = (first & 0x20) !== 0;
  let tag = first & 0x1f;
  if (tag === 0x1f) {
    tag = 0;
    let b: number;
    let n = 0;
    do {
      if (pos >= buf.length || ++n > 4) throw new Error('der: bad tag');
      b = buf[pos++];
      tag = tag * 128 + (b & 0x7f);
    } while (b & 0x80);
  }
  if (pos >= buf.length) throw new Error('der: no length');
  let len = buf[pos++];
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4) throw new Error('der: bad length');
    len = 0;
    for (let i = 0; i < n; i++) {
      if (pos >= buf.length) throw new Error('der: bad length');
      len = len * 256 + buf[pos++];
    }
  }
  const end = pos + len;
  if (end > buf.length) throw new Error('der: length past end');
  return { cls, constructed, tag, start, body: buf.subarray(pos, end), end };
}

function children(body: Buffer): Tlv[] {
  const out: Tlv[] = [];
  let pos = 0;
  while (pos < body.length) {
    const t = readTlv(body, pos);
    out.push(t);
    pos = t.end;
  }
  return out;
}

function intOf(t: Tlv): number {
  let v = 0;
  for (const b of t.body) v = v * 256 + b;
  return v;
}

const KEY_DESCRIPTION_OID = Buffer.from([0x2b, 0x06, 0x01, 0x04, 0x01, 0xd6, 0x79, 0x02, 0x01, 0x11]); // 1.3.6.1.4.1.11129.2.1.17

/** The raw KeyDescription extension value from a certificate, or null. */
export function keyDescriptionOf(certDer: Buffer): Buffer | null {
  const cert = readTlv(certDer, 0);
  const tbs = children(cert.body)[0];
  for (const f of children(tbs.body)) {
    if (f.cls !== 2 || f.tag !== 3) continue; // [3] extensions
    const exts = children(children(f.body)[0].body);
    for (const e of exts) {
      const parts = children(e.body);
      if (parts[0]?.tag === 6 && parts[0].body.equals(KEY_DESCRIPTION_OID)) {
        const octet = parts[parts.length - 1];
        return Buffer.from(octet.body);
      }
    }
  }
  return null;
}

export interface KeyDescription {
  attestationSecurityLevel: number; // 0 software, 1 TEE, 2 StrongBox
  keymasterSecurityLevel: number;
  challenge: Buffer;
  /** Tags present in the hardware-enforced list. */
  hardwareTags: Set<number>;
  packageNames: string[];
}

const TAG_NO_AUTH_REQUIRED = 503;
const TAG_USER_AUTH_TYPE = 504;
const TAG_PURPOSE = 1;
const TAG_ALGORITHM = 2;
const TAG_EC_CURVE = 10;
const TAG_APPLICATION_ID = 709;

function authTags(list: Tlv): Map<number, Tlv> {
  const out = new Map<number, Tlv>();
  for (const t of children(list.body)) if (t.cls === 2) out.set(t.tag, t);
  return out;
}

export function parseKeyDescription(ext: Buffer): KeyDescription {
  const seq = children(readTlv(ext, 0).body);
  if (seq.length < 8) throw new Error('KeyDescription too short');
  const software = authTags(seq[6]);
  const hardware = authTags(seq[7]);
  const packageNames: string[] = [];
  const appId = software.get(TAG_APPLICATION_ID) ?? hardware.get(TAG_APPLICATION_ID);
  if (appId) {
    // [709] EXPLICIT OCTET STRING { AttestationApplicationId SEQUENCE { SET OF PackageInfo, SET OF digest } }
    const octet = children(appId.body)[0];
    const aai = readTlv(octet.body, 0);
    const infos = children(aai.body)[0];
    for (const info of children(infos.body)) {
      const name = children(info.body)[0];
      if (name) packageNames.push(name.body.toString('utf8'));
    }
  }
  return {
    attestationSecurityLevel: intOf(seq[1]),
    keymasterSecurityLevel: intOf(seq[3]),
    challenge: Buffer.from(seq[4].body),
    hardwareTags: new Set(hardware.keys()),
    packageNames,
  };
}

/** Serial numbers as Google's status list writes them: lowercase hex, no leading zeros. */
export function serialKey(hex: string): string {
  return hex.toLowerCase().replace(/^0+(?=.)/, '');
}

export interface AttestationInput {
  chain: Buffer[];          // leaf first
  publicKey: Buffer;        // SPKI the app sent
  challenge: Buffer;        // what the server issued
  rootPems: string[];       // Google attestation roots
  revokedSerials: Set<string>;
  packageName?: string;
  now?: Date;
}

export type AttestationResult = { ok: true; hardware: Hardware } | { ok: false; reason: string };

export function verifyAndroidAttestation(input: AttestationInput): AttestationResult {
  const { chain, publicKey, challenge, rootPems, revokedSerials } = input;
  const now = input.now ?? new Date();
  if (chain.length < 2 || chain.length > 8) return { ok: false, reason: 'chain_length' };
  let certs: crypto.X509Certificate[];
  try {
    certs = chain.map((d) => new crypto.X509Certificate(d));
  } catch {
    return { ok: false, reason: 'chain_parse' };
  }
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].verify(certs[i + 1].publicKey)) return { ok: false, reason: 'chain_signature' };
    // Leaf validity dates are not meaningful on many devices; check the issuers.
    if (i > 0) {
      const from = new Date(certs[i].validFrom);
      const to = new Date(certs[i].validTo);
      if (now < from || now > to) return { ok: false, reason: 'chain_expired' };
    }
  }
  const top = certs[certs.length - 1];
  if (!top.verify(top.publicKey)) return { ok: false, reason: 'root_not_self_signed' };
  const topKey = top.publicKey.export({ type: 'spki', format: 'der' });
  const rootMatch = rootPems.some((pem) => {
    try {
      return new crypto.X509Certificate(pem).publicKey.export({ type: 'spki', format: 'der' }).equals(topKey);
    } catch {
      return false;
    }
  });
  if (!rootMatch) return { ok: false, reason: 'unknown_root' };
  for (const c of certs) if (revokedSerials.has(serialKey(c.serialNumber))) return { ok: false, reason: 'revoked' };

  const leafKey = certs[0].publicKey.export({ type: 'spki', format: 'der' });
  if (!leafKey.equals(publicKey)) return { ok: false, reason: 'key_mismatch' };

  let desc: KeyDescription;
  try {
    const ext = keyDescriptionOf(chain[0]);
    if (!ext) return { ok: false, reason: 'no_key_description' };
    desc = parseKeyDescription(ext);
  } catch {
    return { ok: false, reason: 'key_description_parse' };
  }
  if (desc.challenge.length !== challenge.length || !crypto.timingSafeEqual(desc.challenge, challenge)) {
    return { ok: false, reason: 'challenge_mismatch' };
  }
  if (desc.attestationSecurityLevel < 1 || desc.keymasterSecurityLevel < 1) return { ok: false, reason: 'software_key' };
  if (desc.hardwareTags.has(TAG_NO_AUTH_REQUIRED) || !desc.hardwareTags.has(TAG_USER_AUTH_TYPE)) {
    return { ok: false, reason: 'no_user_auth' };
  }
  for (const t of [TAG_PURPOSE, TAG_ALGORITHM, TAG_EC_CURVE]) {
    if (!desc.hardwareTags.has(t)) return { ok: false, reason: 'not_hardware_enforced' };
  }
  const pkg = input.packageName ?? APP_PACKAGE;
  if (!desc.packageNames.includes(pkg)) return { ok: false, reason: 'wrong_app' };
  return { ok: true, hardware: desc.attestationSecurityLevel >= 2 ? 'strongbox' : 'tee' };
}

/** What a device signs to prove it holds the key (and the user passed a biometric). */
export function proofPayload(p: { purpose: 'register' | 'verify'; uid: string; challengeId: string; challenge: string; deviceId?: string }): Buffer {
  return Buffer.from(canonicalJson({ v: 1, ...p }), 'utf8');
}

export interface DeviceState {
  revokedAt?: number | null;
  trustedAt?: number | null;
  coolDownUntil?: number | null;
}

/** Can this device approve money right now? Large amounts wait out the new-device cool-down. */
export function deviceCanApprove(d: DeviceState, now: number, large: boolean): { ok: boolean; reason?: string } {
  if (d.revokedAt) return { ok: false, reason: 'revoked' };
  if (!d.trustedAt) return { ok: false, reason: 'not_trusted' };
  if (large && d.coolDownUntil && now < d.coolDownUntil) return { ok: false, reason: 'cool_down' };
  return { ok: true };
}

/** Step-up must be fresh and not already spent on another device. */
export function stepUpUsable(stepUpAt: number | null, lastUsedAt: number | null, now: number): boolean {
  if (!stepUpAt || now - stepUpAt > STEP_UP_WINDOW_MS || stepUpAt > now + 60_000) return false;
  return !lastUsedAt || stepUpAt > lastUsedAt;
}
