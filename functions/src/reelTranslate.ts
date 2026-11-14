/**
 * Reel translator: each reel is translated once per language and cached.
 *
 *   reelTranslate({ postId, target })
 *     → { postId, target, source, same, support, caption, hashtags, segments: [{ startMs, endMs, text }], cached }
 *
 * The reel lives in `content/{id}` (or the older `posts/{id}`). Translations are
 * stored at `{collection}/{id}/translations/{lang}`; clients may read them, only
 * this function writes them (firestore.rules). The caption is translated without
 * its hashtags (they stay as they are), plus the reel's transcribed caption
 * track (`content/{id}/transcripts/default`) when it has one. The source
 * language is detected once and stored on the reel as `sourceLanguage` (with
 * `sourceLanguageHash`, so an edited caption is detected again).
 *
 * Text translation runs on OpenRouter (OPENROUTER_API_KEY secret) through the
 * same helper as studioTranslate (studioAi.ts). No AI key reaches the app, and
 * caption text is never logged.
 */
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, DocumentReference } from 'firebase-admin/firestore';
import { limit } from './guard/protect';
import { openRouterSecret, translateWithOpenRouter } from './studioAi';
import {
  normalizeLang,
  sameLanguage,
  captionBody,
  cleanSegments,
  buildItems,
  applyTranslations,
  sourceHash,
  cleanSupport,
  validPostId,
  Segment,
} from './reelTranslateLogic';

interface Result {
  postId: string;
  target: string;
  source: string | null;
  same: boolean;
  support: string;
  caption: string;
  hashtags: string[];
  segments: Segment[];
  cached: boolean;
}

async function findReel(postId: string): Promise<{ ref: DocumentReference; data: Record<string, unknown> } | null> {
  const db = getFirestore();
  for (const col of ['content', 'posts']) {
    const ref = db.collection(col).doc(postId);
    const snap = await ref.get();
    if (snap.exists) return { ref, data: snap.data() ?? {} };
  }
  return null;
}

/** Same idea as canReadAuthorContent in the rules, kept strict: public reels of public accounts, or your own. */
async function mayRead(uid: string, data: Record<string, unknown>): Promise<boolean> {
  const authorId = typeof data.authorId === 'string' ? data.authorId : '';
  if (authorId && authorId === uid) return true;
  if ((data.visibility ?? 'public') !== 'public') return false;
  if (!authorId) return true;
  const author = await getFirestore().collection('users').doc(authorId).get();
  return author.get('isPrivate') !== true;
}

export const reelTranslate = onCall(
  { memory: '256MiB', timeoutSeconds: 90, secrets: [openRouterSecret] },
  async (request): Promise<Result> => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in to see translations.');
    const uid = request.auth.uid;
    const data = (request.data ?? {}) as Record<string, unknown>;
    const postId = data.postId;
    const target = normalizeLang(data.target);
    if (!validPostId(postId)) throw new HttpsError('invalid-argument', 'Unknown reel.');
    if (!target) throw new HttpsError('invalid-argument', 'Pick a language to translate into.');

    // Cheap reads of cached translations while scrolling.
    await limit(uid, 'reel_translate', 300, 10 * 60000);

    const reel = await findReel(postId);
    if (!reel) throw new HttpsError('not-found', 'This reel is no longer available.');
    if (!(await mayRead(uid, reel.data))) throw new HttpsError('permission-denied', 'You can\'t see this reel.');

    const caption = typeof reel.data.description === 'string' ? reel.data.description : '';
    const hashtags = Array.isArray(reel.data.hashtags)
      ? (reel.data.hashtags as unknown[]).filter((t): t is string => typeof t === 'string').slice(0, 30)
      : [];
    const body = captionBody(caption);
    const transcript = await reel.ref.collection('transcripts').doc('default').get();
    const segments = cleanSegments(transcript.get('segments'));
    const hash = sourceHash(body, segments);
    // Trusted only while the caption it was detected from is unchanged.
    const storedSource = reel.data.sourceLanguageHash === hash ? normalizeLang(reel.data.sourceLanguage) : null;
    const base: Omit<Result, 'same' | 'support' | 'caption' | 'segments' | 'cached'> = { postId, target, source: storedSource, hashtags };

    if (!body && !segments.length) {
      return { ...base, same: true, support: 'good', caption: '', segments: [], cached: true };
    }
    if (sameLanguage(storedSource, target)) {
      return { ...base, same: true, support: 'good', caption: body, segments, cached: true };
    }

    const tref = reel.ref.collection('translations').doc(target);
    const hit = await tref.get();
    if (hit.exists && hit.get('sourceHash') === hash) {
      return {
        ...base,
        source: storedSource ?? normalizeLang(hit.get('source')),
        same: hit.get('same') === true,
        support: cleanSupport(hit.get('support')),
        caption: String(hit.get('caption') ?? body),
        segments: cleanSegments(hit.get('segments')),
        cached: true,
      };
    }

    // A new translation costs a model call: tighter per-user cap.
    await limit(uid, 'reel_translate_new', 60, 60 * 60000);

    let out: { support: string; translations: string[]; source?: string };
    try {
      out = await translateWithOpenRouter(buildItems(body, segments), target, storedSource ?? undefined, !storedSource);
    } catch (e) {
      logger.error('[reelTranslate] model call failed', { postId, target, error: String(e) });
      throw new HttpsError('unavailable', 'Translation is not available right now. Try again in a moment.');
    }
    const source = storedSource ?? normalizeLang(out.source);
    const support = cleanSupport(out.support);
    const same = sameLanguage(source, target);
    const mapped = same || support === 'unsupported' ? { caption: body, segments } : applyTranslations(body, segments, out.translations);
    if (!mapped) throw new HttpsError('internal', 'The translation came back incomplete. Try again.');

    const writes: Promise<unknown>[] = [
      tref.set({
        target,
        source: source ?? null,
        same,
        support,
        caption: mapped.caption,
        segments: mapped.segments,
        sourceHash: hash,
        model: 'openrouter:google/gemini-2.5-flash',
        updatedAt: FieldValue.serverTimestamp(),
      }),
    ];
    // Detected once, then reused for every other language and by the app.
    if (!storedSource && source) writes.push(reel.ref.update({ sourceLanguage: source, sourceLanguageHash: hash }));
    await Promise.all(writes);

    return { ...base, source, same, support, caption: mapped.caption, segments: mapped.segments, cached: false };
  },
);
