import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/challenges/models/challenge_models.dart';
import 'package:oneova/backend/challenges/services/challenge_service.dart';

void main() {
  late ChallengeService service;
  late Challenge activeChallenge;

  setUp(() {
    service = ChallengeService();
    
    activeChallenge = Challenge(
      id: 'chal_1',
      creatorId: 'brand_x',
      title: 'Summer Edit Challenge',
      description: 'Edit your best summer video.',
      rules: ['No AI generation', 'Must use our song'],
      startTime: DateTime.now().subtract(const Duration(days: 1)), // Started yesterday
      endTime: DateTime.now().add(const Duration(days: 7)), // Ends next week
      criteria: const ChallengeCriteria(requiresVideo: true),
      hashtags: ['#summerEdit'],
      rewards: [const ChallengeReward(description: '1000 USD', monetaryValue: 1000)],
      allowPublicVoting: true,
    );

    service.createChallenge(activeChallenge);
  });

  test('Anti-abuse: Blocks duplicate submissions', () {
    // First submission succeeds
    service.submitToChallenge('chal_1', 'user_1', 'video_abc');

    // Second submission throws anti-abuse duplicate error
    expect(
      () => service.submitToChallenge('chal_1', 'user_1', 'video_xyz'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Anti-abuse: Duplicate submissions'))),
    );
  });

  test('Anti-abuse: Blocks vote manipulation', () {
    final sub = service.submitToChallenge('chal_1', 'user_2', 'video_qwe');

    // Voter 1 casts a vote
    service.castVote('chal_1', sub.id, 'voter_99');

    // Voter 1 tries to cast another vote (manipulation)
    expect(
      () => service.castVote('chal_1', sub.id, 'voter_99'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Anti-abuse: Vote manipulation'))),
    );
  });

  test('Leaderboard derives strictly from verified vote ledger', () {
    final sub1 = service.submitToChallenge('chal_1', 'user_a', 'vid_a');
    final sub2 = service.submitToChallenge('chal_1', 'user_b', 'vid_b');

    // user_b gets 2 votes
    service.castVote('chal_1', sub2.id, 'voter_1');
    service.castVote('chal_1', sub2.id, 'voter_2');

    // user_a gets 1 vote
    service.castVote('chal_1', sub1.id, 'voter_3');

    final board = service.generateLeaderboard('chal_1');
    
    // Sub 2 should be winning
    expect(board[0]['submissionId'], sub2.id);
    expect(board[0]['score'], 2.0);
    
    expect(board[1]['submissionId'], sub1.id);
    expect(board[1]['score'], 1.0);
  });
}
