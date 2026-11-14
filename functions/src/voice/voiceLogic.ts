/**
 * Pure helpers for "My voice" (testable without Firebase).
 * Stream tokens must match services/voice/voice/logic.py byte for byte.
 */
import * as crypto from 'crypto';

/** Chatterbox speaks these directly in the person's voice; others are converted. */
export const CLONE_LANGUAGES = new Set('ar da de el en es fi fr he hi it ja ko ms nl no pl pt ru sv sw tr zh'.split(' '));
export const CONSENT_VERSION = 1;
export const MAX_SPEAK_CHARS = 400;

export function baseLang(code: unknown): string {
  return String(code ?? '').trim().toLowerCase().split(/[-_]/)[0];
}

export function engineFor(language: unknown): 'clone' | 'convert' {
  return CLONE_LANGUAGES.has(baseLang(language)) ? 'clone' : 'convert';
}

/** Only an https Cloud Run URL is ever called. */
export function validVoiceUrl(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  try {
    const u = new URL(v.trim());
    return u.protocol === 'https:' && u.hostname.endsWith('.run.app') && !u.search && !u.hash ? u.origin : null;
  } catch {
    return null;
  }
}

const b64url = (b: Buffer) => b.toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

/** {"call":…,"exp":…,"uid":…}.HMAC — same as Python's json.dumps(sort_keys=True, separators=(",", ":")). */
export function signStreamToken(key: Buffer, uid: string, callId: string, ttlS = 900, nowS = Math.floor(Date.now() / 1000)): string {
  const body = JSON.stringify({ call: callId, exp: Math.floor(nowS + ttlS), uid });
  const sig = crypto.createHmac('sha256', key).update(body).digest();
  return `${b64url(Buffer.from(body))}.${b64url(sig)}`;
}

/** Practical phrases to read, about a minute in all (also shown in the app). */
export const ENROLL_PROMPTS = [
  'Hi, it’s me. I’m on my way, I’ll call you when I get there.',
  'Can you send me the price and the delivery time, please?',
  'Thank you so much for watching, see you in the next video!',
  'That sounds great. Let’s meet tomorrow at ten in the morning.',
  'I’m a bit busy right now, can I call you back in five minutes?',
  'Welcome to my shop. This one is my favourite, let me show you.',
];
