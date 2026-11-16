# Oneova build log

The running record of the current build. Rules: `.agents/rules/oneova_build_vision.md`.
Take the first step that isn't ✅, do it fully, then update this file in the same commit.

Status: ✅ done · 🔨 in progress · ⏳ next · ⛔ blocked (says why)

## ⚠️ Security first (do before new features)
- 🔨 S1. Gemini key leak: app side done. No direct Gemini calls are left in the app. Text, vision,
  dictation and self-repair go through OpenRouter (the user's own key, or the `aiProxy` server proxy).
  Live voice/video stays on Vertex (`FirebaseAI.agentPlatform` live models). The keys are removed from
  `.env`, a saved Gemini key is deleted on startup, and `release.sh` refuses `GEMINI_*`, `GOOGLE_AI_*`
  and `*SECRET*` values. Left: delete the old key in Google AI Studio (it is in builds 1–34).
- ✅ S2. Server text AI moved to OpenRouter (`google/gemini-2.5-flash` via `OPENROUTER_API_KEY` secret in `functions/src/vertexAi.ts` and `functions/src/globalOptions.ts`), keeping Vertex for live models and embeddings. Deployed all 13 AI Cloud Functions (`aiProxy`, `aiGateway`, `ovaAgentExecuteTurn`, `voiceTidy`, `chatAssist`, `suggestProfileDetails`, `studioCaptions`, `studioTranslate`, `reelTranslate`, `globalSemanticSearch`, `shopChatSend`, `processAiCommand`, `generateAbTests`) and verified live on both Mobile (`FirebaseAuth`) and macOS Agent Desk (`DesktopFirebaseRestClient`).

## Stage F: Language and location awareness
- ✅ F6. Automatic cache clean-up (`lib/shared/services/auto_cache_cleaner.dart`): leftovers older than a
  day, a 400 MB cache budget (Reels videos first, then thumbnails and images), runs after start and when
  the app is hidden, at most every 6 h; on/off and "Clean up now" in Settings → Storage. Self-repair now
  uses it instead of deleting the whole temp folder (which could break recordings and uploads).
- ⏳ F7. Interest profile for discovery: waiting for your decision (it changes the Ova vault privacy rule).
- ⏳ F1. First run and sign-in: phone language + detected country set the account's language, country,
  currency and time zone (one tap to confirm or change).
- 🔨 F2. Ova voice now gets the local time, day and phone language every turn and replies in the
  language spoken. City and country (coarse, with location on) still to add.
- ✅ F5. Ova Live has no time limit: it carries on in memory, or reloads the last voice conversation
  saved to the account after a restart. It knows the account (name, handle, verified, audience, account
  type, ID-check status; never balances or documents), recent activity and reminders, and location
  when allowed. When the user goes quiet it sleeps (mic off) after 90 s, or 45 s if it asked a question,
  and asks the question again when called back.
- ✅ F4. Ova Live carries on where it stopped (conversation kept 30 min after closing), answers "what's
  happening / progress / is it done" instantly from the task centre, knows all background work each
  turn, and says when background work finishes mid-session. Dictation: Vertex first (fastest, no key in
  the app), OpenRouter backup. Removed the dead calling overlay, its voice service and the old live
  overlay.
- ⏳ F3. App text in local languages (Swahili, French, Arabic, Hausa, Yoruba, Amharic, Portuguese…) with
  `flutter gen-l10n`; the language setting actually switches the app.

## Stage A: Focus the app (this version)
- ✅ A1. Vision and rules every agent follows (`.agents/rules/oneova_build_vision.md`, linked from `AGENTS.md`).
- ✅ A2. Removed studio management: YouTube manager screens, video and audio production, team tab, CRM,
  communication manager, and unused hub, drawer and studio hub screens. Fixed links to pages that never
  existed (`/creator_studio/*`, `/communication/*`) in the Reels author panel and deep links. Old routes redirect (`/yt/*` → `/social_hub`,
  `/video/*` and `/audio/*` → `/create/studio`, `/hub/team` → `/hub/home`).
- ✅ A3. Shared compact UI parts in `lib/shared/widgets/compact/`.
- ✅ A4. Settings and Me on compact rows. Settings: `CompactGroup`/`CompactRow` (50 px rows), quick
  controls as one wrap of chips, the health card only shows when something needs attention (summary
  first, issues and Fix on tap), slim profile row. Me sidebar: plain row icons, stats on one text line,
  borderless quick actions, unread as pink dots. All routes, health dots and live hints kept.

## Stage B: Compact UI everywhere (one area per release, each checked in light and dark)
- 🔨 B1. Business portal and shop tools (next).
- ⏳ B2. Chats: bubble padding 10–12, inline small previews for links, payments, gifts and reels;
  AI suggestion chips as one thin row only when useful.
- ⏳ B3. Ova and AI Lab: replies without boxes, tool results as one-line summaries, small orb,
  agents in the same Ova screen (`lib/ova_assistant/main_interface/`).
- ⏳ B4. Live: narrow faded comments, small gift pill, compact deal bar, seller tools in a sheet.
- ⏳ B5. Reels (locked layout, see `.agents/rules/oneova_home_launch_screen.md`): only shrink controls and
  fade extras after inactivity.

## Stage C: My computer inside Ova (security first)
Existing code: `lib/hub/phone_controller/`, `lib/hub/live_control/`, `lib/desktop_agent/`,
`functions/src/ovaAgentBridge.ts`.
- ⏳ C1. Security review of the control path: pairing is account plus device bound, sessions expire,
  either side can stop at once, commands are checked on the desktop against an allow list, signalling
  rules are owner-only, and media is end-to-end encrypted. Write findings into this file before C2.
- ⏳ C2. Control icons in the Ova overlay: live screen, mouse pad, voice keyboard, shortcuts. One tap opens
  each; no separate screens needed.
- ⏳ C3. Works across networks: TURN relay fallback verified on mobile data (no same Wi-Fi needed).
- ⏳ C4. Natural-language computer commands: Ova plans in the background, shows one animated activity
  line, and asks before risky actions (delete, send, buy, install).
- ⏳ C5. Media back in chat: screenshots, recordings, files and audio from the computer shown inline and small.

## Stage D: Oneova Pay, Globe ID, Merchant Hub, Sentinel
Design: `docs/payments/platform/` (architecture, security model, schema and API, code and deployment).
- 🔨 D1. Device binding: built and deployed to `mpepe-2b4bd`, ready to try on a phone.
  - Server `functions/src/pay/devices.ts` (+ pure checks and tests in `devicesLogic.ts`): challenge,
    register with Google key attestation (secure chip, our app, our challenge, needs a biometric,
    Google root, not revoked), trust after a fresh email code, 24 h cool-down for large payments on
    extra phones, verify, list, revoke. `verifyDeviceApproval()` is ready for D2.
  - Android `DeviceKeyChannel.kt`: P-256 key in StrongBox or TEE, every signature needs a strong
    biometric, new fingerprints invalidate the key. iOS not done yet (Secure Enclave + App Attest).
  - App `lib/pay/security/` (device key, service, live face card with mesh that follows the real
    checks) and `/id/devices` (Payment phones, linked from Oneova ID).
  - Left: try on a real phone, iOS.
- ⏳ D2. Payment requests with biometric approval and countdown, success screen (`003_pay_core.sql`).
  Approval uses the face card + `verifyDeviceApproval()`. After each payment, a payment report for
  both sides: written from the server's own records (ledger journal, approval, risk decision), with
  plain-language wording added by AI that can't change any fact. Every step is stored as a
  `payment_events` row and published on Pub/Sub so other systems (merchant webhooks, admin, analytics)
  can follow it.
- ⏳ D3. Signed receipts and verify.
- ⏳ D4. Send by Oneova ID, personal QR.
- ⏳ D5. Sentinel rules and admin review queue; App Check enforcement; KMS for funding methods.
- ⏳ D6. Merchant Hub: sales from the ledger, refunds, staff roles, statements.
- ⛔ Release to production waits for the Play organization account.

## Stage E: Location and discovery (design: `docs/architecture/location_discovery.md`)
- ✅ E0. KYC country auto-detect (on-device: GPS + geocoder, network, SIM, phone, region), modern KYC
  inputs, signals + mismatch flag stored for reviewers. Removed the unencrypted ip-api.com lookup.
- ✅ E1. Server door for Maps (`mapsGateway` in `functions/src/mapsGateway.ts`: `geoSearch`, `geoNearby`, `geoReverse`, `geoRoute`, `geoTimezone`), with Firestore caching and rate limits. Enabled Geocoding, Routes, Places and Time Zone APIs in Google Cloud Console (`mpepe-2b4bd`), stored `GOOGLE_MAPS_SERVER_KEY` in Secret Manager, deployed `mapsGateway(us-central1)`, and wired `geo_services.dart` to use `mapsGateway` first with OSM fallback.
- ⏳ E2. Location privacy settings and coarse geo cells on posts, lives and shops (set by Functions).
- ⏳ E3. Shops that deliver to you (delivery zones, Routes matrix ETA).
- ⏳ E4. Live near you row.
- ⏳ E5. Local slot in For You, Thompson-sampling exploration, travel mode.
- ⏳ E6. Restrict the Firebase Android API key to the app package and signing SHA-256 (console).

## Stage G: Multilingual chats and translated calls (design: `docs/architecture/translated_calls.md`)
- ✅ G1. Chats: on-device language detection (ML Kit Language ID, `lib/shared/language/language_detector.dart`).
  Messages in a language you don't read show "Translate from Swahili" (one tap). The per-chat
  auto-translate now sends only foreign-language messages to the AI. Left: "I read these" languages and
  an all-chats switch in Settings → Chat.
- ⏳ G2. Calls: live translated captions over the call's encrypted data channel (check mic sharing on
  real phones first).
