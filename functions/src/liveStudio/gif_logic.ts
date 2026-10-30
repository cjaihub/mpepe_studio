/**
 * LIVE STUDIO v2 — GIF comments (pure). GIFs come from GIPHY (searched
 * server-side by lsGifSearch); a comment may carry one GIF whose URL must be
 * a GIPHY media host, so clients can't post arbitrary links as images.
 */

export interface CommentGif {
  id: string;
  url: string;
  w: number;
  h: number;
}

const GIPHY_MEDIA = /^https:\/\/media[0-9]?\.giphy\.com\/[A-Za-z0-9/_.\-?=&]+$/;

/** Validated GIF, null when absent, or throws (via the returned string) when invalid. */
export function parseCommentGif(raw: unknown): CommentGif | null | 'invalid' {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== 'object' || Array.isArray(raw)) return 'invalid';
  const g = raw as Record<string, unknown>;
  const url = typeof g.url === 'string' ? g.url.trim() : '';
  const id = typeof g.id === 'string' ? g.id.trim() : '';
  const w = typeof g.w === 'number' && Number.isFinite(g.w) ? Math.round(g.w) : 0;
  const h = typeof g.h === 'number' && Number.isFinite(g.h) ? Math.round(g.h) : 0;
  if (!GIPHY_MEDIA.test(url) || url.length > 500 || !/^[A-Za-z0-9]{1,40}$/.test(id)) return 'invalid';
  if (w < 1 || h < 1 || w > 4000 || h > 4000) return 'invalid';
  return { id, url, w, h };
}

/** Maps one GIPHY API result to what the app renders (small webp + size). */
export function fromGiphy(r: unknown): CommentGif | null {
  const o = (r && typeof r === 'object' ? r : {}) as Record<string, any>;
  const img = o.images?.fixed_width ?? o.images?.downsized;
  const url = (img?.webp || img?.url || '') as string;
  const parsed = parseCommentGif({ id: o.id, url: url.split('?')[0], w: Number(img?.width), h: Number(img?.height) });
  return parsed && parsed !== 'invalid' ? parsed : null;
}

export const sanitizeGifQuery = (q: unknown): string =>
  typeof q === 'string' ? q.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, 50) : '';
