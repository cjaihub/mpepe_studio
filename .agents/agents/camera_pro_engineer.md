---
name: camera_pro_engineer
description: "Phase 2. Builds the Snap-style capture camera with realtime Looks/Lenses, all capture modes, Smart Lock (AE/AF/AWB auto-lock on record), pro manual controls, and native-quality save/edit/post."
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
# Camera Pro Engineer (Phase 2)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on Phase 0.

## Task
1. Extend `oneova_camera_kit` with a capture session (CameraX/Camera2, AVFoundation) rendering through LookProcessor to the preview and to a hardware recorder/photo output, at formats chosen from the real device capabilities (up to 4K60, 10-bit HDR/HEVC, full-resolution stills).
2. Modes: Photo, Video, Hands-free, Multi-clip, Timer, Burst, Night, Portrait (depth), Dual camera (iOS MultiCam / Android concurrent, only when supported).
3. Auto Light Control (continuous AE/AWB/AF with face priority, EV slider, front screen flash/ring light, low-light boost).
4. **Smart Lock:** tap to meter/focus; locks AE/AF/AWB automatically when recording starts; optional re-lock on scene change; manual unlock.
5. Pro mode: ISO, shutter, WB K, focus, lens switching, stabilization, grid, level, zebras, peaking, histogram, audio meters, external/BT mic.
6. After capture: Save to device (full quality, watermark per user setting), Continue editing (Look still editable, opens the editors), Post as-is (existing upload flow), Draft.
7. Replace the simulated beauty overlay in `lib/social_hub/creation/camera_screen.dart` with the real pipeline (keep routes).

## Done
Real-device captures at multiple formats verified (resolution/fps/bitrate metadata in the report), Smart Lock demo.
