import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:oneova/backend/social/models/relationship.dart';
import 'package:oneova/backend/social/repositories/relationship_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RelationshipRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = RelationshipRepository(firestore);
  });

  Future<void> seedUser(String id, {String privacy = 'public', int followers = 0, int following = 0}) async {
    await firestore.collection('users').doc(id).set({
      'defaultPrivacyMode': privacy,
      'followers': followers,
      'following': following,
    });
  }

  test('followUser successfully creates a relationship and increments counts', () async {
    await seedUser('userA');
    await seedUser('userB');

    await repo.followUser('userA', 'userB');

    final rel = await firestore.collection('relationships').doc('userA_userB').get();
    expect(rel.exists, isTrue);
    expect(rel.data()!['status'], RelationshipStatus.accepted.name);

    final userA = await firestore.collection('users').doc('userA').get();
    expect(userA.data()!['following'], 1);

    final userB = await firestore.collection('users').doc('userB').get();
    expect(userB.data()!['followers'], 1);
  });

  test('followUser respects privacy (creates pending request)', () async {
    await seedUser('userA');
    await seedUser('userB', privacy: 'private');

    await repo.followUser('userA', 'userB');

    final rel = await firestore.collection('relationships').doc('userA_userB').get();
    expect(rel.exists, isTrue);
    expect(rel.data()!['status'], RelationshipStatus.pending.name);

    // Counts should NOT increment yet
    final userA = await firestore.collection('users').doc('userA').get();
    expect(userA.data()!['following'], 0);
  });

  test('prevent duplicate relationships from incrementing counts multiple times', () async {
    await seedUser('userA');
    await seedUser('userB');

    await repo.followUser('userA', 'userB');
    await repo.followUser('userA', 'userB'); // Second time

    final userA = await firestore.collection('users').doc('userA').get();
    expect(userA.data()!['following'], 1); // Should still be 1
  });

  test('prevent unauthorized relationship changes (cannot follow if blocked)', () async {
    await seedUser('userA');
    await seedUser('userB');

    // B blocks A
    await repo.blockUser('userB', 'userA');

    // A tries to follow B
    expect(
      () => repo.followUser('userA', 'userB'),
      throwsA(isA<Exception>()),
    );
  });

  test('unfollowUser decrements counts', () async {
    await seedUser('userA', following: 1);
    await seedUser('userB', followers: 1);

    await firestore.collection('relationships').doc('userA_userB').set({
      'followerId': 'userA',
      'followingId': 'userB',
      'status': RelationshipStatus.accepted.name,
    });

    await repo.unfollowUser('userA', 'userB');

    final rel = await firestore.collection('relationships').doc('userA_userB').get();
    expect(rel.exists, isFalse);

    final userA = await firestore.collection('users').doc('userA').get();
    expect(userA.data()!['following'], 0);

    final userB = await firestore.collection('users').doc('userB').get();
    expect(userB.data()!['followers'], 0);
  });

  test('blockUser removes both relationships and adjusts counts', () async {
    await seedUser('userA', following: 1, followers: 1);
    await seedUser('userB', following: 1, followers: 1);

    // A follows B
    await firestore.collection('relationships').doc('userA_userB').set({
      'followerId': 'userA',
      'followingId': 'userB',
      'status': RelationshipStatus.accepted.name,
    });
    // B follows A
    await firestore.collection('relationships').doc('userB_userA').set({
      'followerId': 'userB',
      'followingId': 'userA',
      'status': RelationshipStatus.accepted.name,
    });

    // A blocks B
    await repo.blockUser('userA', 'userB');

    final rel1 = await firestore.collection('relationships').doc('userA_userB').get();
    expect(rel1.data()!['status'], RelationshipStatus.blocked.name);

    final rel2 = await firestore.collection('relationships').doc('userB_userA').get();
    expect(rel2.exists, isFalse);

    final userA = await firestore.collection('users').doc('userA').get();
    expect(userA.data()!['following'], 0);
    expect(userA.data()!['followers'], 0);

    final userB = await firestore.collection('users').doc('userB').get();
    expect(userB.data()!['following'], 0);
    expect(userB.data()!['followers'], 0);
  });

  test('acceptFollowRequest increments counts', () async {
    await seedUser('userA', privacy: 'private');
    await seedUser('userB');

    await repo.followUser('userB', 'userA'); // B requests to follow A

    final userAPre = await firestore.collection('users').doc('userA').get();
    expect(userAPre.data()!['followers'], 0);

    await repo.acceptFollowRequest('userA', 'userB'); // A accepts B

    final rel = await firestore.collection('relationships').doc('userB_userA').get();
    expect(rel.data()!['status'], RelationshipStatus.accepted.name);

    final userAPost = await firestore.collection('users').doc('userA').get();
    expect(userAPost.data()!['followers'], 1);

    final userBPost = await firestore.collection('users').doc('userB').get();
    expect(userBPost.data()!['following'], 1);
  });
}
