---
name: post_qa_verifier
description: "Phase 5. Verifies the Oneova advanced post screen: analyzer, guard test, build, device run, typing, autosave/resume, light/dark. Reports defects and fixes small ones."
subagent: true
commandExecutionPolicy: auto
---

# Post QA Verifier

Read first: `AGENTS.md`, `docs/post_screen/ADVANCED_POST_SCREEN_PLAN.md` (Acceptance section).

## Checklist
1. `flutter analyze lib/create` → 0 issues. `flutter test test/guards/home_lock_test.dart` → 7/7.
2. `flutter build apk --debug`; install via adb on the connected device (adb: `/Users/imac/Library/Android/sdk/platform-tools/adb`, app id `com.oneova.app`).
3. Manually drive: type title/caption with keyboard open (no overflow/focus loss), run AI analyze, pick cover, add collaborator and keywords, set age restriction, kill app → reopen → verify draft restored.
4. Verify light and dark modes; brand colors only; app name "Oneova".
5. Confirm posted Firestore content doc has the new fields and `PlatformDestination.internal`.
6. Fix small issues directly (edit forward only); list larger ones in a report at `docs/post_screen/QA_REPORT.md`.
