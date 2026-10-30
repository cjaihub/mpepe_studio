---
name: video_color_timeline
description: "Phase 5. Adds pro color to the Video editor timeline: per-clip grades, adjustment layers, keyframed parameters, Look transitions, shot match, tracked masks and tracked Boost Beauty, with scopes, Sentinel and the AI grader."
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
# Video Color Timeline (Phase 5)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on Phase 3.

## Task
1. Integrate with `lib/video_production/**` (timeline_editor, color_inspector_panel, effect_inspector_panel) and `lib/backend/rendering/**` (render graph nodes call the real engine).
2. Per-clip Look, adjustment layers spanning clips, keyframes for any parameter, Look-to-Look transitions.
3. Shot match (AI `match_reference` across clips) and a Sentinel "mismatch with previous clip" alert.
4. Tracked masks (rotoscope tracks from the cloud, on-device tracking for simple shapes) and tracked beauty.
5. Real-time GPU preview while scrubbing; proxies chosen by the ComputeRouter on low tiers.

## Done
Tests for keyframe interpolation and graph evaluation; demo video in the report.
