import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/create/studio/models/studio_project.dart';
import 'package:oneova/create/studio/services/studio_stabilizer.dart';

StudioClip _video({int start = 0, int end = 4000}) =>
    StudioClip.create(path: '/v.mp4', isImage: false, durationMs: 10000, width: 1920, height: 1080, startMs: start, endMs: end);

void main() {
  test('overlay from a clip respects the room left on the timeline', () {
    final o = StudioOverlay.fromClip(_video(start: 1000, end: 9000), offsetMs: 2000, maxMs: 3000);
    expect(o.durationMs, 3000);
    expect(o.endOnTimeline, 5000);
    expect(o.aspect, closeTo(16 / 9, 1e-9));
    final back = StudioOverlay.fromJson(o.copyWith(scale: 0.6, rotation: 12, opacity: 0.8).toJson());
    expect(back.scale, 0.6);
    expect(back.rotation, 12);
    expect(back.opacity, 0.8);
    final p = StudioProject.create(isPhoto: false, clips: [_video()]).copyWith(overlays: [o]);
    expect(StudioProject.fromJson(p.toJson()).overlays.single.id, o.id);
  });

  test('stabilizer cancels shake and stays inside the zoom margin', () {
    // Camera jitters left/right every frame.
    final times = [for (var i = 0; i < 40; i++) i * 125];
    final xs = [for (var i = 0; i < 40; i++) i.isEven ? 0.0 : 0.02];
    final m = StudioMotion(times, xs, List.filled(40, 0.0));
    final c = _video(end: 5000).copyWith(stabilize: 1);
    final plan = StudioStabilizer.plan(c, m)!;
    final margin = (plan.zoom - 1) / (2 * plan.zoom);
    for (var i = 0; i < 40; i++) {
      expect(plan.dx[i].abs(), lessThanOrEqualTo(margin + 1e-9));
      // Correction moves each frame toward the smoothed path (~0.01).
      expect((xs[i] + plan.dx[i] - 0.01).abs(), lessThan(0.006));
    }
    expect(StudioStabilizer.plan(c.copyWith(stabilize: 0), m), isNull);
  });

  test('clip retouch, voice and stabilize settings round trip', () {
    final c = _video().copyWith(stabilize: 0.4, voiceClean: 0.6);
    final back = StudioClip.fromJson(c.toJson());
    expect(back.stabilize, 0.4);
    expect(back.voiceClean, 0.6);
  });
}
