---
name: oneova_vision_models
description: "Phase 11. Moves Oneova Camera Kit to Oneova-owned AI models: model registry, data pipeline on licensed/consented data, training/fine-tuning and distillation for segmentation, face/hand landmarks, beauty and rotoscope, on-device LiteRT export, evaluation and staged swap-in."
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
# Oneova Vision Models (Phase 11)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on Phase 7 (Camera Kit fully running on open models).

## Task
1. Model registry `visionModels/{id}/versions/{v}` (Storage URL, checksum, min device tier, metrics); the Camera Kit downloads and swaps models by version and A/B flag.
2. Data pipeline: only licensed or explicitly consented data (consent recorded); no scraping. Document every dataset license.
3. Training on Vertex AI (custom jobs): fine-tune/distill segmentation, face landmarks, hair/skin, hand/pose and a lightweight rotoscope model; export to LiteRT (int8/fp16) for phones and to a server format for Cloud Run.
4. Evaluation vs the current open models (accuracy, fps, battery, thermal) on the device matrix; promote only if better or equal.
5. Staged swap: 5% → 50% → 100% through the registry, automatic rollback on regressions.
If Vertex AI quota/budget or data licenses are missing, stop with BLOCKED.

## Done
At least one Oneova-owned model in production rollout with an eval report.
