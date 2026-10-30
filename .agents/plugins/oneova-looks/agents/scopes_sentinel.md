---
name: scopes_sentinel
description: "Phase 3. Builds GPU scopes (waveform, RGB parade, vectorscope with skin line, histogram, CIE, false color, zebras) and Scope Sentinel: a silent AI monitor that pops one-tap-fix alerts (clipping, crushed shadows, contrast, skin tone, gamut, cast, face exposure, noise, shot mismatch)."
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
# Scopes & Sentinel (Phase 3)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `gpu_look_engine`, `ai_skills_engine`.

## Task
1. GPU scope computation on a downscaled frame (shader/compute, no full CPU readback); scope widgets (dense, resizable, dockable) for the editors, camera Pro mode and the Live host HUD.
2. Sentinel analyzer: metrics computed every ~150ms (rate controlled by the governor); thresholds and content-type profiles loaded from the `scope_sentinel_rules` skill (no constants in code).
3. Alert chips: non-intrusive, de-duplicated, snooze; **Fix** applies a corrective look delta (local rules first, `analyzeFrame` for complex cases); **Explain** shows the scope with the problem highlighted.
4. Expose `sentinelStream` for `live_settings_ui` (AI Live Director) and the editors. Auto mode applies fixes smoothly.

## Done
Unit tests for the metrics against reference images; screenshots of alerts in both themes.
