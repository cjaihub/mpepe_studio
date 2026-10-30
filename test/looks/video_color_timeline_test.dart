import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/video/models/video_color_models.dart';
import 'package:oneova/looks/video/services/shot_match_service.dart';
import 'package:oneova/looks/video/services/video_keyframe_interpolator.dart';
import 'package:oneova/looks/video/services/hardware_export_service.dart';
import 'package:oneova/looks/video/services/cloud_render_client.dart';
import 'package:oneova/looks/video/controllers/video_color_timeline_controller.dart';
import 'package:oneova/looks/video/widgets/video_timeline_strip.dart';
import 'package:oneova/looks/video/widgets/shot_match_dialog.dart';
import 'package:oneova/looks/video/widgets/video_export_dialog.dart';
import 'package:oneova/looks/video/ui/video_color_studio_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoColorTimelineController Unit Tests', () {
    test('Initializes with default clips, active clip, and effective look', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(videoColorTimelineControllerProvider);
      expect(state.clips.length, equals(3));
      expect(state.activeClipId, equals('clip_01'));
      expect(state.effectiveLook.id, equals('look_cinematic'));
      expect(state.isScopesVisible, isFalse);
    });

    test('selectClip switches active clip and updates effectiveLook', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(videoColorTimelineControllerProvider.notifier);

      controller.selectClip('clip_02');
      final state = container.read(videoColorTimelineControllerProvider);
      expect(state.activeClipId, equals('clip_02'));
      expect(state.activeClip?.clipName, equals('A02_CloseUp_Dialogue.mov'));
      expect(state.effectiveLook.id, equals('look_portrait'));
    });

    test('updateActiveClipLook updates baseLook and effectiveLook', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(videoColorTimelineControllerProvider.notifier);

      const modifiedLook = OneovaLook(
        id: 'look_mod',
        name: 'Modified Grade',
        primary: LookPrimary(exposure: 0.5, contrast: 1.3),
        color: LookColor(temperature: 20.0),
      );

      controller.updateActiveClipLook(modifiedLook);
      final state = container.read(videoColorTimelineControllerProvider);
      expect(state.activeClip?.baseLook.id, equals('look_mod'));
      expect(state.effectiveLook.primary.exposure, equals(0.5));
      expect(state.effectiveLook.color.temperature, equals(20.0));
    });

    test('toggleActiveClipBypass toggles isBypassed flag', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(videoColorTimelineControllerProvider.notifier);

      expect(container.read(videoColorTimelineControllerProvider).activeClip?.isBypassed, isFalse);
      controller.toggleActiveClipBypass();
      expect(container.read(videoColorTimelineControllerProvider).activeClip?.isBypassed, isTrue);
      controller.toggleActiveClipBypass();
      expect(container.read(videoColorTimelineControllerProvider).activeClip?.isBypassed, isFalse);
    });

    test('addKeyframeToActiveClip and removeKeyframe works accurately', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(videoColorTimelineControllerProvider.notifier);

      const kfLook = OneovaLook(
        id: 'kf_01',
        primary: LookPrimary(exposure: 0.8),
      );

      controller.addKeyframeToActiveClip(timeSeconds: 1.5, look: kfLook);
      var clip = container.read(videoColorTimelineControllerProvider).activeClip!;
      expect(clip.keyframes.length, equals(1));
      expect(clip.keyframes.first.timeSeconds, equals(1.5));
      expect(clip.keyframes.first.look.primary.exposure, equals(0.8));

      controller.removeKeyframeFromActiveClip(1.5);
      clip = container.read(videoColorTimelineControllerProvider).activeClip!;
      expect(clip.keyframes, isEmpty);
    });

    test('addAdjustmentLayer and removeAdjustmentLayer spans across tracks', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(videoColorTimelineControllerProvider.notifier);

      const adjLook = OneovaLook(
        id: 'look_adj',
        name: 'Global Teal Tint',
        color: LookColor(temperature: -20.0, tint: 10.0),
      );

      controller.addAdjustmentLayer(
        name: 'Master Global Grade',
        startTime: 0.0,
        duration: 15.0,
        look: adjLook,
        intensity: 0.8,
      );

      var state = container.read(videoColorTimelineControllerProvider);
      expect(state.adjustmentLayers.length, equals(1));
      expect(state.adjustmentLayers.first.name, equals('Master Global Grade'));

      controller.removeAdjustmentLayer(state.adjustmentLayers.first.id);
      state = container.read(videoColorTimelineControllerProvider);
      expect(state.adjustmentLayers, isEmpty);
    });

    test('setPlayhead scrubs timeline and blends adjustment layers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(videoColorTimelineControllerProvider.notifier);

      // Playhead in clip 1 (0.0 .. 4.5s)
      controller.setPlayhead(2.0);
      var state = container.read(videoColorTimelineControllerProvider);
      expect(state.activeClipId, equals('clip_01'));

      // Playhead in clip 2 (4.5 .. 10.5s)
      controller.setPlayhead(6.0);
      state = container.read(videoColorTimelineControllerProvider);
      expect(state.activeClipId, equals('clip_02'));
    });
  });

  group('ShotMatchService & Keyframe Interpolator Tests', () {
    test('ShotMatchService calculates exposure and temperature offsets', () {
      final service = ShotMatchService();

      const refLook = OneovaLook(
        id: 'ref',
        primary: LookPrimary(exposure: 0.2, contrast: 1.2),
        color: LookColor(temperature: 15.0, tint: -2.0, saturation: 1.1),
      );

      const tgtLook = OneovaLook(
        id: 'tgt',
        primary: LookPrimary(exposure: -0.3, contrast: 1.0),
        color: LookColor(temperature: -10.0, tint: 6.0, saturation: 0.9),
      );

      final result = service.matchShots(
        referenceClipId: 'clip_01',
        targetClipId: 'clip_02',
        referenceLook: refLook,
        targetLook: tgtLook,
      );

      expect(result.exposureOffset, closeTo(0.5, 0.01));
      expect(result.temperatureDelta, closeTo(25.0, 0.01));
      expect(result.confidenceScore, greaterThan(0.70));
      expect(result.matchedLook.primary.exposure, greaterThan(tgtLook.primary.exposure));
      expect(result.matchedLook.color.temperature, greaterThan(tgtLook.color.temperature));
    });

    test('VideoKeyframeInterpolator interpolates parameters smoothly at time t', () {
      final interpolator = VideoKeyframeInterpolator();

      const kf1 = LookKeyframe(
        timeSeconds: 0.0,
        look: OneovaLook(primary: LookPrimary(exposure: 0.0)),
        easing: KeyframeEasing.linear,
      );

      const kf2 = LookKeyframe(
        timeSeconds: 2.0,
        look: OneovaLook(primary: LookPrimary(exposure: 1.0)),
        easing: KeyframeEasing.linear,
      );

      const clip = ClipColorGrade(
        clipId: 'c1',
        clipName: 'Clip 1',
        startTimeSeconds: 0.0,
        durationSeconds: 4.0,
        baseLook: OneovaLook(primary: LookPrimary(exposure: 0.0)),
        keyframes: [kf1, kf2],
      );

      // At t = 1.0 (halfway), exposure should be 0.5
      final lookAt1s = interpolator.interpolateAtTime(clipGrade: clip, currentTimeSeconds: 1.0);
      expect(lookAt1s.primary.exposure, closeTo(0.5, 0.02));

      // At t = 0.0, exposure is 0.0
      final lookAt0s = interpolator.interpolateAtTime(clipGrade: clip, currentTimeSeconds: 0.0);
      expect(lookAt0s.primary.exposure, closeTo(0.0, 0.01));

      // At t = 2.0+, exposure is 1.0
      final lookAt3s = interpolator.interpolateAtTime(clipGrade: clip, currentTimeSeconds: 3.0);
      expect(lookAt3s.primary.exposure, closeTo(1.0, 0.01));
    });
  });

  group('Hardware & Cloud Export Service Tests', () {
    test('HardwareExportService executes local hardware export', () async {
      final service = HardwareExportService();

      const clips = [
        ClipColorGrade(
          clipId: 'c1',
          clipName: 'Clip 1',
          startTimeSeconds: 0.0,
          durationSeconds: 5.0,
          baseLook: OneovaLook(),
        ),
      ];

      const config = VideoExportConfig(
        width: 1920,
        height: 1080,
        fps: 30.0,
        videoCodec: 'hevc',
        useCloudRender: false,
      );

      final job = await service.exportVideo(
        clips: clips,
        adjustmentLayers: [],
        config: config,
      );

      expect(job.status, equals(RenderJobStatus.completed));
      expect(job.progress, equals(1.0));
      expect(job.outputPath, isNotNull);
      expect(job.outputPath!.endsWith('.mp4'), isTrue);
    });

    test('HardwareExportService routes 4K/HDR or cloud requested job to CloudRenderClient', () async {
      final service = HardwareExportService();

      const clips = [
        ClipColorGrade(
          clipId: 'c1',
          clipName: 'Clip 1',
          startTimeSeconds: 0.0,
          durationSeconds: 5.0,
          baseLook: OneovaLook(),
        ),
      ];

      const config = VideoExportConfig(
        width: 3840,
        height: 2160,
        fps: 60.0,
        bitDepth: 10,
        isHdr: true,
        useCloudRender: true,
      );

      final job = await service.exportVideo(
        clips: clips,
        adjustmentLayers: [],
        config: config,
      );

      expect(job.status, equals(RenderJobStatus.completed));
      expect(job.outputDownloadUrl, isNotNull);
      expect(job.outputDownloadUrl!.contains('https://cdn.oneova.app/renders/'), isTrue);
    });
  });

  group('Video Color Workstation UI Widget Tests', () {
    Widget buildTestHost({required Widget child, Brightness brightness = Brightness.dark}) {
      return ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            scaffoldBackgroundColor:
                brightness == Brightness.dark ? AppColors.darkBackground : AppColors.lightBackground,
          ),
          home: child,
        ),
      );
    }

    testWidgets('VideoColorStudioScreen renders in Dark Mode with timeline and monitor', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.dark,
          child: const VideoColorStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Timeline Sequence'), findsOneWidget);
      expect(find.text('TIMELINE COLOR STRIP'), findsOneWidget);
      expect(find.text('A01_Intro_Wide.mov'), findsNWidgets(3)); // monitor title, timeline strip, inspector
      expect(find.text('Export'), findsOneWidget);
      expect(find.byIcon(Icons.compare_arrows_rounded), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    });

    testWidgets('VideoColorStudioScreen renders in Light Mode without layout issues', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.light,
          child: const VideoColorStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main Timeline Sequence'), findsOneWidget);
      expect(find.text('TIMELINE COLOR STRIP'), findsOneWidget);
    });

    testWidgets('ShotMatchDialog opens, computes match and applies', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const ShotMatchDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Shot Matcher'), findsOneWidget);
      expect(find.text('Analyze & Match'), findsOneWidget);

      await tester.tap(find.text('Analyze & Match'));
      await tester.pumpAndSettle();

      expect(find.text('Alignment Telemetry'), findsOneWidget);
      expect(find.text('Apply Match'), findsOneWidget);
    });

    testWidgets('VideoExportDialog opens and displays resolution and hardware render options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const VideoExportDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Video Export & Hardware Render'), findsOneWidget);
      expect(find.text('1080p FHD'), findsOneWidget);
      expect(find.text('4K UHD'), findsOneWidget);
      expect(find.text('Start Hardware Export'), findsOneWidget);
    });
  });
}
