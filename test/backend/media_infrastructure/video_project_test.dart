import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oneova/backend/media_infrastructure/models/video_project_models.dart';
import 'package:oneova/backend/media_infrastructure/services/video_project_service.dart';

void main() {
  late VideoProjectService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = VideoProjectService();
  });

  test('Project creation saves incrementally', () async {
    await service.createProject('user123', 'My Epic Video');
    
    final current = service.currentProject;
    expect(current, isNotNull);
    expect(current!.name, 'My Epic Video');
    
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('video_project_${current.id}');
    expect(savedJson, isNotNull);
    expect(savedJson, contains('My Epic Video'));
  });

  test('Trim operation modifies timeline but not original media id', () async {
    await service.createProject('user123', 'My Epic Video');
    
    final track = Track(type: TrackType.video);
    service.addTrack(track);
    
    final clip = Clip(
      sourceMediaId: 'raw_video_1',
      sourceStartTime: const Duration(seconds: 0),
      sourceEndTime: const Duration(seconds: 10),
      timelineStartTime: const Duration(seconds: 0),
    );
    service.addClip(track.id, clip);
    
    // Original duration is 10s
    expect(service.currentProject!.timeline.tracks.first.clips.first.duration.inSeconds, 10);
    
    // Trim from 2s to 8s (duration = 6s)
    service.trimClip(track.id, clip.id, const Duration(seconds: 2), const Duration(seconds: 8));
    
    final updatedClip = service.currentProject!.timeline.tracks.first.clips.first;
    expect(updatedClip.duration.inSeconds, 6);
    expect(updatedClip.sourceMediaId, 'raw_video_1'); // Non-destructive
  });

  test('Split operation duplicates non-destructively', () async {
    await service.createProject('user123', 'My Epic Video');
    final track = Track(type: TrackType.video);
    service.addTrack(track);
    
    final clip = Clip(
      sourceMediaId: 'raw_video_2',
      sourceStartTime: const Duration(seconds: 0),
      sourceEndTime: const Duration(seconds: 10),
      timelineStartTime: const Duration(seconds: 0),
    );
    service.addClip(track.id, clip);
    
    // Split at 4 seconds
    service.splitClip(track.id, clip.id, const Duration(seconds: 4));
    
    final clips = service.currentProject!.timeline.tracks.first.clips;
    expect(clips.length, 2);
    
    // Part 1: 0s -> 4s
    expect(clips[0].sourceStartTime.inSeconds, 0);
    expect(clips[0].sourceEndTime.inSeconds, 4);
    
    // Part 2: 4s -> 10s
    expect(clips[1].sourceStartTime.inSeconds, 4);
    expect(clips[1].sourceEndTime.inSeconds, 10);
    
    // Timeline start times should offset properly
    expect(clips[0].timelineStartTime.inSeconds, 0);
    expect(clips[1].timelineStartTime.inSeconds, 4);
  });

  test('Undo and Redo preserve edit history and original media', () async {
    await service.createProject('user123', 'My Epic Video');
    final track = Track(type: TrackType.video);
    service.addTrack(track);
    
    final clip = Clip(
      sourceMediaId: 'raw_video_3',
      sourceStartTime: const Duration(seconds: 0),
      sourceEndTime: const Duration(seconds: 10),
      timelineStartTime: const Duration(seconds: 0),
    );
    service.addClip(track.id, clip);
    
    // Ensure we can undo adding the clip
    expect(service.currentProject!.timeline.tracks.first.clips.length, 1);
    
    service.undo();
    expect(service.currentProject!.timeline.tracks.first.clips.length, 0);
    
    service.redo();
    expect(service.currentProject!.timeline.tracks.first.clips.length, 1);
  });

  test('Test project restoration after application restart', () async {
    await service.createProject('user123', 'My Epic Video');
    final track = Track(type: TrackType.video);
    service.addTrack(track);
    final clip = Clip(
      sourceMediaId: 'raw_video_4',
      sourceStartTime: const Duration(seconds: 0),
      sourceEndTime: const Duration(seconds: 10),
      timelineStartTime: const Duration(seconds: 0),
    );
    service.addClip(track.id, clip);
    
    final originalProjectId = service.currentProject!.id;
    
    // Simulate App Restart by instantiating a new service
    final restartedService = VideoProjectService();
    await restartedService.loadProject(originalProjectId);
    
    expect(restartedService.currentProject, isNotNull);
    expect(restartedService.currentProject!.id, originalProjectId);
    expect(restartedService.currentProject!.timeline.tracks.length, 1);
    expect(restartedService.currentProject!.timeline.tracks.first.clips.length, 1);
    expect(restartedService.currentProject!.timeline.tracks.first.clips.first.sourceMediaId, 'raw_video_4');
  });
}
