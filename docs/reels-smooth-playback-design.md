# Reels: How TikTok Feels Smooth, and the Design for Our App

Written 2026-11-25. Part 1 is a case study. Part 2 is the design for our stack (Flutter, media_kit, Firebase, Google Cloud).

**A note on sources.** TikTok has not published its own internals. Everything in Part 1 comes from academic measurement of the app, Meta's public engineering write-up and system-design articles. Treat exact numbers as approximate. Where something is my own estimate, it says so.

## What is built (2026-11-25)

| Piece | Where | Notes |
|---|---|---|
| Upload trigger | `functions/src/reels.ts` | Checks the uploader owns the doc, claims it once, starts the job |
| FFmpeg worker | `reels_worker/` | 360/540/720 H.264 HLS, 2 s segments, keyframe per segment, 30 fps cap, poster + 16 px preview. `deploy.sh` sets up bucket, job, IAM |
| Rules + indexes | `firestore.rules`, `storage.rules`, `firestore.indexes.json` | `content` had no rule before (all reads denied). Now: public or own content readable, create only as `uploading` with zero counts |
| Upload from app | `lib/backend/social/services/reels/reel_upload_service.dart` | Creates doc, resumable upload, `watch()` for ready/failed |
| Shared disk cache | `.../reels/reel_segment_cache.dart` | Local proxy, LRU, prefetch first segments, measures speed |
| Player pool | `.../video_playback_manager.dart` | 3 reused players, first-frame signal, rung per video, Analytics events |
| Feed screen | `lib/social_hub/feed/short_video_feed_screen.dart` | Blurred preview to poster to video cross-fade, paging, pause in background |
| Remote Config | `.../reels/reel_playback_config.dart` | All `reels_*` keys with safe defaults and limits |

Changes from the plan above:
- **Tiny JPEG instead of blurhash.** The worker stores a 16 px JPEG (about 600 bytes) in the doc. Flutter blurs it. No extra package on either side.
- **Quality is chosen per video, not switched mid-video.** media_kit (mpv) does not switch HLS quality while playing. The manager picks the rung when it opens each video, from network type and the speed it measured on earlier downloads. Reels are short, so this is close to real adaptive playback.

Analytics events to build the dashboard from: `reel_first_frame` (ms, rung, prefetched, cellular), `reel_view` (watch_ms, rebuffers, rung), `reel_session` (played, prefetched_unwatched, cache_hit_kb, network_kb, est_kbps).

---

## Part 1. Case study: why TikTok feels instant

### What the user feels

You swipe and the next video is already playing, with no spinner. That is not fast downloading. It is that the video was **already on the phone before you asked for it**. Smoothness is mostly decided before the swipe.

### The engineering behind it

**1. Upload**
- Uploads are split into chunks (about 5 MB in the write-ups) and are resumable, so a bad connection does not restart the upload.
- The app confirms the upload at once. Processing happens afterward in the background. The creator sees "posted" while encoding still runs.
- Raw files go to object storage. A transcoding pipeline then makes several quality levels. Reports say GPUs and ByteDance's own video chips are used to cut cost (Volcano Engine reports, 2023).

