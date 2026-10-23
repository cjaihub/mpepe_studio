import 'package:oneova/backend/challenges/models/challenge_models.dart';

class ChallengeService {
  final Map<String, Challenge> _challenges = {};
  final Map<String, ChallengeSubmission> _submissions = {}; // Keyed by submission ID
  final List<VerifiedVote> _verifiedVotes = []; // Master ledger of votes

  void createChallenge(Challenge challenge) {
    _challenges[challenge.id] = challenge;
  }

  ChallengeSubmission submitToChallenge(String challengeId, String participantId, String contentId) {
    final challenge = _challenges[challengeId];
    if (challenge == null) throw Exception('Challenge not found');

    if (!challenge.isActive) {
      throw Exception('Anti-abuse: Challenge is not currently active.');
    }

    // Anti-duplicate constraint
    final existing = _submissions.values.where((s) => s.challengeId == challengeId && s.participantId == participantId);
    if (existing.isNotEmpty) {
      throw Exception('Anti-abuse: Duplicate submissions are prohibited.');
    }

    final sub = ChallengeSubmission(
      id: 'sub_${DateTime.now().microsecondsSinceEpoch}',
      challengeId: challengeId,
      participantId: participantId,
      contentId: contentId,
      submittedAt: DateTime.now(),
    );

    _submissions[sub.id] = sub;
    return sub;
  }

  void castVote(String challengeId, String submissionId, String voterId) {
    final challenge = _challenges[challengeId];
    if (challenge == null) throw Exception('Challenge not found');

    if (!challenge.allowPublicVoting) {
      throw Exception('Anti-abuse: Public voting is disabled for this challenge.');
    }
    
    if (!challenge.isActive) {
      throw Exception('Anti-abuse: Voting is closed.');
    }

    final sub = _submissions[submissionId];
    if (sub == null || sub.challengeId != challengeId) {
      throw Exception('Submission invalid');
    }

    // Anti-vote manipulation: 1 vote per user per challenge
    final existingVote = _verifiedVotes.where((v) {
      final s = _submissions[v.submissionId];
      return s?.challengeId == challengeId && v.voterId == voterId;
    });

    if (existingVote.isNotEmpty) {
      throw Exception('Anti-abuse: Vote manipulation detected (multiple votes cast).');
    }

    _verifiedVotes.add(VerifiedVote(
      submissionId: submissionId,
      voterId: voterId,
      timestamp: DateTime.now(),
    ));
  }

  /// Derives leaderboard scores purely from the append-only ledger of VerifiedVotes
  List<Map<String, dynamic>> generateLeaderboard(String challengeId) {
    final Map<String, double> scores = {}; // submissionId -> total score

    for (final vote in _verifiedVotes) {
      final sub = _submissions[vote.submissionId];
      if (sub != null && sub.challengeId == challengeId) {
        scores[vote.submissionId] = (scores[vote.submissionId] ?? 0) + vote.score;
      }
    }

    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.map((e) => {
      'submissionId': e.key,
      'score': e.value,
      'participantId': _submissions[e.key]?.participantId,
    }).toList();
  }
}
