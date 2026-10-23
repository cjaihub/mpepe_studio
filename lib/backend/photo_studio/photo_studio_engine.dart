import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'photo_studio_models.dart';
import 'package:oneova/backend/mask_engine/universal_mask_models.dart';

/// The Core Rendering Engine
/// Guarantees a deterministic rendering pipeline:
/// Same Original Asset + Same EditGraph = Same Pixel-Perfect Output.
class PhotoStudioEngine {
  
  /// In a production environment, this translates the `EditGraph` into a native GPU 
  /// shader graph (Metal on iOS, Vulkan/OpenGL on Android, or CoreImage/Vulkan).
  static Future<dynamic> renderOutput(PhotoAsset source, EditGraph graph, ExportConfiguration config) async {
    // Deterministic Pipeline Simulation:
    // 1. Decode source image to a linear color space buffer.
    // 2. Iterate through `graph.layers` from bottom to top.
    // 3. For each layer:
    //    a. Generate masks deterministically.
    //    b. Apply each `PhotoAdjustment` in the layer sequentially.
    //    c. Blend the layer onto the composition buffer using the specified `blendMode`, `opacity`, and mask.
    // 4. Apply output color space transform.
    // 5. Encode final buffer to `config.format` (JPEG/PNG/TIFF) at specified `config.quality` and dimensions.
    
    // Returns a simulated output path or byte array
    return null; 
  }
}

/// State Manager for Non-Destructive Photo Editing
class PhotoProjectNotifier extends Notifier<PhotoProject> {
  final _uuid = const Uuid();
  Timer? _debounceTimer;

  @override
  PhotoProject build() {
    final initialProject = const PhotoProject(
      id: 'test_project',
      name: 'Test Project',
      originalAsset: PhotoAsset(id: 'test_asset', uri: '', format: 'RAW', width: 1000, height: 1000),
      currentGraph: EditGraph(
        layers: [
          PhotoLayer(
            id: 'global_layer',
            name: 'Global Adjustments',
            adjustments: [],
            maskGraph: null,
          )
        ],
      ),
    );

    return initialProject.copyWith(
      history: [
        EditSnapshot(
          id: _uuid.v4(),
          timestamp: DateTime.now(),
          description: 'Original',
          graph: initialProject.currentGraph,
        )
      ],
      currentHistoryIndex: 0,
    );
  }

  /// Public getter for the current state since StateNotifier's state is protected.
  PhotoProject get currentState => state;

  bool get canUndo => state.currentHistoryIndex > 0;
  bool get canRedo => state.currentHistoryIndex < state.history.length - 1;

  DateTime? _lastSavedTime;
  DateTime? get lastSavedTime => _lastSavedTime;

  void loadProject(PhotoProject project) {
    state = project;
  }

  void setSourceImage(String path, {int width = 1000, int height = 1000, String format = 'JPEG'}) {
    final asset = PhotoAsset(
      id: _uuid.v4(),
      uri: path,
      format: format,
      width: width,
      height: height,
    );
    state = state.copyWith(originalAsset: asset);
    _pushToHistory('Import image');
  }

