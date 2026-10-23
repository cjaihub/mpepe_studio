# PHASE F: EFFECTS INVENTORY

## Existing Functionality Audit

### `pro_project_models.dart`
- **KEEP**: `ProProject`, `Sequence`, `Track`, `TransformState`, `ColorState` (and related color classes), `AudioState`.
- **REFACTOR**: `Clip` (Needs `effects` array integration with `EffectState` instead of basic `Effect`, add `TransformState` keyframing).
- **UPGRADE**: `Effect` (Currently a minimal struct with `id`, `type`, `parameters`. Needs to become `EffectState` with full typed parameters, keyframes, maskId, trackingId, blendMode, etc.). Add `AdjustmentTrack`/`AdjustmentLayer` capabilities.

### `pro_editor_screen.dart` & `timeline_editor.dart` & `export_center_screen.dart`
- **UPGRADE**: Need to support effect stack rendering and timeline effect indicators.
- **CONNECT**: Connect new Effect Graph to the Viewer and Export Center so preview and export share the same exact pipeline.

### `universal_mask_models.dart` & `temporal_video_tracker.dart` & `keyframe_models.dart`
- **KEEP**: These existing architectures must be used directly by the effect system without creating parallel structures.
- **CONNECT**: `EffectState` must hold `maskId` pointing to a `UniversalMask`, `trackingId` pointing to `TrackingData`, and use `Keyframe` directly.

### `color_inspector_panel.dart`
- **KEEP/UPGRADE**: Ensure color processing order is maintained: Input -> Primary -> Secondary -> LUT -> Effects -> Composite -> Output.

### `PhotoStudio` (`photo_studio_models.dart`)
- **CONNECT / REFACTOR**: PhotoStudio uses `PhotoAdjustment`. We need to ensure the new Effect Engine (or `EffectState` models) are shared across video and photo where applicable. Photo uses `AdjustmentType`.

## Classification
- **KEEP**: `UniversalMask`, `TrackingData`, `Keyframe`, `ColorState`, `TransformState`
- **UPGRADE**: `Effect` -> `EffectState`, Timeline visualization, Export rendering
- **CONNECT**: `EffectState` to Masks and Keyframes, Viewer/Export to EffectGraph, PhotoStudio to EffectGraph
- **REFACTOR**: Project rendering graph to include the effect stack in the correct order.
- **DUPLICATE**: NONE. No new mask engines, keyframe systems, color systems, or tracking models should be built.
