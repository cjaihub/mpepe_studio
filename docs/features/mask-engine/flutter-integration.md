# Mask Engine: Flutter Integration Contract

## Architecture Overview
The MPEPE STUDIO Mask Engine integrates with the Flutter UI using Riverpod for state management. No raw backend calls are allowed inside Flutter Widgets.

Flutter UI (Riverpod ConsumerWidgets)
    ↓
`MaskEditorProvider` (Riverpod StateNotifier)
    ↓
`MaskEngineRepository` (Gatekeeper)
    ↓
Backend Engine (`CvInferenceService`, `IntersectionOrchestrator`, etc.)

## Endpoint Contract (Internal APIs)

### 1. Semantic Selection
- **Method:** `MaskEngineRepository.addSemanticMask(mediaId, semanticTarget)`
- **Request:** `mediaId: String`, `semanticTarget: String` (e.g. 'person', 'skin')
- **Response:** `Future<void>`
- **Realtime Behavior:** Synchronously updates `MaskLayerManager` and adds an event to the `MaskVersionControlSystem`.

### 2. AI Editing (NLP)
- **Method:** `MaskEngineRepository.executeNaturalLanguageCommand(mediaId, command)`
- **Request:** `mediaId: String`, `command: String`
- **Response:** `Future<void>`
- **Authentication/Authorization:** Verified internally against user session in higher layers; repository assumes pre-authorized context.
- **Errors:** Returns generic `Exception` mapped to `MaskEngineException` for the UI.

### 3. Mask Undo/Redo Versioning
- **Method:** `MaskEngineRepository.restoreVersion(versionNumber)`
- **Request:** `versionNumber: int`
- **Response:** `void` (Synchronous state rebuild)

### 4. GPU Telemetry
- **Method:** `MaskEngineRepository.gpuHealth`
- **Request:** Getter
- **Response:** `CvTelemetry`

## Cancellation and Retry
- Processing nodes currently run synchronously or immediately on the backend logic thread. Long-running AI requests via OpenRouter handle timeout and throw `TimeoutException`. UI should catch and show an actionable error state.

## File Handling
- Mask graphs do not store raw files. They store mathematical trees applied via the media-kit or custom shaders dynamically at runtime.
