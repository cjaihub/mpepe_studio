# AGENTS.md — READ BEFORE ANY CHANGE (all AI agents, all models)

This app is **Oneova**. Re-introducing old versions burns tokens and the user's patience. Follow this file first.

## 0. Pre-flight checklist (mandatory)
1. Read `.agents/rules/oneova_home_launch_screen.md` and `.agents/rules/ui_ux_guidelines.md`.
2. Run `flutter test test/guards/home_lock_test.dart`. If it fails after your change, REVERT your change.
3. Never "restore", "revert", `git checkout`, or overwrite from older copies/backups/patch scripts (`patch*.sh`, `*.py`, `*_patch`). Edit forward only.
4. Never bulk `sed`/regex across `lib/` (it previously corrupted code). Make targeted edits.

## 1. LOCKED (do not change without explicit user request)
- Home = `ShortVideoFeedScreen` (`lib/feed/main_feed_screen.dart`) at `/hub/home`. Splash `/splash` -> home.
- Bottom nav = `OneovaBottomNav` (`lib/shared/widgets/oneova_bottom_nav.dart`): Reels | Chat | STUDIO(+) | AI Lab | Me. Used by `HubShell` in `lib/shared/router.dart`.
- Top row: Search · Following / For You / Biz · Bell. Stories row below it.
- Routes that must exist: `/splash`, `/hub/home`, `/hub/messages`, `/hub/ai`, `/hub/discover`, `/biz_feed`, `/notifications`, `/profile/me`, `/profile/:uid`.

## 2. Brand
- Name: **Oneova** (never Mpepe/Oneover). 
- **Primary: `AppColors.brandBlue` #0C4FA8.** **Secondary accent: `AppColors.brandPink` #FF2D87** (badges, remix, live, highlights, notification dots, secondary CTAs). Blue stays dominant; pink is an accent.
- Never use Maroon/Red as branding. Always use `AppColors`, never hard-coded colors.
- Icons: Material `Icons` only. `lucide_icons` is banned (breaks build).

## 3. Data
- No mock/dummy data, no seeded fake content. Everything from Firestore (real-time streams). Likes/comments/follows enforce one-per-user.

## 4. Navigation
- `context.push` for hierarchical navigation, every screen has a back path.

## 5. Verification before finishing
- `flutter analyze` on touched files shows no errors; app builds; guard test passes.
