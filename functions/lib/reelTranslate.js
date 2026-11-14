"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.reelTranslate = void 0;
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
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const protect_1 = require("./guard/protect");
const studioAi_1 = require("./studioAi");
const reelTranslateLogic_1 = require("./reelTranslateLogic");
async function findReel(postId) {
    var _a;
    const db = (0, firestore_1.getFirestore)();
    for (const col of ['content', 'posts']) {
        const ref = db.collection(col).doc(postId);
        const snap = await ref.get();
        if (snap.exists)
            return { ref, data: (_a = snap.data()) !== null && _a !== void 0 ? _a : {} };
    }
    return null;
}
/** Same idea as canReadAuthorContent in the rules, kept strict: public reels of public accounts, or your own. */
async function mayRead(uid, data) {
    var _a;
    const authorId = typeof data.authorId === 'string' ? data.authorId : '';
    if (authorId && authorId === uid)
        return true;
    if (((_a = data.visibility) !== null && _a !== void 0 ? _a : 'public') !== 'public')
        return false;
    if (!authorId)
        return true;
    const author = await (0, firestore_1.getFirestore)().collection('users').doc(authorId).get();
    return author.get('isPrivate') !== true;
}
exports.reelTranslate = (0, https_1.onCall)({ memory: '512MiB', timeoutSeconds: 90, secrets: [studioAi_1.openRouterSecret] }, async (request) => {
    var _a, _b;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to see translations.');
    const uid = request.auth.uid;
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const postId = data.postId;
    const target = (0, reelTranslateLogic_1.normalizeLang)(data.target);
    if (!(0, reelTranslateLogic_1.validPostId)(postId))
        throw new https_1.HttpsError('invalid-argument', 'Unknown reel.');
    if (!target)
        throw new https_1.HttpsError('invalid-argument', 'Pick a language to translate into.');
    // Cheap reads of cached translations while scrolling.
    await (0, protect_1.limit)(uid, 'reel_translate', 300, 10 * 60000);
    const reel = await findReel(postId);
    if (!reel)
        throw new https_1.HttpsError('not-found', 'This reel is no longer available.');
    if (!(await mayRead(uid, reel.data)))
        throw new https_1.HttpsError('permission-denied', 'You can\'t see this reel.');
    const caption = typeof reel.data.description === 'string' ? reel.data.description : '';
    const hashtags = Array.isArray(reel.data.hashtags)
        ? reel.data.hashtags.filter((t) => typeof t === 'string').slice(0, 30)
        : [];
    const body = (0, reelTranslateLogic_1.captionBody)(caption);
    const transcript = await reel.ref.collection('transcripts').doc('default').get();
    const segments = (0, reelTranslateLogic_1.cleanSegments)(transcript.get('segments'));
    const hash = (0, reelTranslateLogic_1.sourceHash)(body, segments);
    // Trusted only while the caption it was detected from is unchanged.
    const storedSource = reel.data.sourceLanguageHash === hash ? (0, reelTranslateLogic_1.normalizeLang)(reel.data.sourceLanguage) : null;
    const base = { postId, target, source: storedSource, hashtags };
    if (!body && !segments.length) {
        return Object.assign(Object.assign({}, base), { same: true, support: 'good', caption: '', segments: [], cached: true });
    }
    if ((0, reelTranslateLogic_1.sameLanguage)(storedSource, target)) {
        return Object.assign(Object.assign({}, base), { same: true, support: 'good', caption: body, segments, cached: true });
    }
    const tref = reel.ref.collection('translations').doc(target);
    const hit = await tref.get();
    if (hit.exists && hit.get('sourceHash') === hash) {
        return Object.assign(Object.assign({}, base), { source: storedSource !== null && storedSource !== void 0 ? storedSource : (0, reelTranslateLogic_1.normalizeLang)(hit.get('source')), same: hit.get('same') === true, support: (0, reelTranslateLogic_1.cleanSupport)(hit.get('support')), caption: String((_b = hit.get('caption')) !== null && _b !== void 0 ? _b : body), segments: (0, reelTranslateLogic_1.cleanSegments)(hit.get('segments')), cached: true });
    }
    // A new translation costs a model call: tighter per-user cap.
    await (0, protect_1.limit)(uid, 'reel_translate_new', 60, 60 * 60000);
    let out;
    try {
        out = await (0, studioAi_1.translateWithOpenRouter)((0, reelTranslateLogic_1.buildItems)(body, segments), target, storedSource !== null && storedSource !== void 0 ? storedSource : undefined, !storedSource);
    }
    catch (e) {
        logger.error('[reelTranslate] model call failed', { postId, target, error: String(e) });
        throw new https_1.HttpsError('unavailable', 'Translation is not available right now. Try again in a moment.');
    }
    const source = storedSource !== null && storedSource !== void 0 ? storedSource : (0, reelTranslateLogic_1.normalizeLang)(out.source);
    const support = (0, reelTranslateLogic_1.cleanSupport)(out.support);
    const same = (0, reelTranslateLogic_1.sameLanguage)(source, target);
    const mapped = same || support === 'unsupported' ? { caption: body, segments } : (0, reelTranslateLogic_1.applyTranslations)(body, segments, out.translations);
    if (!mapped)
        throw new https_1.HttpsError('internal', 'The translation came back incomplete. Try again.');
    const writes = [
        tref.set({
            target,
            source: source !== null && source !== void 0 ? source : null,
            same,
            support,
            caption: mapped.caption,
            segments: mapped.segments,
            sourceHash: hash,
            model: 'openrouter:google/gemini-2.5-flash',
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }),
    ];
    // Detected once, then reused for every other language and by the app.
    if (!storedSource && source)
        writes.push(reel.ref.update({ sourceLanguage: source, sourceLanguageHash: hash }));
    await Promise.all(writes);
    return Object.assign(Object.assign({}, base), { source, same, support, caption: mapped.caption, segments: mapped.segments, cached: false });
});
//# sourceMappingURL=reelTranslate.js.map