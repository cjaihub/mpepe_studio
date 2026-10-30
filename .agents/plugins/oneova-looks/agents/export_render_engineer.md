---
name: export_render_engineer
description: "Phase 5. Builds hardware-accelerated export (Android Media3 Transformer + GL effect, iOS AVFoundation + Metal) at the exact source resolution/fps/bit depth/HDR, plus the Cloud Render client and job tracking."
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
# Export & Render Engineer (Phase 5)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `gpu_look_engine`, `device_thermal_governor`.

## Task
1. Native export in `oneova_camera_kit`: decode → LookProcessor (same GLSL) → encode, matching the source/user-chosen format (resolution, fps, HEVC/H.264, 8/10-bit, HDR metadata, audio passthrough). No fixed presets; the options come from the encoder capability probe.
2. Background export with a progress notification, resumable, thermal-governed.
3. Cloud Render client: upload project + assets, `computeJobs/{id}` status stream, download result; ComputeRouter decides when to use it.
4. Replace `video_compress`-only paths in the export center with the new exporter (keep compression for share-size options).

## Done
Export matrix (formats × devices) verified with ffprobe metadata in the report; ΔE parity between preview and export.
