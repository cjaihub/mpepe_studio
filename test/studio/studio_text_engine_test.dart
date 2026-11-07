import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/create/studio/models/studio_project.dart';
import 'package:oneova/create/studio/services/studio_effects.dart';
import 'package:oneova/create/studio/services/studio_text_animator.dart';
import 'package:oneova/create/studio/services/studio_text_templates.dart';

void main() {
  group('text templates', () {
    test('catalog has 100+ unique, categorized templates', () {
      final all = StudioTextTemplates.all;
      expect(all.length, greaterThanOrEqualTo(100));
      expect(all.map((t) => t.id).toSet().length, all.length);
      for (final t in all) {
        expect(StudioTextTemplates.categories, contains(t.category), reason: t.id);
        expect(t.sample.trim(), isNotEmpty, reason: t.id);
      }
      for (final c in StudioTextTemplates.categories) {
        expect(StudioTextTemplates.inCategory(c), isNotEmpty, reason: c);
      }
    });

    test('every animation id used by a template exists', () {
      final ins = StudioTextAnimator.ins.map((d) => d.id).toSet();
      final outs = StudioTextAnimator.outs.map((d) => d.id).toSet();
      final loops = StudioTextAnimator.loops.map((d) => d.id).toSet();
      for (final t in StudioTextTemplates.all) {
        expect(ins, contains(t.anim.inId), reason: t.id);
        expect(outs, contains(t.anim.outId), reason: t.id);
        expect(loops, contains(t.anim.loopId), reason: t.id);
      }
    });

    test('search finds by name, category and tag', () {
      expect(StudioTextTemplates.all.where((t) => t.matches('neon')), isNotEmpty);
      expect(StudioTextTemplates.all.where((t) => t.matches('karaoke')), isNotEmpty);
      expect(StudioTextTemplates.all.where((t) => t.matches('wedding')), isNotEmpty);
    });
  });

  group('animator', () {
    StudioText layer(StudioTextAnim anim) =>
        StudioText(id: 'a', text: 'Hello world again', startMs: 1000, endMs: 4000, anim: anim);

    test('static layers are fully visible and still', () {
      final f = StudioTextAnimator.at(layer(const StudioTextAnim()), 2000);
      expect(f.alpha, 1);
      expect(f.sx, 1);
      expect(f.dx, 0);
      expect(f.revealMode, 0);
    });

    test('fade in/out reaches the ends', () {
      final t = layer(const StudioTextAnim(inId: 'fade', outId: 'fade', inMs: 500, outMs: 500));
      expect(StudioTextAnimator.at(t, 1000).alpha, closeTo(0, 1e-9));
      expect(StudioTextAnimator.at(t, 2500).alpha, 1);
      expect(StudioTextAnimator.at(t, 4000).alpha, closeTo(0, 1e-9));
    });

    test('every in/out/loop evaluates to finite values', () {
      for (final i in StudioTextAnimator.ins) {
        for (final o in StudioTextAnimator.outs) {
          final t = layer(StudioTextAnim(inId: i.id, outId: o.id, loopId: 'pulse'));
          for (var ms = 900; ms <= 4100; ms += 37) {
            final f = StudioTextAnimator.at(t, ms);
            for (final v in [f.alpha, f.sx, f.sy, f.dx, f.dy, f.rot, f.reveal]) {
              expect(v.isFinite, isTrue, reason: '${i.id}/${o.id}@$ms');
            }
          }
        }
      }
    });

    test('typewriter reveals characters in steps', () {
      final t = layer(const StudioTextAnim(inId: 'typewriter', inMs: 1000));
      final f = StudioTextAnimator.at(t, 1500);
      final n = StudioTextAnimator.visibleUnits(t, f, 1500);
      expect(n, isNotNull);
      expect(n!, greaterThan(0));
      expect(n, lessThan(t.text.length));
    });

    test('karaoke highlights the spoken word', () {
      final t = StudioText(
        id: 'c',
        text: 'one two three',
        startMs: 0,
        endMs: 3000,
        isCaption: true,
        type: const StudioTypeStyle(highlightColor: 0xFFFFD60A),
        words: const [StudioWord('one', 0, 900), StudioWord('two', 1000, 1900), StudioWord('three', 2000, 2900)],
      );
      expect(StudioTextAnimator.activeWord(t, 500), 0);
      expect(StudioTextAnimator.activeWord(t, 1500), 1);
      expect(StudioTextAnimator.activeWord(t, 2500), 2);
      expect(StudioTextAnimator.isAnimated(t), isTrue);
    });
  });

  group('project json', () {
    test('text style, animation and words survive a round trip', () {
      final tpl = StudioTextTemplates.byId('tr_punch')!;
      final t = tpl.applyTo(StudioText.create(text: 'Hi', startMs: 0, endMs: 2000, words: const [StudioWord('Hi', 0, 500)]));
      final back = StudioText.fromJson(t.toJson());
      expect(back.type.font, tpl.type.font);
      expect(back.type.stroke, tpl.type.stroke);
      expect(back.anim.inId, tpl.anim.inId);
      expect(back.words.single.text, 'Hi');
      expect(back.templateId, 'tr_punch');
    });

    test('first-version text layers still open', () {
      final old = StudioText.fromJson({'id': 'x', 'text': 'old', 'startMs': 0, 'endMs': 1000, 'style': 'outline', 'color': 0xFFFFD60A});
      expect(old.type.color, 0xFFFFD60A);
      expect(old.type.stroke, greaterThan(0));
    });

    test('effects and looks round trip on the project', () {
      final clip = StudioClip.create(path: '/a.mp4', isImage: false, durationMs: 5000, width: 1080, height: 1920)
          .copyWith(lookId: 'teal_orange', lookIntensity: 0.6);
      final p = StudioProject.create(isPhoto: false, clips: [clip]).copyWith(
        effects: [StudioEffect.create(effectId: 'glitch', startMs: 100, endMs: 900)],
      );
      final back = StudioProject.fromJson(p.toJson());
      expect(back.effects.single.effectId, 'glitch');
      expect(back.clips.single.lookId, 'teal_orange');
      expect(back.clips.single.lookIntensity, 0.6);
    });
  });

  group('effects', () {
    test('overlapping effects go to separate passes and split per clip', () {
      final a = StudioEffect.create(effectId: 'glitch', startMs: 0, endMs: 2000);
      final b = StudioEffect.create(effectId: 'blur', startMs: 1000, endMs: 3000);
      final c = StudioEffect.create(effectId: 'vhs', startMs: 2500, endMs: 4000);
      expect(StudioEffects.passes([a, b, c]).length, 2);
      final clip2 = StudioEffects.exportPasses([a, b, c], 1500, 5000);
      final windows = clip2.expand((p) => p).toList();
      final glitch = windows.firstWhere((w) => w['type'] == 3);
      expect(glitch['startMs'], 0);
      expect(glitch['endMs'], 500);
      expect(glitch['layerOffsetMs'], 1500);
    });

    test('every effect id is unique and maps to a shader type', () {
      expect(StudioEffects.all.map((e) => e.id).toSet().length, StudioEffects.all.length);
      expect(StudioEffects.all.map((e) => e.type).toSet().length, StudioEffects.all.length);
      for (final e in StudioEffects.all) {
        expect(e.type, inInclusiveRange(1, 30));
      }
    });
  });
}
