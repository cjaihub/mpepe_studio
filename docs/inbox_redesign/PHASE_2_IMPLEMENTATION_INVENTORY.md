# MPEPE Studio: Creator/PhotoStudio Implementation Inventory

This document serves as the Phase 1 audit of the existing Creator/PhotoStudio systems. It outlines the current state of features, AI capabilities, media modeling, and masking engines, classifying them to guide the non-destructive professional editor upgrade.

## Classification Legend
- **KEEP**: Retain as is; core functionality works and fits the new architecture.
- **UPGRADE**: Improve, extend, or add missing professional features (e.g., UI, capability, or performance).
- **CONNECT**: Wire the feature into the new unified `ProProject` engine (e.g., allowing an AI mask to apply to a video timeline).
- **REFACTOR**: Restructure the code to fit the new architecture without changing the external behavior.
- **DEPRECATE**: Remove only if completely duplicated by the new unified engine (and functionality is safely replaced).

---

## 1. Project Models & Persistence
| Existing Feature | Current Location | Classification | Notes |
| :--- | :--- | :--- | :--- |
| **StudioProject** | `lib/backend/project_repository.dart` | **UPGRADE / CONNECT** | Currently handles basic metadata, collab status. Must be upgraded to or merged with `ProProject` to handle sequences, tracks, clips, and timeline data. |
| **Persistence / Sync** | `lib/backend/project_repository.dart` | **KEEP** | Standard Firestore streaming works well. Needs to be hooked into the autosave / recovery engine. |
| **Draft System** | `lib/backend/project_repository.dart` | **KEEP / CONNECT** | Existing drafts need to be loadable by the new unified engine without conversion loss. |

---

## 2. Media Workspace & Timeline
| Existing Feature | Current Location | Classification | Notes |
| :--- | :--- | :--- | :--- |
| **Media Selection** | `lib/create/media_preview_screen.dart` | **UPGRADE** | Must be upgraded to a robust Media Browser backing actual device/project media with filtering (Video, Photo, RAW, Audio, Favorites, Recent). |
| **Pro Editor Shell** | `lib/video_production/pro_editor_screen.dart` | **UPGRADE** | Newly introduced. Needs full implementation of non-linear multi-track timeline, viewer, and responsive layouts. |
| **Timeline Engine** | Placeholder in Shell | **UPGRADE** | Must build true non-linear editing (NLE) capabilities: trim, split, ripple, compound clips, keyframes. |
| **Inspector Panel** | `lib/video_production/widgets/pro_inspector_panel.dart` | **UPGRADE** | Needs to reflect Transform, Audio, Color, and Effect state dynamically. |

---

## 3. PhotoStudio Engine
| Existing Feature | Current Location | Classification | Notes |
| :--- | :--- | :--- | :--- |
| **Core Photo Engine** | `lib/backend/photo_studio/photo_studio_engine.dart` | **UPGRADE / CONNECT** | Retain powerful features (RAW editing, tuning), but connect its state representations to `ProProject` structure (Clips/ColorDecisions). |
| **Photo Color Engine** | `lib/backend/photo_studio/photo_color_engine.dart` | **UPGRADE** | Expand into DaVinci-class color workflow (Primary, Curves, Wheels, HSL, Skin Tone). |
| **Photo Format Decoder** | `lib/backend/photo_studio/photo_format_decoder.dart`| **KEEP** | Handles image parsing (JPEG, PNG, TIFF, RAW). |
| **Preset Engine** | `lib/backend/photo_studio/preset_manager.dart` | **REFACTOR / UPGRADE** | Refactor to support Video presets, LUT stacking, and the future Marketplace architecture. |

---

## 4. Mask Engine Architecture
| Existing Feature | Current Location | Classification | Notes |
| :--- | :--- | :--- | :--- |
| **Universal Mask Models** | `lib/backend/mask_engine/universal_mask_models.dart` | **KEEP** | Core data structures are robust. |
| **Background / Sky / People Seg.** | `lib/backend/photo_studio/...` & `mask_engine/...` | **CONNECT** | Retain all AI Select capabilities (Subject, Face, Sky, Background, etc). Connect them to video clips and tracking. |
| **Mask Layer Manager** | `lib/backend/mask_engine/mask_layer_manager.dart` | **UPGRADE / CONNECT**| Support non-destructive, stackable, and trackable masks for both photo and video. |
| **Boolean / Refine Ops** | `lib/backend/photo_studio/mask_boolean_engine.dart` | **KEEP** | Retain Add/Subtract/Intersect/Invert/Feather. |
| **Temporal Video Tracker** | `lib/backend/mask_engine/temporal_video_tracker.dart` | **UPGRADE / CONNECT** | Crucial for tracking photo-style masks across video frames. Needs integration with timeline UI. |

---

## 5. AI Tooling
| Existing Feature | Current Location | Classification | Notes |
| :--- | :--- | :--- | :--- |
| **AI Removal/Replacement** | `lib/backend/photo_studio/ai_removal_engine.dart` | **CONNECT** | Make available in the AI Studio video tools. |
| **AI Relighting/Retouching** | `lib/backend/photo_studio/...retouching.dart` | **CONNECT** | Extend to face enhancement in video frames. |
| **CV Inference / Models** | `lib/backend/mask_engine/cv_inference_service.dart` | **KEEP** | Handles computer vision heavy lifting. Ensure background processing doesn't block UI. |
| **NLP Semantic Orchestrator** | `lib/backend/photo_studio/nlp_color_orchestrator.dart` | **KEEP** | Retain chat-based or semantic generation capabilities for color grades/masks. |

---

## 6. Navigation & Shell
| Existing Feature | Current Location | Classification | Notes |
| :--- | :--- | :--- | :--- |
| **Creator Studio Home** | `lib/video_production/creator_studio_screen.dart` | **UPGRADE** | Acts as the primary entry point. Keep the dashboard, but properly route 'Create' and 'Drafts' to the `ProProject` engine. |
| **Mobile / Desktop Adapting** | `lib/video_production/pro_editor_screen.dart` | **UPGRADE** | Enhance layout logic to ensure the mobile editor is touch/gesture friendly and the desktop editor acts as a pro workspace. |
| **Export Engine** | `lib/video_production/export_center_screen.dart` | **UPGRADE** | Needs proxy/render queue architecture to handle 4K encoding and multiple formats asynchronously. |

## Next Steps
The audit reveals a rich, highly sophisticated set of backend features (especially in AI masking and photo manipulation). The primary task is **NOT** to rebuild these engines, but rather to **UPGRADE** the project data model to handle non-linear video/audio, and **CONNECT** these existing engines to a unified, professional timeline UI. 

We will proceed to **PHASE 2: Upgrade shared project model**.
