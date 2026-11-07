import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/create/studio/models/studio_project.dart';
import 'package:oneova/create/studio/services/studio_agent.dart';
import 'package:oneova/create/studio/services/studio_clip_tools.dart';
import 'package:oneova/create/studio/services/studio_faces.dart';

StudioClip _video({int start = 0, int end = 10000, int source = 20000}) =>
    StudioClip.create(path: '/v.mp4', isImage: false, durationMs: source, width: 1080, height: 1920, startMs: start, endMs: end);

void main() {
  test('retouch survives json and knows when it needs faces', () {
    final c = _video().copyWith(retouch: const StudioRetouch(smooth: 0.5, slim: 0.3), voiceClean: 0.7);
    final back = StudioClip.fromJson(c.toJson());
    expect(back.retouch.smooth, 0.5);
    expect(back.retouch.slim, 0.3);
    expect(back.retouch.needsFaces, isTrue);
    expect(back.voiceClean, 0.7);
    expect(const StudioRetouch(smooth: 0.4).needsFaces, isFalse);
    expect(const StudioRetouch().params.length, 10);
  });

  test('faces map through crop, flip and rotation', () {
    const f = StudioFace(0.25, 0.5, 0.1, 0.2, 0.2, 0.45, 0.3, 0.45, 0.25, 0.55, 0.25, 0.65, 0.05);
    final cropped = f.toClipFrame(_video().copyWith(crop: const StudioCrop(l: 0, t: 0, r: 0.5, b: 1)));
    expect(cropped.cx, closeTo(0.5, 1e-9));
    expect(cropped.rx, closeTo(0.2, 1e-9));
    final flipped = f.toClipFrame(_video().copyWith(flipH: true));
    expect(flipped.cx, closeTo(0.75, 1e-9));
    final turned = f.toClipFrame(_video().copyWith(rotation: 90));
    expect(turned.cx, closeTo(0.5, 1e-9));
    expect(turned.cy, closeTo(0.25, 1e-9));
    expect(turned.rx, closeTo(0.2, 1e-9));
    expect(turned.ry, closeTo(0.1, 1e-9));
  });

  test('face shader data interpolates over time', () {
    const a = StudioFace(0.2, 0.5, 0.1, 0.1, 0.18, 0.45, 0.22, 0.45, 0.2, 0.5, 0.2, 0.6, 0.03);
    const b = StudioFace(0.4, 0.5, 0.1, 0.1, 0.38, 0.45, 0.42, 0.45, 0.4, 0.5, 0.4, 0.6, 0.03);
    final track = StudioFaceTrack(const [0, 1000], const [[a], [b]]);
    final mid = StudioFaceTracker.shaderAt(_video(), track, 500);
    expect(mid[0], 1);
    expect(mid[1], closeTo(0.3, 1e-9));
    expect(mid[16], 0);
    final spec = StudioFaceTracker.exportSpec(_video().copyWith(retouch: const StudioRetouch(smooth: 1)), track);
    expect((spec['keysMs'] as List).length, 2);
    expect((spec['faces'] as List).length, 64);
  });

  test('cut to beats lands clip ends on beats', () {
    final p = StudioProject.create(isPhoto: false, clips: [_video(), _video(), _video()]);
    final music = StudioAudio.create(path: '/m.mp3', title: 'm', durationMs: 60000).copyWith(beatsMs: [1000, 2000, 3000, 4000, 5000, 6000]);
    final cut = StudioClipTools.cutToBeats(p, music);
    expect(cut.clips[0].outDurationMs, 1000);
    expect(cut.clipStartMs(1) + cut.clips[1].outDurationMs, 2000);
    expect(cut.clipStartMs(2) + cut.clips[2].outDurationMs, 3000);
  });

  test('agent exposes the documented actions', () {
    for (final a in ['look', 'retouch', 'beauty', 'add_text', 'add_effect', 'voice_clean', 'reverse', 'beat_sync', 'trim']) {
      expect(StudioAgent.editActions, contains(a));
    }
  });
}
