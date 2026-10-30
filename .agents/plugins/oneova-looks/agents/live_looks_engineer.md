---
name: live_looks_engineer
description: "Phase 1 (top priority). Applies realtime Looks, Boost Beauty and backgrounds inside the LiveKit/WebRTC pipeline so viewers see them, with native-quality simulcast/adaptive streaming up to 1080p/4K and thermal-governed quality."
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
# Live Looks Engineer (Phase 1)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on all Phase 0 agents.

## Task
1. Wire `oneova_camera_kit` LookProcessor into the live publisher (`lib/social_hub/live/**`, `lib/backend/live_studio/**`, LiveKit). Viewers receive the processed stream. **Do not change any viewer layout.**
2. MediaPipe (native) selfie segmentation + 478-point face landmarker at an adaptive rate (governor-controlled) with temporal smoothing → masks feed Boost Beauty (smooth, tone, eyes, teeth, reshape with Natural guard limits from Remote Config) and background (depth-aware blur, image/video replace, green screen).
3. Publish settings come from the camera's real format and Device Advisor ceilings: LiveKit simulcast layers, dynacast, adaptive bitrate, hardware encoder. 720p/1080p/4K only where supported.
4. Look switching: 300ms cross-fade, no track republish.
5. Make `LiveBeautyConfig` actually apply to the stream (through the adapter) so existing saved settings keep working.
6. Integration test: publish to a LiveKit test room, and confirm with a subscriber that the frames are graded (pixel check).

## Done
Real-device demo video in the report (host + viewer), fps/thermal metrics over a 20-minute live.
