import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live/models/live_models.dart';
import 'package:oneova/looks/live/live_looks_controller.dart';
import 'package:oneova/looks/live/models/live_profile.dart';
import 'package:oneova/looks/models/oneova_look.dart';

void main() {
  group('LiveProfile & LiveScene Models', () {
    test('LiveProfile toMap and fromMap preserve all fields', () {
      final now = DateTime(2026, 4, 1, 12, 0, 0);
      final profile = LiveProfile(
        id: 'prof_1',
        name: 'Night Studio',
        description: 'Low-light podcast setup',
        lookId: 'cinematic',
        beauty: const BoostBeautyConfig(smoothSkin: 0.6, eyeBrighten: 0.4),
        resolution: '1080p',
        fps: 60,
        isHdr: true,
        noiseSuppression: true,
        echoCancellation: false,
        voiceEnhance: true,
        updatedAt: now,
      );

      final map = profile.toMap();
      final restored = LiveProfile.fromMap(map);

      expect(restored.id, 'prof_1');
      expect(restored.name, 'Night Studio');
      expect(restored.description, 'Low-light podcast setup');
      expect(restored.lookId, 'cinematic');
      expect(restored.beauty.smoothSkin, 0.6);
      expect(restored.beauty.eyeBrighten, 0.4);
      expect(restored.resolution, '1080p');
      expect(restored.fps, 60);
      expect(restored.isHdr, isTrue);
      expect(restored.noiseSuppression, isTrue);
      expect(restored.echoCancellation, isFalse);
      expect(restored.voiceEnhance, isTrue);
    });

    test('LiveScene toMap and fromMap preserve transition duration and background', () {
      const scene = LiveScene(
        id: 'scene_guest',
        name: 'Guest Interview',
        order: 2,
        lookId: 'warm_mood',
        beauty: BoostBeautyConfig(smoothSkin: 0.5),
        background: BackgroundEffectConfig(mode: 'blur', blurLevel: 0.8),
        audioPreset: 'podcast',
        transitionStyle: 'crossfade',
        transitionDuration: Duration(milliseconds: 450),
      );

      final map = scene.toMap();
      final restored = LiveScene.fromMap(map);

      expect(restored.id, 'scene_guest');
      expect(restored.name, 'Guest Interview');
      expect(restored.order, 2);
      expect(restored.background.mode, 'blur');
      expect(restored.background.blurLevel, 0.8);
      expect(restored.audioPreset, 'podcast');
      expect(restored.transitionDuration, const Duration(milliseconds: 450));
    });
  });

  group('LiveLooksController Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is unattached with default neutral look', () {
      final state = container.read(liveLooksControllerProvider);

      expect(state.isAttached, isFalse);
      expect(state.attachedTrackId, isNull);
      expect(state.beauty.smoothSkin, 0.0);
      expect(state.activeLook.name, 'Neutral Live');
    });

    test('applyLook updates activeLook preserving beauty and background', () async {
      final controller = container.read(liveLooksControllerProvider.notifier);

      const customBeauty = BoostBeautyConfig(smoothSkin: 0.65, eyeBrighten: 0.35);
      await controller.applyBeauty(customBeauty);

      const newLook = OneovaLook(
        id: 'golden_hour',
        name: 'Golden Hour',
        color: LookColor(temperature: 20.0),
      );

      await controller.applyLook(newLook);

      final state = container.read(liveLooksControllerProvider);
      expect(state.activeLook.id, 'golden_hour');
      expect(state.activeLook.color.temperature, 20.0);
      // Beauty preserved through look change
      expect(state.activeLook.boostBeauty.smoothSkin, 0.65);
      expect(state.activeLook.boostBeauty.eyeBrighten, 0.35);
    });

    test('applyLegacyBeauty converts LiveBeautyConfig into BoostBeautyConfig', () async {
      final controller = container.read(liveLooksControllerProvider.notifier);

      const legacy = LiveBeautyConfig(
        smoothSkinLevel: 0.8,
        ringLightIntensity: 0.6,
      );

      await controller.applyLegacyBeauty(legacy);

      final state = container.read(liveLooksControllerProvider);
      expect(state.beauty.smoothSkin, closeTo(0.8, 0.01));
      expect(state.beauty.evenTone, closeTo(0.64, 0.01));
      expect(state.beauty.eyeBrighten, closeTo(0.3, 0.01));
    });

    test('switchScene updates activeScene, look, and background', () async {
      final controller = container.read(liveLooksControllerProvider.notifier);

      const targetScene = LiveScene(
        id: 'scene_stage',
        name: 'Main Stage',
        look: OneovaLook(name: 'Stage Look', primary: LookPrimary(contrast: 1.2)),
        beauty: BoostBeautyConfig(smoothSkin: 0.4),
        background: BackgroundEffectConfig(mode: 'green'),
        transitionDuration: Duration(milliseconds: 300),
      );

      await controller.switchScene(targetScene);

      final state = container.read(liveLooksControllerProvider);
      expect(state.activeScene?.id, 'scene_stage');
      expect(state.activeLook.name, 'Stage Look');
      expect(state.activeLook.primary.contrast, 1.2);
      expect(state.beauty.smoothSkin, 0.4);
      expect(state.background.mode, 'green');
    });

    test('applyProfile applies full settings snapshot', () async {
      final controller = container.read(liveLooksControllerProvider.notifier);

      final profile = LiveProfile(
        id: 'prof_hdr',
        name: 'HDR Podcast',
        customLook: const OneovaLook(name: 'HDR Pro', color: LookColor(vibrance: 0.3)),
        beauty: const BoostBeautyConfig(smoothSkin: 0.5, faceSlim: 0.2),
        updatedAt: DateTime.now(),
      );

      await controller.applyProfile(profile);

      final state = container.read(liveLooksControllerProvider);
      expect(state.activeProfile?.id, 'prof_hdr');
      expect(state.activeLook.name, 'HDR Pro');
      expect(state.activeLook.color.vibrance, 0.3);
      expect(state.beauty.faceSlim, 0.2);
    });
  });
}
