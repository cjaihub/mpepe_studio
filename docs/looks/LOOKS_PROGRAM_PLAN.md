# Oneova Looks & Visual Intelligence — Plan v3 (for review, nothing built yet)

> **v3 changes (your second review):**
> - We build **our own Oneova Camera Kit**: no Snap or BytePlus licenses.
> - **Every language command is understood by AI live.** There's no hard-coded command parser.
> - **Offline AI runs on the phone itself**, using skills synced to the device.
> - **Scale to billions while keeping cloud costs low** (§4.5).
> - **Oneova Wallet + Coins + worldwide payments**, including African mobile money and withdrawals (§12.6).
> - Device Advisor gets a **Pro override** toggle.
> - **No App Store / Play Store release for now.** Backend deploys and internal test builds only.
> - 4 new subagents (23 in total).
>
> v2 included every comment from your first review. The main changes: **Live goes first**, **Cinema Presets become part of Looks**, **Beauty → Boost Beauty**, **conversational AI Color Grader with scope monitoring**, **AI processing that runs on the phone or in the cloud depending on the situation**, a **Snap-style capture camera**, **AR effects**, **100+ server-driven Looks**, **Looks sold in the Biz marketplace**, and **19 Gemini 3 subagents** split across phases.

---

## 0. Your questions answered

### What does CapCut use for video export?
CapCut runs on ByteDance's **own in-house editing engine**. ByteDance sells the same engine to other companies as the *BytePlus Video Editing SDK*. Internally it is built from three parts:
1. **Hardware video decoders/encoders** (Android MediaCodec, iOS VideoToolbox). This is why it's fast and doesn't heat the phone much.
2. **A GPU effects/color pipeline** (OpenGL/Metal).
3. **FFmpeg-derived libraries** for containers and edge-case formats only. Its open-source notices list FFmpeg components.

**My recommendation:** build the same architecture ourselves.
- Hardware codecs through **Android Media3 Transformer + iOS AVFoundation**.
- Our own GPU Look engine on top.
- **No full FFmpeg bundle**, so the app stays light.
- **Cloud render** (Cloud Run GPU) for very long or 4K projects, and for weak phones.

The licensed BytePlus SDK is the paid alternative.

### What do TikTok and Snapchat use for face tracking and AR?
- **TikTok:** ByteDance's in-house **Effect SDK** (Effect House). It's sold to other companies as **BytePlus Effects SDK** under a paid commercial license.
- **Snapchat:** its own engine. Third parties can license it as **Snap Camera Kit** (Lenses), which requires Snap's partner approval and acceptance of their terms.
- **Neither of them uses MediaPipe.**

### Decision (your answer): build **Oneova Camera Kit**, our own SDK, from scratch
It's 100% our code and runs **on the phone and on our Firebase/GCP**. No Snap or BytePlus. It's one native package, `packages/oneova_camera_kit/`, with these modules:

| Module | What it does | Runs on |
|---|---|---|
| **Capture** | Camera sessions, formats, Smart Lock, pro controls | Phone |
| **Look Engine** | GLSL grading graph, LUT stack, film/fx | Phone + cloud (same shaders) |
| **Vision** | Segmentation, face mesh, hands, pose, depth, object tracking | Phone (LiteRT) + cloud |
| **Boost Beauty** | Skin, features, reshape, makeup | Phone |
| **Lens Runtime** | AR effect packages (`.oneovafx`), triggers, 3D stickers | Phone |
| **Live Processor** | Applies everything to WebRTC/LiveKit frames before encoding | Phone |
| **Edit & Export** | Timeline render, hardware encode at source quality | Phone + Cloud Render |
| **Cloud Companion** | Rotoscope, enhance, relight, render, AI skills | Our Cloud Run / Functions |

