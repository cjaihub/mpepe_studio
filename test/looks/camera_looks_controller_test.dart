import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/camera/camera_looks_controller.dart';
import 'package:oneova/looks/camera/models/camera_smart_lock_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraLooksController Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state has default video mode, original look and inactive smart lock', () {
      final state = container.read(cameraLooksControllerProvider);
      expect(state.captureMode, CaptureMode.video);
      expect(state.activeLook.id, 'neutral');
      expect(state.smartLock.isSmartLockActive, false);
      expect(state.smartLock.aeLocked, false);
      expect(state.smartLock.afLocked, false);
      expect(state.smartLock.awbLocked, false);
      expect(state.smartLock.exposureBias, 0.0);
      expect(state.smartLock.iso, isNull);
      expect(state.smartLock.shutterSeconds, isNull);
      expect(state.smartLock.isFocusPeakingEnabled, false);
    });

    test('setCaptureMode updates capture mode correctly', () {
      final controller = container.read(cameraLooksControllerProvider.notifier);
      controller.setCaptureMode(CaptureMode.photo);
      expect(container.read(cameraLooksControllerProvider).captureMode, CaptureMode.photo);

      controller.setCaptureMode(CaptureMode.slowMotion);
      expect(container.read(cameraLooksControllerProvider).captureMode, CaptureMode.slowMotion);
    });

    test('applyLook updates active look and preserves attributes', () {
      final controller = container.read(cameraLooksControllerProvider.notifier);
      const customLook = OneovaLook(
        id: 'gold_hour',
        name: 'Golden Hour',
        intensity: 0.85,
        categories: ['cinematic', 'portrait'],
      );

      controller.applyLook(customLook);
      final state = container.read(cameraLooksControllerProvider);
      expect(state.activeLook.id, 'gold_hour');
      expect(state.activeLook.name, 'Golden Hour');
      expect(state.activeLook.intensity, 0.85);
    });

    test('setLookIntensity scales the active look intensity', () {
      final controller = container.read(cameraLooksControllerProvider.notifier);
      controller.setLookIntensity(0.65);
      expect(container.read(cameraLooksControllerProvider).activeLook.intensity, 0.65);

      controller.setLookIntensity(1.5); // clamps to 1.0
      expect(container.read(cameraLooksControllerProvider).activeLook.intensity, 1.0);
    });

    test('engageSmartLock locks AE, AF, AWB and marks session recording', () async {
      final controller = container.read(cameraLooksControllerProvider.notifier);
      await controller.engageSmartLock();

      final state = container.read(cameraLooksControllerProvider);
      expect(state.isRecording, true);
      expect(state.smartLock.isSmartLockActive, true);
      expect(state.smartLock.aeLocked, true);
      expect(state.smartLock.afLocked, true);
      expect(state.smartLock.awbLocked, true);
      expect(state.smartLock.isAnyLockActive, true);
    });

    test('releaseSmartLock unlocks AE, AF, AWB and resets recording flag', () async {
      final controller = container.read(cameraLooksControllerProvider.notifier);
      await controller.engageSmartLock();
      expect(container.read(cameraLooksControllerProvider).smartLock.isSmartLockActive, true);

      await controller.releaseSmartLock();
      final state = container.read(cameraLooksControllerProvider);
      expect(state.isRecording, false);
      expect(state.smartLock.isSmartLockActive, false);
      expect(state.smartLock.aeLocked, false);
      expect(state.smartLock.afLocked, false);
      expect(state.smartLock.awbLocked, false);
    });

    test('Individual lock toggles operate independently', () async {
      final controller = container.read(cameraLooksControllerProvider.notifier);
      expect(container.read(cameraLooksControllerProvider).smartLock.aeLocked, false);

      await controller.toggleAeLock();
      expect(container.read(cameraLooksControllerProvider).smartLock.aeLocked, true);

      await controller.toggleAfLock();
      expect(container.read(cameraLooksControllerProvider).smartLock.afLocked, true);

      await controller.toggleAwbLock();
      expect(container.read(cameraLooksControllerProvider).smartLock.awbLocked, true);

      await controller.toggleAeLock();
      expect(container.read(cameraLooksControllerProvider).smartLock.aeLocked, false);
      expect(container.read(cameraLooksControllerProvider).smartLock.afLocked, true);
    });

    test('Pro manual exposure controls set EV, ISO, Shutter and Kelvin', () async {
      final controller = container.read(cameraLooksControllerProvider.notifier);

      await controller.setExposureBias(1.5);
      expect(container.read(cameraLooksControllerProvider).smartLock.exposureBias, 1.5);

      controller.setIso(400);
      expect(container.read(cameraLooksControllerProvider).smartLock.iso, 400);

      controller.setShutterSpeed(1 / 1000);
      expect(container.read(cameraLooksControllerProvider).smartLock.shutterSeconds, 1 / 1000);

      controller.setWhiteBalance('kelvin', kelvin: 3200);
      expect(container.read(cameraLooksControllerProvider).smartLock.whiteBalanceMode, 'kelvin');
      expect(container.read(cameraLooksControllerProvider).smartLock.kelvin, 3200);

      controller.toggleFocusPeaking();
      expect(container.read(cameraLooksControllerProvider).smartLock.isFocusPeakingEnabled, true);

      await controller.setManualFocus(0.45);
      expect(container.read(cameraLooksControllerProvider).smartLock.focusDistance, 0.45);
      expect(container.read(cameraLooksControllerProvider).smartLock.afLocked, true);
    });
  });
}
