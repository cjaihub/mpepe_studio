---
name: live_settings_ui
description: "Phase 1. Builds compact advanced live settings (TikTok-plus), auto-save, unlimited Live Profiles and Scenes, the stream health HUD, the real Go Live 'Look, Beauty & Background' step, and AI Live Director chips."
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
# Live Settings UI (Phase 1)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `live_looks_engineer`.

## Task
1. Compact grouped settings sheet (Video, Look & Boost Beauty, Background, Audio, Network, Health HUD), dense per the UI guidelines; Advisor-disabled options show the reason.
2. Auto-save every change (debounced) to `users/{uid}/liveSettings/current`; restore on the next live.
3. **Unlimited** Live Profiles (full snapshot): create/apply/rename/duplicate/delete (confirmation required).
4. **Unlimited** Scenes (Look + beauty + background + overlay + audio preset): reorderable dock, swipe/tap switch, transition style, hotkeys (BT remote/volume keys).
5. Replace the non-functional beauty step in `oneova_live_creation_wizard.dart` / `go_live_sheets.dart` with a real live-preview step.
6. Host-only health HUD (bitrate, fps, drops, temperature, battery) from real stats.
7. AI Live Director chips (backlit, underexposed…) driven by `scopes_sentinel` when available. Until then, build the chip UI and connect it to the Sentinel stream interface only, without fake alerts.
8. Audio: noise suppression, echo cancellation, voice enhance and mic select through the real WebRTC/LiveKit options.

## Done
Widget tests, light/dark screenshots, profiles/scenes persisted and restored across app restarts.
