import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cinema_preset.dart';

final cinemaPresetServiceProvider = Provider<CinemaPresetService>((ref) {
  return CinemaPresetService();
});

final cinemaPresetsListProvider = AsyncNotifierProvider<CinemaPresetsNotifier, List<CinemaPreset>>(() {
  return CinemaPresetsNotifier();
});

class CinemaPresetsNotifier extends AsyncNotifier<List<CinemaPreset>> {
  @override
  Future<List<CinemaPreset>> build() async {
    // Return default presets synchronously so UI never hangs or waits on storage
    _loadCustomPresetsInBackground();
    return CinemaPresetService.defaultPresets;
  }

  Future<void> _loadCustomPresetsInBackground() async {
    try {
      final service = ref.read(cinemaPresetServiceProvider);
      final all = await service.getAllPresets().timeout(const Duration(milliseconds: 600));
      state = AsyncData(all);
    } catch (_) {
      // Keep defaultPresets on timeout or error
    }
  }

  Future<void> saveCustomPreset(CinemaPreset preset) async {
    final service = ref.read(cinemaPresetServiceProvider);
    await service.saveCustomPreset(preset);
    final all = await service.getAllPresets();
    state = AsyncData(all);
  }

  Future<void> deleteCustomPreset(String presetId) async {
    final service = ref.read(cinemaPresetServiceProvider);
    await service.deleteCustomPreset(presetId);
    final all = await service.getAllPresets();
    state = AsyncData(all);
  }
}

class CinemaPresetService {
  static const String _storageKey = 'oneova_custom_cinema_presets_v1';

  /// Standard Factory Cinema Presets built into the OneOva engine.
  static final List<CinemaPreset> defaultPresets = [
    CinemaPreset(
      id: 'factory_bmd_gen5',
      name: 'Blackmagic Gen5 Film',
      colorScience: ColorScienceStandard.blackmagicGen5,
      kelvin: 5600,
      tint: 0.0,
      exposure: 0.1,
      contrast: 1.12,
      saturation: 1.08,
      filmGrain: 0.05,
      isAiEnhanced: false,
      aiPrompt: 'Wide dynamic range Oneova Cinema film stock with warm highlight compression.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_arri_logc4',
      name: 'ARRI Alexa LogC4',
      colorScience: ColorScienceStandard.arriLogC4,
      kelvin: 5600,
      tint: 0.5,
      exposure: 0.0,
      contrast: 1.06,
      saturation: 1.04,
      filmGrain: 0.04,
      isAiEnhanced: false,
      aiPrompt: 'Hollywood standard camera look with soft rolloff and pristine skin tones.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_obsidian_telemetry',
      name: 'Oneova Obsidian Cine',
      colorScience: ColorScienceStandard.obsidianCine,
      kelvin: 5200,
      tint: -1.0,
      exposure: 0.2,
      contrast: 1.25,
      saturation: 1.18,
      filmGrain: 0.1,
      isAiEnhanced: true,
      aiPrompt: 'Pitch black floor, electric cyan shadows, and vibrant electric pink tones.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_sony_slog3',
      name: 'Sony S-Log3 Cine',
      colorScience: ColorScienceStandard.sonySLog3,
      kelvin: 5800,
      tint: -0.5,
      exposure: 0.1,
      contrast: 1.15,
      saturation: 1.14,
      filmGrain: 0.06,
      isAiEnhanced: false,
      aiPrompt: 'Punchy cinema gamut with vivid deep blues and crisp highlights.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_apple_prores',
      name: 'Apple ProRes Log',
      colorScience: ColorScienceStandard.appleProResLog,
      kelvin: 5500,
      tint: 0.0,
      exposure: 0.0,
      contrast: 1.05,
      saturation: 1.05,
      filmGrain: 0.02,
      isAiEnhanced: false,
      aiPrompt: '10-bit logarithmic neutral mobile workflow.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_aces_cc',
      name: 'ACEScc Wide Gamut',
      colorScience: ColorScienceStandard.acesCc,
      kelvin: 5600,
      tint: 0.0,
      exposure: 0.0,
      contrast: 1.10,
      saturation: 1.08,
      filmGrain: 0.08,
      isAiEnhanced: false,
      aiPrompt: 'Academy standard wide color space with digital intermediate mastering curve.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_golden_hour',
      name: 'Golden Hour 35mm',
      colorScience: ColorScienceStandard.blackmagicGen5,
      kelvin: 3800,
      tint: 2.0,
      exposure: 0.3,
      contrast: 1.18,
      saturation: 1.25,
      filmGrain: 0.22,
      isAiEnhanced: true,
      aiPrompt: 'Rich honey twilight atmosphere with soft vintage halation.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_cyberpunk',
      name: 'Cyberpunk Neon',
      colorScience: ColorScienceStandard.obsidianCine,
      kelvin: 7200,
      tint: -3.5,
      exposure: 0.4,
      contrast: 1.35,
      saturation: 1.40,
      filmGrain: 0.15,
      isAiEnhanced: true,
      aiPrompt: 'High-contrast futuristic neon city styling with deep blue shadows.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
    CinemaPreset(
      id: 'factory_noir_silver',
      name: 'Noir Silver Halide',
      colorScience: ColorScienceStandard.arriLogC4,
      kelvin: 5600,
      tint: 0.0,
      exposure: -0.2,
      contrast: 1.45,
      saturation: 0.0, // Pure Monochromatic Silver
      filmGrain: 0.35,
      isAiEnhanced: false,
      aiPrompt: 'Timeless black-and-white 35mm high contrast film negative emulation.',
      isUserCustom: false,
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  /// Retrieves both factory and user-created custom presets.
  Future<List<CinemaPreset>> getAllPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customJson = prefs.getStringList(_storageKey) ?? [];
      final customPresets = customJson.map((str) {
        return CinemaPreset.fromJson(str);
      }).toList();

      return [...defaultPresets, ...customPresets];
    } catch (e) {
      return defaultPresets;
    }
  }

  /// Saves or updates a user-defined custom preset.
  Future<void> saveCustomPreset(CinemaPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getStringList(_storageKey) ?? [];
    final customList = customJson.map((str) => CinemaPreset.fromJson(str)).toList();

    final existingIndex = customList.indexWhere((p) => p.id == preset.id);
    if (existingIndex >= 0) {
      customList[existingIndex] = preset;
    } else {
      customList.insert(0, preset);
    }

    final updatedJson = customList.map((p) => p.toJson()).toList();
    await prefs.setStringList(_storageKey, updatedJson);
  }

  /// Deletes a custom preset by ID.
  Future<void> deleteCustomPreset(String presetId) async {
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getStringList(_storageKey) ?? [];
    final customList = customJson.map((str) => CinemaPreset.fromJson(str)).toList();

    customList.removeWhere((p) => p.id == presetId);

    final updatedJson = customList.map((p) => p.toJson()).toList();
    await prefs.setStringList(_storageKey, updatedJson);
  }
}
