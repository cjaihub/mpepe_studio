import 'package:flutter/foundation.dart';
import '../mask_engine/universal_mask_models.dart';

/// A reusable semantic mask configuration saved in the "MY MASKS" gallery.
class SavedMaskTemplate {
  final String id;
  String name;
  bool isFavorite;
  
  /// The abstract semantic target (e.g. 'face', 'hair', 'person', 'sky', 'background', 'object')
  final String targetSemantics;
  
  /// The procedural construction string or query used to build this mask (e.g. 'semantic_intersect_luminance')
  final String selectionRecipe;
  
  final String model;
  
  /// The mathematical configuration (e.g., edge softness, boolean ops, density)
  final Map<String, dynamic> parameters;

  SavedMaskTemplate({
    required this.id,
    required this.name,
    this.isFavorite = false,
    required this.targetSemantics,
    required this.selectionRecipe,
    required this.model,
    required this.parameters,
  });

  SavedMaskTemplate copyWith({
    String? id,
    String? name,
    bool? isFavorite,
    String? targetSemantics,
    String? selectionRecipe,
    String? model,
    Map<String, dynamic>? parameters,
  }) {
    return SavedMaskTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      isFavorite: isFavorite ?? this.isFavorite,
      targetSemantics: targetSemantics ?? this.targetSemantics,
      selectionRecipe: selectionRecipe ?? this.selectionRecipe,
      model: model ?? this.model,
      parameters: parameters ?? this.parameters,
    );
  }
}

/// A local/cloud repository managing the user's custom reusable Mask configurations.
class SavedMaskRepository extends ChangeNotifier {
  final List<SavedMaskTemplate> _templates = [];

  List<SavedMaskTemplate> get templates => List.unmodifiable(_templates);

  /// Converts a physical UniversalMask into a generalized template.
  /// 
  /// REQUIREMENT: Do not reuse a raw pixel mask on incompatible imagery.
  /// REQUIREMENT: Save selection recipe, model, parameters, target semantics.
  void saveMaskAsTemplate({
    required String customName,
    required UniversalMask sourceMask,
    required String targetSemantics,
  }) {
    // We explicitly reject rasterized bitmaps. 
    // They are physically bound to their source image geometry and cannot be reused.
    if (sourceMask.sourceType == MaskSourceType.bitmap) {
      throw Exception("Cannot save a raw pixel bitmap as a reusable template. Only semantic and procedural masks can be converted to recipes.");
    }

    // Strip physical geometry constraints (like source_geometry_hash or interaction points)
    // to ensure the parameters represent a "Recipe" rather than a fixed boundary.
    final Map<String, dynamic> recipeParameters = Map.from(sourceMask.parameters)
      ..removeWhere((key, value) => key == 'source_geometry_hash' || key == 'interaction_history');

    final template = SavedMaskTemplate(
      id: 'TEMPLATE_\${DateTime.now().millisecondsSinceEpoch}',
      name: customName,
      targetSemantics: targetSemantics,
      selectionRecipe: sourceMask.operation.name, 
      model: sourceMask.parameters['model'] ?? 'oneova_semantic_engine',
      parameters: recipeParameters,
    );

    _templates.add(template);
    notifyListeners();
    debugPrint("SAVED MASKS: Successfully saved semantic recipe '\$customName'.");
  }

  // --- UI OPERATIONS ---
  
  void renameTemplate(String id, String newName) {
    final index = _templates.indexWhere((t) => t.id == id);
    if (index != -1) {
      _templates[index].name = newName;
      notifyListeners();
    }
  }

  void toggleFavorite(String id) {
    final index = _templates.indexWhere((t) => t.id == id);
    if (index != -1) {
      _templates[index].isFavorite = !_templates[index].isFavorite;
      notifyListeners();
    }
  }

  void duplicateTemplate(String id) {
    final original = _templates.firstWhere((t) => t.id == id);
    final copy = original.copyWith(
      id: 'TEMPLATE_COPY_\${DateTime.now().millisecondsSinceEpoch}',
      name: '\${original.name} Copy',
      isFavorite: false,
    );
    _templates.add(copy);
    notifyListeners();
  }

  void deleteTemplate(String id) {
    _templates.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  /// Re-hydrates a saved template into an active UniversalMask on a NEW image.
  UniversalMask applyTemplateToNewMedia(SavedMaskTemplate template, String newMediaId) {
    debugPrint("SAVED MASKS: Executing recipe '\${template.name}' on media \$newMediaId...");
    
    // The mask is reborn as a procedural instruction. The AI/GPU will re-execute the 
    // semantic detection and boolean math dynamically against the new image geometry!
    return UniversalMask(
      id: 'REHYDRATED_\${DateTime.now().millisecondsSinceEpoch}',
      projectId: 'auto',
      mediaId: newMediaId,
      maskType: MaskType.CUSTOM,
      sourceType: MaskSourceType.procedural,
      operation: MaskOperation.values.firstWhere((e) => e.name == template.selectionRecipe, orElse: () => MaskOperation.add),
      parameters: template.parameters,
      createdBy: 'saved_mask_repository',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}
