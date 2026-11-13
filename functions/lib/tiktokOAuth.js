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
exports.tiktokWebhook = exports.tiktokPublish = exports.tiktokCreatorInfo = exports.tiktokVideos = exports.tiktokProfile = exports.tiktokDisconnect = exports.tiktokExchangeCode = void 0;
/**
 * TikTok for Oneova, server side. The client secret and the user's TikTok
 * tokens never reach the app.
 *
 *   tiktokExchangeCode    { code } → connects the account: stores the tokens
 *                         (encrypted, users/{uid}/secure_tokens/tiktok), writes
 *                         social_connections/tiktok and returns the profile.
 *   tiktokProfile         → profile + stats (user.info.basic/profile/stats).
 *   tiktokVideos          { cursor? } → the creator's public videos (video.list).
 *   tiktokCreatorInfo     → what TikTok allows this creator to post (privacy
 *                         options, interaction settings, max duration). The
 *                         post sheet must show these before a direct post.
 *   tiktokPublish         { contentId, mode: 'draft' | 'direct', … } → sends an
 *                         Oneova video to TikTok (video.upload / video.publish).
 *   tiktokDisconnect      → revokes the token and removes the connection.
 *   tiktokWebhook         TikTok webhook: post status + access removed.
 *
 * Setup:
 *   firebase functions:secrets:set TIKTOK_CLIENT_SECRET --project mpepe-2b4bd
 *   TIKTOK_CLIENT_KEY / TIKTOK_REDIRECT_URI live in functions/.env.mpepe-2b4bd.
 * Rotating the client secret makes stored tokens unreadable: people reconnect.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const protect_1 = require("./guard/protect");
const gmailUser_1 = require("./gmailUser");
const db = () => (0, firestore_1.getFirestore)();
const tiktokClientSecret = (0, params_1.defineSecret)('TIKTOK_CLIENT_SECRET');
const tiktokClientKey = (0, params_1.defineString)('TIKTOK_CLIENT_KEY');
const tiktokRedirectUri = (0, params_1.defineString)('TIKTOK_REDIRECT_URI');
const API = 'https://open.tiktokapis.com/v2';
const PROFILE_FIELDS = [
    'open_id', 'union_id', 'avatar_url', 'display_name', 'username', 'bio_description',
    'profile_deep_link', 'is_verified', 'follower_count', 'following_count', 'likes_count', 'video_count',
].join(',');
const VIDEO_FIELDS = [
    'id', 'title', 'video_description', 'cover_image_url', 'share_url', 'duration', 'create_time',
    'view_count', 'like_count', 'comment_count', 'share_count',
].join(',');
const PRIVACY = ['PUBLIC_TO_EVERYONE', 'MUTUAL_FOLLOW_FRIENDS', 'FOLLOWER_OF_CREATOR', 'SELF_ONLY'];
const MAX_UPLOAD_BYTES = 250 * 1024 * 1024;
const tokenRef = (uid) => db().collection('users').doc(uid).collection('secure_tokens').doc('tiktok');
const connectionRef = (uid) => db().collection('users').doc(uid).collection('social_connections').doc('tiktok');
// ── tokens ────────────────────────────────────────────────────────────────
function tokenKey() {
    return Buffer.from(crypto.hkdfSync('sha256', tiktokClientSecret.value(), 'oneova', 'tiktok-user-tokens', 32));
}
async function oauthToken(params) {
    var _a, _b;
    const res = await fetch(`${API}/oauth/token/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams(Object.assign({ client_key: tiktokClientKey.value(), client_secret: tiktokClientSecret.value() }, params)),
    });
    const body = (await res.json().catch(() => ({})));
    if (!res.ok || !body.access_token) {
        logger.warn('[tiktok] token call failed', { status: res.status, error: body.error });
        throw new https_1.HttpsError('failed-precondition', String((_b = (_a = body.error_description) !== null && _a !== void 0 ? _a : body.error) !== null && _b !== void 0 ? _b : 'TikTok sign-in failed.'));
    }
    return body;
}
function toTokenSet(body, now = Date.now()) {
    var _a, _b, _c, _d, _e;
    return {
        accessToken: String(body.access_token),
        refreshToken: String((_a = body.refresh_token) !== null && _a !== void 0 ? _a : ''),
        expiresAt: now + Number((_b = body.expires_in) !== null && _b !== void 0 ? _b : 86400) * 1000,
        refreshExpiresAt: now + Number((_c = body.refresh_expires_in) !== null && _c !== void 0 ? _c : 31536000) * 1000,
        openId: String((_d = body.open_id) !== null && _d !== void 0 ? _d : ''),
        scope: String((_e = body.scope) !== null && _e !== void 0 ? _e : ''),
    };
}
async function saveTokens(uid, t) {
    await tokenRef(uid).set({
        blob: (0, gmailUser_1.encryptWith)(tokenKey(), JSON.stringify(t), uid),
        openId: t.openId,
        scope: t.scope,
        expiresAt: t.expiresAt,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
}
/** A valid access token for [uid], refreshed when it is about to expire. */
async function accessToken(uid) {
    const snap = await tokenRef(uid).get();
    const blob = snap.get('blob');
    if (!blob)
        throw new https_1.HttpsError('failed-precondition', 'Connect TikTok first.');
    let t;
    try {
        t = JSON.parse((0, gmailUser_1.decryptWith)(tokenKey(), blob, uid));
    }
    catch (_a) {
        throw new https_1.HttpsError('failed-precondition', 'Reconnect TikTok.');
    }
    if (t.expiresAt - Date.now() > 5 * 60000)
        return t;
    if (!t.refreshToken || t.refreshExpiresAt < Date.now()) {
        await connectionRef(uid).set({ tokenStore: 'expired' }, { merge: true });
        throw new https_1.HttpsError('failed-precondition', 'Your TikTok sign-in expired. Reconnect TikTok.');
    }
    const fresh = toTokenSet(await oauthToken({ grant_type: 'refresh_token', refresh_token: t.refreshToken }));
    if (!fresh.openId)
        fresh.openId = t.openId;
    if (!fresh.refreshToken)
        fresh.refreshToken = t.refreshToken;
    await saveTokens(uid, fresh);
    return fresh;
}
/** Calls a TikTok API with the user's token; TikTok answers `{ data, error }`. */
async function tiktokApi(t, path, init = {}) {
    var _a, _b, _c;
    var _d, _e, _f;
    const res = await fetch(`${API}${path}`, {
        method: (_d = init.method) !== null && _d !== void 0 ? _d : 'GET',
        headers: Object.assign({ Authorization: `Bearer ${t.accessToken}` }, (init.body !== undefined ? { 'Content-Type': 'application/json; charset=UTF-8' } : {})),
        body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
    });
    const body = (await res.json().catch(() => ({})));
    const code = (_e = (_a = body.error) === null || _a === void 0 ? void 0 : _a.code) !== null && _e !== void 0 ? _e : (res.ok ? 'ok' : String(res.status));
    if (code !== 'ok') {
        logger.warn('[tiktok] api error', { path, status: res.status, code, message: (_b = body.error) === null || _b === void 0 ? void 0 : _b.message });
        const msg = code === 'scope_not_authorized'
            ? 'Reconnect TikTok and allow this permission.'
            : code === 'spam_risk_too_many_posts' || code === 'rate_limit_exceeded'
                ? 'TikTok limits how often you can post. Try again later.'
                : ((_c = body.error) === null || _c === void 0 ? void 0 : _c.message) || 'TikTok request failed.';
        throw new https_1.HttpsError('failed-precondition', msg);
    }
    return (_f = body.data) !== null && _f !== void 0 ? _f : {};
}
function requireUid(request) {
    var _a;
    const uid = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return uid;
}
function publicProfile(user) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    return {
        openId: String((_a = user.open_id) !== null && _a !== void 0 ? _a : ''),
        unionId: String((_b = user.union_id) !== null && _b !== void 0 ? _b : ''),
        displayName: String((_c = user.display_name) !== null && _c !== void 0 ? _c : 'TikTok user'),
        username: (_d = user.username) !== null && _d !== void 0 ? _d : null,
        avatarUrl: (_e = user.avatar_url) !== null && _e !== void 0 ? _e : null,
        bio: (_f = user.bio_description) !== null && _f !== void 0 ? _f : null,
        profileUrl: (_g = user.profile_deep_link) !== null && _g !== void 0 ? _g : null,
        isVerified: user.is_verified === true,
        followerCount: Number((_h = user.follower_count) !== null && _h !== void 0 ? _h : 0),
        followingCount: Number((_j = user.following_count) !== null && _j !== void 0 ? _j : 0),
        likesCount: Number((_k = user.likes_count) !== null && _k !== void 0 ? _k : 0),
        videoCount: Number((_l = user.video_count) !== null && _l !== void 0 ? _l : 0),
    };
}
async function fetchProfile(t) {
    var _a;
    const data = await tiktokApi(t, `/user/info/?fields=${PROFILE_FIELDS}`);
    return publicProfile(((_a = data.user) !== null && _a !== void 0 ? _a : {}));
}
// ── connect ───────────────────────────────────────────────────────────────
exports.tiktokExchangeCode = (0, https_1.onCall)({ secrets: [tiktokClientSecret] }, async (request) => {
    var _a;
    var _b;
    const uid = requireUid(request);
    await (0, protect_1.limit)(uid, 'oauth_tiktok', 10, 10 * 60000);
    const code = String((_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : '');
    if (!code || code.length > 2048)
        throw new https_1.HttpsError('invalid-argument', 'Missing authorization code.');
    const t = toTokenSet(await oauthToken({ code, grant_type: 'authorization_code', redirect_uri: tiktokRedirectUri.value() }));
    await saveTokens(uid, t);
    const profile = await fetchProfile(t);
    await connectionRef(uid).set({
        platform: 'tiktok',
        openId: t.openId || profile.openId,
        unionId: profile.unionId,
        accountName: profile.displayName,
        username: profile.username,
        profilePictureUrl: profile.avatarUrl,
        profileUrl: profile.profileUrl,
        isVerified: profile.isVerified,
        stats: { followers: profile.followerCount, following: profile.followingCount, likes: profile.likesCount, videos: profile.videoCount },
        grantedScopes: t.scope.split(',').filter(Boolean),
        tokenStore: 'server',
        connectedAt: firestore_1.FieldValue.serverTimestamp(),
        statsUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    // Which Oneova account this TikTok person belongs to, so webhook events
    // (post published, access removed…) reach the right person.
    const openId = t.openId || profile.openId;
    if (openId) {
        await db().collection('tiktok_users').doc(openId).set({ uids: firestore_1.FieldValue.arrayUnion(uid), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    }
    return { account: profile, scopes: t.scope.split(',').filter(Boolean) };
});
exports.tiktokDisconnect = (0, https_1.onCall)({ secrets: [tiktokClientSecret] }, async (request) => {
    const uid = requireUid(request);
    try {
        const t = await accessToken(uid);
        await fetch(`${API}/oauth/revoke/`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ client_key: tiktokClientKey.value(), client_secret: tiktokClientSecret.value(), token: t.accessToken }),
        });
    }
    catch (e) {
        logger.info('[tiktokDisconnect] revoke skipped', { error: String(e) });
    }
    await Promise.all([tokenRef(uid).delete(), connectionRef(uid).delete()]);
    return { ok: true };
});
// ── profile, videos ───────────────────────────────────────────────────────
exports.tiktokProfile = (0, https_1.onCall)({ secrets: [tiktokClientSecret] }, async (request) => {
    const uid = requireUid(request);
    await (0, protect_1.limit)(uid, 'tiktok_read', 60, 10 * 60000);
    const profile = await fetchProfile(await accessToken(uid));
    await connectionRef(uid).set({
        accountName: profile.displayName,
        username: profile.username,
        profilePictureUrl: profile.avatarUrl,
        profileUrl: profile.profileUrl,
        isVerified: profile.isVerified,
        stats: { followers: profile.followerCount, following: profile.followingCount, likes: profile.likesCount, videos: profile.videoCount },
        statsUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return { account: profile };
});
exports.tiktokVideos = (0, https_1.onCall)({ secrets: [tiktokClientSecret] }, async (request) => {
    var _a;
    var _b, _c, _d;
    const uid = requireUid(request);
    await (0, protect_1.limit)(uid, 'tiktok_read', 60, 10 * 60000);
    const cursor = Number((_b = (_a = request.data) === null || _a === void 0 ? void 0 : _a.cursor) !== null && _b !== void 0 ? _b : 0) || undefined;
    const data = await tiktokApi(await accessToken(uid), `/video/list/?fields=${VIDEO_FIELDS}`, {
        method: 'POST',
        body: Object.assign({ max_count: 20 }, (cursor ? { cursor } : {})),
    });
    return { videos: (_c = data.videos) !== null && _c !== void 0 ? _c : [], cursor: (_d = data.cursor) !== null && _d !== void 0 ? _d : null, hasMore: data.has_more === true };
});
// ── posting ───────────────────────────────────────────────────────────────
exports.tiktokCreatorInfo = (0, https_1.onCall)({ secrets: [tiktokClientSecret] }, async (request) => {
    var _a, _b, _c, _d;
    const uid = requireUid(request);
    await (0, protect_1.limit)(uid, 'tiktok_read', 60, 10 * 60000);
    const d = await tiktokApi(await accessToken(uid), '/post/publish/creator_info/query/', { method: 'POST', body: {} });
    return {
        nickname: (_a = d.creator_nickname) !== null && _a !== void 0 ? _a : null,
        username: (_b = d.creator_username) !== null && _b !== void 0 ? _b : null,
        avatarUrl: (_c = d.creator_avatar_url) !== null && _c !== void 0 ? _c : null,
        privacyLevelOptions: Array.isArray(d.privacy_level_options) ? d.privacy_level_options : [],
        commentDisabled: d.comment_disabled === true,
        duetDisabled: d.duet_disabled === true,
        stitchDisabled: d.stitch_disabled === true,
        maxVideoPostDurationSec: Number((_d = d.max_video_post_duration_sec) !== null && _d !== void 0 ? _d : 0) || null,
    };
});
/** Storage object path from a Firebase download URL of our bucket. */
function storagePathOf(url) {
    const m = /^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\/([^?]+)/.exec(url);
    return m ? decodeURIComponent(m[1]) : null;
}
/** TikTok FILE_UPLOAD chunking: 5–64 MB chunks, the last one takes the rest. */
function chunking(size) {
    if (size <= 64 * 1024 * 1024)
        return { chunkSize: size, count: 1 };
    const chunkSize = 10 * 1024 * 1024;
    return { chunkSize, count: Math.floor(size / chunkSize) };
}
exports.tiktokPublish = (0, https_1.onCall)({ secrets: [tiktokClientSecret], memory: '1GiB', timeoutSeconds: 300 }, async (request) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const uid = requireUid(request);
    await (0, protect_1.limit)(uid, 'tiktok_publish', 10, 3600000);
    const data = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const contentId = String((_b = data.contentId) !== null && _b !== void 0 ? _b : '');
    const mode = data.mode === 'direct' ? 'direct' : 'draft';
    if (!/^[A-Za-z0-9_-]{1,80}$/.test(contentId))
        throw new https_1.HttpsError('invalid-argument', 'Pick a video.');
    const contentRef = db().collection('content').doc(contentId);
    const content = await contentRef.get();
    if (!content.exists || content.get('authorId') !== uid)
        throw new https_1.HttpsError('permission-denied', 'You can only send your own posts.');
    if (content.get('type') === 'photo')
        throw new https_1.HttpsError('invalid-argument', 'Only videos can go to TikTok.');
    const path = storagePathOf(String((_c = content.get('mediaUrl')) !== null && _c !== void 0 ? _c : ''));
    if (!path || !path.startsWith(`content/${uid}/`))
        throw new https_1.HttpsError('failed-precondition', 'This video can’t be sent to TikTok.');
    const t = await accessToken(uid);
    const file = (0, storage_1.getStorage)().bucket().file(path);
    const [meta] = await file.getMetadata();
    const size = Number((_d = meta.size) !== null && _d !== void 0 ? _d : 0);
    if (!size || size > MAX_UPLOAD_BYTES)
        throw new https_1.HttpsError('failed-precondition', 'This video is too large for TikTok upload.');
    const { chunkSize, count } = chunking(size);
    const sourceInfo = { source: 'FILE_UPLOAD', video_size: size, chunk_size: chunkSize, total_chunk_count: count };
    let init;
    if (mode === 'direct') {
        const privacy = String((_e = data.privacyLevel) !== null && _e !== void 0 ? _e : '');
        if (!PRIVACY.includes(privacy))
            throw new https_1.HttpsError('invalid-argument', 'Choose who can see this post.');
        const brandContent = data.brandContent === true;
        // TikTok: branded content can't be private.
        if (brandContent && privacy === 'SELF_ONLY')
            throw new https_1.HttpsError('invalid-argument', 'Branded content can’t be private.');
        init = await tiktokApi(t, '/post/publish/video/init/', {
            method: 'POST',
            body: {
                post_info: {
                    title: String((_g = (_f = data.title) !== null && _f !== void 0 ? _f : content.get('description')) !== null && _g !== void 0 ? _g : '').slice(0, 2200),
                    privacy_level: privacy,
                    disable_comment: data.disableComment === true,
                    disable_duet: data.disableDuet === true,
                    disable_stitch: data.disableStitch === true,
                    brand_content_toggle: brandContent,
                    brand_organic_toggle: data.brandOrganic === true,
                },
                source_info: sourceInfo,
            },
        });
    }
    else {
        init = await tiktokApi(t, '/post/publish/inbox/video/init/', { method: 'POST', body: { source_info: sourceInfo } });
    }
    const publishId = String((_h = init.publish_id) !== null && _h !== void 0 ? _h : '');
    const uploadUrl = String((_j = init.upload_url) !== null && _j !== void 0 ? _j : '');
    if (!publishId || !uploadUrl)
        throw new https_1.HttpsError('unavailable', 'TikTok did not accept the upload. Try again.');
    await db().collection('tiktok_publishes').doc(publishId).set({ uid, contentId, mode, createdAt: firestore_1.FieldValue.serverTimestamp() });
    await contentRef.set({ tiktok: { publishId, mode, status: 'uploading', updatedAt: firestore_1.FieldValue.serverTimestamp() } }, { merge: true });
    try {
        const [bytes] = await file.download();
        for (let i = 0; i < count; i++) {
            const start = i * chunkSize;
            const end = i === count - 1 ? size - 1 : start + chunkSize - 1;
            const res = await fetch(uploadUrl, {
                method: 'PUT',
                headers: {
                    'Content-Type': String((_k = meta.contentType) !== null && _k !== void 0 ? _k : 'video/mp4'),
                    'Content-Length': String(end - start + 1),
                    'Content-Range': `bytes ${start}-${end}/${size}`,
                },
                body: new Uint8Array(bytes.subarray(start, end + 1)),
            });
            if (!res.ok)
                throw new Error(`upload chunk ${i + 1}/${count}: HTTP ${res.status}`);
        }
    }
    catch (e) {
        logger.warn('[tiktokPublish] upload failed', { publishId, error: String(e) });
        await contentRef.set({ tiktok: { status: 'failed', updatedAt: firestore_1.FieldValue.serverTimestamp() } }, { merge: true });
        throw new https_1.HttpsError('unavailable', 'Upload to TikTok failed. Try again.');
    }
    await contentRef.set({ tiktok: { status: 'processing', updatedAt: firestore_1.FieldValue.serverTimestamp() } }, { merge: true });
    return { publishId, mode };
});
// ── Webhooks ─────────────────────────────────────────────────────────────
// Dashboard: Webhooks → Callback URL
//   https://us-central1-mpepe-2b4bd.cloudfunctions.net/tiktokWebhook
// TikTok signs each call: header `TikTok-Signature: t=<unix>,s=<hex>` where
// s = HMAC-SHA256(client_secret, `${t}.${rawBody}`).
const MAX_SKEW_SECONDS = 5 * 60;
function validSignature(header, rawBody) {
    var _a;
    const parts = Object.fromEntries(header.split(',').map((p) => p.trim().split('=', 2)));
    const t = Number(parts.t);
    const s = (_a = parts.s) !== null && _a !== void 0 ? _a : '';
    if (!t || !/^[0-9a-f]{64}$/i.test(s))
        return false;
    if (Math.abs(Date.now() / 1000 - t) > MAX_SKEW_SECONDS)
        return false;
    const expected = crypto.createHmac('sha256', tiktokClientSecret.value()).update(`${t}.`).update(rawBody).digest();
    const given = Buffer.from(s, 'hex');
    return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}
const EVENT_TEXT = {
    'post.publish.complete': { title: 'Posted to TikTok', body: 'Your video finished uploading to TikTok.' },
    'post.publish.publicly_available': { title: 'Live on TikTok', body: 'Your video is now public on TikTok.' },
    'post.publish.inbox_delivered': { title: 'Draft sent to TikTok', body: 'Open TikTok to finish and post your video.' },
    'post.publish.failed': { title: 'TikTok post failed', body: 'TikTok could not publish your video. Try again from Oneova.' },
    'authorization.removed': { title: 'TikTok disconnected', body: 'Oneova no longer has access to your TikTok account.' },
};
const EVENT_STATUS = {
    'post.publish.complete': 'posted',
    'post.publish.publicly_available': 'public',
    'post.publish.inbox_delivered': 'in_drafts',
    'post.publish.failed': 'failed',
    'post.publish.no_longer_publicaly_available': 'removed',
};
function eventContent(raw) {
    if (typeof raw === 'string') {
        try {
            return JSON.parse(raw);
        }
        catch (_a) {
            return {};
        }
    }
    return (raw !== null && raw !== void 0 ? raw : {});
}
exports.tiktokWebhook = (0, https_1.onRequest)({ secrets: [tiktokClientSecret] }, async (req, res) => {
    var _a, _b, _c, _d;
    var _e, _f, _g, _h, _j;
    if (req.method !== 'POST') {
        res.status(405).send('POST only');
        return;
    }
    if (!validSignature(String((_e = req.headers['tiktok-signature']) !== null && _e !== void 0 ? _e : ''), req.rawBody)) {
        res.status(401).send('Bad signature');
        return;
    }
    // Answer TikTok quickly; it retries on anything but 200.
    const event = String((_f = (_a = req.body) === null || _a === void 0 ? void 0 : _a.event) !== null && _f !== void 0 ? _f : '');
    const openId = String((_g = (_b = req.body) === null || _b === void 0 ? void 0 : _b.user_openid) !== null && _g !== void 0 ? _g : '');
    try {
        const snap = openId ? await db().collection('tiktok_users').doc(openId).get() : null;
        const uids = (_h = snap === null || snap === void 0 ? void 0 : snap.get('uids')) !== null && _h !== void 0 ? _h : [];
        const text = EVENT_TEXT[event];
        const eventId = crypto.createHash('sha256').update(req.rawBody).digest('hex').slice(0, 24);
        // Post status → the Oneova post that was sent.
        const status = EVENT_STATUS[event];
        const publishId = String((_j = eventContent((_c = req.body) === null || _c === void 0 ? void 0 : _c.content).publish_id) !== null && _j !== void 0 ? _j : '');
        if (status && publishId) {
            const pub = await db().collection('tiktok_publishes').doc(publishId).get();
            const contentId = pub.get('contentId');
            if (contentId) {
                const postId = eventContent((_d = req.body) === null || _d === void 0 ? void 0 : _d.content).post_id;
                await db().collection('content').doc(contentId).set({ tiktok: Object.assign(Object.assign({ status }, (postId ? { postId: String(postId) } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp() }) }, { merge: true });
            }
        }
        for (const uid of uids) {
            if (event === 'authorization.removed') {
                await Promise.all([connectionRef(uid).delete(), tokenRef(uid).delete()]);
            }
            if (text) {
                await db().collection('notifications').doc(`tiktok_${eventId}_${uid}`).set({
                    userId: uid,
                    recipientId: uid,
                    category: 'system',
                    priority: 'normal',
                    type: 'system',
                    title: text.title,
                    body: text.body,
                    deepLink: '/social_hub/tiktok',
                    groupId: 'tiktok',
                    isRead: false,
                    createdAt: firestore_1.FieldValue.serverTimestamp(),
                    timestamp: firestore_1.FieldValue.serverTimestamp(),
                });
            }
        }
        if (event === 'authorization.removed' && (snap === null || snap === void 0 ? void 0 : snap.exists))
            await snap.ref.delete();
    }
    catch (e) {
        logger.warn('[tiktokWebhook] handling failed', { event, error: String(e) });
    }
    res.status(200).send('ok');
});
//# sourceMappingURL=tiktokOAuth.js.map