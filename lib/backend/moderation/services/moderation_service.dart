import 'package:oneova/backend/moderation/models/moderation_models.dart';

class ModerationService {
  final Map<String, ModerationCase> _cases = {};
  final Map<String, Reviewer> _reviewers = {};

  void registerReviewer(Reviewer reviewer) {
    _reviewers[reviewer.id] = reviewer;
  }

  ModerationCase openCase({
    required String targetUserId,
    required ModerationEvidence evidence,
  }) {
    final newCase = ModerationCase(
      id: 'case_${DateTime.now().microsecondsSinceEpoch}',
      targetUserId: targetUserId,
      evidence: [evidence],
    );
    _cases[newCase.id] = newCase;
    return newCase;
  }

  void attachEvidence(String caseId, ModerationEvidence evidence) {
    final modCase = _cases[caseId];
    if (modCase == null) throw Exception('Case not found');
    modCase.evidence.add(evidence);
  }

  /// AI calls this to auto-resolve low-level issues or escalate high-impact issues
  void executeDecision(String caseId, String reviewerId, ModerationAction action, String rationale) {
    final modCase = _cases[caseId];
    if (modCase == null) throw Exception('Case not found');
    
    final reviewer = _reviewers[reviewerId];
    if (reviewer == null) throw Exception('Reviewer not found');

    if (!reviewer.maxAuthorityLevel.contains(action)) {
      if (!reviewer.isHuman && (action == ModerationAction.ban || action == ModerationAction.suspend)) {
        throw Exception('AI Governance Block: AI reviewers are strictly forbidden from permanently banning or suspending users. Must escalate to Human review.');
      }
      throw Exception('Reviewer lacks authority for this action.');
    }

    final decision = ModerationDecision(
      id: 'dec_${DateTime.now().microsecondsSinceEpoch}',
      reviewerId: reviewerId,
      actionTaken: action,
      rationale: rationale,
      timestamp: DateTime.now(),
    );

    modCase.decision = decision;
    modCase.status = CaseStatus.resolved;

    // Dispatch action to unified platform (e.g. restrict inbox, hide profile)
  }

  void fileAppeal(String caseId, String userId, String appealText) {
    final modCase = _cases[caseId];
    if (modCase == null) throw Exception('Case not found');
    if (modCase.targetUserId != userId) throw Exception('Unauthorized to appeal this case');
    if (modCase.status != CaseStatus.resolved) throw Exception('Can only appeal resolved cases');

    modCase.appeal = ModerationAppeal(
      id: 'app_${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      appealText: appealText,
      submittedAt: DateTime.now(),
    );

    modCase.status = CaseStatus.appealed; // Re-opens for human queue
  }

  ModerationCase? getCase(String id) => _cases[id];
}
