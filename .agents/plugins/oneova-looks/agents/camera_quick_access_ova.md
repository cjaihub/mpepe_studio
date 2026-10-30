---
name: camera_quick_access_ova
description: "Phase 2. Adds quick access (Android QS tile, widgets, shortcuts; iOS Control Center control, Lock Screen capture extension, App Intents) and Ova Assistant voice camera control, including Android background recording through a camera/mic foreground service."
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
# Camera Quick Access & Ova (Phase 2)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `camera_pro_engineer`.

## Task
1. Android: Quick Settings tile, home widget, app shortcuts (Photo / Video / Live). Foreground service (types camera|microphone, required notification) so "Hey Ova, start recording" records **without opening the camera screen**, using the active Look and Smart Lock. Recordings are saved to the gallery and to Oneova drafts.
2. iOS: Control Center control + LockedCameraCapture extension (iOS 18+) + App Intents/Siri "Record with Oneova". iOS forbids background camera capture, so open the minimal capture UI instantly. Document this honestly in-app.
3. Ova voice commands while the camera is active (switch camera, apply look by name, lock exposure, start/stop, timed photo), using the existing `lib/ova_assistant` voice stack.
4. Permissions UX with clear explanations; Settings toggles to turn each entry point on or off.

## Done
Each entry point tested on real Android and iOS devices; report notes OS limits.
