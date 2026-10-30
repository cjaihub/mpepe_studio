import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live/models/live_models.dart';
import 'package:oneova/backend/live/services/live_service.dart';
import 'package:oneova/backend/social/models/content.dart';
import 'package:oneova/backend/social/models/story.dart';
import 'package:oneova/backend/social/services/recommendation_service.dart';
import 'package:oneova/backend/social/services/story_service.dart';

/// The fields UploadService / OmnichannelUploadEngine write to `content`.
Map<String, dynamic> uploadDoc(String authorId, {String type = 'short_video', String visibility = 'public', DateTime? at}) => {
      'authorId': authorId,
      'description': 'new post',
      'type': type,
      'mediaUrl': 'https://storage.example/$authorId.${type == 'photo' ? 'jpg' : 'mp4'}',
      'hashtags': <String>[],
      'visibility': visibility,
      'viewCount': 0,
      'likeCount': 0,
      'createdAt': Timestamp.fromDate(at ?? DateTime.now()),
    };

/// Next emission of [stream] that satisfies [test].
Future<List<T>> nextWhere<T>(Stream<List<T>> stream, bool Function(List<T>) test) =>
    stream.firstWhere(test).timeout(const Duration(seconds: 5));

void main() {
  late FakeFirebaseFirestore db;
  late RecommendationService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = RecommendationService(db);
  });

  group('For You feed (live content query)', () {
    test('a public reel from user A reaches user B without a refresh', () async {
      final feed = service.watchFeedCandidates('userB', FeedMode.forYou);
      final arrives = expectLater(
        feed,
        emitsInOrder([
          isEmpty,
          emitsThrough(predicate<List<Content>>((l) => l.length == 1 && l.single.id == 'reelA' && l.single.authorId == 'userA')),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      await db.collection('content').doc('reelA').set(uploadDoc('userA'));
      await arrives.timeout(const Duration(seconds: 5));
    });

    test('photos are included; private, burned and placeholder media are not', () async {
      await db.collection('content').doc('photo').set(uploadDoc('a', type: 'photo'));
      await db.collection('content').doc('private').set(uploadDoc('a', visibility: 'private'));
      await db.collection('content').doc('followers').set(uploadDoc('a', visibility: 'followers'));
      await db.collection('content').doc('burned').set(uploadDoc('a', visibility: 'burned_removed'));
      await db.collection('content').doc('story').set(uploadDoc('a', type: 'story'));
      await db.collection('content').doc('picsum').set({...uploadDoc('a'), 'mediaUrl': 'https://picsum.photos/1'});

      final items = await service.watchFeedCandidates('b', FeedMode.forYou).first;
      expect(items.map((c) => c.id), ['photo']);
      expect(items.single.type, ContentType.photo);
    });

    test('newest first, and a malformed doc does not empty the feed', () async {
      final now = DateTime.now();
      await db.collection('content').doc('old').set(uploadDoc('a', at: now.subtract(const Duration(hours: 2))));
      await db.collection('content').doc('new').set(uploadDoc('a', at: now));
      await db.collection('content').doc('bad').set({...uploadDoc('a'), 'mediaMetadata': 'not-a-map'});

      final items = await service.watchFeedCandidates('b', FeedMode.forYou).first;
      expect(items.map((c) => c.id), ['new', 'old']);
    });

    test('rankCandidates keeps every eligible upload and drops hidden creators', () async {
      await db.collection('users').doc('b').collection('preferences').doc('recommendations').set({
        'hiddenCreators': ['muted'],
      });
      await db.collection('content').doc('r1').set(uploadDoc('a'));
      await db.collection('content').doc('r2').set(uploadDoc('muted'));
      final candidates = await service.watchFeedCandidates('b', FeedMode.forYou).first;
      final ranked = await service.rankCandidates('b', FeedMode.forYou, candidates);
      expect(ranked.map((c) => c.id), ['r1']);
    });
  });

  group('Following feed (follow graph)', () {
    Future<void> follow(String follower, String following, {String status = 'accepted'}) =>
        db.collection('relationships').doc('${follower}_$following').set({
          'followerId': follower,
          'followingId': following,
          'status': status,
        });

    test('shows posts from accepted follows only', () async {
      await follow('b', 'a');
      await follow('b', 'p', status: 'pending');
      await db.collection('content').doc('fromA').set(uploadDoc('a'));
      await db.collection('content').doc('fromP').set(uploadDoc('p'));
      await db.collection('content').doc('fromC').set(uploadDoc('c'));

      final items = await nextWhere<Content>(service.watchFeedCandidates('b', FeedMode.following), (l) => l.isNotEmpty);
      expect(items.map((c) => c.id), ['fromA']);
    });

    test('new posts and new follows update the feed live', () async {
      await follow('b', 'a');
      List<String> ids(List<Content> l) => l.map((c) => c.id).toList();
      final updates = expectLater(
        service.watchFeedCandidates('b', FeedMode.following).map(ids),
        emitsInOrder([
          emitsThrough(['a1']),
          emitsThrough(['c1', 'a1']),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      await db.collection('content').doc('a1').set(uploadDoc('a'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await db.collection('content').doc('c1').set(uploadDoc('c', at: DateTime.now().add(const Duration(minutes: 1))));
      await follow('b', 'c');
      await updates.timeout(const Duration(seconds: 5));
    });

    test('follows more than 30 creators (chunked whereIn)', () async {
      for (var i = 0; i < 35; i++) {
        await follow('b', 'creator$i');
      }
      await db.collection('content').doc('first').set(uploadDoc('creator0'));
      await db.collection('content').doc('last').set(uploadDoc('creator34'));
      final items = await nextWhere<Content>(service.watchFeedCandidates('b', FeedMode.following), (l) => l.length == 2);
      expect(items.map((c) => c.id).toSet(), {'first', 'last'});
    });

    test('no follows → empty feed', () async {
      expect(await service.watchFeedCandidates('b', FeedMode.following).first, isEmpty);
    });
  });

  group('Live sessions', () {
    test('only live streams, most watched first, doc id fallback', () {
      final streams = LiveService.mapActiveLiveStreams([
        {'id': 's1', 'hostId': 'a', 'title': 'one', 'status': 'live', 'viewerCount': 3},
        {'id': 's2', 'hostId': 'b', 'title': 'two', 'status': 'live', 'viewerCount': 40},
        {'id': 's3', 'hostId': 'c', 'title': 'ended', 'status': 'ended', 'viewerCount': 99},
        {'id': '', 'hostId': 'd', 'title': 'no id', 'status': 'live'},
        {'id': 's5', 'hostId': 'e', 'status': 'live', 'viewerCount': 'bad'},
      ]);
      expect(streams.map((s) => s.id), ['s2', 's1']);
      expect(streams.first.status, LiveStreamStatus.live);
    });
  });

  group('Status / stories row', () {
    final now = DateTime(2026, 10, 24, 12);
    Map<String, dynamic> story(String id, String author, {required DateTime created, required DateTime expires, String lifecycle = 'active', List<String> viewers = const []}) => {
          'id': id,
          'authorId': author,
          'authorName': author,
          'mediaType': 'photo',
          'mediaUrl': 'https://x/$id.jpg',
          'createdAt': created.millisecondsSinceEpoch,
          'expiresAt': expires.millisecondsSinceEpoch,
          'lifecycle': lifecycle,
          'viewers': viewers,
        };

    test('groups active stories by author and drops expired / malformed', () {
      final groups = StoryService.groupActiveStories([
        story('a2', 'a', created: now.subtract(const Duration(hours: 1)), expires: now.add(const Duration(hours: 5))),
        story('a1', 'a', created: now.subtract(const Duration(hours: 3)), expires: now.add(const Duration(hours: 3)), viewers: ['me']),
        story('old', 'b', created: now.subtract(const Duration(hours: 30)), expires: now.subtract(const Duration(hours: 6))),
        {
          ...story('ts', 'c', created: now, expires: now),
          'createdAt': Timestamp.fromDate(now),
          'expiresAt': Timestamp.fromDate(now.add(const Duration(hours: 24))),
        },
        {...story('bad', 'd', created: now, expires: now.add(const Duration(hours: 1))), 'viewers': 'oops'},
      ], currentUserId: 'me', now: now);

      expect(groups.map((g) => g.authorId), ['a', 'c']);
      expect(groups.first.stories.map((s) => s.id), ['a1', 'a2']);
      expect(groups.first.hasUnviewed, isTrue);
    });

    test('watchFeedStories emits a new status as soon as it is written', () async {
      final service = StoryService(firestore: db);
      final arrives = expectLater(
        service.watchFeedStories(currentUserId: 'b'),
        emitsInOrder([
          isEmpty,
          emitsThrough(predicate<List<UserStoryGroup>>(
              (l) => l.length == 1 && l.single.authorId == 'a' && l.single.hasUnviewed)),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      final created = DateTime.now();
      await db.collection('stories').doc('s1').set(Story(
            id: 's1',
            authorId: 'a',
            authorName: 'A',
            authorAvatarUrl: '',
            mediaType: StoryMediaType.photo,
            mediaUrl: 'https://x/s1.jpg',
            createdAt: created,
            expiresAt: created.add(const Duration(hours: 24)),
            lifecycle: StoryLifecycle.active,
          ).toMap());
      await arrives.timeout(const Duration(seconds: 5));
    });
  });
}
