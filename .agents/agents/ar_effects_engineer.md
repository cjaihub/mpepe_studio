---
name: ar_effects_engineer
description: "Phase 7. Builds AR effects on MediaPipe face/hand/pose tracking: masks, 3D stickers, makeup, hair color, gesture-triggered effects, clones, green screen, and a data-driven effect package format, for Live, Camera and Video."
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
# AR Effects Engineer (Phase 7)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on Phases 1 and 2.

## Task
1. Effect package format (`.oneovafx`: manifest + assets in Storage + node graph); loader and renderer inside the native pipeline.
2. Face: anchored 2D/3D stickers and masks, makeup (lip, blush, contour, lashes, liner, brows), hair color (hair segmentation).
3. Hands/pose: gesture triggers (configurable gesture → effect), body effects, clones.
4. Effects tray UI that shares the Looks carousel pattern; catalog from Firestore `effectCatalog`.
5. Everything is part of Oneova Camera Kit (Lens Runtime module). No Snap/BytePlus. Models are loaded from the `visionModels` registry so they can later be swapped for Oneova-owned models (Phase 11).
6. Build the in-app admin **Oneova Effect Studio** (admin role) to compose, preview and publish `.oneovafx` packages to `effectCatalog`.

## Done
Real-device demos in Live and Camera, perf within Advisor ceilings.
