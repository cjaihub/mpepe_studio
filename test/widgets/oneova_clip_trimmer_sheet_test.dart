import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/create/widgets/oneova_clip_trimmer_sheet.dart';
import 'package:oneova/backend/projects/models/oneova_draft_model.dart';

void main() {
  group('OneovaTrimmedMediaResult & Draft Ingest Tests', () {
    test('Calculates trimmed effective duration with speed multipliers', () {
      final result = OneovaTrimmedMediaResult(
        file: File('/tmp/sample_video.mp4'),
        isVideo: true,
        startSeconds: 5.0,
        endSeconds: 20.0,
        totalDurationSeconds: 60.0,
        speed: 1.5,
        aspectRatio: 9 / 16,
        isFullClip: false,
      );

      // (20.0 - 5.0) / 1.5 = 10.0 seconds
      expect(result.trimmedDuration, closeTo(10.0, 0.01));
      expect(result.isFullClip, isFalse);
      expect(result.aspectRatio, closeTo(9 / 16, 0.001));
    });

    test('Full clip calculations honor total duration and speed', () {
      final fullClip = OneovaTrimmedMediaResult(
        file: File('/tmp/sample_video.mp4'),
        isVideo: true,
        totalDurationSeconds: 45.0,
        speed: 2.0,
        isFullClip: true,
      );

      // 45.0 / 2.0 = 22.5 seconds
      expect(fullClip.trimmedDuration, closeTo(22.5, 0.01));
      expect(fullClip.isFullClip, isTrue);
    });

    test('OneovaDraft effective duration correctly reflects trim range and speed', () {
      final draft = OneovaDraft(
        id: 'draft_test_01',
        title: 'Oneova Cine Test Project',
        mediaPath: '/tmp/test_clip.mp4',
        isVideo: true,
        durationSeconds: 120.0,
        trimStartSeconds: 10.0,
        trimEndSeconds: 40.0,
        speedMultiplier: 1.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // (40.0 - 10.0) / 1.0 = 30.0 seconds
      expect(draft.effectiveDuration, equals(30.0));

      final fastDraft = draft.copyWith(speedMultiplier: 2.0);
      // (40.0 - 10.0) / 2.0 = 15.0 seconds
      expect(fastDraft.effectiveDuration, equals(15.0));
    });
  });

  group('OneovaClipTrimmerSheet Widget Tests', () {
    testWidgets('Renders OneovaClipTrimmerSheet with transport controls & import CTA',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneovaClipTrimmerSheet(
              videoFile: File('/tmp/mock_footage.mp4'),
              clipTitle: 'Cinematic_Roll_01.mp4',
              actionLabel: 'Import to Timeline',
            ),
          ),
        ),
      );

      // Verify Clip Title is rendered
      expect(find.text('Cinematic_Roll_01.mp4'), findsOneWidget);

      // Verify Header & Badge
      expect(find.text('Trim Video Clip'), findsOneWidget);
      expect(find.text('PRE-INGEST'), findsOneWidget);

      // Verify Action Label
      expect(find.text('Import to Timeline'), findsOneWidget);

      // Verify Full Clip button
      expect(find.text('Full Clip'), findsWidgets);

      // Verify Preset chips
      expect(find.text('15s Reel'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('60s'), findsOneWidget);

      // Verify Aspect Ratio and Audio toggles
      expect(find.text('Aspect: 9:16'), findsOneWidget);
      expect(find.text('Audio On'), findsOneWidget);

      // Verify Speed chips
      expect(find.text('0.5x'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);
    });
  });
}
