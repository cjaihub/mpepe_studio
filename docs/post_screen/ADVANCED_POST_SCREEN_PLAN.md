# Oneova Advanced Post Screen — Implementation Plan

Target: rebuild `lib/create/media_preview_screen.dart` (1163 lines, monolithic) into a modular, advanced posting flow.
Sources: user comment on *High-Density Post Configuration Screen* in `reel_export_publishing_workflow.md`.

## Goals (from user request)
1. Typing (caption/title/hashtags/mentions) works flawlessly (IME, keyboard insets, no lost focus/jank).
2. **AI auto title + caption**: scan the video, understand content, suggest title/caption/hashtags/keywords **for the creator's niche**.
3. Cover picker: frame scrubber from video, upload custom image, AI-suggested best frames.
4. Collaborator search (real Firestore users), invite/accept status.
5. Keyword/hashtag search with suggestions + trending.
6. Advanced settings: age restriction, privacy, comments/duet/stitch/download toggles, location + geo radius, link, schedule, AI-content label, branded-content label, platform syndication.
7. **Auto-save drafts** (debounced), resume later, draft list entry point.

## Hard constraints (AGENTS.md / ui_ux_guidelines)
- Brand: `AppColors.brandBlue` primary, `AppColors.brandPink` accent. Theme via `context.bg/surface/border/textPrimary…` (light + dark). No hard-coded colors, Material `Icons` only.
- No mock data — Firestore/real services only. One-per-user rules preserved.
- Compact density (buttons 38–42px, inputs `isDense`, Inter font scale). Confirm dialogs on destructive actions (discard draft). `context.push`, always a back path.
- Edit forward only; no bulk sed. Run `flutter analyze` on touched files and `flutter test test/guards/home_lock_test.dart` (must pass).
- Oneova Reels (`PlatformDestination.internal`) stays mandatory/locked.

## Architecture
```
lib/create/post/
  post_screen.dart                  # replaces MediaPreviewScreen body (keep route + constructor)
  models/post_draft.dart            # PostDraft (all fields, toMap/fromMap, schemaVersion)
  providers/post_draft_provider.dart# Riverpod Notifier: state, debounced autosave (800ms), restore
  services/post_draft_repository.dart # Firestore users/{uid}/post_drafts + local cache fallback
  services/ai_post_assistant.dart   # frame sampling -> Gemini (Firebase AI Logic) -> title/caption/tags/niche
  services/post_search_service.dart # user search, hashtag/keyword search
  widgets/caption_editor.dart       # title + caption, @mention/#tag autocomplete, char counters
  widgets/ai_suggestion_card.dart   # "Analyze video" + chips, apply/regenerate
  widgets/cover_picker_sheet.dart   # frame strip + gallery upload
  widgets/collaborator_sheet.dart   # search + select + roles
  widgets/keyword_sheet.dart
  widgets/advanced_settings_sheet.dart # age, privacy, interactions, schedule, labels, geo
  widgets/draft_status_pill.dart    # "Saving… / Saved just now"
lib/create/drafts_screen.dart       # list + resume + delete(confirm)
```
Data: reuse `oneova_draft_engine.dart` for media drafts; `PostDraft` stores post-metadata and links to the media draft id. `UploadService` extended with new fields (title, coverUrl/coverTimeMs, ageRestriction, keywords, collaborators, scheduledAt, aiGenerated, allowDownload, allowStitch).

## Phases & subagents
| Phase | Subagent | Deliverable |
|---|---|---|
| 1 | `post_architect` | PostDraft model, repository, provider, autosave, resume; refactor skeleton keeping route working |
| 2 | `post_ai_assistant` | AI video scan → title/caption/hashtags/niche; suggestion UI |
| 3 | `post_cover_collab_search` | Cover picker, collaborator search, keyword search |
| 4 | `post_settings_ui` | Advanced settings sheet, age restriction, schedule, caption editor typing quality, final screen assembly |
| 5 | `post_qa_verifier` | Analyze, guard test, device run, light/dark check, report |

Order is sequential 1→2→(3 ∥ 4)→5. Each agent must end by running analyze on its files.

## Acceptance
- Typing smooth with keyboard open on 1080x2400; no overflow.
- AI suggestions appear within ~10s of tapping Analyze and are editable; failure shows retry, never blocks posting.
- Kill app mid-edit → reopen → draft restored with caption, cover, settings.
- Age restriction (All / 13+ / 16+ / 18+) persisted to Firestore content doc and respected in feed queries note logged for backend follow-up.
- 0 analyzer issues, guard test 7/7.
