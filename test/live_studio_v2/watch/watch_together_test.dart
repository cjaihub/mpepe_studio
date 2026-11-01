import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/watch/studio_watch.dart';
import 'package:oneova/social_hub/live/studio_v2/shell/shell_widgets.dart';
import 'package:oneova/social_hub/live/studio_v2/shell/stage_panel_grid.dart';
import 'package:oneova/social_hub/live/studio_v2/watch/watch_layer.dart';

void main() {
  group('youTubeIdFrom', () {
    const id = 'dQw4w9WgXcQ';
    test('accepts links and bare ids', () {
      for (final s in [
        id,
        'https://www.youtube.com/watch?v=$id&t=42',
        'youtube.com/watch?v=$id',
        'https://m.youtube.com/watch?v=$id',
        'https://youtu.be/$id?si=x',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id',
        'https://music.youtube.com/watch?v=$id',
      ]) {
        expect(youTubeIdFrom(s), id, reason: s);
      }
    });
    test('rejects everything else', () {
      for (final s in ['', 'lofi beats', 'https://vimeo.com/123', 'https://www.youtube.com/@channel', 'https://youtu.be/short']) {
        expect(youTubeIdFrom(s), isNull, reason: s);
      }
    });
  });

  test('watchUrlFromInput: addresses become https, words become a search', () {
    expect(watchUrlFromInput('wikipedia.org'), 'https://wikipedia.org');
    expect(watchUrlFromInput('http://example.com/a'), 'https://example.com/a');
    expect(watchUrlFromInput('https://example.com'), 'https://example.com');
    expect(watchUrlFromInput('best pizza near me'), startsWith('https://www.google.com/search?q=best+pizza'));
    expect(watchUrlFromInput('   '), '');
  });

  group('WatchLayer.fromJson', () {
    test('youtube layer and its target position', () {
      final l = WatchLayer.fromJson({
        'kind': 'youtube',
        'youtube': {'videoId': 'dQw4w9WgXcQ', 'title': 'Song'},
        'state': 'playing',
        'positionMs': 1000,
        'rate': 1.5,
        'anchorServerMs': 10000,
        'by': 'host',
      })!;
      expect(l.isYouTube, isTrue);
      expect(l.targetPositionMs(12000), 4000);
      expect(l.party.state, PlaybackState.playing);
    });
    test('empty / stopped / unsafe docs are no layer', () {
      expect(WatchLayer.fromJson(null), isNull);
      expect(WatchLayer.fromJson({'kind': null}), isNull);
      expect(WatchLayer.fromJson({'kind': 'browser', 'browser': {'url': 'http://x.com'}}), isNull);
      expect(WatchLayer.fromJson({'kind': 'browser', 'browser': {'url': 'https://x.com'}})!.url, 'https://x.com');
    });
  });

  test('stage panel grid: 1–10 people', () {
    expect([for (var n = 1; n <= 10; n++) stagePanelColumns(n, phone: true)], [1, 2, 2, 2, 2, 2, 3, 3, 3, 3]);
    expect([for (var n = 1; n <= 10; n++) stagePanelColumns(n, phone: false)], [1, 2, 2, 2, 3, 3, 4, 4, 5, 5]);
    expect(studioWorldCapacity(phone: true), 5);
    expect(studioWorldCapacity(phone: false), 7);
    const full = StageLayout(centerUid: 'h', wall: ['a', 'b', 'c', 'd', 'e', 'f'], overflow: ['x', 'y', 'z']);
    expect(full.headcount, StudioLimits.maxOnStage);
    expect(full.isFull, isTrue);
  });

  test('mentions: query at the cursor and handles', () {
    TextEditingValue at(String s) => TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
    expect(liveMentionQueryAt(at('hi @am')), 'am');
    expect(liveMentionQueryAt(at('@')), '');
    expect(liveMentionQueryAt(at('mail a@b')), isNull);
    expect(liveMentionQueryAt(at('hello')), isNull);
    expect(liveMentionHandle('Amina K.'), 'AminaK.');
    expect(kLiveMentionRe.allMatches('hey @Amina and @Jo!').map((m) => m.group(0)), ['@Amina', '@Jo!']);
  });
}
