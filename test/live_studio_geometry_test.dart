import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live/models/live_models.dart';
import 'package:oneova/social_hub/live/studio/live_studio_geometry.dart';
import 'package:oneova/social_hub/live/studio/live_studio_roster.dart';

void main() {
  group('homographyFromQuad', () {
    final allSlots = [
      ...kStudioGeometry.landscape.slots,
      ...kStudioGeometry.phone.slots,
    ];

    for (final slot in allSlots) {
      test('reproduces the configured matrix for ${slot.id}', () {
        final w = slot.nativeSize.width, h = slot.nativeSize.height;
        final corners = [
          slot.project(Offset.zero),
          slot.project(Offset(w, 0)),
          slot.project(Offset(w, h)),
          slot.project(Offset(0, h)),
        ];
        final rebuilt = homographyFromQuad(slot.nativeSize, corners);
        for (var i = 0; i < 16; i++) {
          expect(rebuilt[i], closeTo(slot.matrix3d[i], 1e-6),
              reason: '${slot.id}[$i]');
        }
      });
    }

    test('L1 lands on the expected wall corners', () {
      final l1 = kStudioGeometry.landscape.slots.firstWhere((s) => s.id == 'L1');
      expect(l1.project(Offset.zero).dx, closeTo(24, 0.01));
      expect(l1.project(const Offset(160, 0)).dx, closeTo(162, 0.05));
      expect(l1.project(const Offset(160, 100)).dy, closeTo(261.1, 0.1));
    });
  });

  group('StudioWorldPlacement', () {
    test('landscape scales by height and centers horizontally', () {
      final p = StudioWorldPlacement.forViewport(const Size(1440, 810));
      expect(p.isLandscape, isTrue);
      expect(p.scale, closeTo(810 / 768, 1e-9));
      expect(p.offset.dx, closeTo((1440 - 1376 * 810 / 768) / 2, 1e-9));
      expect(p.offset.dy, 0);
    });

    test('phone uses 0.66 at 390px with x=688 centered, top 30', () {
      final p = StudioWorldPlacement.forViewport(const Size(390, 844));
      expect(p.isLandscape, isFalse);
      expect(p.scale, closeTo(0.66, 1e-9));
      expect(p.offset.dx, closeTo(195 - 688 * 0.66, 1e-9));
      expect(p.offset.dy, 30);
      expect(p.worldToScreen(const Offset(688, 0)).dx, closeTo(195, 1e-9));
    });

    test('767px is phone, 768px is landscape', () {
      expect(StudioWorldPlacement.forViewport(const Size(767, 1000)).isLandscape, isFalse);
      expect(StudioWorldPlacement.forViewport(const Size(768, 1000)).isLandscape, isTrue);
    });
  });

  test('curved stage path matches the brief', () {
    expect(kStudioGeometry.landscape.stage.svgPath,
        'M0 0 Q273.5 78 547 0 L547 266 Q273.5 306 0 266 Z');
    expect(kStudioGeometry.phone.stage.svgPath,
        'M0 0 Q273.5 78 547 0 L547 104 Q273.5 138 0 104 Z');
  });

  group('buildStudioRoster', () {
    final created = DateTime(2026, 1, 1);
    LiveStream stream() => LiveStream.fromJson({
          'id': 's1',
          'hostId': 'host',
          'hostDisplayName': 'Host',
          'title': 'Show',
          'createdAt': created.toIso8601String(),
        });
    LiveParticipant guest(String id, int minute, {bool coHost = true}) =>
        LiveParticipant(
          userId: id,
          displayName: id,
          avatarUrl: '',
          isCoHost: coHost,
          role: coHost ? LiveGuestRole.coHost : LiveGuestRole.speaker,
          joinedAt: created.add(Duration(minutes: minute)),
        );

    test('host on center, guests fill walls, extras overflow', () {
      final guests = [for (var i = 0; i < 8; i++) guest('g$i', i)];
      final r = buildStudioRoster(
        stream: stream(),
        participants: guests,
        requests: const [],
        stageFocusUserId: null,
        slots: kStudioGeometry.landscape.slots,
      );
      expect(r.center!.uid, 'host');
      expect(r.wall.length, 6);
      expect(r.overflow.map((m) => m.uid), ['g6', 'g7']);
    });

    test('phone has 4 wall slots', () {
      final r = buildStudioRoster(
        stream: stream(),
        participants: [for (var i = 0; i < 6; i++) guest('g$i', i)],
        requests: const [],
        stageFocusUserId: null,
        slots: kStudioGeometry.phone.slots,
      );
      expect(r.wall.length, 4);
      expect(r.overflow.length, 2);
    });

    test('stage focus swaps a guest onto center and the host onto a wall', () {
      final r = buildStudioRoster(
        stream: stream(),
        participants: [guest('g0', 0), guest('g1', 1)],
        requests: const [],
        stageFocusUserId: 'g1',
        slots: kStudioGeometry.landscape.slots,
      );
      expect(r.center!.uid, 'g1');
      expect(r.wall.values.map((m) => m.uid), containsAll(['host', 'g0']));
    });

    test('pending or rejected speakers are not on stage', () {
      final pending = LiveParticipant(
        userId: 'p',
        displayName: 'p',
        avatarUrl: '',
        hasRequestedToJoin: true,
        role: LiveGuestRole.speaker,
        joinedAt: created,
      );
      final rejected = guest('x', 2, coHost: false); // speaker, no approval
      final r = buildStudioRoster(
        stream: stream(),
        participants: [pending, rejected],
        requests: const [],
        stageFocusUserId: null,
        slots: kStudioGeometry.landscape.slots,
      );
      expect(r.publisherIds, {'host'});
    });

    test('portrait video prefers the glass panels', () {
      final r = buildStudioRoster(
        stream: stream(),
        participants: [guest('phone', 0)],
        requests: const [],
        stageFocusUserId: null,
        slots: kStudioGeometry.landscape.slots,
        isPortraitVideo: (uid) => uid == 'phone',
      );
      expect(r.assignment['LP'], 'phone');
    });

    test('assignment is sticky across updates', () {
      final first = buildStudioRoster(
        stream: stream(),
        participants: [guest('a', 0), guest('b', 1)],
        requests: const [],
        stageFocusUserId: null,
        slots: kStudioGeometry.landscape.slots,
      );
      final bSlot = first.assignment.entries.firstWhere((e) => e.value == 'b').key;
      final second = buildStudioRoster(
        stream: stream(),
        participants: [guest('b', 1)], // 'a' left
        requests: const [],
        stageFocusUserId: null,
        slots: kStudioGeometry.landscape.slots,
        previous: first.assignment,
      );
      expect(second.assignment[bSlot], 'b');
    });
  });
}
