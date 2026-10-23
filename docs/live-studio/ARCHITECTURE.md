# Live Studio v2 — Architecture

Status: **Approved 2026-10-17.** Decisions:
- Q1: ~~LiveKit Cloud~~ → **self-hosted LiveKit (open-source server, option B)**, changed 2026-10-17 at the user's request: no third-party cloud. API key and secret are values we generate ourselves for our own server. Client and functions code is unchanged; only `LIVEKIT_URL` and the keys point at our servers. Dev: `livekit-server --dev` locally. Production at 100k viewers needs a multi-node cluster + Redis + TURN/TLS (§2 option B).
- Q2: server-authoritative callables.
- Q3: a viewer's tap opens a local pop-out.
- Q4: participants = stage + co-hosts + pending requests.
- Q5: **both** sources. The Biz `products` catalog first, falling back to the per-stream list.
- Q6: `https://mpepe-2b4bd.web.app/live/<id>`, since we control that domain. It can move to oneova.com later.
- Q7: empty admin-curated watch catalog.
- Q8: remove only the v1 Studio.

Sub-agents work in the main checkout (425 uncommitted changes rule out worktrees) with strict file ownership per §10.
Inputs: [SPEC.md](SPEC.md) (approved), [assets/live_studio/studio-geometry.json](../../assets/live_studio/studio-geometry.json), and the audit in §1.

---

## 1. Audit: what we have today

**Stack**:
- Flutter, with Riverpod 3 (`Notifier` / `StreamProvider.family`) for state and go_router 18 for routing.
- Firebase backend: Auth, Firestore, Cloud Functions v2 (TypeScript, `firebase-functions` 7), Remote Config, FCM.
- `flutter_webrtc` 1.6, `share_plus`, `flutter_animate`, `wakelock_plus` and `permission_handler` are already dependencies.

| Area | Current code | Finding |
|---|---|---|
| **Video / WebRTC** | `lib/backend/live/services/live_stage_media_controller.dart` | **A P2P mesh with Firestore signaling and STUN only.** Each publisher uploads one copy to every viewer. No SFU, no TURN (`CallIceConfig` reads optional TURN from Remote Config for calls only), no simulcast, no screen-share track. Active speaker comes from client `getStats` polling. **This cannot carry 7 publishers to 100k viewers, or even ~20.** |
| RTMP | `live_service.dart` writes `rtmps://live.oneova.com/live` + stream key | No ingest server in the repo. The value is decorative |
| **Live session** | `LiveService` (`live_streams/{id}`, subcollections `comments`, `participants`, `reactions`, `guest_requests`, `signaling`) | All writes are client-side Firestore writes. A client-side heartbeat ends the stream |
| Comments | `watchComments` (last 50, live listener), `sendComment` | No rate limit and no moderation hook. "AI question detection" is just `endsWith('?')`. Every comment fans out as Firestore reads to every viewer |
| Reactions | `sendLikeReaction` = 1 doc + `totalLikes++` on the stream doc | Firestore allows about 1 sustained write/s per document. At scale, hot counters on the stream doc fail and contend with everything else |
| Viewer count | `increment/decrementViewerCount` from the client | Anyone can set it to any number. It drifts when apps are killed |
| Join requests | `requestToJoinStage` / `respondToGuestRequest` | Works, but see the security rows |
| Products | `live_streams/{id}/products` (host-entered) + `featuredProductId`; global Biz `products` collection (used by search) | Two sources. Goods mode needs a choice (Q5) |
| Follows | `RelationshipRepository.followUser/unfollowUser/watchFollowState` (transactional, block-aware) | Reuse as is |
| Profiles | `users/{uid}` (public read) | Reuse |
| Share | `SharePlus` with text only, no link | `oneova://` scheme exists on Android. No https App Links / Universal Links. The router already has `/live/viewer/:streamId` |
| Feature flags | `FeatureFlagService` + `AppFeature` enum (Remote Config, allow-list, % rollout) | Add `liveStudioV2('live_studio_v2')`. Do not reuse the existing `liveV2` |
| Studio v1 | `lib/social_hub/live/studio/**` (≈3.6k lines), `/live/studio/:id`, `LiveRoomGate` picks it when `layoutMode=='studio'` | It has a Dart `homographyFromQuad`, a roster/slot assigner (sticky, overflow) and 28 passing tests. Its geometry is the old design. **v2 reuses the math and replaces the rest** |
| Tests | `test/guards/home_lock_test.dart`, `test/live_studio_geometry_test.dart` | Baseline green, 28/28 |

