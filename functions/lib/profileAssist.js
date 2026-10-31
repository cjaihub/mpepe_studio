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
exports.onAppReleasePublished = exports.onFeedTuned = exports.suggestProfileDetails = void 0;
/**
 * Smart account completion: Gemini (Vertex AI, the function's service
 * account) suggests a bio, interests and username ideas for details the
 * person has not filled in yet, based on their name and their own recent post
 * captions. Nothing is written; the app shows the ideas and saves only what
 * the person picks. 20 suggestion runs per person per day.
 *
 * Also: `onFeedTuned` turns a `feed_updates/{id}` doc (written by an admin or
 * the ranking jobs when what people see changes) into a friendly
 * "recommendation" notification for each listed person, and
 * `onAppReleasePublished` announces a new `app_releases/{id}` to everyone who
 * has not opted out, through the normal notification pipeline.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const vertexAi_1 = require("./vertexAi");
const db = () => (0, firestore_2.getFirestore)();
const MODEL = 'gemini-2.5-flash';
const DAILY_LIMIT = 20;
function str(v, max = 300) {
    return typeof v === 'string' ? v.slice(0, max).trim() : '';
}
async function underDailyLimit(uid) {
    const day = new Date().toISOString().slice(0, 10);
    const ref = db().collection('ai_usage').doc(`${uid}_profile_${day}`);
    return db().runTransaction(async (tx) => {
        var _a;
        const n = (_a = (await tx.get(ref)).get('count')) !== null && _a !== void 0 ? _a : 0;
        if (n >= DAILY_LIMIT)
            return false;
        tx.set(ref, { uid, kind: 'profile', day, count: n + 1, updatedAt: firestore_2.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    });
}
exports.suggestProfileDetails = (0, https_1.onCall)({ timeoutSeconds: 60, memory: '256MiB' }, async (request) => {
    var _a, _b;
    var _c, _d, _e;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to get profile ideas.');
    if (!(await underDailyLimit(uid))) {
        throw new https_1.HttpsError('resource-exhausted', 'You have used today’s profile ideas. Try again tomorrow.');
    }
    const user = (await db().collection('users').doc(uid).get()).data() || {};
    const name = str(user.fullName || user.displayName || user.name, 80);
    const username = str(user.username, 40);
    const bio = str(user.bio, 200);
    const niches = Array.isArray(user.niches) ? user.niches.filter((n) => typeof n === 'string').slice(0, 10) : [];
    const country = str(user.country || user.countryIso, 40);
    const posts = await db().collection('posts').where('authorId', '==', uid).orderBy('createdAt', 'desc').limit(10).get()
        .catch(() => null);
    const captions = ((_c = posts === null || posts === void 0 ? void 0 : posts.docs) !== null && _c !== void 0 ? _c : [])
        .map((d) => str(d.get('caption') || d.get('description') || d.get('title'), 200))
        .filter(Boolean);
    const lang = str((_b = request.data) === null || _b === void 0 ? void 0 : _b.lang, 10) || 'en';
    try {
        const res = await (0, vertexAi_1.vertexAi)().models.generateContent({
            model: MODEL,
            contents: [{
                    role: 'user',
                    parts: [{ text: JSON.stringify({ name, username, bio, niches, country, recentCaptions: captions }) }],
                }],
            config: {
                systemInstruction: 'You help someone finish their profile on Oneova, a creator social app. Reply ONLY with JSON: ' +
                    '{"bios":["...","...","..."],"interests":["..."],"usernames":["...","...","..."]}. ' +
                    'bios: three short first-person bios (max 120 characters), warm and specific to what they post; ' +
                    'interests: up to 6 one- or two-word topics; usernames: three lowercase handle ideas (letters, digits, _ or ., 3-24 chars) based on their name. ' +
                    `Write in language "${lang}". Never invent facts like jobs, awards or locations that are not in the input. No hashtags.`,
                responseMimeType: 'application/json',
                temperature: 0.7,
                maxOutputTokens: 500,
                thinkingConfig: { thinkingBudget: 0 },
            },
        });
        const raw = (_d = res.text) !== null && _d !== void 0 ? _d : '{}';
        const out = JSON.parse((raw.match(/\{[\s\S]*\}/) || ['{}'])[0]);
        const list = (v, max, len) => (Array.isArray(v) ? v : []).filter((x) => typeof x === 'string' && x.trim().length > 0)
            .map((x) => x.trim().slice(0, len)).slice(0, max);
        return {
            bios: list(out.bios, 3, 160),
            interests: list(out.interests, 6, 30),
            usernames: list(out.usernames, 3, 24).map((u) => u.toLowerCase().replace(/[^a-z0-9_.]/g, '')).filter((u) => u.length >= 3),
        };
    }
    catch (e) {
        logger.error('suggestProfileDetails failed', (_e = e === null || e === void 0 ? void 0 : e.message) !== null && _e !== void 0 ? _e : e);
        throw new https_1.HttpsError('internal', 'We could not come up with ideas right now. Please try again.');
    }
});
/**
 * `feed_updates/{id}`: { userIds: string[], title?, body? } — one friendly
 * note per person that their For You feed changed (e.g. after new interests).
 */
