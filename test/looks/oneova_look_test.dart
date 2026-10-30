import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/adapters/legacy_look_adapters.dart';
import 'package:oneova/create/models/cinema_preset.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';
import 'package:oneova/backend/live/models/live_models.dart';

void main() {
  group('OneovaLook Model Tests', () {
    test('Default look creates valid neutral instance', () {
      final look = OneovaLook(
        id: 'test_default',
        name: 'Natural Test',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      expect(look.schemaVersion, 2);
      expect(look.intensity, 1.0);
      expect(look.primary.isNeutral, isTrue);
      expect(look.color.isNeutral, isTrue);
      expect(look.wheels.isNeutral, isTrue);
      expect(look.curves.isNeutral, isTrue);
      expect(look.hsl.isNeutral, isTrue);
      expect(look.boostBeauty.isNeutral, isTrue);
      expect(look.background.isNeutral, isTrue);
      expect(look.isRealtimeCompatible, isTrue);
    });

    test('OneovaLook serialization toMap and fromMap preserves all fields', () {
      final now = DateTime.now();
      final original = OneovaLook(
        id: 'look_gold_hour',
        name: 'Golden Hour Pro',
        ownerUid: 'user_123',
        categories: ['portrait', 'warm'],
        tags: ['golden', 'sunset'],
        thumbnailUrl: 'https://cdn.oneova.com/thumb.jpg',
        intensity: 0.85,
        primary: const LookPrimary(
          exposure: 0.2,
          contrast: 1.15,
          highlights: -0.1,
          shadows: 0.05,
        ),
        color: const LookColor(
          temperature: 15.0,
          tint: -2.0,
          saturation: 1.1,
        ),
        boostBeauty: const BoostBeautyConfig(
          isEnabled: true,
          smoothSkin: 0.6,
          eyeBrighten: 0.4,
        ),
        createdAt: now,
        updatedAt: now,
      );

      final map = original.toMap();
      final restored = OneovaLook.fromMap(map);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.ownerUid, original.ownerUid);
      expect(restored.categories, original.categories);
      expect(restored.tags, original.tags);
      expect(restored.intensity, original.intensity);
      expect(restored.primary.exposure, original.primary.exposure);
      expect(restored.primary.contrast, original.primary.contrast);
      expect(restored.color.temperature, original.color.temperature);
      expect(restored.boostBeauty.isEnabled, isTrue);
      expect(restored.boostBeauty.smoothSkin, 0.6);
    });

    test('Json string round-trip preserves integrity', () {
      final look = OneovaLook(
        id: 'json_test',
        name: 'JSON Look',
        primary: const LookPrimary(exposure: 0.5),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final jsonStr = look.toJson();
      final parsed = OneovaLook.fromJson(jsonStr);

      expect(parsed.id, 'json_test');
      expect(parsed.primary.exposure, 0.5);
    });
  });

  group('LegacyLookAdapters Tests', () {
    test('Converts CinemaPreset into OneovaLook correctly', () {
      final cp = CinemaPreset(
        id: 'cinema_teal',
        name: 'Cinema Teal Orange',
        colorScience: ColorScienceStandard.obsidianCine,
        kelvin: 6500,
        tint: 2.0,
        exposure: 0.3,
        contrast: 1.2,
        saturation: 1.1,
        filmGrain: 0.25,
        isAiEnhanced: true,
        createdAt: DateTime(2026, 2, 1),
      );

      final look = LegacyLookAdapters.fromCinemaPreset(cp);

      expect(look.id, 'cinema_teal');
      expect(look.name, 'Cinema Teal Orange');
      expect(look.categories, contains('cinematic'));
      expect(look.tags, contains('OBSIDIAN'));
      expect(look.tags, contains('ai_enhanced'));
      expect(look.primary.exposure, 0.3);
      expect(look.primary.contrast, 1.2);
      expect(look.film.emulationProfile, 'obsidianCine');
      expect(look.film.grain, 0.25);
    });

    test('Converts ColorPreset into OneovaLook', () {
      final colorPreset = ColorPreset(
        id: 'preset_pro_night',
        name: 'Night Pro',
        category: 'Pro',
        state: ColorState(
          exposure: -0.1,
          contrast: 1.2,
          highlights: -0.2,
          shadows: 0.1,
          temperature: -0.05,
          tint: 0.02,
        ),
      );

      final look = LegacyLookAdapters.fromColorPreset(colorPreset);

      expect(look.id, 'preset_pro_night');
      expect(look.categories, contains('pro'));
      expect(look.categories, contains('video'));
      expect(look.primary.contrast, 1.2);
      expect(look.primary.highlights, -0.2);
    });

    test('Bidirectional conversion between LiveBeautyConfig and BoostBeautyConfig', () {
      const liveBeauty = LiveBeautyConfig(
        smoothSkinLevel: 0.7,
        ringLightIntensity: 0.8,
        warmToneLevel: 0.2,
      );

      final boost = LegacyLookAdapters.fromLiveBeautyConfig(liveBeauty);
      expect(boost.isEnabled, isTrue);
      expect(boost.smoothSkin, 0.7);
      expect(boost.eyeBrighten, 0.4);

      final backToLive = LegacyLookAdapters.toLiveBeautyConfig(boost);
      expect(backToLive.smoothSkinLevel, 0.7);
      expect(backToLive.ringLightIntensity, 0.8);
    });
  });
}
