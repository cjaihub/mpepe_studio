import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/looks/cloud_vision/controllers/cloud_vision_controller.dart';
import 'package:oneova/looks/cloud_vision/models/cloud_vision_models.dart';
import 'package:oneova/looks/cloud_vision/services/cloud_vision_service_client.dart';
import 'package:oneova/looks/cloud_vision/ui/cloud_vision_studio_screen.dart';
import 'package:oneova/looks/cloud_vision/widgets/ai_enhance_sheet.dart';
import 'package:oneova/looks/cloud_vision/widgets/relight_sheet.dart';
import 'package:oneova/looks/cloud_vision/widgets/rotoscope_prompt_sheet.dart';
import 'package:oneova/looks/cloud_vision/widgets/sky_replacement_sheet.dart';

Widget buildTestHost({
  required Widget child,
  Brightness brightness = Brightness.dark,
}) {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudVision Models & Quota Unit Tests', () {
    test('RotoscopeTarget serializes to JSON correctly', () {
      const target = RotoscopeTarget(
        prompt: 'isolate neon sports car',
        boxCoords: [0.1, 0.2, 0.8, 0.9],
        trackFrames: true,
      );

      final json = target.toJson(videoUrl: 'https://cdn.example.com/v.mp4', userId: 'user_123');
      expect(json['prompt'], 'isolate neon sports car');
      expect(json['box_coords'], [0.1, 0.2, 0.8, 0.9]);
      expect(json['track_frames'], true);
      expect(json['user_id'], 'user_123');
    });

    test('RelightConfig updates and serializes properly', () {
      const initial = RelightConfig();
      final updated = initial.copyWith(
        lightPosition: [0.2, 0.8, 1.5],
        lightColorHex: '#FF2D87',
        intensity: 2.5,
      );

      expect(updated.lightPosition, [0.2, 0.8, 1.5]);
      expect(updated.lightColorHex, '#FF2D87');
      expect(updated.intensity, 2.5);

      final json = updated.toJson(videoUrl: 'https://cdn.example.com/v.mp4', userId: 'user_123');
      expect(json['light_color'], '#FF2D87');
      expect(json['intensity'], 2.5);
    });

    test('SkyPreset default catalog contains expected high-fidelity presets', () {
      final presets = SkyPreset.defaultPresets;
      expect(presets.length, greaterThanOrEqualTo(5));
      expect(presets.any((p) => p.name == 'Golden Hour Dusk'), isTrue);
      expect(presets.any((p) => p.name == 'Cyber Twilight'), isTrue);
    });

    test('CloudVisionQuota calculates remaining credits and limits correctly', () {
      final quota = CloudVisionQuota(
        dailyBudgetJobs: 20,
        jobsUsedToday: 5,
        resetAt: DateTime.now().add(const Duration(hours: 12)),
      );

      expect(quota.jobsRemaining, 15);
      expect(quota.hasRemainingQuota, isTrue);
      expect(quota.usagePercent, 0.25);

      final exhausted = quota.copyWith(jobsUsedToday: 20);
      expect(exhausted.jobsRemaining, 0);
      expect(exhausted.hasRemainingQuota, isFalse);
      expect(exhausted.usagePercent, 1.0);
    });

    test('CloudVisionJob deserializes from API response', () {
      final job = CloudVisionJob.fromJson({
        'job_id': 'cv_roto_abc123',
        'task_type': 'rotoscope',
        'status': 'completed',
        'progress': 1.0,
        'output_url': 'https://cdn.example.com/out.mp4',
        'preview_url': 'https://cdn.example.com/prev.jpg',
        'telemetry': {'model': 'sam2_hiera_large'},
      });

      expect(job.jobId, 'cv_roto_abc123');
      expect(job.taskType, VisionTaskType.rotoscope);
      expect(job.isCompleted, isTrue);
      expect(job.progress, 1.0);
      expect(job.outputUrl, 'https://cdn.example.com/out.mp4');
    });
  });

  group('CloudVisionServiceClient Unit Tests', () {
    late CloudVisionServiceClient client;

    setUp(() {
      client = CloudVisionServiceClient();
    });

    tearDown(() {
      client.clearCache();
    });

    test('warmupGpuInstance triggers warm-up probe successfully', () async {
      final warmed = await client.warmupGpuInstance();
      expect(warmed, isTrue);
    });

    test('submitRotoscope creates job and caches subsequent identical requests', () async {
      const target = RotoscopeTarget(prompt: 'isolate model hair');
      final job1 = await client.submitRotoscope(
        target: target,
        videoUrl: 'https://cdn.example.com/take.mp4',
        userId: 'creator_1',
      );

      expect(job1.taskType, VisionTaskType.rotoscope);
      expect(job1.isProcessing, isTrue);

      final job2 = await client.submitRotoscope(
        target: target,
        videoUrl: 'https://cdn.example.com/take.mp4',
        userId: 'creator_1',
      );

      expect(job2.jobId, job1.jobId);
    });

    test('streamJobProgress streams updates to completion', () async {
      final job = await client.submitEnhance(
        mode: AiEnhanceMode.upscale4x,
        videoUrl: 'https://cdn.example.com/take.mp4',
        userId: 'creator_1',
      );

      final updates = await client.streamJobProgress(
        job.jobId,
        pollInterval: const Duration(milliseconds: 10),
      ).toList();

      expect(updates.isNotEmpty, isTrue);
      expect(updates.last.isCompleted, isTrue);
      expect(updates.last.outputUrl, isNotNull);
    });
  });

  group('CloudVisionController Unit Tests', () {
    test('Selects task and updates parameters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cloudVisionControllerProvider.notifier);

      notifier.selectTask(VisionTaskType.relight);
      expect(container.read(cloudVisionControllerProvider).activeTask, VisionTaskType.relight);

      notifier.updateRelightPosition(0.8, 0.2, 1.0);
      expect(container.read(cloudVisionControllerProvider).relightConfig.lightPosition, [0.8, 0.2, 1.0]);

      notifier.selectTask(VisionTaskType.skyReplace);
      notifier.selectSkyPreset(SkyPreset.defaultPresets[1]);
      expect(container.read(cloudVisionControllerProvider).selectedSky.id, SkyPreset.defaultPresets[1].id);
    });

    test('executeCurrentTask dispatches job, updates progress and decrements quota', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(cloudVisionControllerProvider.notifier);
      final initialJobsUsed = container.read(cloudVisionControllerProvider).quota.jobsUsedToday;

      await notifier.executeCurrentTask(
        videoUrl: 'https://cdn.example.com/clip.mp4',
        userId: 'creator_pro',
      );

      expect(container.read(cloudVisionControllerProvider).activeJob, isNotNull);

      // Wait briefly for stream completion in mock
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(container.read(cloudVisionControllerProvider).quota.jobsUsedToday, initialJobsUsed + 1);
    });
  });

  group('CloudVision UI Widgets & Studio Screen Tests', () {
    testWidgets('RotoscopePromptSheet renders prompt field, chips and CTA', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Scaffold(
            body: RotoscopePromptSheet(onExecute: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Natural-Language Rotoscoping'), findsOneWidget);
      expect(find.text('Isolate Main Subject'), findsOneWidget);
      expect(find.text('Track Object Across Video Timeline'), findsOneWidget);
      expect(find.text('Generate AI Mask (1 Credit)'), findsOneWidget);
    });

    testWidgets('AiEnhanceSheet renders 4 modes and CTA', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Scaffold(
            body: AiEnhanceSheet(onExecute: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Visual Enhancement'), findsOneWidget);
      expect(find.text('2x HD Upscale'), findsOneWidget);
      expect(find.text('4x Ultra Upscale'), findsOneWidget);
      expect(find.text('Neural Denoise'), findsOneWidget);
      expect(find.text('60 FPS Smooth Flow'), findsOneWidget);
    });

    testWidgets('RelightSheet renders light position pad and color presets', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Scaffold(
            body: RelightSheet(onExecute: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Neural 3D Relighting'), findsOneWidget);
      expect(find.text('Light Source Position (X / Y)'), findsOneWidget);
      expect(find.text('Intensity'), findsOneWidget);
      expect(find.text('Apply Relighting (1 Credit)'), findsOneWidget);
    });

    testWidgets('SkyReplacementSheet renders presets carousel and sliders', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Scaffold(
            body: SkyReplacementSheet(onExecute: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AI Sky Replacement'), findsOneWidget);
      expect(find.text('Golden Hour Dusk'), findsOneWidget);
      expect(find.text('Horizon Line'), findsOneWidget);
      expect(find.text('Spill Blend'), findsOneWidget);
    });

    testWidgets('CloudVisionStudioScreen renders in Dark Mode with tabs and monitor', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.dark,
          child: const CloudVisionStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cloud Vision AI'), findsOneWidget);
      expect(find.text('16/20 Credits'), findsOneWidget);
      expect(find.text('Rotoscope'), findsOneWidget);
      expect(find.text('AI Enhance'), findsOneWidget);
      expect(find.text('Relight 3D'), findsOneWidget);
      expect(find.text('Sky Replace'), findsOneWidget);
      expect(find.text('4K Source Timeline Monitor'), findsOneWidget);
      expect(find.text('Hold Compare'), findsOneWidget);
    });

    testWidgets('CloudVisionStudioScreen renders in Light Mode without layout issues', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.light,
          child: const CloudVisionStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cloud Vision AI'), findsOneWidget);
      expect(find.text('Rotoscope'), findsOneWidget);
    });

    testWidgets('Tapping task tabs switches the configuration sheet', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const CloudVisionStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Generate AI Mask (1 Credit)'), findsOneWidget);

      await tester.tap(find.text('AI Enhance'));
      await tester.pumpAndSettle();
      expect(find.text('Start AI Enhance (1 Credit)'), findsOneWidget);

      await tester.tap(find.text('Relight 3D'));
      await tester.pumpAndSettle();
      expect(find.text('Apply Relighting (1 Credit)'), findsOneWidget);

      await tester.tap(find.text('Sky Replace'));
      await tester.pumpAndSettle();
      expect(find.text('Replace Sky & Blend (1 Credit)'), findsOneWidget);
    });
  });
}
