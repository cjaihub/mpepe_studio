class ChallengeReward {
  final String description;
  final int? monetaryValue; // Optional

  const ChallengeReward({required this.description, this.monetaryValue});
}

class ChallengeCriteria {
  final bool requiresVideo;
  final bool requiresAudio;
  final int minDurationSeconds;
  final int maxDurationSeconds;

  const ChallengeCriteria({
    this.requiresVideo = true,
    this.requiresAudio = false,
    this.minDurationSeconds = 0,
    this.maxDurationSeconds = 60,
  });
}

class Challenge {
  final String id;
  final String creatorId;
  final String title;
  final String description;
  final List<String> rules;
  final DateTime startTime;
  final DateTime endTime;
  final ChallengeCriteria criteria;
  final List<String> hashtags;
  final List<ChallengeReward> rewards;
  final bool allowPublicVoting;

  const Challenge({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.rules,
    required this.startTime,
    required this.endTime,
    required this.criteria,
    required this.hashtags,
    required this.rewards,
    this.allowPublicVoting = true,
  });

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }
}

class ChallengeSubmission {
  final String id;
  final String challengeId;
  final String participantId;
  final String contentId; // Maps to media asset
  final DateTime submittedAt;
  bool isVerified;

  ChallengeSubmission({
    required this.id,
    required this.challengeId,
    required this.participantId,
    required this.contentId,
    required this.submittedAt,
    this.isVerified = true,
  });
}

class VerifiedVote {
  final String submissionId;
  final String voterId;
  final DateTime timestamp;
  final double score; // Can be simple +1

  const VerifiedVote({
    required this.submissionId,
    required this.voterId,
    required this.timestamp,
    this.score = 1.0,
  });
}