exports.onFeedTuned = (0, firestore_1.onDocumentCreated)('feed_updates/{id}', async (event) => {
    var _a;
    const d = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!d)
        return;
    const ids = Array.isArray(d.userIds) ? d.userIds.filter((u) => typeof u === 'string').slice(0, 500) : [];
    const batch = db().batch();
    for (const uid of ids) {
        batch.set(db().collection('notifications').doc(`feed_${event.params.id}_${uid}`), {
            userId: uid,
            recipientId: uid,
            category: 'recommendation',
            priority: 'low',
            type: 'system',
            title: str(d.title, 80) || 'Your For You feed just got smarter',
            body: str(d.body, 200) || 'We tuned what you see based on what you enjoy. Take a look.',
            deepLink: '/hub/home',
            groupId: 'feed_update',
            isRead: false,
            createdAt: firestore_2.FieldValue.serverTimestamp(),
            timestamp: firestore_2.FieldValue.serverTimestamp(),
        });
    }
    if (ids.length > 0)
        await batch.commit();
});
/**
 * `app_releases/{id}`: { versionCode: number, versionName?, notes? } — tells
 * everyone (except people who switched update notes off) that a new version is
 * out. Written in pages of 400 so large audiences stay within batch limits.
 */
exports.onAppReleasePublished = (0, firestore_1.onDocumentCreated)({ document: 'app_releases/{id}', timeoutSeconds: 540, memory: '512MiB' }, async (event) => {
    var _a;
    const d = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    const code = Number((d === null || d === void 0 ? void 0 : d.versionCode) || 0);
    if (!d || !code)
        return;
    const notes = str(d.notes, 160);
    let last;
    let sent = 0;
    for (;;) {
        let q = db().collection('users').orderBy('__name__').limit(400);
        if (last)
            q = q.startAfter(last);
        const page = await q.get();
        if (page.empty)
            break;
        const batch = db().batch();
        // The app may already have left this note for someone; never send twice.
        const refs = page.docs.map((u) => db().collection('notifications').doc(`app_update_${u.id}_${code}`));
        const existing = new Set((await db().getAll(...refs)).filter((s) => s.exists).map((s) => s.id));
        for (const u of page.docs) {
            if (u.get('notifyAppUpdates') === false)
                continue;
            if (existing.has(`app_update_${u.id}_${code}`))
                continue;
            batch.set(db().collection('notifications').doc(`app_update_${u.id}_${code}`), {
                userId: u.id,
                recipientId: u.id,
                category: 'appUpdate',
                priority: 'low',
                type: 'system',
                title: 'A new version of Oneova is ready',
                body: notes || 'Update to get the latest features and fixes. It only takes a moment.',
                groupId: 'app_update',
                payload: { versionCode: code, versionName: str(d.versionName, 20) },
                isRead: false,
                createdAt: firestore_2.FieldValue.serverTimestamp(),
                timestamp: firestore_2.FieldValue.serverTimestamp(),
            });
            sent++;
        }
        await batch.commit();
        last = page.docs[page.docs.length - 1];
        if (page.size < 400)
            break;
    }
    logger.info('app release announced', { code, sent });
});
//# sourceMappingURL=profileAssist.js.map