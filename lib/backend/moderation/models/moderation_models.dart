enum ModerationInputType {
  content,
  comments,
  messages,
  profiles,
  live,
  communities,
  reports,
}

enum ModerationDetectionType {
  spam,
  harassment,
  fraud,
  impersonation,
  malware,
  unsafeContent,
  copyrightSignals,
}

enum ModerationAction {
  none,
  warn,
  restrict,
  remove,
  ageRestrict,
  suspend,
  ban,
}

enum CaseStatus {
  open,
  underReview,
  resolved,
  appealed,
}

class ModerationEvidence {
  final String id;
  final ModerationInputType inputType;
  final String targetId; // ID of the content/message/profile
  final String? snapshotData; // text of the message when reported
  final ModerationDetectionType? aiDetectionSignal;
  final double? aiConfidence;

  const ModerationEvidence({
    required this.id,
    required this.inputType,
    required this.targetId,
    this.snapshotData,
    this.aiDetectionSignal,
    this.aiConfidence,
  });
}

class Reviewer {
  final String id;
  final String name;
  final bool isHuman;
  final List<ModerationAction> maxAuthorityLevel;

  const Reviewer({
    required this.id,
    required this.name,
    required this.isHuman,
    required this.maxAuthorityLevel,
  });
}

class ModerationDecision {
  final String id;
  final String reviewerId;
  final ModerationAction actionTaken;
  final String rationale;
  final DateTime timestamp;

  const ModerationDecision({
    required this.id,
    required this.reviewerId,
    required this.actionTaken,
    required this.rationale,
    required this.timestamp,
  });
}

class ModerationAppeal {
  final String id;
  final String userId;
  final String appealText;
  final DateTime submittedAt;
  bool isResolved;

  ModerationAppeal({
    required this.id,
    required this.userId,
    required this.appealText,
    required this.submittedAt,
    this.isResolved = false,
  });
}

class ModerationCase {
  final String id;
  final String targetUserId;
  CaseStatus status;
  final List<ModerationEvidence> evidence;
  ModerationDecision? decision;
  ModerationAppeal? appeal;

  ModerationCase({
    required this.id,
    required this.targetUserId,
    this.status = CaseStatus.open,
    required this.evidence,
    this.decision,
    this.appeal,
  });
}
