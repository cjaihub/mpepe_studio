import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/projects/editor/timeline_controller.dart';
import 'package:oneova/backend/projects/editor/commands/clip_commands.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';

void main() {
  group('TimelineController Tests', () {
    late Sequence sequence;
    late TimelineController controller;
    late Track trackV1;
    late Clip clip1;

    setUp(() {
      clip1 = Clip(
        id: 'clip-1',
        sourceMediaId: 'media-1',
        type: MediaType.video,
        startTime: 0.0,
        duration: 5.0,
        sourceStart: 0.0,
      );

      trackV1 = Track(
        id: 'track-v1',
        name: 'V1',
        type: TrackType.video,
        clips: [clip1],
      );

      sequence = Sequence(
        id: 'seq-1',
        name: 'Main Sequence',
        settings: const ProjectSettings(width: 1080, height: 1920, frameRate: 30.0),
        tracks: [trackV1],
      );

      controller = TimelineController(sequence);
    });

    test('Trimming clip start reduces duration and adjusts sourceStart', () {
      final command = TrimClipCommand(
        trackId: trackV1.id,
        clipId: clip1.id,
        oldStartTime: clip1.startTime,
        newStartTime: 2.0, // trimmed 2 seconds from the start
        oldDuration: clip1.duration,
        newDuration: 3.0,
        oldSourceStart: clip1.sourceStart,
        newSourceStart: 2.0,
      );

      controller.execute(command);

      expect(clip1.startTime, 2.0);
      expect(clip1.duration, 3.0);
      expect(clip1.sourceStart, 2.0);
    });

    test('Undo and Redo restore clip trim state', () {
      final command = TrimClipCommand(
        trackId: trackV1.id,
        clipId: clip1.id,
        oldStartTime: clip1.startTime,
        newStartTime: 2.0,
        oldDuration: clip1.duration,
        newDuration: 3.0,
        oldSourceStart: clip1.sourceStart,
        newSourceStart: 2.0,
      );

      controller.execute(command);
      expect(controller.canUndo, true);

      controller.undo();
      expect(clip1.startTime, 0.0);
      expect(clip1.duration, 5.0);
      expect(clip1.sourceStart, 0.0);

      expect(controller.canRedo, true);
      controller.redo();
      expect(clip1.startTime, 2.0);
      expect(clip1.duration, 3.0);
      expect(clip1.sourceStart, 2.0);
    });

    test('Moving a clip prevents overlap via canMoveClip', () {
      final clip2 = Clip(
        id: 'clip-2',
        sourceMediaId: 'media-2',
        type: MediaType.video,
        startTime: 6.0,
        duration: 4.0,
        sourceStart: 0.0,
      );
      trackV1.clips.add(clip2);

      // Attempt to move clip1 to 3.0, which overlaps clip2 (starts at 6.0, clip1 is 5s long)
      // Wait, 3.0 + 5.0 = 8.0 > 6.0 (overlap)
      final canMove = controller.canMoveClip(trackV1.id, clip1.id, 3.0);
      expect(canMove, false);

      // Attempt to move to 1.0 (1.0 + 5.0 = 6.0 == clip2.start), which is fine
      final canMoveValid = controller.canMoveClip(trackV1.id, clip1.id, 1.0);
      expect(canMoveValid, true);
    });
  });
}
