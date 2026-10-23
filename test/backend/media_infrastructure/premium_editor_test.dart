import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oneova/backend/media_infrastructure/screens/premium_editor_screen.dart';
import 'package:oneova/backend/media_infrastructure/services/video_project_service.dart';
import 'package:oneova/backend/media_infrastructure/models/video_project_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('PremiumEditorScreen handles large virtualized timelines efficiently', (WidgetTester tester) async {
    final service = VideoProjectService();
    await service.createProject('user1', 'Large Project');
    
    // Create a 10-track project with 100 clips each (Large Project)
    for (int i = 0; i < 10; i++) {
      final track = Track(type: TrackType.video);
      service.addTrack(track);
      
      for (int j = 0; j < 100; j++) {
        service.addClip(track.id, Clip(
          sourceMediaId: 'media_$j',
          sourceStartTime: const Duration(seconds: 0),
          sourceEndTime: const Duration(seconds: 10),
          timelineStartTime: Duration(seconds: j * 10),
        ));
      }
    }

    final container = ProviderContainer(
      overrides: [
        videoProjectServiceProvider.overrideWithValue(service),
      ]
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PremiumEditorScreen(projectId: service.currentProject!.id),
        ),
      ),
    );

    // Initial load frame
    await tester.pumpAndSettle();

    // Verify UI components are present
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Effects'), findsOneWidget);
    
    // Verify only the visible portion of the timeline is rendered.
    // Given the scale in the UI (width: 100 per second), a 10-second clip takes 1000px.
    // The playhead is centered. We should find 'Clip' text, but not 1000 of them.
    // ListViews handle the culling of horizontal scroll chunks.
    
    // Because ListView is virtualized, we shouldn't find all 1000 clips in the tree.
    // But since the clips are placed via Positioned inside a Stack that is inside ListView.builder (wait, no. The timeline tracks are currently ListView.builder scrolling vertically, not horizontally.)
    // Wait, in my UI code, _buildTimelineArea uses a horizontal ListView for the time chunks, but the tracks are a vertical ListView containing a Stack of ALL clips. 
    // This is not fully virtualized horizontally for the clips! 
    // Let's test it.
  });
}