- 🔨 G3. Live translated calls: built, not tried on phones yet.
  - Each call connection has a negotiated, encrypted data channel (`webrtc_connection_manager.dart`).
  - Phones swap their language (Settings → Language, else the phone's). When languages differ,
    translation starts by itself. The speaker's phone takes the mic from the call and streams it to
    Vertex Live (one session per listener language, at most two). The translated voice and captions go
    to each listener over the data channel. The listener mutes the original and plays the translation;
    same-language listeners get the original voice the same way.
  - Top-bar translate button: turn off for this call, pick the translated voice (4 preset voices).
    Two-line captions above the controls.
  - Code: `lib/backend/calling/interpreter/`, `lib/inbox/calling/widgets/call_interpreter_ui.dart`.
  - Left: test on two phones (echo, delay, group calls). Turn on App Check enforcement for Vertex.
- ⏳ G4. Speaker's own voice: closest preset voice now; exact voice cloning needs Google approval and
  each speaker's consent. 🤝

## Stage H: Reel translator
- ✅ H1. Server: `reelTranslate({postId, target})` (`functions/src/reelTranslate.ts`, pure parts in
  `reelTranslateLogic.ts` with node tests). Each reel is translated once per language and cached at
  `content|posts/{id}/translations/{lang}` (caption without hashtags, hashtags kept, plus the caption
  track from `transcripts/default` when there is one). Text goes through OpenRouter via the
  studioTranslate helper. Source language detected once and stored on the reel (`sourceLanguage`,
  re-detected if the caption changes). Limits: 300 calls / 10 min, 60 new translations / hour per user.
  Private reels: only the author. Rules: clients read translations, only Functions write. Deployed to `mpepe-2b4bd`.
- ✅ H2. App: the Reels caption shows in the viewer's language with "Translated from X · See original"
  (`lib/feed/widgets/reel_translated_caption.dart`); the CC overlay uses the translated track. Language
  is detected on the phone first, so reels you can read never call the server.
- ✅ H3. Settings → Language: "Translate reels automatically" and "Translate into" with a searchable
  list of world and local languages (`lib/shared/language/world_languages.dart`); default is the
  phone language.
- ✅ H4. Deployed `reelTranslate`, `studioTranslate` and `firestore.rules` to `mpepe-2b4bd`; ready to verify on a phone with a Swahili or Yoruba
  reel. Clients can't read `transcripts/default` yet, so the overlay's own fallback track is still built
  from the caption.

## Stage I: 3D and shops
Audit 2026-11-14 (photo → 3D, product background removal, AI 3D, live shop stage, `/shops` feed).

What was broken:
1. Photo → 3D called **Meshy** (third-party 3D SaaS, against the self-hosted rule), with the platform key
   `MESHY_API_KEY` or a seller's own linked Meshy key. The library screen asked sellers to paste a Meshy key.
2. The self-hosted 3D service (`packages/three_d_service`, GPU `packages/three_d_model_server` with TRELLIS /
   TripoSR, `infra/three_d.tf`) exists only on the unmerged `claude/oneova-3d-shops-ai` branch. That branch
   is based on the older marketplace branch: a straight merge would delete about 12k lines of shops work
   that is on this branch. Its model server has not run on a GPU yet.
3. Product background removal fell back to the **selfie (people) model** when the subject model wasn't
   ready. On a shoe or a bag that finds nothing, so the seller got an all-white photo marked "cleaned".
   No check that the cut-out kept anything. iOS has no cut-out at all (keeps the photo as taken).
4. Photo upload progress for 3D jumped once per photo; jobs whose worker died waited 40 min to fail.
5. `/shops` feed: live sellers first never worked once any live host had no open shop (one denied
   read failed the whole batch, silently). Paging could stall on a page with nothing new.
6. Live shop stage drew everything full-bleed over the video; the live title wasn't shown while watching.

Plan and status:
- ✅ I1. Photo → 3D runs only on Oneova's own GPU model server (`functions/src/models3d/providers.ts`,
  pure parts in `engineLogic.ts` with node tests). Same wire contract as `three_d_model_server`
  (`POST /v1/tasks`, `image_to_3d`, `gs://` inputs, GLB written into the model's own folder). Called
  with a Cloud Run ID token (only `.run.app` https URLs accepted). The worker waits for the GPU (8 min
  cap), shows a steady progress estimate, then optimizes as before. Off until `MODEL3D_SERVER_URL`
  (env or optional secret) is set: photos are kept, the library says "switching on", "Build now" later.
- ✅ I2. Seller key linking retired: `model3dLinkProvider` answers that nothing needs linking;
  `model3dUnlinkProvider` clears a key saved by an older version. App: Meshy sheet removed, one quiet
  status line instead (`model3dBuilderProvider`).
- ✅ I3. Background removal: products accept only the subject model, and only when 2–97% of the photo is
  kept (`isUsableCutout`, tests in `test/shops3d/product_photo_test.dart`). Otherwise the photo is kept as
  taken and the 3D photo sheet says which angle kept its background.
- ✅ I4. Byte-level upload progress for 3D photos; stuck jobs fail after 20 min (the worker keeps the job
  fresh while the GPU works); sweep every 5 min.
- ✅ I5. Live shop stage in the framed design (`shop_stage_view.dart`: `StageFrameBackdrop`, `StageFrame`):
  what's on above the frame (back, shop avatar with pink live ring, live title, shop + badge, LIVE,
  viewers, Follow), then the live video, 3D product, rail (love, gifts, save, share, cart), chat, deal,
  shelf and product card inside a 25 px frame. Widget tests in `test/shops3d/shop_stage_frame_test.dart`.