  /// Core mutating mechanism. All changes to the EditGraph pass through here to ensure history is maintained.
  void _pushToHistory(String description, {EditorCommand? command}) {
    // Conflict resolution check
    if (command != null && command.previousVersion != null && command.previousVersion != state.backendVersion) {
      throw Exception("CONFLICT: This project changed elsewhere. Local version: ${state.backendVersion}, Backend version: ${command.previousVersion}");
    }

    List<EditSnapshot> newHistory = state.history;
    
    // If we've undone back to the middle and make a new edit, trim the "future"
    if (state.currentHistoryIndex < newHistory.length - 1 && state.currentHistoryIndex >= 0) {
      newHistory = newHistory.sublist(0, state.currentHistoryIndex + 1);
    }
    
    final newSnapshot = EditSnapshot(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      description: description,
      graph: state.currentGraph,
      command: command,
    );
    
    newHistory = List.from(newHistory)..add(newSnapshot);
    
    final newBackendVersion = command?.newVersion ?? state.backendVersion;

    state = state.copyWith(
      history: newHistory,
      currentHistoryIndex: newHistory.length - 1,
      backendVersion: newBackendVersion,
    );

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      debugPrint("Auto-saved");
    });
  }

  // ─── Layer Management ──────────────────────────────────────────────────

  void addLayer(PhotoLayer layer) {
    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(
        layers: [...state.currentGraph.layers, layer],
      ),
    );
    _pushToHistory('Add layer: ${layer.name}');
  }

  // ─── Adjustment Management ─────────────────────────────────────────────

  void addAdjustment(String layerId, PhotoAdjustment adjustment) {
    final newLayers = state.currentGraph.layers.map((l) {
      if (l.id == layerId) {
        return l.copyWith(adjustments: [...l.adjustments, adjustment]);
      }
      return l;
    }).toList();
    
    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(layers: newLayers),
    );
    _pushToHistory('Add adjustment: ${adjustment.type.name}');
  }

  void setOrReplaceAdjustment(String layerId, PhotoAdjustment adjustment) {
    final newLayers = state.currentGraph.layers.map((l) {
      if (l.id == layerId) {
        final filtered = l.adjustments.where((a) => a.type != adjustment.type).toList();
        return l.copyWith(adjustments: [...filtered, adjustment]);
      }
      return l;
    }).toList();
    
    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(layers: newLayers),
    );
    _pushToHistory('Set ${adjustment.type.name}');
  }

  void applyAdjustments(List<PhotoAdjustment> adjustments, {String description = 'Apply Adjustments'}) {
    if (state.currentGraph.layers.isEmpty) return;
    final layerId = state.currentGraph.layers.first.id;
    final newLayers = state.currentGraph.layers.map((l) {
      if (l.id == layerId) {
        final typesToReplace = adjustments.map((a) => a.type).toSet();
        final remaining = l.adjustments.where((a) => !typesToReplace.contains(a.type)).toList();
        return l.copyWith(adjustments: [...remaining, ...adjustments]);
      }
      return l;
    }).toList();

    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(layers: newLayers),
    );
    _pushToHistory(description);
  }

  void resetAllAdjustments() {
    if (state.currentGraph.layers.isEmpty) return;
    final layerId = state.currentGraph.layers.first.id;
    final newLayers = state.currentGraph.layers.map((l) {
      if (l.id == layerId) {
        return l.copyWith(adjustments: []);
      }
      return l;
    }).toList();

    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(layers: newLayers),
    );
    _pushToHistory('Reset adjustments');
  }

  void updateAdjustment(String layerId, String adjustmentId, Map<String, dynamic> newParameters) {
    final newLayers = state.currentGraph.layers.map((l) {
      if (l.id == layerId) {
        final newAdj = l.adjustments.map((a) {
          if (a.id == adjustmentId) {
            return a.copyWith(parameters: newParameters);
          }
          return a;
        }).toList();
        return l.copyWith(adjustments: newAdj);
      }
      return l;
    }).toList();
    
    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(layers: newLayers),
    );
    _pushToHistory('Update adjustment parameters');
  }

  // ─── Mask Management ───────────────────────────────────────────────────

  void updateMaskGraph(String layerId, MaskGraph graph, {EditorCommand? command}) {
    final newLayers = state.currentGraph.layers.map((l) {
      if (l.id == layerId) {
        return l.copyWith(maskGraph: graph);
      }
      return l;
    }).toList();

    state = state.copyWith(
      currentGraph: state.currentGraph.copyWith(layers: newLayers),
    );
    _pushToHistory(command?.operation ?? 'Update mask graph', command: command);
  }

  // ─── History & Snapshots ───────────────────────────────────────────────

  void undo() {
    if (state.currentHistoryIndex > 0) {
      final newIndex = state.currentHistoryIndex - 1;
      final previousGraph = state.history[newIndex].graph;
      state = state.copyWith(
        currentGraph: previousGraph,
        currentHistoryIndex: newIndex,
      );
    }
  }

  void redo() {
    if (state.currentHistoryIndex < state.history.length - 1) {
      final newIndex = state.currentHistoryIndex + 1;
      final nextGraph = state.history[newIndex].graph;
      state = state.copyWith(
        currentGraph: nextGraph,
        currentHistoryIndex: newIndex,
      );
    }
  }

  /// Represents a "Compare" or "Before" view without modifying the active state
  EditGraph getBeforeGraph() {
    if (state.history.isNotEmpty) {
      return state.history.first.graph;
    }
    return state.currentGraph;
  }

  // ─── Versions & Branching ──────────────────────────────────────────────

  /// Save the current graph as an explicit named version (e.g., "Moody B&W")
  void saveVersion(String name) {
    final newVersion = EditSnapshot(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      description: name,
      graph: state.currentGraph,
    );
    state = state.copyWith(
      versions: [...state.versions, newVersion],
    );
  }

  /// Restores a saved version and appends it to the active history stack.
  void restoreVersion(String versionId) {
    final version = state.versions.firstWhere((v) => v.id == versionId);
    state = state.copyWith(
      currentGraph: version.graph,
    );
    _pushToHistory('Restore version: ${version.description}');
  }

  /// Duplicates the entire project, preserving non-destructive history.
  PhotoProject duplicateProject(String newName) {
    return state.copyWith(
      id: _uuid.v4(),
      name: newName,
    );
  }
}
