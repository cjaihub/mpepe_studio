---
name: post_ai_assistant
description: "Phase 2. Implements AI video analysis for the Oneova post screen: auto title, caption, hashtags, keywords and niche detection, plus the suggestion UI."
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

# Post AI Assistant

Read first: `AGENTS.md`, `.agents/rules/ui_ux_guidelines.md`, `docs/post_screen/ADVANCED_POST_SCREEN_PLAN.md`. Depends on Phase 1 (`PostDraft`, provider).

## Task
1. `lib/create/post/services/ai_post_assistant.dart`: sample 6–8 evenly spaced frames from the video (reuse existing frame/thumbnail utilities), send to Gemini via Firebase AI Logic (see skill `firebase-ai-logic-basics`; reuse the existing `AIContentOptimizationResult` / optimizer service if present) with structured JSON output: `title`, `caption`, `hashtags[]`, `keywords[]`, `niche`, `bestCoverFrameIndex`, `suggestedAgeRating`.
2. Niche step: use detected niche + creator profile to query real trending tags/search data from Firestore for niche-relevant hashtags (no fabricated data).
3. `widgets/ai_suggestion_card.dart`: "Analyze video" button, shimmer, chips to apply title/caption/tags individually, Regenerate, error + retry. Never blocks posting. Mark `aiGenerated` only when user applies AI text.
4. Wire into `post_screen.dart` and autosave.

## Rules
No mock data; timeouts + graceful failure; Oneova brand colors; analyze clean; guard test passes.
