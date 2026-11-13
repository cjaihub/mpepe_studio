/** Pure rules for tracked share links. Tested in __tests__/models3d.test.ts. */
import * as crypto from 'crypto';

export type ShareType = 'product' | 'shop';
export const SHARE_TYPES: readonly ShareType[] = ['product', 'shop'];

const ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789';

export function newShareCode(): string {
  let out = '';
  for (const b of crypto.randomBytes(10)) out += ALPHABET[b % ALPHABET.length];
  return out;
}

export const validShareCode = (code: unknown): code is string => typeof code === 'string' && /^[a-z0-9]{10}$/.test(code);

export function validShareTarget(type: unknown, id: unknown): boolean {
  return SHARE_TYPES.includes(type as ShareType) && typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
}

export type SharePlatform = 'android' | 'ios' | 'desktop' | 'bot';

export function sharePlatform(userAgent: string): SharePlatform {
  const ua = userAgent.toLowerCase();
  if (/bot|crawler|spider|facebookexternalhit|whatsapp|telegram|slack|discord|preview|twitter/.test(ua)) return 'bot';
  if (ua.includes('android')) return 'android';
  if (/iphone|ipad|ipod/.test(ua)) return 'ios';
  return 'desktop';
}

/** App route a link opens. */
export function shareRoute(type: ShareType, targetId: string, code: string): string {
  return type === 'product' ? `/shops/p/${targetId}?ref=${code}` : `/shops/${targetId}/stage?ref=${code}`;
}

export const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