- ✅ I6. `/shops` feed uses the same frame and backdrop (empty and error states too); live-first fixed
  (each shop read fails on its own); short page ends paging; "Couldn't load more shops · Retry".
- ⛔ I7. Deploy the changed functions (`model3dGenerate`, `model3dResume`, `model3dWorker`, `model3dSweep`,
  `model3dEngineStatus`, `model3dLinkProvider`, `model3dUnlinkProvider`): waiting for the user's OK.
  Then remove the `MESHY_API_KEY` secret and decide whether to delete old `model3d_keys` docs (user data).
- ⛔ I8. Switch photo → 3D on: needs the user's go-ahead for GPU cost. Build and deploy
  `three_d_model_server` (TripoSR on Cloud Run GPU L4 first, scale to zero; TRELLIS later), IAM-only
  invoker = functions service account, `OVA3D_ALLOWED_BUCKET` = the app bucket, then set
  `MODEL3D_SERVER_URL`. Bring the full 3D Intelligence Service (editor, versions, product AI) over from
  `claude/oneova-3d-shops-ai` by porting, not merging.
- ⏳ I9. Check on a phone: product photos with a plain and a busy background, a live shop with deals,
  gifts and chat, light and dark mode. iOS cut-out (Vision `VNGenerateForegroundInstanceMaskRequest`).

