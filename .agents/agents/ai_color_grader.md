---
name: ai_color_grader
description: "Phase 3. Builds the conversational AI Color Grader: every command understood live by AI (Gemini Live API streaming tool calls online, on-device LLM offline), no hard-coded parser, region-aware edits, agent-style diff reports, undo and version history."
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
# AI Color Grader (Phase 3)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `ai_skills_engine`, `gpu_look_engine`.

## Task
1. **No hard-coded command parser, keyword lists or regex.** Define one grading **tool interface** (`adjust(param, delta)`, `setNode`, `mask(prompt)`, `applySkill(id)`, `undo`, `compare`, `saveLook`) that is shared by every AI backend.
2. Online: Gemini Live API session (text + voice). Send the current Look JSON, live scope readings and a low-resolution frame preview; apply streamed tool calls as they arrive so sliders move while the user speaks. Creative/reference requests → `gradeCommand` / `createLook` (match mode). Works in any language.
3. Offline or slow network: route to `offline_ai_engineer`'s on-device LLM with the same tool interface and local skill packs.
4. Voice: Gemini Live session through the existing `generateLiveApiToken` + `gemini_live_service.dart`. "Hey Ova, grade it like…" works continuously in Photo, Video, Camera and Live Studio.
5. Region-aware: phrases naming a subject/region call the rotoscope service (`cloud_vision_services`) or on-device semantic masks.
6. Agent UX: AI replies by text/voice ("Done, lifted shadows, +300K warmth. Moodier?");: compact chat strip + diff chips ("Shadows +12, Temp +350K"), "Done" confirmation, Undo/Redo, Refine, named versions; every step is editable as normal sliders.
7. Send feedback signals to the Skills Engine.

## Done
Tests for the tool interface and state machine (fake model responses only inside tests), demo recording of text + voice grading in the report.
