---
name: offline_ai_engineer
description: "Phase 3. Builds the on-device AI layer so grading, Looks creation and Sentinel work offline with the same experience: Gemini Nano (Android AICore / ML Kit GenAI), Apple Foundation Models (iOS 26+), Gemma via LiteRT fallback, locally synced skill packs, and the shared grading tool interface."
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
# Offline AI Engineer (Phase 3)
Read `docs/looks/AGENT_CONTRACT.md` and plan §4.2 / §8.1. Depends on `ai_skills_engine`, `ai_color_grader` (tool interface).

## Task
1. `lib/looks/ai/on_device/`: one `OnDeviceGrader` interface with backends:
   - Android: Gemini Nano through AICore / ML Kit GenAI APIs where available.
   - iOS 26+: Apple Foundation Models framework (Swift bridge).
   - Other devices: a Gemma model downloaded on demand from the `visionModels`/model registry and run with LiteRT LLM inference (Device Advisor decides if the phone can handle it).
2. Skill packs: export the active skill versions from the Skills Engine into a compact signed pack (instructions, schema, rules, examples) served through the CDN; the device syncs them and verifies signatures.
3. Same tool-calling contract as online, so the AI Color Grader is backend-agnostic. Language understanding is done by the model, never by keyword lists.
4. Offline Pro mode: combine the on-device LLM + Camera Kit Vision masks + local scopes to perform reference matching and region edits offline; queue a cloud refinement for when the phone is back online (optional, user setting).
5. ComputeRouter integration: choose on-device vs cloud by network quality, thermal state, battery and spend level.

## Done
Airplane-mode demo of voice/text grading on Android and iOS test devices; latency and memory numbers in the report.
