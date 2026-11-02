# Oneova Release Overview — Version 8 (v1.0.0+8)

## 1. Executive Summary
Build 8 delivers high-density polish, refined visual aesthetics, complete elimination of dead overlay spaces, executive workstation uncluttering, and new AR Face Effects & Oneova Looks in Live Studio v2.

---

## 2. Key Features & Enhancements

### 2.1 Feed Bottom Gap Elimination & Premium Edge Alignment
- **Problem**: When entering Focus Mode or when the bottom navigation bar auto-hid, reels overlays retained a static `66.0 + bottomPad` offset, leaving an empty ~96px dead black gap below comments and the audio disc.
- **Solution**: Replaced static coordinates with a reactive `bottomInset` powered by `oneovaBottomNavVisibleProvider`. When navigation is unmounted or hidden, the comment bar, quick reaction pills, and audio disc smoothly animate flush to `8.0 + bottomPad` using `Curves.easeOutCubic`.

### 2.2 Super Premium Curved Reel Frame
- Dynamic corner radius scaling:
  $$\text{radius} = 16.0 + 18.0 \times t$$
- Embedded inside high-performance `ClipRRect` containers with transition scaling to give every reel an executive, luxury feel rather than sharp 0px rectangle edges.

### 2.3 Secondary Tab & Workstation Navigation Decluttering
- In `HubShell`, `bottomNavigationBar` is strictly mounted on Home Reels (`currentIndex == 0`).
- When navigating to Studio, In-App Messages, AI Lab, Team, Settings, or Editors, the bottom bar is automatically hidden, expanding active screen real estate.
- Added stack-safe back navigation buttons (`Navigator.canPop(context) ? Navigator.pop(context) : context.go('/hub/home')`) with haptic feedback across all secondary tabs.

### 2.4 Streaming Optimization & Zero Background Playback
- Integrated `videoPlaybackManagerProvider.setScreenActive(false)` triggers across:
  - Tab switches away from `/hub/home`
  - Modal routes pushed on top of the feed (`didPushNext`)
  - Route pop events (`didPop`)
  - App lifecycle states (`paused`, `inactive`, `hidden`)
  - Export Center (`ExportCenterScreen`) and Post Screen (`MediaPreviewScreen`, `PremiumPostScreen`)
- All audio volume is immediately silenced to `0.0` and video slots are paused, preventing phantom background audio or hanging clips. Playback automatically resumes cleanly on return.

### 2.5 LiveKit Studio v2 AR Face Effects & Oneova Looks
- Built `_FaceAndLooksTab` inside `LiveControlHub`:
  - **Oneova Looks**: *Clean Pro*, *Teal & Warm*, *Golden Hour*, *Moody Noir*, *Velvet Pop*.
  - **AR Glasses**: *Neon Cat-Eye*, *Aviator Gold*, *Cyber Shades*, *Retro Specs*.
  - **Caps & Hats**: *Snapback Cap*, *Golden Halo*, *Studio Beanie*, *Party Crown*.
  - **Wigs & Hair**: *Cyber Violet*, *Platinum Bob*, *Neon Afro*, *Crimson Fade*.
  - **Masks & FX**: *Glitter Dust*, *Studio Glow*, *Anime Sparkle*, *Cyber Visor*.
- Compact executive sizing, live selection states, toggle clear buttons, and haptic feedback.

### 2.6 Built-in Auto-Transcription & Closed Captions (CC)
- **YouTube-Style CC Dock Button**: Direct toggle on the reel top controls bar (`Auto | Loop | Focus | CC`) with persistent user preference (`oneovaCaptionsEnabledProvider`).
- **Interactive Transcript Sheet**: Long-pressing CC or tapping the floating caption opens `showOneovaTranscriptSheet` featuring real-time timestamped dialogue, live search query filtering, active sentence auto-highlighting, full dialogue copying, and click-to-seek video playback.
- **Floating Subtitle Overlay**: `OneovaCaptionOverlay` delivers smooth subtitle rendering with cross-fade transitions and high-contrast dark scrim styling.
- **Advance Pre-Transcription**: Background pre-transcription triggers automatically on scroll, parsing and caching speech for current and adjacent reels in memory and Firestore with zero playback latency.

---

## 3. Verification & Compliance
- `flutter test test/guards/home_lock_test.dart`: 100% Passed (7/7).
- `flutter test test/social_hub/oneova_reel_comment_gif_test.dart`: 100% Passed (3/3).
- `flutter test test/social_hub/oneova_transcription_test.dart`: 100% Passed (4/4).
- `flutter analyze`: 0 Errors, 0 Warnings across touched files.
- Branding: 100% Oneova executive branding (`AppColors.brandBlue`, `AppColors.brandPink`).

