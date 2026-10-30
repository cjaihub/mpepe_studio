---
name: post_settings_ui
description: "Phase 4. Builds advanced settings (age restriction, privacy, interactions, schedule, labels, geo), the high-quality caption/title editor with mention/hashtag autocomplete, draft status UI and final screen assembly."
tools:
  - view_file
  - list_dir
  - grep_search
  - find_by_name
  - search_web
  - read_url_content
  - send_message
  - schedule
  - invoke_subagent
  - manage_subagents
  - write_to_file
  - replace_file_content
  - multi_replace_file_content
  - run_command
  - ask_question
mainAgent: true
subagent: true
commandExecutionPolicy: auto
---

# Post Settings & Final Assembly

Read first: `AGENTS.md`, `.agents/rules/ui_ux_guidelines.md`, `docs/post_screen/ADVANCED_POST_SCREEN_PLAN.md`. Depends on Phase 1 (can run parallel to Phase 3).

## Task
1. `widgets/caption_editor.dart`: title + caption fields, correct `TextInputAction`, `isDense`, keyboard-inset safe scrolling, no focus loss on rebuild (stable keys/controllers owned by state), `@mention` and `#tag` inline autocomplete, character counters.
2. `widgets/advanced_settings_sheet.dart`: age restriction (All / 13+ / 16+ / 18+), privacy, comments / duet / stitch / download toggles, location + geo radius tier, link, schedule (date-time picker), AI-generated label, branded-content label, high-quality upload, platform syndication (Oneova locked on).
3. `widgets/draft_status_pill.dart` ("Saving…/Saved") and `lib/create/drafts_screen.dart` (list, resume, delete with confirm dialog); add entry point from Studio/create flow with `context.push`.
4. Assemble final `post_screen.dart` with compact sections, back-button discard confirmation ("Save draft / Discard / Keep editing").

## Rules
Brand colors only, dual-mode theme, 38–42px buttons, analyze clean, guard test passes.
