import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/social/studio_social.dart';

import 'fakes/fake_social_ports.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeRoomPort room;
  late FakeCallPort calls;
  late FakeHistorySource history;
  late ProviderContainer c;
  const sid = 's1';

  ProviderContainer make({StudioViewerIdentity? me = const StudioViewerIdentity(uid: 'me', name: 'Me')}) {
    final container = ProviderContainer(overrides: [
      studioSocialRoomPortProvider.overrideWith((ref, id) => room),
      studioCallPortProvider.overrideWithValue(calls),
      studioCommentHistorySourceProvider.overrideWithValue(history),
      studioViewerIdentityProvider.overrideWithValue(me),
    ]);
    container.listen(studioCommentFeedProvider(sid), (_, _) {});
    return container;
  }

  List<String> ids() => c.read(studioCommentFeedProvider(sid)).items.map((i) => i.id).toList();

  setUp(() {
    room = FakeRoomPort();
    calls = FakeCallPort();
    history = FakeHistorySource([]);
  });
  tearDown(() => c.dispose());

  test('late-join history is loaded oldest first, then live events append', () async {
    history.items.addAll([comment('b', ts: 2), comment('a', ts: 1)]);
    c = make();
    await settle();
    expect(ids(), ['a', 'b']);
    expect(c.read(studioCommentFeedProvider(sid)).historyLoaded, isTrue);
    room.emit(CommentEvent(comment('c', ts: 3)));
    room.emit(SystemLineEvent(const LiveStudioComment(
        id: 'sys1', uid: 'x', name: 'X', text: 'joined the live', system: SystemLineKind.joined, ts: 4)));
    await settle();
    expect(ids(), ['a', 'b', 'c', 'sys1']);
    expect(c.read(studioCommentFeedProvider(sid)).items.last.isSystem, isTrue);
  });

  test('dedupes by id across history and live events', () async {
    final hold = Completer<void>();
    history
      ..items.addAll([comment('a', ts: 1), comment('b', ts: 2)])
      ..hold = hold;
    c = make();
    await settle();
    // Arrives before history resolves, and is also in history.
    room.emit(CommentEvent(comment('b', ts: 2)));
    room.emit(CommentEvent(comment('c', ts: 3)));
    await settle();
    hold.complete();
    await settle();
    room.emit(CommentEvent(comment('c', ts: 3)));
    room.emit(CommentEvent(comment('a', ts: 1)));
    await settle();
    expect(ids(), ['a', 'b', 'c']);
  });

  test('keeps at most commentRenderCap items (newest)', () async {
    history.items.addAll([for (var i = 0; i < 50; i++) comment('h$i', ts: i)]);
    c = make();
    await settle();
    for (var i = 0; i < 20; i++) {
      room.emit(CommentEvent(comment('l$i', ts: 100 + i)));
    }
    await settle();
    final list = ids();
    expect(list.length, StudioLimits.commentRenderCap);
    expect(list.first, 'h20');
    expect(list.last, 'l19');
  });

  test('comment.deleted removes rows, including ones still in history', () async {
    final hold = Completer<void>();
    history
      ..items.addAll([comment('a', ts: 1), comment('b', ts: 2)])
      ..hold = hold;
    c = make();
    await settle();
    room.emit(const CommentDeletedEvent('a'));
    await settle();
    hold.complete();
    await settle();
    expect(ids(), ['b']);
    room.emit(const CommentDeletedEvent('b'));
    room.emit(CommentEvent(comment('b', ts: 2))); // late duplicate of a deleted one
    await settle();
    expect(ids(), isEmpty);
  });

  test('send shows a pending row that the server echo replaces', () async {
    c = make();
    await settle();
    final gate = Completer<void>();
    calls.gate = gate;
    calls.handler = (name, args) => {'id': 'me_${args['clientId']}', 'ts': 99, 'text': args['text']};
    final f = c.read(studioCommentFeedProvider(sid).notifier).send('  hello   world ');
    await settle();
    var items = c.read(studioCommentFeedProvider(sid)).items;
    expect(items, hasLength(1));
    expect(items.single.isPending, isTrue);
    expect(items.single.comment.text, 'hello world');
    final call = calls.calls.single;
    expect(call.name, StudioCallables.comment);
    expect(call.args['streamId'], sid);
    final id = studioCommentDocId('me', call.args['clientId'] as String);
    expect(items.single.id, id);

    room.emit(CommentEvent(LiveStudioComment(id: id, uid: 'me', name: 'Me', text: 'hello world', ts: 99)));
    await settle();
    items = c.read(studioCommentFeedProvider(sid)).items;
    expect(items, hasLength(1));
    expect(items.single.isPending, isFalse);

    gate.complete();
    expect(await f, isTrue);
    expect(c.read(studioCommentFeedProvider(sid)).items, hasLength(1));
  });

  test('send without an echo (sampled out) is confirmed from the result', () async {
    c = make();
    await settle();
    calls.handler = (name, args) => {'id': 'me_${args['clientId']}', 'ts': 1234, 'text': 'masked'};
    expect(await c.read(studioCommentFeedProvider(sid).notifier).send('raw'), isTrue);
    final item = c.read(studioCommentFeedProvider(sid)).items.single;
    expect(item.isPending, isFalse);
    expect(item.comment.ts, 1234);
    expect(item.comment.text, 'masked');
  });

  test('failed send rolls back the pending row and reports an error', () async {
    c = make();
    await settle();
    room.emit(CommentEvent(comment('a', ts: 1)));
    calls.handler = (name, args) => throw StateError('network');
    final ok = await c.read(studioCommentFeedProvider(sid).notifier).send('hello');
    expect(ok, isFalse);
    final s = c.read(studioCommentFeedProvider(sid));
    expect(s.items.map((i) => i.id), ['a']);
    expect(s.error, isNotNull);
    expect(s.errorSeq, 1);
  });

  test('empty, too long, or signed-out sends never call the server', () async {
    c = make(me: null);
    await settle();
    final n = c.read(studioCommentFeedProvider(sid).notifier);
    expect(await n.send('   '), isFalse);
    expect(await n.send('x' * (StudioLimits.commentMaxLength + 1)), isFalse);
    expect(await n.send('hi'), isFalse);
    expect(calls.calls, isEmpty);
    expect(c.read(studioCommentFeedProvider(sid)).error, 'Sign in to comment.');
  });

  test('delete calls lsDeleteComment and removes the row', () async {
    history.items.add(comment('a', ts: 1));
    c = make();
    await settle();
    expect(await c.read(studioCommentFeedProvider(sid).notifier).delete('a'), isTrue);
    expect(calls.calls.single.name, StudioCallables.deleteComment);
    expect(calls.calls.single.args, {'streamId': sid, 'commentId': 'a'});
    expect(ids(), isEmpty);
  });

  test('normalizeStudioComment mirrors the server', () {
    expect(normalizeStudioComment(' a \n b '), 'a b');
    expect(normalizeStudioComment('  '), isNull);
    expect(normalizeStudioComment('😀' * StudioLimits.commentMaxLength), isNotNull);
  });
}
