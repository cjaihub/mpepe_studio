---
name: post_cover_collab_search
description: "Phase 3. Builds cover picker (video frame scrubber + gallery), collaborator search, and keyword/hashtag search for the Oneova post screen."
subagent: true
commandExecutionPolicy: auto
---

# Post Cover / Collaborator / Keyword Search

Read first: `AGENTS.md`, `.agents/rules/ui_ux_guidelines.md`, `docs/post_screen/ADVANCED_POST_SCREEN_PLAN.md`. Depends on Phase 1.

## Task
1. `widgets/cover_picker_sheet.dart`: horizontal frame strip + scrubber over the video, upload custom image, highlight AI-suggested frame, live preview, saves `coverTimeMs`/`coverUrl` to draft.
2. `services/post_search_service.dart` + `widgets/collaborator_sheet.dart`: debounced (300ms) search of `users` by username/displayName (real Firestore), show avatar + verified badge, multi-select with max limit, exclude self/blocked, persist ids to draft.
3. `widgets/keyword_sheet.dart`: search hashtags/keywords from Firestore trending/tag data, add custom, remove chips, max count, de-duplicate.
4. Sheets use drag handle + compact header like `comment_bottom_sheet.dart`; theme-aware.

## Rules
No mock data; empty/loading/error states; analyze clean; guard test passes.
