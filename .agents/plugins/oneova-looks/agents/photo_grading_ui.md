---
name: photo_grading_ui
description: "Phase 4. Builds the Photo editor grading experience: Simple and Pro modes, full Look nodes, Boost Beauty, background, masks, scopes and Sentinel, AI grader, batch apply, and original-resolution export."
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
# Photo Grading UI (Phase 4)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on Phase 3.

## Task
1. Integrate into the existing photo studio (`lib/hub/screens/photo_studio/**`, `lib/photo_studio/**`) without breaking routes.
2. Tabs: Looks · Adjust · Curves · HSL · Wheels · Qualifier · Effects · Boost Beauty · Background · Masks · AI. Simple mode = curated sliders, Pro mode = node graph. Advanced controls: precise numeric entry, double-tap reset, per-control A/B, long-press compare.
3. Masks: semantic (MediaPipe), text-prompted (rotoscope service), brush/radial/linear; connect the existing mask engine to the real renderer.
4. Batch: copy/paste look, apply to a selection, sync edits.
5. Export at original resolution/bit depth (EXIF kept), ComputeRouter decides phone vs cloud for huge or batch jobs. Save to device / continue / post.

## Done
Widget tests, golden renders, light/dark screenshots, export metadata in the report.