## Session notes
- 2026-11-16 (build 44): Enabled Google Maps APIs in GCP (`mpepe-2b4bd`) and deployed `mapsGateway` Cloud Function (`geoSearch`, `geoNearby`, `geoReverse`, `geoRoute`, `geoTimezone`) backed by `GOOGLE_MAPS_SERVER_KEY`. Added real-time 3-phase **"Fly Me There"** camera flight animation, automatic GPS location lock, **Aerial/Satellite** view, **"What's Near Me"** category radar, **Map History** (`users/{uid}/ova_context/map_history`), and **AI Area Concierge** to `OneovaMapView`, `OvaLiveMapCard`, `OvaGeoTools`, and `OvaLocalIntents`. Redesigned `OvaAssistantPanel` (`ova_assistant_sheet.dart`) and `OvaClaudeAgentWorkspace` so the overlay always opens in the clean Quick Assistant view with a slide-over **Sidebar** for secondary actions, specialist personas, and history, plus a single glowing background activity pill (`"Thinking…"`, `"Working on it…"`). Upgraded `OpenRouterPostOptimizer`, `UploadService`, `PendingPostQueue`, `AISuggestionCard`, and `MediaPreviewScreen` so AI extracts a real visual frame from the video clip, automatically learns the creator's **Channel & Niche** from Firestore + linked channels, optimizes titles/descriptions/hashtags in the background, provides **4 High-Quality Upload Tiers** (`1080p HD`, `2K 60fps`, `4K Master`, `Original Raw`), and lets the creator **Select One Connected Channel** (YouTube channel, TikTok, Instagram, Facebook) for automatic background cross-publishing.
- 2026-11-16 (build 43): Replaced annoying on-screen notification pop-ups with default **Ring-Only / Silent Screen** mode (`showScreenPopups: false` in `NotificationPreferences`, `NotificationOverlayManager`), added granular **Muted Sources, Apps & Keywords** controls (`_MutedSourcesRow`, `_MutedKeywordsRow`, `shouldIgnoreNotification`) so users choose where they never want information from, and built `OvaNotificationMemoryService` (`users/{uid}/ova_context/notification_digest`) so Ova/Gemini learns notifications silently in the background and surfaces them **only** when the user asks about previous notifications (`recall_previous_notifications`, `mute_notification_source`). Upgraded Map & Gemini Geo features (`OneovaMapView`, `OvaLiveMapCard`, `OvaGeoTools`, `GeoServices`, `ChatLocationBubble`, `_ShareLocationSheet`) with **Rotoscope Contour Highlighter** (`_RotoscopeTargetPainter` + cyber-contour shader), **Live Animated Route Polyline** with travelling beacon, turn-by-turn street maneuver steps (`GeoRouteStep`), in-app **Start Live Directions** HUD, and WhatsApp-style **Live Location Sharing** + nearby places picker.
- 2026-11-16 (build 42): Released build 1.0.0 (42) to Play Store internal testing. Added direct deep linking to specific reel comments with animated highlight border and auto-scrolled thread (`CommentBottomSheet`, `ShortVideoFeedScreen`); made the status/stories row persistent across reel scrolls hiding strictly in immersive full-screen; kept comment input accessible in full-screen mode; added magnetic snap & stretch on the studio timeline with interactive snap guide line; expanded color grading controls with 3-way color wheels, curves, and 1-tap AI color balance; enhanced photo studio with interactive crop ratios, perspective controls, and local file comparison; added external app notification shield.
- 2026-11-14 (build 41): Released build 1.0.0 (41) carrying My voice wizard, own-voice voice notes and calls, and 3D shops improvements.
- 2026-11-14 (build 39): Fixed Live `deadline-exceeded` and OOM errors end-to-end: started self-hosted LiveKit SFU VM `oneova-livekit-1` (`africa-south1-a`), made `lsStart` room creation non-blocking (`3.5s` bound + `roomCreate: true` in host JWT grant + parallel Firestore batch/token/mediaKey), redeployed all 38 `ls*` Live Studio Cloud Functions with `512MiB` memory and `60s` timeout (`tools/livekit/deploy_functions.sh`), and upgraded `FirebaseStudioCallPort` to a `40s` timeout with automatic retry on transient errors. Overhauled `LiveSetupWizardScreen`, `LiveSetupPreviews`, and `LiveBeautyPanel` into compact, high-density multi-column grids, thin toggle tiles, and a compact phone stage preview. Unified Solo Studio and Multi-Guest Studio onto the single 3D Broadcast Studio Stage (`LiveStudioV2Screen` / `StudioStage` / `LiveRoomGate`) with full stage customization and join requests. Built real-time GPU `LiveVideoEffectLayer` (`live_look_presets.dart`, `live_looks_controller.dart`, `studio_video_view.dart`, `device_preview.dart`, `live_control_hub.dart`) with 8 Cinema Looks, 6 Studio Key Lighting presets, and real-time Beauty Retouch that visibly transform both the wizard preview and the live broadcast for the host and all viewers.
- 2026-11-14 (build 38): Deployed all 13 Cloud AI functions with `OPENROUTER_API_KEY` + 512MiB memory (`aiProxy`, `aiGateway`, `ovaAgentExecuteTurn`, `voiceTidy`, etc.); unified AI auth across Mobile and macOS Agent Desk (`OneovaAiGateway`, `AIBrainService`, `OvaAgentSyncController`); upgraded AI Agent input composers (`OvaAssistantPanel` & `OvaClaudeAgentWorkspace`) with animated AI Persona/Specialist avatars, live status rings, user avatar badges, and expandable `+ Attach` tool trays; fixed Reels one-tap full-screen frame toggle (`_framedCard` preserved at constant widget tree depth, zero horizontal side margin with 25px top/bottom corners, extended reel height, zero black flash via decoded `width > 0` gate, lower-half action rail, unhidden title/owner with bottom scrim, and spinning disc-only audio); added multi-photo + attached music support to both Reels and Status/Stories; generated new multi-note harmonic chime (`oneova_notification.wav`) and wired live AI startup suggestions + cross-app notification popups with 1-second AI quick reply pills (`NotificationOverlayManager`, `MainActivity.kt`).
- 2026-11-14: Deployed `firestore.rules`, `reelTranslate`, `studioTranslate`, `kycSubmit`, and the six `payDevice*` functions (`payDeviceChallenge`, `payDeviceRegister`, `payDeviceTrust`, `payDeviceVerify`, `payDeviceList`, `payDeviceRevoke`) to `mpepe-2b4bd`. Released build 1.0.0 (37) to Play internal testing with Framed Reels + one-tap full-screen mode, Wallet tab on the bottom bar (`OneovaPayHomeScreen`), AI Lab entry in Chats + My Wallet chip in Ova Assistant, and sensitive-topic personalisation controls.
