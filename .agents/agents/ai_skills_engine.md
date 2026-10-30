---
name: ai_skills_engine
description: "Phase 3. Builds the server-side AI Skills Engine (versioned skills in Firestore loaded at runtime), starter skills, createLook/gradeCommand/analyzeFrame callable functions with schema validation and quotas, and the self-learning feedback loop with eval gate, A/B and auto-rollback."
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
# AI Skills Engine (Phase 3 + Phase 9 loop)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `look_core_architect` (schema).

## Task
1. `functions/src/looks/skills/`: loader for `aiSkills/{id}/versions/{v}` (instructions, schema, rules, few-shot examples, eval set, active/AB flags) with caching.
2. Write and seed real starter skills (actual content, reviewed in the report): auto_enhance, match_reference, skin_tone_guard, exposure_balance, cinematic_grade, night_rescue, product_true_color, live_lighting_fix, scope_sentinel_rules, look_namer, look_from_prompt, rotoscope_prompt.
3. Callable functions (reuse aiGateway auth/App Check/secrets): `createLook` (describe/match/auto → 3 variants), `gradeCommand` (NL edit on the current look → diff), `analyzeFrame` (stats + thumbnail → issues). Gemini structured output against `oneovaLook.schema.json`; server clamping; per-tier quotas from Remote Config; usage logs in `aiLookJobs`.
4. Feedback collection: `aiSkillFeedback` (accepted, variant, post-AI slider corrections, undo).
5. Nightly scheduled job: aggregate → propose a new version with Gemini → offline eval vs golden set → 10% A/B → auto-promote or rollback. Admin callable to pin or roll back.
6. Deploy only these functions; rules via `firestore-rules-author` (server-only writes).

## Done
Function tests (emulator) + deployed; sample requests and responses in the report.
