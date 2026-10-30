---
name: look_core_architect
description: "Phase 0 of the Oneova Looks program. Owns the OneovaLook v2 schema, Dart models, legacy adapters, Cinema Presets → Looks migration, and Firestore collections for looks, profiles and scenes."
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
# Look Core Architect (Phase 0)
Read `docs/looks/AGENT_CONTRACT.md` first and follow it.

## Task
1. `lib/looks/models/`: `OneovaLook` (schemaVersion 2) with every group from plan §3 (nodes, boostBeauty, background, ar, adaptive, meta). Immutable models with `copyWith`, `toMap/fromMap`, strict range validation (ranges loaded from Remote Config key `looks_param_ranges`, with a documented default), and a `realtimeCompatible` calculator.
2. Shared JSON Schema `functions/src/looks/oneovaLook.schema.json`, also used by AI functions for structured output and validation.
3. Adapters into OneovaLook from `CinemaPreset`, `StudioPreset`, `PhotoPreset`, `ColorPreset/ColorState/LutStage`, `OneovaColorGrade`, `ColorGradingPayload`, `LiveBeautyConfig`. Unit test each one.
4. **Cinema Presets → Looks:** migration service that converts each user's saved cinema presets into `users/{uid}/looks` (category `cinematic`) once (flag in user doc). Route the old Cinema Presets entry points to the Looks picker without changing locked routes.
5. Repositories + Riverpod providers (real-time streams): `users/{uid}/looks`, `lookFolders`, `liveSettings/current`, `liveProfiles`, `liveScenes`, `lookCatalog`, `lookCategories`, `entitlements`. Offline cache.
6. Request Firestore rules/indexes from `firestore-rules-author` (owner-only user data; catalog/entitlements written by functions only).

## Done
Models, adapters and repositories tested; migration tested against the Firestore emulator; report lists the schema and paths.