**Security gaps in `firestore.rules`** (these must be fixed for "enforce all permissions server-side"):
1. `participants/{id}`: `create, update: if isSignedIn()`. **Any user can write any participant doc**, including `role: coHost` or `isMuted` for other people.
2. `guest_requests`: the requester may update their own doc, so they **can set `status: approved` themselves**.
3. Stream doc: any user may change `viewerCount`, `totalLikes` and `totalComments` to any number.
4. `banUser` only deletes the participant doc. Nothing stops the user from rejoining.
5. No per-user rate limits anywhere.

---

## 2. Decision needed: media provider (blocks Step 2)

We have **no media provider that meets the brief**. I propose **LiveKit**, and I'm waiting for your approval before adding it.

Why LiveKit over mediasoup:
- It has a first-party Flutter SDK (`livekit_client`), so mediasoup would mean writing our own Flutter client.
- Built in, it covers almost the whole Realtime Media workstream:
  - simulcast and dynacast;
  - adaptive stream (the subscriber chooses the layer by rendered size);
  - server-computed active-speaker events;
  - reconnect / ICE restart;
  - TURN;
  - screen-share tracks;
  - data channels;
  - room and participant metadata/attributes;
  - webhooks;
  - an egress option.

| Option | Pros | Cons |
|---|---|---|
| **A. LiveKit Cloud (recommended)** | Large rooms (100k WebRTC subscribers) without running servers. Viewers on WebRTC get **<500 ms**, well inside the 2 s target. Global edge | Paid per participant-minute. Vendor dependency |
| B. Self-hosted LiveKit (OSS) | Same API, our infra | We run a multi-region cluster, TURN and autoscaling. 100k viewers is a real ops project |
| C. Keep the mesh | No new deps | Cannot meet any scale or latency criterion |

New dependencies if approved:
- `livekit_client` (Flutter);
- `livekit-server-sdk` (functions);
- secrets `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_URL`.

`flutter_webrtc` stays; the call feature uses it.

---

## 3. System overview

```
             ┌────────── Flutter client (one per viewer / publisher) ──────────┐
             │  StudioController (Riverpod)  ← merges →  StudioState          │
             │     ▲ media events  ▲ data events    ▲ Firestore snapshot(once)│
             └─────┼───────────────┼────────────────┼──────────────▲──────────┘
     WebRTC media  │   data topics │                │ get()        │ callable fns
             ┌─────┴───────────────┴──────┐   ┌─────┴──────────────┴──────────┐
             │      LiveKit SFU room      │◄──│  Cloud Functions (liveStudio*) │
             │  tracks · active speakers  │   │  authz · rate limit · moderate │
             │  data broadcast · webhooks │──►│  aggregate · persist · token   │
             └────────────────────────────┘   └──────────────┬─────────────────┘
                                                             ▼
                                                  Firestore (source of record)
```

- **Media** goes over the SFU only.
- **Authoritative state** lives in Firestore at `live_streams/{id}/studio/state`. **Only Cloud Functions** write it (Admin SDK); clients get write-deny rules.
- **Fan-out to viewers** uses LiveKit data messages sent by functions with the server API. Viewers never listen to hot Firestore documents. That avoids 100k reads per comment and the 1 write/s per document limit.
- **Late joiners**: one `get()` of `studio/state` plus the last 50 comments, then the data stream. Duplicates are dropped by `seq` / `id`.
- **Client → server**: every mutation is a callable function. Callables check the role, rate-limit, moderate, persist, then broadcast.

---

## 4. Shared state model

Dart models live in `lib/backend/live_studio/contracts/` (owned by the integrator, read-only for sub-agents). TypeScript mirrors them in `functions/src/liveStudio/contracts.ts`.