**About "from scratch" for AI models:**
- Training face-tracking and segmentation models from zero needs large licensed datasets and months of work.
- So the kit **starts with open models whose licenses allow commercial use** (MediaPipe model files and SAM 2 are Apache-2.0; Gemma uses Google's Gemma terms, which allow commercial use). These run **inside our own runtime**, so we own the SDK, the pipeline and the hosting.
- **Phase 11, "Oneova Vision Models"**, then fine-tunes and distills **Oneova-owned models** on licensed/consented data and swaps them in without any app changes, because models are downloaded files, versioned in Storage.

Effect authoring: an in-app admin **Oneova Effect Studio** first, with a desktop version later (desktop/web come later, per your earlier answer).

---

## 1. Program principles (every agent must follow these)

1. **Nothing hard-coded.**
   - Looks, categories, thresholds, quality ladders, AI skills, prompts, limits and feature flags all come from **Firestore / Remote Config / device capability probes**.
   - The app bundles only a small offline starter cache, synced from the server.
2. **No placeholders, mocks or `// TODO` stubs.** If a feature needs an external account (Snap, BytePlus, payments, App Store), the agent **stops and asks you** instead of faking it.
3. **Preserve native quality.**
   - Capture, edit and export at the **real negotiated resolution, fps, bit depth and HDR** of the device and source, up to 4K60 / 10-bit HEVC where supported.
   - No fixed resolutions anywhere.
4. **The phone stays cool.**
   - Zero-copy GPU textures and hardware encoders only.
   - ML runs at adaptive rates.
   - A predictive thermal governor (§4).
5. **Hybrid compute.** Every heavy task goes through the **Compute Router**, which picks the phone, a nearby fallback, or the cloud based on device tier, thermal headroom, battery, network quality and cost.
6. **Live layout is locked.** None of this changes the existing Live viewer layout or the locked Home/Nav rules in `AGENTS.md`.
7. **Oneova design rules apply:** brandBlue primary, brandPink accent, compact/dense, light and dark mode, confirmations, `context.push`.

---

## 2. Current state (from the v1 audit)

- There are 7 separate preset models: `CinemaPreset`, `StudioPreset`, `PhotoPreset`, `ColorPreset`/`ColorState`, `OneovaColorGrade`, `ColorGradingPayload`, `LiveBeautyConfig`.
- Rendering is placeholder code:
  - `PhotoColorEngine` returns null.
  - `LutNode` passes frames through unchanged.
  - The `.cube` files don't exist.
  - Camera "beauty" is a white overlay.
  - Live beauty is never applied to the stream.
- Things we can build on:
  - `aiGateway.ts` (Gemini 2.5 Flash).
  - `generateLiveApiToken` (Gemini Live API), which is good for voice grading.
  - LiveKit live studio backend (`functions/src/liveStudio`).
  - `creator_marketplace_service.dart` + `biz_feed_screen.dart`.
  - `ova_assistant/`.
  - The mask engine.

**Consolidation (your comment):** `CinemaPreset` and the Cinema Presets UI are **folded into Looks** and become the "Cinematic" category. A one-time migration converts saved user cinema presets into Looks, and the old entry points then route to the Looks UI. Same for the other 6 models: there are adapters while migrating, then the old models are retired. All edits move forward only.

---

## 3. The OneovaLook format (v2, extended)

One versioned JSON document describes every filter, preset, AI look, marketplace look and live scene look.

```
OneovaLook (schemaVersion 2)
├─ meta        id, name, owner, category[], tags, thumbs, source(catalog|user|ai|remix|market),
│              parentLookId, priceRef?, realtimeCompatible, minDeviceTier
├─ intensity   master 0–1 + per-group intensities
├─ nodes[]     ordered grading graph (Simple mode shows a flat UI; Pro mode exposes nodes)
│   ├─ primary      exposure, contrast, pivot, highlights, shadows, whites, blacks, brightness
│   ├─ wheels       lift / gamma / gain / offset (+ log wheels: shadow/mid/highlight)
│   ├─ color        temperature, tint, vibrance, saturation, color boost
│   ├─ curves       custom RGB, Hue-vs-Hue, Hue-vs-Sat, Hue-vs-Lum, Lum-vs-Sat, Sat-vs-Sat
│   ├─ hsl          8+ bands × (hue, sat, lum) with range/falloff
│   ├─ qualifier    HSL key → secondary correction (point color / color picker)
│   ├─ warper       color warper mesh (hue–sat grid)
│   ├─ lutStack[]   multiple LUTs with blend + intensity (cube/png, 17–65³)
│   ├─ film         emulation profile, halation, bloom, grain (size/roughness), gate weave, fade
│   ├─ detail       sharpen, clarity, texture, dehaze, noise reduction (luma/chroma)
│   ├─ optics       vignette, chromatic aberration, lens distortion, tilt-shift, bokeh (depth)
│   ├─ fx           light leaks, flares, glitch, VHS, RGB split, prism, mirror, dust & scratches
│   └─ masks        semantic (skin/face/hair/sky/bg/person/object) | text-prompted | drawn | tracked
├─ boostBeauty  (see §6)
├─ background   keep | blur(depth-aware) | replace(image/video/AI-generated) | color | green-screen
├─ ar           lensRef? (Phase 7)
└─ adaptive     rules evaluated per frame/scene, e.g. "auto-exposure-assist", "skin-protect",
                "highlight-guard" (thresholds come from the server, not the code)
```

Each node is marked **realtime** (allowed in Live/Camera) or **editor-only**. The device tier decides which realtime nodes are actually active.

---

## 4. Engine, Compute Router, thermal and device intelligence

### 4.1 Rendering
- **One GLSL source of truth**, compiled to:
  - a Flutter `FragmentProgram` (editor previews),
  - Android GLES 3 / Vulkan,
  - iOS Metal (via SPIR-V cross-compiling).
- The pipeline is **zero-copy**: camera/decoder texture → Look graph → encoder/preview. Frames never get copied back to the CPU.
- Golden ΔE tests check that every rendering path looks the same.

### 4.2 Compute Router (phone ↔ cloud)
| Task | Default | Falls back to |
|---|---|---|
| Live / camera looks, beauty, segmentation | Phone GPU/NPU | Lower quality tier (never the cloud; latency matters) |
| Scopes and Scope Sentinel | Phone GPU | — |
| **All** natural-language / voice grade commands | **AI only, understood live.** Gemini Live API (streaming voice/text) when online | **On-device LLM** when offline or the network is slow: Gemini Nano (Android AICore), Apple Foundation Models (iOS 26+), or a downloaded Gemma model through LiteRT on other phones |
| Complex grading, "match this", rotoscoping | Cloud (Gemini + Cloud Run GPU) | **Offline Pro mode:** on-device LLM + **locally synced skill packs** + on-device Vision masks + scopes. It does the same job at slightly lower precision, and syncs/refines when back online |
| Photo export | Phone | Cloud for 50MP+/batch jobs on low-tier phones |
| Video export | Phone hardware encoder | **Cloud Render** for 4K/long jobs, low battery, overheating or weak phones |
| AI enhance (upscale, denoise, relight, sky replace) | Cloud Run GPU (L4, scales to zero) | Lighter on-device model on high-tier phones |

The router weighs: device tier, thermal headroom forecast, battery, network bandwidth and RTT (`connectivity_plus` + live measurement), file size, and the **user's cost quota**. Routing policies live in Remote Config.

### 4.3 AI Device Advisor (your "detect device and force recommended settings")
- **First-run 5-second benchmark** (GPU frame time, encoder capabilities, sustained thermal behavior) combined with a **crowd-learned device profile** at `deviceProfiles/{model}`. The profile is built from anonymous telemetry of what each phone model actually sustains.
- Output: a **safe ceiling** (e.g. "4K30 recording, 1080p30 live, beauty high, segmentation 15fps"). Settings above the ceiling are **disabled and show the reason** (enforced, as you asked).
- **Pro override (your answer: yes):**
  - A toggle in Settings → Camera & Live: "Pro override, at your own risk", with a one-time confirmation dialog.
  - The Thermal Governor **still protects the device** (it can step quality down if it gets critical), and a small badge shows the override is on.
- It re-learns as new telemetry comes in. New phones get a ceiling within days.

### 4.4 Thermal Governor (TikTok-style, but predictive)
- Uses **Android ADPF** (`getThermalHeadroom` forecast + performance hint sessions) and **iOS `thermalState`**. It acts *before* the phone gets hot.
- **Step-down ladder** (from the server; the order can vary by device):
  1. ML rate
  2. effects quality
  3. background
  4. beauty
  5. fps
  6. resolution

  It steps back up when the phone cools. Every change is a smooth cross-fade, never a stutter.
- Also handles battery saver, low-power mode and charging state.

### 4.5 Built for billions of users, at the lowest possible cloud bill
The cheapest cloud call is the one we never make, so **the phone does the work by default**.

| Layer | How it scales | How it stays cheap |
|---|---|---|
| **Realtime (Live/Camera filters, beauty, AR, scopes)** | 100% on the phone, so it scales automatically with the number of users | **$0 cloud cost** per frame |
| **Catalog, Looks, effects, models, skill packs** | Served as static files through **Firebase Hosting / Cloud CDN** + **Firestore data bundles**; clients cache and use ETags | CDN egress instead of millions of Firestore reads; delta updates only |
| **AI (Gemini)** | Cloud Functions 2nd gen (concurrency 80+, autoscaling) + Gemini API | **Result cache** (same skill version + prompt + image-stats bucket → reuse); **context caching** for skill instructions; **Flash-Lite** for light tasks; **Batch API** (≈50% cheaper) for nightly/self-learning jobs; on-device LLM first when it's good enough |
| **GPU jobs** | **Interactive:** Cloud Run GPU, scales to zero, with max-instance caps. **Batch** (exports, enhance, LookSmith): **GKE Autopilot Spot GPUs** pulled from a Pub/Sub queue | Spot GPUs are about 60–90% cheaper; jobs are queued instead of failing; paid users get a priority lane |
| **Overload protection** | Pub/Sub/Cloud Tasks queues absorb spikes; **backpressure**: when queues are long, the Compute Router sends work back to the phone | Nothing crashes, it degrades smoothly |
| **Budget guard (D5)** | Cloud Billing budget → Pub/Sub → function writes `opsConfig/cloudSpend` = green / amber / red | Amber: free-tier cloud jobs go to the phone. Red: only paid/critical jobs use the cloud. Never a hard outage |
| **Abuse / cost attacks** | App Check + per-user token-bucket rate limits + per-tier quotas | Bots can't burn our GPU budget |
| **Firestore at scale** | No hot documents: sharded counters, ledger append-only, TTL policies on jobs/feedback, analytics exported to **BigQuery** instead of Firestore queries | Fewer reads/writes, predictable cost |
| **Live streaming** (the biggest cost at scale) | LiveKit with regional SFUs, simulcast + dynacast (only send the layers people watch) | Option to **self-host LiveKit on GKE** when volume makes it cheaper than LiveKit Cloud |

Each phase ships with a **load test** (k6 / Locust, simulated spikes) and a **cost-per-1,000-users report**, so we can see the bill before it happens.

---

## 5. Phase 1 — LIVE first

### 5.1 Live Looks
- Realtime Looks applied **inside the WebRTC/LiveKit capture pipeline** (native processor before encoding), so **viewers see exactly what the host sees**.
- 300ms cross-fade when switching, with no reconnect.
- Quality follows the real camera format, **720p / 1080p / 4K where the device and network allow**:
  - LiveKit simulcast layers
  - dynacast
  - adaptive bitrate
  - hardware H.264/HEVC
- **Viewer layout does not change.**

### 5.2 Advanced live settings (compact, TikTok-plus)
- Grouped compact sheet with these sections:
  - **Video:** resolution/fps (capped by the Advisor), low-latency mode, HDR where supported, stabilization, lens.
  - **Look & Boost Beauty**
  - **Background:** blur, replace, green screen.
  - **Audio:** noise suppression, voice enhance, echo cancellation, mic select (BT/USB), music ducking.
  - **Network:** auto/manual bitrate, reconnect policy.
  - **Health HUD:** bitrate, fps, dropped frames, temperature, battery. Host only.
- **Auto-save:** every change is saved to `users/{uid}/liveSettings/current`, and the next live restores it.
- **Live Profiles, unlimited:** save the full settings snapshot as a named profile (e.g. "Night Podcast", "Outdoor Vlog"), apply it with one tap, edit, duplicate or delete.
- **Scenes, unlimited:**
  - A scene is Look + beauty + background + overlay + audio preset.
  - Reorderable dock, swipe to switch, optional transition style and hotkeys (BT remote / volume keys).
- **AI Live Director**, optional:
  - Watches the host's frame through the Scope Sentinel.
  - Shows quiet chips like "You're backlit, Fix" or "Face underexposed, Fix" and applies a smooth correction.
  - Can run on auto.

### 5.3 Go Live wizard
The beauty step that currently doesn't apply anything becomes a real, compact **"Look, Beauty & Background"** step with live preview, Device Advisor recommendations and profile selection.

---

## 6. Boost Beauty (replaces Beauty)

**Face (MediaPipe 478-point face mesh, per face, multi-person):**
- **Skin:** texture-preserving smoothing (frequency separation), blemish/spot removal, even tone, under-eye brightening, shine control.
- **Features:** eye brighten/enlarge, teeth whitening, brow/lip definition.
- **Reshape:** face slim, jaw, chin, cheekbones, nose, forehead, eye distance. Mesh-warp based, with a **"Natural guard"** that caps extremes (limits set on the server).
- **Makeup (Phase 7 AR):** lipstick, blush, contour, lashes, liner, brow tint, hair color.
- **Auto Boost:** AI analyzes the face and lighting and sets everything with one tap, plus an intensity slider.
- Saved per profile/scene. Works the same in Live, Camera, Photo and Video (with tracking).

---

## 7. Phase 2 — Snap-style capture camera + pro camera

### 7.1 Capture
- **Modes:** Photo, Video, Hands-free, Multi-clip, Timer, Burst, Night, Portrait (depth), **Dual camera** front+back (iOS MultiCam / Android concurrent camera where supported).
- The Looks/Lens carousel is applied live while capturing.
- **After capture:**
  - **Save to device** at full original quality (user setting: with or without watermark),
  - **Continue editing** (opens the Photo/Video editor with the Look still editable),
  - **Post exactly as is**,
  - Save as draft.
- Quality is negotiated from the device's real formats: up to 4K60, 10-bit HDR/HEVC, full-resolution photos. Nothing is fixed.

### 7.2 Pro camera controls
- **Auto Light Control:** continuous exposure/white balance/focus with face priority, an exposure-compensation slider, front-camera ring light/screen flash, low-light boost.
- **Smart Lock (your request):**
  - The user taps where the shot should be judged; the app meters there.
  - When recording starts, **exposure, white balance and focus lock automatically**, so the picture doesn't pump or shift.
  - Optional re-lock on scene change, and a manual unlock.
- **Pro mode:** manual ISO, shutter, white balance (K), focus, lens switching (ultra-wide/wide/tele), stabilization modes, grid, level, zebras, focus peaking, histogram, audio meters, external/Bluetooth mic.

### 7.3 Quick access and Ova Assistant camera
- **Android:**
  - Quick Settings tile, home widget, app shortcuts.
  - **"Hey Ova, start recording"** works in the background without opening the camera screen, through a camera+microphone **foreground service**. Android requires a visible notification while recording; that's an OS rule.
- **iOS:**
  - Control Center control and **Lock Screen capture extension** (iOS 18).
  - Siri / App Intents: "Record with Oneova".
  - **iOS does not allow camera recording in the background.** The fastest possible option is that Ova opens a minimal capture view instantly. I'll be upfront about this limit rather than fake it.
- **Ova voice commands while the camera is open:** "switch to front", "apply Golden Hour", "lock exposure", "start/stop", "take photo in 3".

---

## 8. Phase 3 — AI Color Grader + Scope Sentinel + AI Skills Engine

### 8.1 Conversational grading (text and voice, real time)
- "Hey Ova, grade it like a 90s film", "reduce the light", "lower contrast a bit", "lift shadows", "less saturation", "make it warm", "make the sky bluer", "match this photo".
- **No hard-coded command parser. Every request is understood by AI, live**, in any language, slang or mix (e.g. Swahili + English).
  1. **Online:** a **Gemini Live API** streaming session (already wired: `generateLiveApiToken`). The model receives the current Look, scope readings and a small frame preview, and streams **tool calls** (`adjust`, `mask`, `applySkill`, `undo`) that the app applies as they arrive. Sliders move while you're still speaking.
  2. **Creative or reference jobs:** Gemini with structured output against the OneovaLook schema, using the skills from §8.4.
  3. **Offline or slow network:** the on-device LLM (Gemini Nano / Apple Foundation Models / Gemma via LiteRT) with the **same tool interface and locally cached skill packs**, so the experience stays the same.
  4. The AI **replies** by text or voice ("Done, I lifted shadows and warmed it by about 300K. Want it moodier?").
- **Region-aware:** "make *her jacket* red" → text-prompted mask (rotoscope, §10) → applied only to that region.
- **Works like an agent:** it applies changes step by step, shows a diff ("Shadows +12, Temp +350K, Sky sat +18"), **reports when it's done**, offers Undo/Refine, and keeps a version history.

### 8.2 Pro grading tools (Simple mode by default, Pro mode one tap away)
- Everything in §3:
  - wheels (lift/gamma/gain/offset + log)
  - all 6 curve types
  - HSL qualifier
  - color warper
  - LUT stack
  - film emulation and halation
  - node graph (serial/parallel/layer)
- **Workflow tools:**
  - stills gallery, versions, split/wipe compare
  - copy/paste grade, shot match
  - power windows with tracking (Video)
- **Scopes:** waveform, RGB parade, vectorscope with skin-tone line, histogram, CIE chromaticity, false color, zebras.

### 8.3 Scope Sentinel (silent AI monitor)
- GPU-computed scopes on a downscaled frame, roughly every 150ms. It stays silent until something is wrong, then shows a small chip with **one-tap Fix** and **Explain**:
  - "Highlights clipping (4.2%)"
  - "Shadows crushed"
  - "Contrast compressed / crushing"
  - "Skin off the skin-tone line (too magenta)"
  - "Over-saturated / out of broadcast gamut"
  - "Color cast: green"
  - "Face underexposed"
  - "Noise high in shadows"
  - "Mismatch with previous clip"
- All thresholds are **server-configured skills** (§8.4), adapted per content type (portrait, night, product, etc.).

### 8.4 AI Skills Engine (built-in skills, deployed and self-learning)
- **A skill** = versioned package in `aiSkills/{skillId}/versions/{v}`:
  - instructions,
  - JSON schema,
  - analysis rules/thresholds,
  - few-shot examples,
  - evaluation set.
- **Starter skills:**
  - `auto_enhance`, `match_reference`, `skin_tone_guard`, `exposure_balance`, `cinematic_grade`, `night_rescue`, `product_true_color`, `live_lighting_fix`, `scope_sentinel_rules`, `look_namer`, `look_from_prompt`, `rotoscope_prompt`.
- The Cloud Function loads the active skill version at runtime. **Changing a skill doesn't need an app release.**
- **Self-learning loop:**
  1. Collect signals into `aiSkillFeedback`: accepted/rejected, which variant was picked, **how much the user re-adjusted sliders after the AI** (what the AI got wrong), undo rate.
  2. A nightly scheduled function aggregates the signals → Gemini proposes an improved skill version → **offline eval against the golden set** → **10% A/B rollout** → auto-promote if metrics improve, auto-rollback if they get worse.
  3. An admin can pin, roll back or review versions.

  This learning is feedback-driven updates to prompts, rules and examples; there's no custom model training, which keeps it cheap and safe.

---

## 9. Phases 4–5 — Photo and Video editors

- **Photo:** full grading UI (Simple/Pro), Boost Beauty, background, masks, scopes, Sentinel, AI grader, batch apply, export at original resolution (cloud for huge or batch jobs).
- **Video:**
  - per-clip grade + adjustment layers
  - keyframed intensity and parameters
  - Look transitions, shot-match across clips
  - tracked masks, beauty with tracking
- **Export:**
  - **hardware codecs, matching the source** resolution, fps, bit depth, HDR,
  - with Cloud Render as a background job with a progress notification for heavy projects.
- Both editors open captures from §7 with the Look still editable, without baking it in.

---

## 10. Phase 6 — Cloud vision services (server, light on the phone)

Cloud Run GPU services (L4, scale to zero, per-user quotas):
- **Natural-language rotoscope:**
  - Gemini 2.5 finds and boxes what you describe ("the man in red", "the sky").
  - **SAM 2** produces precise masks and **tracks them through the video**.
  - The result comes back as a compressed mask track usable in Live Studio scenes, the photo editor and the video editor.
  - The agent reports: "Selected *the car* across 214 frames. Done."
- **AI Enhance:** upscale, denoise, deblur, frame interpolation (slow-mo).
- **AI Relight** (portrait relighting) and **Sky replace**.
- **Cloud Render:** the same GLSL graph running server-side, so it's pixel-identical to the phone.

---

## 11. Phase 7 — AR Effects
- Face-tracked effects: masks, 3D stickers, makeup, hair color, face swap-style styling.
- Hand/gesture-triggered effects ("peace sign → confetti"), body/pose effects, clones, green screen.
- **Effect packages** are data plus assets from Storage (no hard-coded effects), with an internal authoring format. Optional Snap Camera Kit / BytePlus integration (Decision D1).
- Works in Live, Camera and Video.

---

## 12. Phase 8 — Looks library, presets, sharing, Biz marketplace

### 12.1 Catalog (100+ at launch, organized like CapCut)
- **Categories** (server-driven, reorderable):
  - Trending, For You (AI-personalized), Life, Portrait, **Cinematic** (former Cinema Presets), Film, Retro, Vintage, B&W
  - Food, Travel, Landscape, Night, Seasons, Mood, Style (Y2K, K-style, Moody…)
  - Product/Biz, Live-optimized, Creator Picks, Marketplace
- **Storage:** `lookCatalog/{lookId}` + Storage assets, managed through an **admin publishing tool** (admin role only).
- **How the 100+ Looks get made:**
  - The **LookSmith** agent generates candidate Looks with the Skills Engine and real reference images.
  - **You (or a colorist) approve them in an admin review screen** before they go live.
  - This is real product content, not fake data.

### 12.2 Presets
- Save any Look, live profile or scene.
- Unlimited presets, folders, favorites, auto-save, device sync.

### 12.3 Share and export
- In-app sharing via DM, link or QR.
- "Filter by @user → Try this look" on posts.
- Remix with attribution.
- Export `.cube` / `.oneovalook` (Pro).

### 12.4 Sell in the Biz marketplace (Business profile required)
**Package (`.oneovapack` zip), auto-generated:**
- Look JSON + LUTs (.cube + png)
- **auto-saved before/after reference stills**
- metadata and license

**A showcase video is mandatory:** it shows the result and carries the purchase link.

**Publish creates:**
- a **Biz marketplace product** (extends `creator_marketplace_service`) with price, preview and **Add to cart**,
- a **Biz feed post** with the showcase video and a "Buy look" CTA.

**After purchase:**
- entitlement at `users/{uid}/entitlements/{lookPackId}`, which unlocks the pack in every filter tray,
- revenue share and moderation review before listing.

### 12.5 AI limits per tier
- Daily AI generation quotas per plan (Free/Pro/Business) and cloud-compute credits.
- All values are in Remote Config. Extra AI credits can be bought with **Coins** (§12.6).

### 12.6 Oneova Wallet, Coins and worldwide payments
Today `payment_provider_service.dart` and `monetization_service.dart` are placeholder code (only comments for Stripe/KYC). They get replaced with a real system.

**Coins economy (TikTok-style, app-wide):**
- Users **buy Coins** and spend them on Looks/packs, effects, AI credits, gifts in Live and Biz goods.
- Creators/sellers **earn** a separate balance (**Oneova Earnings**), shown in the user's local currency at **real-time FX rates**.
- They can convert or **withdraw to their local provider** (mobile money or bank) in their country.

**Payment orchestration** (one internal API, several providers, routed by country, platform and method; routing tables in Firestore/Remote Config):
| Need | Recommended provider | Coverage |
|---|---|---|
| Africa: pay in and **withdraw to mobile money** | **Flutterwave** (main Africa rail) | M-Pesa (Kenya), MTN MoMo (Ghana, Uganda, Rwanda, Zambia, Cameroon, Côte d'Ivoire…), Airtel Money, Telecel (ex-Vodafone) Cash Ghana, Vodacom M-Pesa markets, Orange Money, plus cards and bank payouts in ~30+ African countries |
| Lower-fee direct rails (later) | **Safaricom Daraja** (M-Pesa C2B/B2C), **MTN MoMo Open API** | Kenya; MTN markets |
| Rest of world: cards, **Google Pay**, Apple Pay, payouts | **Stripe** (+ Stripe Connect for creator payouts) | 45+ countries for accounts, cards worldwide |
| Backup / Nigeria-Ghana-SA strength | **Paystack** (owned by Stripe) | NG, GH, KE, ZA, CI |
| Buying Coins **inside the app** | **Google Play Billing / Apple IAP** where store rules require it; alternative billing (Flutterwave/Stripe) where the law allows it (EU DMA, US external links, Google User Choice Billing markets) | Global |

> [!WARNING]
> **Store rule:** Apple and Google require their own in-app purchase for Coins and digital goods bought inside the app in most countries (they take 15–30%). **Withdrawals, creator payouts, physical Biz goods and web top-ups** can use Flutterwave/Stripe. The orchestrator chooses the legally allowed rail per country, and that table is maintained in config.

**Wallet backend (built to be safe at scale):**
- **Double-entry ledger:** an append-only `ledger/{entryId}` collection; balances are calculated only by Cloud Functions in transactions, and clients can never write them. Idempotency keys come from provider webhooks.
- **Real-time balance:** `wallets/{uid}` (coins, earnings, pending, currency), streamed live.
- **Withdrawals:**
  - KYC through the provider, plus AML limits, sanctions screening and velocity/fraud rules.
  - Payouts go through the provider's transfer API to the user's saved mobile-money/bank account, with status webhooks.
- **Compliance:**
  - Coins are a closed-loop virtual currency (not cash, not refundable except where the law says so).
  - Licensed providers hold the money; Oneova doesn't.
  - Tax/invoice records are kept per country.
- **Biz marketplace:** look packs and goods are priced in Coins *or* local currency. **Add to cart** → checkout with the wallet → entitlement unlocked. The seller is credited after a hold period.

---

## 13. Data model (summary)

```
lookCatalog/{lookId}                     server catalog (admin-published)
lookCategories/{catId}                   order, names, icons
users/{uid}/looks/{lookId}               user looks/presets (+ folders, favorites)
users/{uid}/liveSettings/current         auto-saved live settings
users/{uid}/liveProfiles/{id}            unlimited
users/{uid}/liveScenes/{id}              unlimited
users/{uid}/entitlements/{packId}
publicLooks/{lookId} (+ /uses/{uid})     shared/remixable looks, one-per-user counters
lookPacks/{packId}                       marketplace packs (showcaseVideo, price, productRef)
aiSkills/{skillId}/versions/{v}          skills engine
aiSkillFeedback/{id}                     learning signals (server-only write)
deviceProfiles/{model}                   crowd-learned device ceilings
computeJobs/{jobId}                      cloud render/rotoscope/enhance jobs + status
wallets/{uid}                            coins, earnings, pending, currency (functions-only write)
ledger/{entryId}                         append-only double-entry ledger (functions-only)
payoutAccounts/{uid}/{id}                mobile money / bank destinations (encrypted refs)
payouts/{id} · paymentIntents/{id}       provider-synced status via webhooks
paymentRouting/{country}                 allowed rails per country/platform
visionModels/{modelId}/versions/{v}      Camera Kit model registry (Storage URLs, min tier)
opsConfig/cloudSpend                     live spend level written by budget alerts
```
Rules are written by the existing `firestore-rules-author` subagent. Counters, catalog, skills and entitlements are writable by functions only.

---

## 14. Phases and Gemini 3 subagents

**Order:**
- **Phase 0** (core engine, required by Live)
- → **1 Live**
- → 2 Camera
- → 3 AI Grader/Skills
- → 4 Photo
- → 5 Video/Export
- → 6 Cloud vision
- → 7 AR
- → 8 Library/Marketplace
- → 9 Self-learning and personalization tuning
- → 10 Backend deploy + internal test builds (**no store release yet**)
- → 11 Oneova Vision Models (our own trained models)

> v3: the native package is now **`packages/oneova_camera_kit/`** in every agent brief.

**New in v3:**
| Phase | Subagent | Main deliverable | Depends on |
|---|---|---|---|
| 0 | `scale_cost_architect` | §4.5 setup: CDN/bundles, AI caching, GPU queues + Spot batch, budget kill-switch, rate limits, load tests | core_architect |
| 3 | `offline_ai_engineer` | On-device LLM layer (Gemini Nano / Apple Foundation Models / Gemma LiteRT), skill-pack sync, shared tool interface | ai_skills_engine |
| 8 | `wallet_payments_engineer` | Coins, ledger, wallet UI, payment orchestrator (Flutterwave, Stripe, Play/IAP), withdrawals, KYC | look_core_architect |
| 11 | `oneova_vision_models` | Model registry, training/distillation pipeline, swap in Oneova-owned models | P7 |

**Original v2 roster (updated briefs):**

| Phase | Subagent | Main deliverable | Depends on |
|---|---|---|---|
| 0 | `look_core_architect` | OneovaLook v2 schema, Dart models, adapters, Cinema→Looks migration, Firestore collections | — |
| 0 | `gpu_look_engine` | Shared GLSL graph, Flutter shader, Android GLES/iOS Metal native plugin, LUT stack, golden ΔE tests | core_architect |
| 0 | `device_thermal_governor` | Device Advisor (benchmark + `deviceProfiles`), ADPF/thermalState governor, Compute Router | gpu_look_engine |
| 1 | `live_looks_engineer` | Native frame processor in the LiveKit/WebRTC pipeline, simulcast/adaptive quality, Boost Beauty realtime, background | P0 |
| 1 | `live_settings_ui` | Compact advanced live settings, auto-save, unlimited profiles and scenes, health HUD, Go Live step, AI Live Director chips | live_looks_engineer |
| 2 | `camera_pro_engineer` | Native capture plugin, modes, Smart Lock, pro controls, native-quality recording, save/edit/post | P0 |
| 2 | `camera_quick_access_ova` | QS tile, widgets, iOS Control/Lock-screen extension, App Intents, Ova voice + Android background capture service | camera_pro_engineer |
| 3 | `ai_skills_engine` | `aiSkills` runtime loader, starter skills, `createLook`/`gradeCommand` functions, quotas | P0 |
| 3 | `ai_color_grader` | NL/voice grading (intent parser + Gemini + Live API), agent diff/undo/history | ai_skills_engine |
| 3 | `scopes_sentinel` | GPU scopes, Scope Sentinel alerts with one-tap fix | gpu_look_engine, ai_skills_engine |
| 4 | `photo_grading_ui` | Simple/Pro grading UI, Boost Beauty, masks, export | P3 |
| 5 | `video_color_timeline` | Per-clip/adjustment-layer grading, keyframes, tracked masks | P3 |
| 5 | `export_render_engineer` | Media3/AVFoundation hardware export at source quality, Cloud Render job client | gpu_look_engine |
| 6 | `cloud_vision_services` | Cloud Run GPU: SAM 2 rotoscope, enhance, relight, sky, cloud render | export_render_engineer |
| 7 | `ar_effects_engineer` | MediaPipe face/hand/pose effects, effect package format, makeup | P1, P2 |
| 8 | `looks_library_curator` | Catalog backend, admin publishing/review, LookSmith generation of 100+ candidates, CapCut-style browser | ai_skills_engine |
| 8 | `biz_marketplace_packs` | `.oneovapack` builder, showcase video requirement, product/cart/entitlements | looks_library_curator |
| all | `filter_qa_verifier` | Guard tests, analyze, golden ΔE, thermal/perf soak tests, light and dark mode review after each phase | — |
| 10 | `release_deployer` | Deploys functions/rules/indexes/Cloud Run/Remote Config; **internal debug/profile builds only, no store submission** | QA pass |

Draft agent files are in [subagents/](file:///Users/imac/.gemini/antigravity-ide/brain/c271fc60-3f49-43ce-a2a4-65ca7dbba4c6/subagents/), with a shared [AGENT_CONTRACT.md](file:///Users/imac/.gemini/antigravity-ide/brain/c271fc60-3f49-43ce-a2a4-65ca7dbba4c6/subagents/AGENT_CONTRACT.md). **Once you approve, I'll install them** to `.agents/agents/` and copy this plan to `docs/looks/LOOKS_PROGRAM_PLAN.md`. You can then run them in Antigravity with Gemini 3, phase by phase. Each agent is told to take its time, run nothing fake, verify, deploy its part, and report.

> [!IMPORTANT]
> **Steps where you have to act (agents will stop and ask):**
> - Firebase/GCP login, Cloud Run GPU quota (L4) and the monthly budget amount
> - Merchant accounts + API keys: **Flutterwave, Stripe** (and Paystack/Daraja/MTN later), Play Billing / App Store Connect products for Coins
> - Business registration documents required by payment providers (KYB)
> - Approving the 100+ catalog Looks
> - (No store release now; Snap/BytePlus are not needed because we build our own kit)

---

## 15. Risks
| Risk | Mitigation |
|---|---|
| iOS WebRTC frame processing is complex | P0 spike inside `gpu_look_engine`; fallback is a custom capturer feeding LiveKit |
| Cloud GPU costs | Scale to zero, per-user quotas, Compute Router prefers the phone, cost dashboards |
| Overheating at 4K + beauty + segmentation | Device Advisor ceilings + predictive governor + soak tests on real devices |
| Self-learning makes things worse | Offline eval gate + 10% A/B + auto-rollback |
| Marketplace abuse / stolen looks | Moderation review, showcase required, attribution through `parentLookId` |
| Gemini 3 agents stubbing things | Contract forbids it; `filter_qa_verifier` greps for TODO/mock/placeholder and fails the phase |

---

## 16. Decisions (resolved in v3)
- **D1 AR/face stack:** ✅ Build our own **Oneova Camera Kit**. Start with open models that allow commercial use, then move to Oneova-owned models in Phase 11.
- **D2 Video export:** ✅ Our own Edit & Export module (hardware codecs + our GPU engine + Cloud Render). No BytePlus.
- **D3 Payments:** ✅ **Oneova Wallet + Coins** with a payment orchestrator: **Flutterwave** (Africa mobile money: M-Pesa, MTN, Airtel, Telecel/Vodafone, Orange), **Stripe** (global cards, Google Pay, Apple Pay, payouts), Play Billing/IAP where store rules require it.
- **D4 Device Advisor:** ✅ Enforced + **Pro override** toggle.
- **D5 Cloud budget:** ✅ Phone-first + spend levels (green/amber/red) + Spot GPUs + caching. **You still need to give a monthly amount** (e.g. $300 or $1,000 to start). It's a setting you can change any time.

**Still open:**
- **Q1:** Coin price and creator share. TikTok-style is about 50% of gift value to creators after store fees. What share do you want for creators and for Look sellers?
- **Q2:** Which country/currency launches first for withdrawals? (Kenya with M-Pesa is the easiest first rail.)
