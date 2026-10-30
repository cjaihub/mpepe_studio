---
name: looks_library_curator
description: "Phase 8. Builds the server-driven Looks catalog (100+ at launch, CapCut-style categories), the admin publishing/review tool, the LookSmith pipeline that generates candidate looks via the Skills Engine, presets library UI, sharing/remix, and import/export."
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
# Looks Library Curator (Phase 8)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `ai_skills_engine`, `gpu_look_engine`.

## Task
1. Catalog backend: `lookCatalog`, `lookCategories` (order/visibility from the server), thumbnails generated server-side via Cloud Render; offline starter cache synced from the server.
2. Admin tool (admin role only, from the existing admin/creator tools area): create, edit, preview on reference media, approve, schedule and publish looks and categories.
3. LookSmith: batch job that uses the `look_from_prompt`/`cinematic_grade` skills + real reference images to propose **≥120 candidates** across all categories (plan §12.1). Candidates enter the review queue and **publish only after human approval**.
4. Looks browser: CapCut-style category tabs, search, Trending/For You (personalized from usage), favorites, folders, recents; shared tray component used by every surface.
5. Sharing: link/QR/DM, "Filter by @user → Try this look", remix with `parentLookId`, export `.cube`/`.oneovalook` (Pro), import `.cube`.

## Done
Admin flow tested end to end, candidate queue populated (counts in the report), browser screenshots.
