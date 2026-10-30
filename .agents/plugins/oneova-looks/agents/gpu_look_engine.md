---
name: gpu_look_engine
description: "Phase 0. Builds the shared GLSL Look graph renderer used by Live, Camera, Photo and Video: Flutter FragmentProgram path plus an Android GLES/iOS Metal native plugin, LUT stack, curve textures, and golden ΔE tests."
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
# GPU Look Engine (Phase 0)
Read `docs/looks/AGENT_CONTRACT.md` first. Depends on `look_core_architect`.

## Task
1. `shaders/look/*.frag`: one source of truth for primary, wheels, color, curves (baked textures), HSL, LUT stack (trilinear, 17–65³, PNG atlas + .cube parser), film/halation/grain, detail, optics, fx and mask blending. Register the shaders in pubspec.
2. `lib/looks/engine/look_compiler.dart`: OneovaLook → uniform buffers + textures. Only enabled nodes get compiled; respects device tier flags.
3. Flutter path: `LookShaderView` widget + `LookImageRenderer` (full-resolution offscreen export, no downscale). Replace the stubbed `PhotoColorEngine.compileRealtimePreviewShader` and `LutNode.execute` with real implementations that call the engine, and implement the real eyedropper/point-color sampling.
4. Native plugin `packages/oneova_camera_kit/` (Kotlin GLES 3, Swift Metal via SPIR-V cross-compiled from the same GLSL): `LookProcessor` that takes a camera/decoder texture and outputs a texture (zero-copy) with `setLook(json)` and a 300ms cross-fade.
5. **Spike + implementation:** hook `LookProcessor` into the flutter_webrtc/LiveKit capture pipeline on Android (`VideoProcessor`) and iOS (capturer delegate / custom capturer). Document the API for `live_looks_engineer`.
6. Golden tests: 20 reference looks rendered through the Dart and native paths; ΔE2000 < 1.0.

## Done
Both paths render identically; frame-time benchmark on a real device in the report; no CPU readback in realtime paths.
