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
import * as crypto from 'crypto';
import { onCall, onRequest, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { defineSecret, defineString } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { limit } from './guard/protect';
import { encryptWith, decryptWith } from './gmailUser';

const db = () => getFirestore();

const tiktokClientSecret = defineSecret('TIKTOK_CLIENT_SECRET');
const tiktokClientKey = defineString('TIKTOK_CLIENT_KEY');
const tiktokRedirectUri = defineString('TIKTOK_REDIRECT_URI');

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

const tokenRef = (uid: string) => db().collection('users').doc(uid).collection('secure_tokens').doc('tiktok');
const connectionRef = (uid: string) => db().collection('users').doc(uid).collection('social_connections').doc('tiktok');

// ── tokens ────────────────────────────────────────────────────────────────

function tokenKey(): Buffer {
  return Buffer.from(crypto.hkdfSync('sha256', tiktokClientSecret.value(), 'oneova', 'tiktok-user-tokens', 32));
}

interface TokenSet {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  refreshExpiresAt: number;
  openId: string;
  scope: string;
}

async function oauthToken(params: Record<string, string>): Promise<Record<string, unknown>> {
  const res = await fetch(`${API}/oauth/token/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_key: tiktokClientKey.value(), client_secret: tiktokClientSecret.value(), ...params }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok || !body.access_token) {
    logger.warn('[tiktok] token call failed', { status: res.status, error: body.error });
    throw new HttpsError('failed-precondition', String(body.error_description ?? body.error ?? 'TikTok sign-in failed.'));
  }
  return body;
}

function toTokenSet(body: Record<string, unknown>, now = Date.now()): TokenSet {
  return {
    accessToken: String(body.access_token),
    refreshToken: String(body.refresh_token ?? ''),
    expiresAt: now + Number(body.expires_in ?? 86400) * 1000,
    refreshExpiresAt: now + Number(body.refresh_expires_in ?? 31536000) * 1000,
    openId: String(body.open_id ?? ''),
    scope: String(body.scope ?? ''),
  };
}

async function saveTokens(uid: string, t: TokenSet): Promise<void> {
  await tokenRef(uid).set({
    blob: encryptWith(tokenKey(), JSON.stringify(t), uid),
    openId: t.openId,
    scope: t.scope,
    expiresAt: t.expiresAt,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** A valid access token for [uid], refreshed when it is about to expire. */
async function accessToken(uid: string): Promise<TokenSet> {
  const snap = await tokenRef(uid).get();
  const blob = snap.get('blob') as string | undefined;
  if (!blob) throw new HttpsError('failed-precondition', 'Connect TikTok first.');
  let t: TokenSet;
  try {
    t = JSON.parse(decryptWith(tokenKey(), blob, uid)) as TokenSet;
  } catch {
    throw new HttpsError('failed-precondition', 'Reconnect TikTok.');
  }
  if (t.expiresAt - Date.now() > 5 * 60000) return t;
  if (!t.refreshToken || t.refreshExpiresAt < Date.now()) {
    await connectionRef(uid).set({ tokenStore: 'expired' }, { merge: true });
    throw new HttpsError('failed-precondition', 'Your TikTok sign-in expired. Reconnect TikTok.');
  }
  const fresh = toTokenSet(await oauthToken({ grant_type: 'refresh_token', refresh_token: t.refreshToken }));
  if (!fresh.openId) fresh.openId = t.openId;
  if (!fresh.refreshToken) fresh.refreshToken = t.refreshToken;
  await saveTokens(uid, fresh);
  return fresh;
}

/** Calls a TikTok API with the user's token; TikTok answers `{ data, error }`. */
async function tiktokApi(t: TokenSet, path: string, init: { method?: string; body?: unknown } = {}): Promise<Record<string, unknown>> {
  const res = await fetch(`${API}${path}`, {
    method: init.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${t.accessToken}`,
      ...(init.body !== undefined ? { 'Content-Type': 'application/json; charset=UTF-8' } : {}),
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  const body = (await res.json().catch(() => ({}))) as { data?: Record<string, unknown>; error?: { code?: string; message?: string } };
  const code = body.error?.code ?? (res.ok ? 'ok' : String(res.status));
  if (code !== 'ok') {
    logger.warn('[tiktok] api error', { path, status: res.status, code, message: body.error?.message });
    const msg = code === 'scope_not_authorized'
      ? 'Reconnect TikTok and allow this permission.'
      : code === 'spam_risk_too_many_posts' || code === 'rate_limit_exceeded'
        ? 'TikTok limits how often you can post. Try again later.'
        : body.error?.message || 'TikTok request failed.';
    throw new HttpsError('failed-precondition', msg);
  }
  return body.data ?? {};
}

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

function publicProfile(user: Record<string, unknown>) {
  return {
    openId: String(user.open_id ?? ''),
    unionId: String(user.union_id ?? ''),
    displayName: String(user.display_name ?? 'TikTok user'),
    username: user.username ?? null,
    avatarUrl: user.avatar_url ?? null,
    bio: user.bio_description ?? null,
    profileUrl: user.profile_deep_link ?? null,
    isVerified: user.is_verified === true,
    followerCount: Number(user.follower_count ?? 0),
    followingCount: Number(user.following_count ?? 0),
    likesCount: Number(user.likes_count ?? 0),
    videoCount: Number(user.video_count ?? 0),
  };
}

async function fetchProfile(t: TokenSet) {
  const data = await tiktokApi(t, `/user/info/?fields=${PROFILE_FIELDS}`);
  return publicProfile((data.user ?? {}) as Record<string, unknown>);
}

// ── connect ───────────────────────────────────────────────────────────────

export const tiktokExchangeCode = onCall({ secrets: [tiktokClientSecret] }, async (request) => {
  const uid = requireUid(request);
  await limit(uid, 'oauth_tiktok', 10, 10 * 60000);
  const code = String((request.data as Record<string, unknown> | undefined)?.code ?? '');
  if (!code || code.length > 2048) throw new HttpsError('invalid-argument', 'Missing authorization code.');

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
    connectedAt: FieldValue.serverTimestamp(),
    statsUpdatedAt: FieldValue.serverTimestamp(),
  });
  // Which Oneova account this TikTok person belongs to, so webhook events
  // (post published, access removed…) reach the right person.
  const openId = t.openId || profile.openId;
  if (openId) {
    await db().collection('tiktok_users').doc(openId).set(
      { uids: FieldValue.arrayUnion(uid), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }
  return { account: profile, scopes: t.scope.split(',').filter(Boolean) };
});

export const tiktokDisconnect = onCall({ secrets: [tiktokClientSecret] }, async (request) => {
  const uid = requireUid(request);
  try {
    const t = await accessToken(uid);
    await fetch(`${API}/oauth/revoke/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_key: tiktokClientKey.value(), client_secret: tiktokClientSecret.value(), token: t.accessToken }),
    });
  } catch (e) {
    logger.info('[tiktokDisconnect] revoke skipped', { error: String(e) });
  }
  await Promise.all([tokenRef(uid).delete(), connectionRef(uid).delete()]);
  return { ok: true };
});

// ── profile, videos ───────────────────────────────────────────────────────

export const tiktokProfile = onCall({ secrets: [tiktokClientSecret] }, async (request) => {
  const uid = requireUid(request);
  await limit(uid, 'tiktok_read', 60, 10 * 60000);
  const profile = await fetchProfile(await accessToken(uid));
  await connectionRef(uid).set({
    accountName: profile.displayName,
    username: profile.username,
    profilePictureUrl: profile.avatarUrl,
    profileUrl: profile.profileUrl,
    isVerified: profile.isVerified,
    stats: { followers: profile.followerCount, following: profile.followingCount, likes: profile.likesCount, videos: profile.videoCount },
    statsUpdatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { account: profile };
});

export const tiktokVideos = onCall({ secrets: [tiktokClientSecret] }, async (request) => {
  const uid = requireUid(request);
  await limit(uid, 'tiktok_read', 60, 10 * 60000);
  const cursor = Number((request.data as Record<string, unknown> | undefined)?.cursor ?? 0) || undefined;
  const data = await tiktokApi(await accessToken(uid), `/video/list/?fields=${VIDEO_FIELDS}`, {
    method: 'POST',
    body: { max_count: 20, ...(cursor ? { cursor } : {}) },
  });
  return { videos: data.videos ?? [], cursor: data.cursor ?? null, hasMore: data.has_more === true };
});

// ── posting ───────────────────────────────────────────────────────────────

export const tiktokCreatorInfo = onCall({ secrets: [tiktokClientSecret] }, async (request) => {
  const uid = requireUid(request);
  await limit(uid, 'tiktok_read', 60, 10 * 60000);
  const d = await tiktokApi(await accessToken(uid), '/post/publish/creator_info/query/', { method: 'POST', body: {} });
  return {
    nickname: d.creator_nickname ?? null,
    username: d.creator_username ?? null,
    avatarUrl: d.creator_avatar_url ?? null,
    privacyLevelOptions: Array.isArray(d.privacy_level_options) ? d.privacy_level_options : [],
    commentDisabled: d.comment_disabled === true,
    duetDisabled: d.duet_disabled === true,
    stitchDisabled: d.stitch_disabled === true,
    maxVideoPostDurationSec: Number(d.max_video_post_duration_sec ?? 0) || null,
  };
});

/** Storage object path from a Firebase download URL of our bucket. */
function storagePathOf(url: string): string | null {
  const m = /^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^/]+\/o\/([^?]+)/.exec(url);
  return m ? decodeURIComponent(m[1]) : null;
}

/** TikTok FILE_UPLOAD chunking: 5–64 MB chunks, the last one takes the rest. */
function chunking(size: number): { chunkSize: number; count: number } {
  if (size <= 64 * 1024 * 1024) return { chunkSize: size, count: 1 };
  const chunkSize = 10 * 1024 * 1024;
  return { chunkSize, count: Math.floor(size / chunkSize) };
}

export const tiktokPublish = onCall(
  { secrets: [tiktokClientSecret], memory: '1GiB', timeoutSeconds: 300 },
  async (request) => {
    const uid = requireUid(request);
    await limit(uid, 'tiktok_publish', 10, 3600000);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const contentId = String(data.contentId ?? '');
    const mode = data.mode === 'direct' ? 'direct' : 'draft';
    if (!/^[A-Za-z0-9_-]{1,80}$/.test(contentId)) throw new HttpsError('invalid-argument', 'Pick a video.');

    const contentRef = db().collection('content').doc(contentId);
    const content = await contentRef.get();
    if (!content.exists || content.get('authorId') !== uid) throw new HttpsError('permission-denied', 'You can only send your own posts.');
    if (content.get('type') === 'photo') throw new HttpsError('invalid-argument', 'Only videos can go to TikTok.');
    const path = storagePathOf(String(content.get('mediaUrl') ?? ''));
    if (!path || !path.startsWith(`content/${uid}/`)) throw new HttpsError('failed-precondition', 'This video can’t be sent to TikTok.');

    const t = await accessToken(uid);
    const file = getStorage().bucket().file(path);
    const [meta] = await file.getMetadata();
    const size = Number(meta.size ?? 0);
    if (!size || size > MAX_UPLOAD_BYTES) throw new HttpsError('failed-precondition', 'This video is too large for TikTok upload.');
    const { chunkSize, count } = chunking(size);
    const sourceInfo = { source: 'FILE_UPLOAD', video_size: size, chunk_size: chunkSize, total_chunk_count: count };

    let init: Record<string, unknown>;
    if (mode === 'direct') {
      const privacy = String(data.privacyLevel ?? '');
      if (!PRIVACY.includes(privacy)) throw new HttpsError('invalid-argument', 'Choose who can see this post.');
      const brandContent = data.brandContent === true;
      // TikTok: branded content can't be private.
      if (brandContent && privacy === 'SELF_ONLY') throw new HttpsError('invalid-argument', 'Branded content can’t be private.');
      init = await tiktokApi(t, '/post/publish/video/init/', {
        method: 'POST',
        body: {
          post_info: {
            title: String(data.title ?? content.get('description') ?? '').slice(0, 2200),
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
    } else {
      init = await tiktokApi(t, '/post/publish/inbox/video/init/', { method: 'POST', body: { source_info: sourceInfo } });
    }
    const publishId = String(init.publish_id ?? '');
    const uploadUrl = String(init.upload_url ?? '');
    if (!publishId || !uploadUrl) throw new HttpsError('unavailable', 'TikTok did not accept the upload. Try again.');

    await db().collection('tiktok_publishes').doc(publishId).set({ uid, contentId, mode, createdAt: FieldValue.serverTimestamp() });
    await contentRef.set({ tiktok: { publishId, mode, status: 'uploading', updatedAt: FieldValue.serverTimestamp() } }, { merge: true });

    try {
      const [bytes] = await file.download();
      for (let i = 0; i < count; i++) {
        const start = i * chunkSize;
        const end = i === count - 1 ? size - 1 : start + chunkSize - 1;
        const res = await fetch(uploadUrl, {
          method: 'PUT',
          headers: {
            'Content-Type': String(meta.contentType ?? 'video/mp4'),
            'Content-Length': String(end - start + 1),
            'Content-Range': `bytes ${start}-${end}/${size}`,
          },
          body: new Uint8Array(bytes.subarray(start, end + 1)),
        });
        if (!res.ok) throw new Error(`upload chunk ${i + 1}/${count}: HTTP ${res.status}`);
      }
    } catch (e) {
      logger.warn('[tiktokPublish] upload failed', { publishId, error: String(e) });
      await contentRef.set({ tiktok: { status: 'failed', updatedAt: FieldValue.serverTimestamp() } }, { merge: true });
      throw new HttpsError('unavailable', 'Upload to TikTok failed. Try again.');
    }

    await contentRef.set({ tiktok: { status: 'processing', updatedAt: FieldValue.serverTimestamp() } }, { merge: true });
    return { publishId, mode };
  },
);

// ── Webhooks ─────────────────────────────────────────────────────────────
// Dashboard: Webhooks → Callback URL
//   https://us-central1-mpepe-2b4bd.cloudfunctions.net/tiktokWebhook
// TikTok signs each call: header `TikTok-Signature: t=<unix>,s=<hex>` where
// s = HMAC-SHA256(client_secret, `${t}.${rawBody}`).

const MAX_SKEW_SECONDS = 5 * 60;

function validSignature(header: string, rawBody: Buffer): boolean {
  const parts = Object.fromEntries(header.split(',').map((p) => p.trim().split('=', 2) as [string, string]));
  const t = Number(parts.t);
  const s = parts.s ?? '';
  if (!t || !/^[0-9a-f]{64}$/i.test(s)) return false;
  if (Math.abs(Date.now() / 1000 - t) > MAX_SKEW_SECONDS) return false;
  const expected = crypto.createHmac('sha256', tiktokClientSecret.value()).update(`${t}.`).update(rawBody).digest();
  const given = Buffer.from(s, 'hex');
  return given.length === expected.length && crypto.timingSafeEqual(given, expected);
}

const EVENT_TEXT: Record<string, { title: string; body: string } | undefined> = {
  'post.publish.complete': { title: 'Posted to TikTok', body: 'Your video finished uploading to TikTok.' },
  'post.publish.publicly_available': { title: 'Live on TikTok', body: 'Your video is now public on TikTok.' },
  'post.publish.inbox_delivered': { title: 'Draft sent to TikTok', body: 'Open TikTok to finish and post your video.' },
  'post.publish.failed': { title: 'TikTok post failed', body: 'TikTok could not publish your video. Try again from Oneova.' },
  'authorization.removed': { title: 'TikTok disconnected', body: 'Oneova no longer has access to your TikTok account.' },
};

const EVENT_STATUS: Record<string, string | undefined> = {
  'post.publish.complete': 'posted',
  'post.publish.publicly_available': 'public',
  'post.publish.inbox_delivered': 'in_drafts',
  'post.publish.failed': 'failed',
  'post.publish.no_longer_publicaly_available': 'removed',
};

function eventContent(raw: unknown): Record<string, unknown> {
  if (typeof raw === 'string') {
    try {
      return JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return {};
    }
  }
  return (raw ?? {}) as Record<string, unknown>;
}

export const tiktokWebhook = onRequest({ secrets: [tiktokClientSecret] }, async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('POST only');
    return;
  }
  if (!validSignature(String(req.headers['tiktok-signature'] ?? ''), req.rawBody)) {
    res.status(401).send('Bad signature');
    return;
  }
  // Answer TikTok quickly; it retries on anything but 200.
  const event = String(req.body?.event ?? '');
  const openId = String(req.body?.user_openid ?? '');
  try {
    const snap = openId ? await db().collection('tiktok_users').doc(openId).get() : null;
    const uids = (snap?.get('uids') as string[] | undefined) ?? [];
    const text = EVENT_TEXT[event];
    const eventId = crypto.createHash('sha256').update(req.rawBody).digest('hex').slice(0, 24);

    // Post status → the Oneova post that was sent.
    const status = EVENT_STATUS[event];
    const publishId = String(eventContent(req.body?.content).publish_id ?? '');
    if (status && publishId) {
      const pub = await db().collection('tiktok_publishes').doc(publishId).get();
      const contentId = pub.get('contentId') as string | undefined;
      if (contentId) {
        const postId = eventContent(req.body?.content).post_id;
        await db().collection('content').doc(contentId).set(
          { tiktok: { status, ...(postId ? { postId: String(postId) } : {}), updatedAt: FieldValue.serverTimestamp() } },
          { merge: true },
        );
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
          createdAt: FieldValue.serverTimestamp(),
          timestamp: FieldValue.serverTimestamp(),
        });
      }
    }
    if (event === 'authorization.removed' && snap?.exists) await snap.ref.delete();
  } catch (e) {
    logger.warn('[tiktokWebhook] handling failed', { event, error: String(e) });
  }
  res.status(200).send('ok');
});
