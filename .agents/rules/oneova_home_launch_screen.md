# Oneova Home / Launch Screen (LOCKED - DO NOT CHANGE)

*Highest priority. Never override, redesign, or replace this screen.*

## Launch behavior
- After the Oneova splash, an authenticated mobile user ALWAYS lands on `/hub/home`, which MUST render `ShortVideoFeedScreen` (`lib/feed/main_feed_screen.dart`). Never route `/hub/home` to `HubHomeScreen` or any dashboard.
- Unauthenticated users go to `/auth/main_login`, then land on the same home feed.

## Layout (exactly as in `ui_screenshot_splash.png`)
- Top row: Search icon (left) -> `Following | For You | Biz` tabs (center) -> Notification bell (right).
- Stories row under the top nav: "Your Story" (+ badge) then friends' stories (blue ring). Tapping opens the WhatsApp-style creator/viewer.
- Full-screen vertical video feed (PageView), video keeps playing behind overlays.
- Right action rail: author avatar with blue "+" (hidden once followed), Like, Comment, Save, Share, REMIX button, audio disc.
- Bottom-left: author pill, caption, "Shop ..." product chip, "Add comment..." bar with emoji + mic.
- Bottom nav: Reels, Chat (badge), center blue STUDIO "+" button, AI Lab, Me. Active tab = solid `AppColors.brandBlue` with scale animation.

## Branding
- App name is **Oneova**. Color is `AppColors.brandBlue` (#007AFF). Never reintroduce Mpepe, Maroon, or Red.
- All data must come from the backend (no mocks). Likes/comments update in real time.

## Approved changes (by the user)
- 2026-11-14: Reels are full width and full height (the framed card design is off). On Reels the bottom
  nav hides while a reel plays and slides back when the viewer taps to pause or the feed is empty
  (`reelsNavPeekProvider`). Its design and placement are unchanged. The side rail stays in the lower
  half. Comments roll in one at a time, and hearts rise only from the like button.
- 2026-11-14 (later, replaces the full-bleed entry above): the user chose the **framed reel design**
  (`docs/design/reel-feed-framed/`): reel inside a 25px rounded frame, header "Trends · ● LIVE · Shop" with
  glass search and bell, stories row, Auto / Loop / Captions chips in the frame, Gift on the rail, and the
  comment row under the frame (🔥 😂 😍 + mic). `_framedDesignEnabled = true` in `lib/feed/main_feed_screen.dart`.
  In the framed design the bottom nav stays on screen. Full-bleed is only for focus mode, one-tap full-screen reel mode, and landscape.
  Don't switch the framed design off without asking the user.
- 2026-11-14: On the user's explicit request, the 4th bottom-nav tab (`OneovaBottomNav`) was changed from `AI Lab` to `Wallet` (`/hub/wallet` -> `OneovaPayHomeScreen`), and `AI Lab` (`/hub/ai`) opens from the glowing AI button in Chats and from Ova Assistant.

## Never
- Never use `lucide_icons` (broken on current Flutter). Use Material `Icons`.
- Never change the bottom nav design or placement.

## Agent protocol (added)
- BEFORE any change: read `AGENTS.md` at repo root, then run `flutter test test/guards/home_lock_test.dart`. Run it again after. Revert if it fails.
- Bottom nav is `OneovaBottomNav` (`lib/shared/widgets/oneova_bottom_nav.dart`), wired in `HubShell`. Do not replace with `SharedBottomNavBar` on the hub.
- Brand: Blue `AppColors.brandBlue` = primary. Pink `AppColors.brandPink` (#FF2D87) = secondary accent (badges, remix, live, dots). Never maroon/red.
- Never restore old versions, run old patch scripts, or bulk sed/regex across `lib/`.
