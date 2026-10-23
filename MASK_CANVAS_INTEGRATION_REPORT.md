# Mask Canvas Integration Report

## 1. Overview
The Mask Canvas Integration links the client-side user interactions (taps, strokes, panning) to the deterministic Mask Engine backend. It fulfills the core requirement of maintaining mathematical truth (backend) while providing immediate, smooth feedback (frontend).

## 2. Implemented Features

### 2.1 Mask Display Modes
The UI supports multiple display modes configured via a dropdown in the `DeterministicRenderView`.
- **NORMAL**: Original image with raw adjustments.
- **OVERLAY**: Mask overlay with the approved solid brand color and border.
- **MASK ONLY**: High-contrast rendering (white for selected, black for unselected).
- **EDGE**: Highlights only the boundaries of the mask.
- **CHECKERBOARD**: Shows transparency matting (mocked).
The `MaskLayerManager` stores the mode, and `_MaskOverlayPainter` respects it.

### 2.2 Mask Stack Integration
- The `MaskStackPanel` sits on top of the canvas, strictly reflecting the state of the backend's `MaskLayerManager`.
- The stack avoids duplicate or "fake" client-side layers.
- Supports toggling visibility, lock state, and layer selection.

### 2.3 Coordinate Transformation Utility
- Created `MaskCoordinateTransformer` as the canonical utility.
- It normalizes screen coordinates (from `InteractiveViewer` and `GestureDetector` bounding boxes) into `[0.0, 1.0]` image-relative space using `BoxFit.contain` logic.
- Avoids writing ad-hoc geometry math in every gesture handler.

### 2.4 Tap Select & Brush Stroke Gestures
- The `DeterministicRenderView` intercepts `onTapUp`, `onPanStart`, `onPanUpdate`, and `onPanEnd`.
- **Tap Select**: Translates tap to normalized `(x, y)` and calls `addPointMask`.
- **Brush Stroke**: Accumulates points in a local UI buffer (`_currentStroke`) to draw a 120fps local paint trail via `_LocalStrokePainter`. On `onPanEnd`, it flushes the stroke to the `MaskEngineRepository` via `addStrokeMask`.

## 3. Mathematical Contract Adherence
- No hardcoded or fake masks are placed into the true graph.
- The UI paints what the backend returns (`normalized_path`).
- The UI only uses local buffers during the active stroke gesture to maintain the 120fps requirement, explicitly clearing the local buffer and waiting for the definitive engine result upon gesture completion.

## 4. Next Steps
- Implement specific `MaskOperation.subtract` and `MaskOperation.intersect` parameterizations from the UI tools panel.
- Wire the specific sliders (Feather, Expand) to the `MaskEngineRepository` refinement endpoints.
- Integrate the active Mask Graph into the Video Timeline orchestrator for batch processing.