```dart
StudioState {
  int schemaVersion;           // 1
  String streamId, hostId, studioId;           // studioId → studio-geometry.json
  StudioStatus status;         // preparing | live | ended
  int seq;                     // monotonic, bumped by every server mutation
  StudioSettings settings;     // copied from the host's saved settings at start, then live-edited
  StageLayout stage;
  TableState table;
  StudioCounts counts;
}

StudioSettings {               // persisted per host: users/{hostId}/live_studio/settings
  String studioId;             // 'broadcast_curved_wall'
  StudioTheme theme;           // dark | light
  int frameWidth;              // 0–12, default 4
  String frameColor;           // one of the theme's 4 options
  GuestSize guestSize;         // s | m | l, default m (landscape only)
  bool showNames;              // true
  double studioDim;            // 0–0.6; dark .15, light 0
  SpeakerMode speakerMode;     // hostPinned (default) | autoActiveSpeaker | manual
}

StageLayout {
  String centerUid;            // host at start
  List<String?> wall;          // ordered, length 6. Landscape index→slot L1,L2,R2,R1,LP,RP.
                               // Phone uses index 0–3 → PL1,PL2,PR1,PR2; 4–5 show in Participants.
  List<String> overflow;       // publishers beyond 6 (on stage but off the wall)
  String? pinnedUid;           // a pin overrides auto mode
  int updatedAtMs; String updatedBy;
}

TableState {
  TableMode mode;              // goods | screen | match | movie
  GoodsRef? goods;             // { source: biz|stream, productId }
  ScreenRef? screen;           // { publisherUid, trackName: 'table_screen' }
  WatchParty? watch;           // match/movie
}
WatchParty {
  String catalogId;            // rights-cleared entry in live_watch_catalog (§9)
  PlaybackState state;         // playing | paused | ended
  int positionMs; double rate; int anchorServerMs;   // position at anchorServerMs
}

StageMember {                  // live_streams/{id}/members/{uid} (function-written)
  String uid, displayName, avatarUrl; String accent;   // accent assigned from a fixed palette on join
  StudioRole role;             // host | coHost | guest | viewer
  bool micOn, camOn, removed, blocked;
}

StudioCounts { int viewers, participants, loves, sparkles; }
```

**Client-local state** (not synced):
- pop-out `{target, rect, fullScreen}`;
- drawer open;
- selected room tab;
- comment draft;
- `watching` per table mode (whether this viewer subscribes to the table stream);
- the local theme preview when the host edits settings.

**Orientation independence**: `wall` is one ordered list. Landscape and phone viewers see the same people in the same order. Phone shows the first 4, matching prototype order s1..s4.

---

## 5. Realtime event schema

LiveKit data messages are JSON with `{v:1, type, seq?, ts}`. All are reliable unless marked lossy.

| Topic | Type | Payload | Sender |
|---|---|---|---|
| `studio.state` | `state.patch` | `{seq, path, value}` (e.g. `stage`, `table`, `settings`) | Function |
| `studio.state` | `state.full` | `StudioState` (after reconnect, or when `seq` has a gap) | Function, on client request |
| `chat` | `comment` | `{id, uid, name, avatarUrl, text, ts}` | Function |
| `chat` | `system` | `{id, kind: joined\|love\|sparkles\|shared\|requested\|onStage, uid, name, ts}` | Function |
| `chat` | `comment.deleted` | `{id}` | Function |
| `react` (lossy) | `reaction.agg` | `{loves:+n, sparkles:+n, totals}` every 500 ms when non-zero | Function |
| `counts` (lossy) | `counts` | `{viewers, participants}` every 2 s when changed | Function (from webhooks) |
| `stage.req` | `request.new` / `request.update` | `{uid, name, status}` — **sent only to host/co-host** (`destinationIdentities`) | Function |
| `media` | — | Built-in LiveKit events: `ActiveSpeakersChanged`, track publish/mute, connection quality | SFU |

**Callable functions** (`functions/src/liveStudio/*`). Each one checks auth, role and rate limit:

