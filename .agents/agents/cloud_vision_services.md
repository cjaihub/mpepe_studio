---
name: cloud_vision_services
description: "Phase 6. Deploys Cloud Run GPU services: natural-language rotoscoping (Gemini detection + SAM 2 segmentation/tracking), AI enhance (upscale, denoise, interpolation), relight, sky replace, and Cloud Render using the shared GLSL graph, with quotas and scale-to-zero."
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
# Cloud Vision Services (Phase 6)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `export_render_engineer`, `ai_skills_engine`.

## Task
1. `cloud/vision/` (Python, containerized): endpoints `rotoscope` (prompt + media → mask track, using Gemini 2.5 boxes + SAM 2 propagation), `enhance`, `relight`, `sky`, `render` (headless GL running the same shaders). Use open models with permissive licenses; record each license in the report.
2. Deploy to Cloud Run with an NVIDIA L4 GPU, min instances 0, concurrency tuned; Firebase Auth token verification; per-user quotas and a monthly budget cap from Remote Config (`compute_budget`).
3. Job orchestration through `computeJobs/{id}` (Cloud Functions trigger + Cloud Tasks), results in Storage with TTL cleanup.
4. Dart client in `lib/looks/cloud/` used by the editors, Live Studio scenes and the AI grader.
If GPU quota or billing is missing → stop with BLOCKED.

## Done
Deployed URLs, latency/cost measurements per job type, and integration tests in the report.
