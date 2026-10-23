import 'effect_models.dart';

/// Centralized registry for all available effects in the system.
/// This prevents hardcoding effect IDs and provides a scalable way to list, 
/// categorize, and instantiate effects.
class EffectRegistry {
  static final EffectRegistry _instance = EffectRegistry._internal();
  factory EffectRegistry() => _instance;
  EffectRegistry._internal();

  final List<EffectDefinition> _effects = [
    EffectDefinition(
      id: 'gaussian_blur',
      name: 'Gaussian Blur',
      category: EffectCategory.blur,
      description: 'Applies a standard Gaussian blur to the image.',
      createDefaultParameters: () => GaussianBlurParameters(),
    ),
    EffectDefinition(
      id: 'glow',
      name: 'Glow',
      category: EffectCategory.stylize,
      description: 'Adds a luminous glow to the highlights.',
      createDefaultParameters: () => GlowParameters(),
    ),
    EffectDefinition(
      id: 'chroma_key',
      name: 'Chroma Key',
      category: EffectCategory.keying,
      description: 'Removes a specific color range for green screen compositing.',
      createDefaultParameters: () => ChromaKeyParameters(),
    ),
    EffectDefinition(
      id: 'sharpen',
      name: 'Sharpen',
      category: EffectCategory.stylize,
      description: 'Enhances edge contrast to make the image appear sharper.',
      createDefaultParameters: () => SharpenParameters(),
    ),
    EffectDefinition(
      id: 'motion_preset_zoom',
      name: 'Zoom Transition',
      category: EffectCategory.motion,
      description: 'A dynamic zoom-in/out motion effect.',
      createDefaultParameters: () => MotionPresetParameters(),
    ),
  ];

  List<EffectDefinition> get allEffects => List.unmodifiable(_effects);

  List<EffectDefinition> getEffectsByCategory(EffectCategory category) {
    return _effects.where((e) => e.category == category).toList();
  }

  EffectDefinition? getEffectById(String id) {
    try {
      return _effects.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  EffectState createEffect(String id) {
    final def = getEffectById(id);
    if (def == null) {
      throw ArgumentError('Effect with id $id not found in registry.');
    }
    return EffectState(
      name: def.name,
      type: def.id,
      parameters: def.createDefaultParameters(),
    );
  }
}

/// Defines an available effect type, its metadata, and how to instantiate it.
class EffectDefinition {
  final String id;
  final String name;
  final EffectCategory category;
  final String description;
  final EffectParameters Function() createDefaultParameters;

  const EffectDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.createDefaultParameters,
  });
}