**2. Many small files, not one big file**
- A research study that measured TikTok directly ([Dashlet](https://www.icst.pku.edu.cn/NetVideo/docs/20220826143529921247.pdf)) found each video is split into chunks and downloaded in a hedged order, so a fast swipe does not hit an empty buffer.
- Only the first chunk of upcoming videos is fetched, not the whole video. That is what makes the next video start instantly at low cost.

**3. Prefetch only what is likely to be watched**
- The next few videos in the queue are preloaded. The same research shows smarter choices of what to preload cut wasted downloaded bytes by about 30%. Wasted bytes are the main hidden cost of a feed.

**4. Memory, not only disk**
- Meta's write-up on [Instagram and Facebook with Media3 PreloadManager](https://developer.android.com/blog/posts/instagram-and-facebook-deliver-instant-playback-and-boost-user-engagement-with-media3-preload-manager) says they moved from disk prefetch to preparing the player in memory, so the video is ready the moment the user arrives.
- Developers report about 4 to 6 live players is the practical limit before memory trouble.

**5. Disk cache for swipe-back**
- A small least-recently-used cache (a few hundred MB) keeps watched videos so swiping back is free.

**6. The feed itself is also prefetched**
- The ranked list of next videos is fetched ahead of time, so the app never waits on the server to know what comes next.

**7. Cheap delivery**
- Videos are served from CDN edge servers near the user. The segments are cached for a long time, so the origin is rarely touched.

### Where the money goes in a video app

| Cost | What drives it | Lever |
|---|---|---|
| **Delivery (egress)** | Bytes sent to viewers. Usually the biggest bill. | Smaller files, lower rungs on cellular, preload only the first chunk, CDN cache hits |
| **Encoding** | Number of quality levels × video minutes | Fewer rungs, encode once, skip rungs nobody watches |
| **Storage** | Original plus every rung | Delete originals later, move cold videos to cheaper storage |
| **Database reads** | Feed queries, interaction events | Batch events, paginate, cache |

---

## Part 2. Our design

### Where we are today

- `media_kit` with a pool of 3 players. A new `Player` is created and disposed on every swipe.
- The raw uploaded file is streamed from `mediaUrl`.
- No transcoding, no disk cache, no first-frame handling, and the whole feed is fetched in one call.
- `MediaMetadata` already has `isAdaptiveBitrate`, `resolutions`, `thumbnailUrl`, so the data model is ready.

### Target pipeline

```
Creator phone
  │ 1. resumable upload (Firebase Storage)
  ▼
Storage: uploads/{uid}/{id}/original.mp4
  │ 2. Storage trigger (Cloud Function)  ->  Content.status = "processing"
  ▼
Cloud Run Job (FFmpeg, our own container)
  │ 3. makes: 3 HLS rungs + poster + blurhash + 1.5s preview
  ▼
Cloud Storage bucket: reels/{id}/...   (public, long cache headers)
  │ 4. writes Content: status="ready", hlsUrl, resolutions, blurhash
  ▼
Cloud CDN (load balancer in front of the bucket)
  ▼
Viewer phone: feed (Firestore) + player pool + disk cache
```

### Pipeline choices, and why

**Encoder: our own FFmpeg on Cloud Run Jobs, not the managed Transcoder API.**
- Google's [Transcoder API](https://cloud.google.com/transcoder/pricing) charges per output minute: SD $0.015, HD $0.030, UHD $0.060. A 30-second reel with 360p, 540p and 720p rungs costs about $0.03, so 10,000 uploads a month is about $300.
- My estimate (not measured): FFmpeg on Cloud Run with 4 vCPU for about 20 seconds per 30-second reel costs well under a cent. That would be roughly 5 to 10 times cheaper, and it fits your rule to self-host on our own Google Cloud.
- Start with the Transcoder API if speed to ship matters more, since it is a few lines of code. Move to FFmpeg when volume grows. The data model is the same either way.

**The ladder (kept small on purpose)**

| Rung | Size | Video bitrate | Used for |
|---|---|---|---|
| Low | 360×640 | ~500 kbps | Preload, weak or cellular network |
| Mid | 540×960 | ~1 Mbps | Default start |
| High | 720×1280 | ~2 Mbps | Good Wi-Fi |

- Skip 1080p. A phone screen shows little extra at reel size, and it adds about 2.5× the bytes.
- Use H.264, because every phone decodes it in hardware. Add AV1 later for new uploads of popular videos only, since it saves bytes but costs far more to encode.
- Segments are 2 seconds, with a keyframe at each segment start. That keeps the first chunk small.
- Put the first segment's moov data up front (`+faststart`) so the first frame shows quickly.

**Extras made in the same job**
- Poster frame, plus a **blurhash** string stored in Firestore (about 30 bytes). It lets the feed show a blurred preview with no image download.
- Optional: audio loudness normalization, so videos do not jump in volume.

### Firestore fields to add to `Content`

```
status:        uploading | processing | ready | failed
hlsUrl:        https://cdn.../reels/{id}/master.m3u8
rungs:         [360, 540, 720]
blurhash:      "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
firstSegBytes: 85000      // size of first segment on the low rung, for preload budget
durationMs:    28000
```

The feed query only returns `status == "ready"`.

### Delivery and cost control

- Put the bucket behind **Cloud CDN** with `Cache-Control: public, max-age=31536000, immutable` on segments. Videos never change after processing, so cache hit rate stays high.
- Do not serve from Firebase Storage download URLs. They carry tokens that defeat CDN caching.
- Lifecycle rule: delete `original.mp4` after 30 days, or move it to Nearline. Rungs stay.
- Cold videos (no views for 90 days): keep only the mid rung.

### Client playback design (Flutter, media_kit)

1. **Fixed pool of 3 players, reused.** Create them once. On swipe, call `open()` on the player that just left the window instead of disposing it.
2. **Preload by size, not by whole file.** For the next 2 videos, load only the first 1 to 2 segments of the low rung (about 80 to 150 KB each). A swipe then starts from memory.
3. **Starting quality rule.**
   - Wi-Fi: start mid, allow high after the first segment plays cleanly.
   - Cellular: start low, cap at mid.
   - Data Saver on: low only.
4. **First-frame handshake.** Show blurhash, then the poster. Cross-fade to video only when the player reports the first frame is rendered, not when the controller exists. This removes the black flash.
5. **Disk cache.** Roughly 300 MB, least-recently-used, keeping watched videos longer for swipe-back. Cache segments, not whole files.
6. **Feed paging.** Fetch 10 at a time. Fetch the next page when 5 remain. Keep a local buffer so a slow network does not stall the list.
7. **Pause everything that is not on screen**, and dispose players on app background.
8. **Fix the rebuild bug.** Make the playback manager a `ChangeNotifier` (or use a `StateNotifier`) so neighbor items refresh when their controller appears.

### Cutting wasted bytes (the cheapest win)

- Preload depth adapts to the user's swipe speed. Fast swipers get one video ahead and only a first segment. Slow, watch-to-the-end users get two.
- Stop preloading if the user left the feed.
- Cap preload on cellular, and tie it to the Data Saver setting.
- Track `wastedBytes` (preloaded but never played) as a metric. Target under 25%.

### Remote Config knobs (tune without a release)

`preload_count`, `preload_segments`, `cache_mb`, `start_rung_wifi`, `start_rung_cell`, `max_rung_cell`, `page_size`, `prefetch_page_at`.

### Measurements that define "smooth"

| Metric | Target |
|---|---|
| Time to first frame after swipe | under 300 ms (p50), under 700 ms (p95) |
| Rebuffer events per 100 plays | under 2 |
| Dropped frames while scrolling | under 1% |
| Wasted preload bytes | under 25% |
| Cache hit rate at CDN | over 90% |
| Cost per 1,000 plays | tracked weekly |

Log these to Firebase Analytics and Performance Monitoring from day one. Without them, "smooth" is a guess.

### Cost picture, qualitative

- **Encoding**: small, one time per upload. Own FFmpeg keeps it near zero.
- **Storage**: small. Lifecycle rules keep it flat.
- **Delivery**: the real bill. Three levers cut it the most: no 1080p, first-segment-only preload, and a high CDN hit rate.
- **Firestore**: batch interaction events (send every 5 to 10 seconds or on leaving the feed, not on each tap) and page the feed.

### Build order

1. **Pipeline**: `status` fields, upload trigger, FFmpeg job (or Transcoder API first), CDN.
2. **Client core**: reusable player pool, first-frame handshake, blurhash, rebuild fix.
3. **Preload and cache**: first-segment preload, disk cache, adaptive start quality.
4. **Metrics and Remote Config**: ship the dashboard, then tune the numbers from real data.
5. **Later**: AV1 for popular videos, cold-video cleanup, smarter preload from watch history.

### Open risks

- `media_kit` HLS cache control is limited. If disk caching of segments is hard there, the fallback is a small local proxy that caches segments, or a switch to native players (Media3 on Android, AVPlayer on iOS) behind a Flutter wrapper. Check this first with a prototype before step 3.
- Cloud Run Job cold start adds a few seconds before processing starts. Fine for uploads, which are already asynchronous.

### Sources

- [Dashlet study of TikTok chunking and preloading](https://www.icst.pku.edu.cn/NetVideo/docs/20220826143529921247.pdf)
- [Meta: Instagram and Facebook with Media3 PreloadManager](https://developer.android.com/blog/posts/instagram-and-facebook-deliver-instant-playback-and-boost-user-engagement-with-media3-preload-manager)
- [Google Transcoder API pricing](https://cloud.google.com/transcoder/pricing)
- [TikTok-style feed design write-up](https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/?format=md)
- [Short-video platform architecture write-up](https://dev.to/matt_frank_usa/designing-tiktok-short-video-platform-architecture-401m)
