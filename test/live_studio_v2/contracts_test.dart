import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';

void main() {
  StudioState sample() => StudioState(
        streamId: 's1',
        hostId: 'host',
        title: 'Single Searching',
        status: StudioStatus.live,
        seq: 7,
        settings: const StudioSettings(guestSize: GuestSize.l, frameWidth: 6),
        stage: const StageLayout(
          centerUid: 'host',
          wall: ['g1', 'g2', null, 'g4', 'g5', 'g6'],
          overflow: ['g7'],
          pinnedUid: 'g1',
        ),
        table: const TableState(
          mode: TableMode.movie,
          watch: WatchParty(
              catalogId: 'c1', state: PlaybackState.playing, positionMs: 1000, anchorServerMs: 5000),
        ),
        counts: const StudioCounts(viewers: 200000, participants: 36),
      );

  test('StudioState JSON round-trip', () {
    final s = sample();
    final back = StudioState.fromJson(s.toJson());
    expect(back.toJson(), s.toJson());
  });

  test('unknown enum wires fall back to safe defaults', () {
    final s = StudioState.fromJson({
      'streamId': 's',
      'hostId': 'h',
      'status': 'exploded',
      'settings': {'guestSize': 'xl', 'frameWidth': 99, 'studioDim': 5, 'speakerMode': '?'},
      'stage': {'centerUid': 'h', 'wall': ['a']},
      'table': {'mode': 'karaoke'},
    });
    expect(s.status, StudioStatus.preparing);
    expect(s.settings.guestSize, GuestSize.m);
    expect(s.settings.frameWidth, StudioLimits.frameWidthMax);
    expect(s.settings.studioDim, StudioLimits.studioDimMax);
    expect(s.settings.speakerMode, SpeakerMode.hostPinned);
    expect(s.stage.wall.length, StudioLimits.wallSlots);
    expect(s.table.mode, TableMode.goods);
  });

  test('light defaults use the grey-blue frame and no dim', () {
    final d = StudioSettings.defaultsFor(StudioTheme.light);
    expect(d.frameColor, '#3B4763');
    expect(d.studioDim, 0);
    expect(StudioSettings.fromJson({'theme': 'light'}).frameColor, '#3B4763');
  });

  test('slot mapping is orientation-independent order', () {
    final st = sample().stage;
    expect(st.slotIdFor('g1', phone: false), 'L1');
    expect(st.slotIdFor('g1', phone: true), 'PL1');
    expect(st.slotIdFor('g4', phone: false), 'R1');
    expect(st.slotIdFor('g5', phone: true), isNull);
    expect(st.phoneOffWall, ['g5', 'g6', 'g7']);
    expect(st.publishers, ['host', 'g1', 'g2', 'g4', 'g5', 'g6', 'g7']);
  });

  test('watch party target position', () {
    const w = WatchParty(
        catalogId: 'c', state: PlaybackState.playing, positionMs: 1000, rate: 1, anchorServerMs: 5000);
    expect(w.targetPositionMs(7500), 3500);
    const p = WatchParty(catalogId: 'c', state: PlaybackState.paused, positionMs: 1000);
    expect(p.targetPositionMs(99999), 1000);
  });

  test('events decode and patch apply', () {
    final s = sample();
    final e = StudioEvent.decode(StudioTopics.state, {
      'v': 1,
      'type': 'state.patch',
      'seq': 8,
      'path': 'table',
      'value': {'mode': 'match'},
    });
    expect(e, isA<StatePatchEvent>());
    final p = e as StatePatchEvent;
    final next = s.applyPatch(p.seq, p.path, p.value);
    expect(next.seq, 8);
    expect(next.table.mode, TableMode.match);
    expect(next.stage.toJson(), s.stage.toJson());

    final sys = StudioEvent.decode(StudioTopics.chat,
        {'type': 'system', 'id': 'x', 'uid': 'u', 'name': 'lee', 'kind': 'joined', 'ts': 1});
    expect((sys as SystemLineEvent).line.system, SystemLineKind.joined);
    expect(StudioEvent.decode('x', {'type': 'future.thing'}), isA<UnknownEvent>());
  });

  test('gaming preset and gameTitle round-trip; unknown preset → studio', () {
    final g = sample().copyWith(
      settings: const StudioSettings(layoutPreset: LayoutPreset.gaming),
      gameTitle: 'Ludo',
    );
    final back = StudioState.fromJson(g.toJson());
    expect(back.toJson(), g.toJson());
    expect(back.isGaming, isTrue);
    expect(back.gameTitle, 'Ludo');
    expect(g.toJson()['settings']['layoutPreset'], 'gaming');

    // Old docs (no layoutPreset / gameTitle) still parse.
    final old = StudioState.fromJson({'streamId': 's', 'hostId': 'h', 'stage': {'centerUid': 'h'}});
    expect(old.settings.layoutPreset, LayoutPreset.studio);
    expect(old.gameTitle, isNull);
    expect(old.toJson().containsKey('gameTitle'), isFalse);
    expect(StudioSettings.fromJson({'layoutPreset': 'arena'}).layoutPreset, LayoutPreset.studio);

    final long = StudioState.fromJson({
      'streamId': 's',
      'hostId': 'h',
      'gameTitle': '  ${'x' * 80}  ',
      'stage': {'centerUid': 'h'},
    });
    expect(long.gameTitle!.length, kGameTitleMaxLength);
    expect(sample().applyPatch(9, 'gameTitle', 'Free Fire').gameTitle, 'Free Fire');
  });
}
