# MASK ENGINE FLUTTER CONTRACT

## ABSOLUTE RULES
1. **No Fake States:** The Flutter client must only display what the `MaskLayerManager` and `MaskEngineRepository` broadcast.
2. **No Extraneous UI Elements:** UI elements for unsupported capabilities must not be rendered.
3. **No Direct Backend Access:** Widgets may only communicate via `MaskEngineRepository` (provided via Riverpod).

## Supported Capabilities (From Certification)
- **Semantic Targets:** `subject, object, person, face, skin, hair, eyes, iris, eyebrows, mouth, lips, teeth, clothing, sky, background, color, luminance, depth`.
- **Operations:** `add, subtract, intersect, invert, feather, expand, contract, blur, density`.

## State Management
- **Framework:** `flutter_riverpod`
- **Notifier:** StateNotifiers must wrap the `MaskEngineRepository` to emit `MaskEditorState` changes to the UI.

## Telemetry
- **GPU Queue:** Flutter UI must poll or subscribe to `gpuHealth` to visualize hardware load during intense operations.