| Callable | Who | Effect |
|---|---|---|
| `lsStart(title, settings)` | signed-in creator | Create stream + `studio/state`. Create the LiveKit room. Return a token |
| `lsToken(streamId)` | anyone allowed to watch | LiveKit token with grants by role (§6) |
| `lsEnd(streamId)` | host | End the room, `status=ended` |
| `lsComment(streamId, text)` | viewer+ | 1 per 2 s and 20 per minute per user. Length ≤ 200. Block-list and moderation hook. Persist, broadcast |
| `lsDeleteComment`, `lsMuteChat(uid, minutes)` | host/co-host | |
| `lsReact(streamId, kind, n)` | viewer+ | n ≤ 10 per call, 5 calls/s. Sharded counter + aggregate broadcast |
| `lsShare(streamId)` | viewer+ | System line "shared this live" + share count. Returns the deep link |
| `lsRequestJoin` / `lsCancelRequest` | viewer | Queue entry, notify the host |
| `lsRespondRequest(uid, approve)` | host/co-host | On approve: role=guest, assign the first free wall index, re-issue the guest's token with publish grants |
| `lsSetLayout(op)` | host/co-host (manual) · host client leader (auto) | ops: `swap(i)`, `pin(uid)`, `unpin`, `setMode`, `rotateIn(uid, index)`. Validated against the members list |
| `lsSetTable(mode, ref)` / `lsPlayback(state, positionMs)` | host/co-host (screen: the publishing user) | |
| `lsSetSettings(partial)` | host | Validate ranges, persist to the host profile + `studio/state` |
| `lsModerate(uid, action: mute\|removeFromStage\|block)` | host/co-host (co-hosts cannot act on the host) | Server-side mute through the LiveKit API; remove revokes publish; block kicks and denies future tokens |
| `lsLeaveStage` | guest | Revoke publish, free the slot |
| `lsTime()` | anyone | Returns server ms, for clock offset |
| `lsSetOwnMedia(micOn, camOn)` | guest/co-host/host | Updates own `members` doc so nameplates and avatar fallback sync for everyone |
| `lsStateFull(streamId)` | anyone in the room | Returns `StudioState` (resync after a `seq` gap or a reconnect) |

Scale guard for 100k viewers: if comments arrive faster than **25/s**, the function still persists all of them but broadcasts a fair sample. Host and co-host comments and system lines are never dropped. Reactions are always aggregated, never sent one by one.

---

## 6. Roles and permissions

Enforced in three places:
1. **LiveKit token grants** (media);
2. **Callable functions** (all state);
3. **Firestore rules**: clients can read state; writes come from functions only.

| Capability | Host | Co-host | Guest (on stage) | Viewer |
|---|:-:|:-:|:-:|:-:|
| Subscribe to media | ✅ | ✅ | ✅ | ✅ |
| Publish cam/mic (`canPublish`) | ✅ | ✅ | ✅ | ❌ |
| Publish screen share to the table | ✅ | ✅ | ✅ if host allows | ❌ |
| Toggle own mic/cam | ✅ | ✅ | ✅ | — |
| Comment / react / share / follow | ✅ | ✅ | ✅ | ✅ (signed in, not blocked) |
| Request to join | — | — | — | ✅ |
| Approve/decline requests | ✅ | ✅ | ❌ | ❌ |
| Swap / pin / set speaker mode | ✅ | ✅ | ❌ | ❌ (tapping only opens a pop-out locally) |
| Rotate overflow onto the wall | ✅ | ✅ | ❌ | ❌ |
| Set table mode / control playback | ✅ | ✅ | ❌ | ❌ |
| Mute others / remove from stage | ✅ | ✅ (not the host) | ❌ | ❌ |
| Block user | ✅ | ✅ (not the host or co-hosts) | ❌ | ❌ |
| Delete any comment / mute chat | ✅ | ✅ | ❌ | ❌ |
| Change studio settings | ✅ | ❌ | ❌ | ❌ |
| Promote co-host | ✅ | ❌ | ❌ | ❌ |
| End the live | ✅ | ❌ | ❌ | ❌ |
| Leave stage | — | ✅ | ✅ | — |

The LiveKit `canPublishData` grant is **false for everyone**. All data goes through functions so it can be rate-limited and moderated.

**Viewer tap on a guest**: the brief says "tapping a guest swaps them into the center". Applying that to every viewer would break "layout broadcast so all viewers stay in sync". Proposal: for host/co-host a tap is a broadcast swap; for viewers a tap opens that person's pop-out window, which is local. See Q3.

**Rules changes** (integrator owns `firestore.rules`):
- `studio/**`, `members/**`, `comments` (v2) and `counters/**`: `allow write: if false` (Admin SDK bypasses rules);
- reads stay `isSignedIn()`.

v1 collections keep their current rules until v1 is removed, then the gaps in §1 close with it.

---

## 7. Media design (if LiveKit is approved)

