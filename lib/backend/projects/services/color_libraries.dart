import '../models/pro_project_models.dart';

class LutLibrary {
  static final Map<String, String> _availableLuts = {
    'cinematic': 'luts/cinematic.cube',
    'night': 'luts/night_cinema.cube',
    'vintage': 'luts/vintage.cube',
    'teal_orange': 'luts/teal_orange.cube',
  };

  static bool exists(String lutId) {
    return _availableLuts.containsKey(lutId.toLowerCase());
  }

  static String? getPath(String lutId) {
    return _availableLuts[lutId.toLowerCase()];
  }
}

class PresetLibrary {
  static final Map<String, ColorPreset> _availablePresets = {
    'cinematic': ColorPreset(
      id: 'preset_cinematic',
      name: 'Cinematic',
      category: 'Pro',
      state: ColorState(
        exposure: 0.1,
        contrast: 1.1,
        highlights: -0.1,
        shadows: 0.1,
        temperature: -0.05,
      ),
    ),
    'moody dark': ColorPreset(
      id: 'preset_moody_dark',
      name: 'Moody Dark',
      category: 'Pro',
      state: ColorState(
        exposure: -0.2,
        contrast: 1.2,
        highlights: -0.2,
        shadows: -0.3,
        temperature: -0.1,
      ),
    ),
    'portrait skin': ColorPreset(
      id: 'preset_portrait_skin',
      name: 'Portrait Skin',
      category: 'Portrait',
      state: ColorState(
        exposure: 0.05,
        contrast: 0.95,
        temperature: 0.05,
        tint: 0.02,
      ),
    ),
  };

  static bool exists(String presetId) {
    return _availablePresets.containsKey(presetId.toLowerCase());
  }

  static ColorPreset? getPreset(String presetId) {
    return _availablePresets[presetId.toLowerCase()];
  }
}
