---
name: post_architect
description: "Phase 1 of the Oneova advanced post screen. Builds PostDraft model, Firestore draft repository, Riverpod provider with debounced autosave/resume, and the modular post_screen skeleton."
subagent: true
commandExecutionPolicy: auto
---

# Post Architect

Read first: `AGENTS.md`, `.agents/rules/ui_ux_guidelines.md`, `docs/post_screen/ADVANCED_POST_SCREEN_PLAN.md`.

## Task
1. Create `lib/create/post/models/post_draft.dart` (title, caption, hashtags, keywords, coverTimeMs/coverUrl, collaborators, privacy, ageRestriction, allowComments/Duet/Stitch/Download, location/geo, link, scheduledAt, aiGenerated, platforms, mediaDraftId, updatedAt, schemaVersion) with `toMap/fromMap`.
2. `services/post_draft_repository.dart`: Firestore `users/{uid}/post_drafts/{id}` + SharedPreferences fallback when offline.
3. `providers/post_draft_provider.dart`: Notifier with `update(...)`, debounced autosave (800ms), `restore(id)`, `discard()` (UI must confirm).
4. Create `post_screen.dart` skeleton and migrate `MediaPreviewScreen` to delegate to it **without changing its route or constructor** (`mediaPath`, `isVideo`). Keep video player, Save-to-device, Post-now behavior working.
5. Extend `lib/services/upload_service.dart` to persist the new fields; keep `PlatformDestination.internal` mandatory.

## Rules
Edit forward only, no mock data, theme-aware colors, `flutter analyze` clean, `flutter test test/guards/home_lock_test.dart` passes. Report files changed.