- **One room per stream.** Track names: `cam`, `mic`, `table_screen`.
- **Simulcast** publishes 3 layers (e.g. 180p / 360p / 720p; the host adds 1080p). Subscribers use `adaptiveStream` + `dynacast`, so the layer follows the rendered size:
  - wall tiles get the low layer;
  - the center, pop-outs and full screen get the high layer;
  - tiles off screen or in a pop-out pause their video.
  The renderer passes its pixel size to `VideoTrackRenderer` / `setVideoDimensions`.
- **Network**:
  - reconnect is built in, plus an app-level retry with exponential backoff (1, 2, 4, 8 s, max 30 s, with jitter) around `connect`;
  - when connection quality stays `poor` for 5 s, a viewer drops to **audio-only** (unsubscribes from video and keeps the avatar fallback), and a publisher stops video;
  - it recovers after 15 s of `good`.
- **Active speaker**: the SFU's `ActiveSpeakersChanged` events feed the hysteresis engine (§8).
- **Latency**: everyone is on WebRTC, so the target is ≤500 ms glass-to-glass for stage members and well under 2 s for viewers.
- **QoS metrics** to `telemetry_service`:
  - join→first-frame;
  - RTT, jitter and packet loss per track;
  - the current layer;
  - number of reconnects;
  - time spent in audio-only.
  They are sampled every 10 s.

---

## 8. Layout and speaker logic

The **layout leader** is the host client (or the longest-serving co-host if the host has been disconnected for more than 10 s). It runs `SpeakerHysteresis` and calls `lsSetLayout`. Viewers only render `stage`.

- `hostPinned` (default): the host stays in the center. Only manual swaps by host/co-host change it.
- `autoActiveSpeaker`:
  - a speaker takes the center after **1.5 s** of continuous speech;
  - the person in the center **stays at least 4 s**;
  - the previous center person moves into the slot the new speaker left;
  - `pinnedUid` blocks auto moves until it is unpinned.
- `manual`: only explicit swaps.

`SpeakerHysteresis` is a pure Dart class with an injected clock, unit-tested with synthetic event sequences. Overflow rotation: `rotateIn(uid, index)` swaps an overflow member with the wall occupant at `index`.

---

## 9. On the table

- **Goods**: `GoodsRef` points to a product (Q5 picks the source). The card shows name, price and image. "View item" opens the product.
- **Screen**: the publisher shares `table_screen` (Android MediaProjection / iOS ReplayKit broadcast extension; desktop `getDisplayMedia`). On the table it renders at 16:9.
- **Match / Movie watch party**:
  - content comes **only** from `live_watch_catalog/{id}`, curated by admins, with `rightsHolder`, `territories`, `validUntil` and an HLS URL;
  - no free-form URLs, and no restreaming of third-party DRM content;
  - screen share of DRM content stays blocked by the OS. We document it and do not try to work around it.
- **Sync**:
  - each client estimates the clock offset with 5 `lsTime()` pings and keeps the lowest-RTT sample;
  - target position = `positionMs + (serverNow − anchorServerMs) · rate`;
  - if |drift| > 300 ms, seek; otherwise do nothing. The brief only asks to correct above 300 ms.
  The host's play/pause/seek re-anchors through `lsPlayback`.
- "Join" ↔ "Watching" is local: the viewer starts or stops playback. The table shows a poster until they join.
- Lazy loading: each mode's widget and its player load only when that mode is active, through a deferred import / `FutureBuilder` gate.

---

## 10. Module boundaries (sub-agents)

New code goes in v2 folders so v1 keeps working until removal. `contracts/`, `firestore.rules`, `functions/src/index.ts` exports, `router.dart`, the feature flag and pubspec are **integrator-owned**. Sub-agents ask for changes there.

| # | Workstream | Owns (create/modify) | Depends on | Main tests |
|---|---|---|---|---|
| 1 | Realtime media | `lib/backend/live_studio/media/**`, `functions/src/liveStudio/token.ts` | contracts | Backoff schedule, audio-only fallback state machine, role→grant mapping |
| 2 | Realtime social | `lib/backend/live_studio/social/**`, `functions/src/liveStudio/social.ts` | contracts, media (data channel) | Rate limiter, aggregator, sampler, late-join dedupe, optimistic follow |
| 3 | Stage renderer | `lib/social_hub/live/studio_v2/stage/**`, `…/studio_v2/geometry/**`, `assets/live_studio/studio-geometry.json`, the studio photo | contracts, tokens | **Homography matches the prototype `matrix3d` within 1e-3**, hysteresis, pop-out clamp, golden images of the world layer |
| 4 | Roles, join, moderation | `lib/backend/live_studio/roles/**`, `functions/src/liveStudio/roles.ts`, `…/studio_v2/join/**` (queue, device check) | contracts, media | Permission matrix (§6) as table-driven tests against the functions emulator |
| 5 | On the table | `lib/social_hub/live/studio_v2/table/**`, `lib/backend/live_studio/table/**`, `functions/src/liveStudio/table.ts` | contracts, media (screen track) | **Watch-party sync** (offset estimate, drift > 300 ms → seek) |
| 6 | Stage customization | `lib/backend/live_studio/settings/**`, `…/studio_v2/settings/**` | contracts | Range validation, persistence round-trip, applied for viewers |
| 7 | UI shell | `lib/social_hub/live/studio_v2/shell/**`, `…/studio_v2/theme/live_studio_tokens.dart`, `live_studio_v2_screen.dart` | everything above, as interfaces | Golden tests vs the PNGs (≤2%), 44 px targets, Semantics labels, contrast, comments never overlap screens |
| 8 | Performance and QA | `test/live_studio_v2/**`, `integration_test/live_studio_v2/**`, `tools/loadtest/live_studio/**` | all | E2E per acceptance criterion; load test (100k simulated subscribers on data and reactions + 7 publishers via LiveKit's `lk load-test`); profiling on a mid-range Android |

**Integration order**:
1. Contracts and flag first.
2. Then 1, 2, 3, 6 in parallel.
3. Then 4 and 5, which need media.
4. Then 7.
5. Then 8, with fixes looping back to owners.

Flutter-specific notes:
- "GPU transforms" = `Transform(Matrix4)` + `RepaintBoundary` per tile, with animations through `AnimatedBuilder` on transforms and opacity only.
- `BackdropFilter` is expensive, so glass blur is limited to chrome groups and one shared filter layer.
- The comment feed is a `ListView.builder` capped at 50 items.
- "aria-labels" = `Semantics(label:)`; focus rings come from `FocusableActionDetector`.

---

## 11. Feature flag and rollout

- Add `AppFeature.liveStudioV2('live_studio_v2')` (default off). Remote Config JSON uses the existing allow-list and percentage rules.
- `LiveRoomGate` and Go Live: if the flag is on and `stream.layoutMode == 'studio'`, route to `LiveStudioV2Screen`. Otherwise use v1 / classic, unchanged.
- The routes in AGENTS.md §1 are untouched. New route: `/live/studio2/:streamId` (pushed, with a back path).
- v1 studio files, routes and rules are removed only after every acceptance criterion passes and you sign off.

## 12. Share / deep link

`lsShare` returns `https://<domain>/live/<streamId>` (domain: Q6). Firebase Hosting serves a small landing page. Android App Links (`assetlinks.json`) and iOS Universal Links open `/live/viewer/:streamId`, with `oneova://live/<id>` as a fallback. The router change is integrator-owned.

---

## 13. Open questions (need your answers before Step 2)

1. **Media provider**: approve LiveKit? Cloud (A, recommended) or self-hosted (B)? Adds `livekit_client` + `livekit-server-sdk`.
2. **Server-authoritative design**: OK to move all v2 mutations to callable functions and lock the v2 Firestore paths to function-only writes?
3. **Viewer tap on a guest**: open a local pop-out (proposed), or does a viewer's tap also swap their own view, which would break sync?
4. **"Participants" count (36)**: stage members + co-hosts + pending requests (proposed), or everyone signed in watching?
5. **Goods source**: Biz `products` collection (host's business catalog), the per-stream `products` list, or both?
6. **Share domain**: `oneova.com` (do we control it?) or the Firebase Hosting domain `mpepe-2b4bd.web.app`?
7. **Watch-party content**: do we have any rights-cleared football or movie sources? If not, Match/Movie ship with an empty admin catalog, which keeps the mode working and testable without unlicensed content.
8. **"Old live interface" to remove**: the v1 Studio only (proposed), or also the Classic vertical live viewer?
