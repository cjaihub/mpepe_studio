import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/moderation/models/moderation_models.dart';
import 'package:oneova/backend/moderation/services/moderation_service.dart';

void main() {
  late ModerationService service;

  setUp(() {
    service = ModerationService();

    // Register AI Reviewer (Low authority)
    service.registerReviewer(const Reviewer(
      id: 'ai_bot_1',
      name: 'System AI Mod',
      isHuman: false,
      maxAuthorityLevel: [ModerationAction.warn, ModerationAction.restrict, ModerationAction.remove, ModerationAction.ageRestrict],
    ));

    // Register Human Admin (Max authority)
    service.registerReviewer(const Reviewer(
      id: 'admin_1',
      name: 'Human Admin',
      isHuman: true,
      maxAuthorityLevel: ModerationAction.values,
    ));
  });

  test('AI governance block prevents AI from suspending or banning users', () {
    final modCase = service.openCase(
      targetUserId: 'bad_actor_1',
      evidence: const ModerationEvidence(
        id: 'ev_1',
        inputType: ModerationInputType.content,
        targetId: 'vid_123',
        aiDetectionSignal: ModerationDetectionType.spam,
      ),
    );

    // AI can remove content
    service.executeDecision(modCase.id, 'ai_bot_1', ModerationAction.remove, 'Spam video detected');
    expect(modCase.decision?.actionTaken, ModerationAction.remove);

    // Open a new high-severity case
    final severeCase = service.openCase(
      targetUserId: 'bad_actor_2',
      evidence: const ModerationEvidence(
        id: 'ev_2',
        inputType: ModerationInputType.profiles,
        targetId: 'bad_actor_2',
        aiDetectionSignal: ModerationDetectionType.malware,
      ),
    );

    // AI MUST FAIL if it attempts to ban
    expect(
      () => service.executeDecision(severeCase.id, 'ai_bot_1', ModerationAction.ban, 'Malware detected'),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('AI Governance Block'))),
    );

    // Human MUST SUCCEED when banning
    service.executeDecision(severeCase.id, 'admin_1', ModerationAction.ban, 'Confirmed malware profile');
    expect(severeCase.decision?.actionTaken, ModerationAction.ban);
  });

  test('Filing an appeal reopens the case status', () {
    final modCase = service.openCase(
      targetUserId: 'user_99',
      evidence: const ModerationEvidence(
        id: 'ev_3',
        inputType: ModerationInputType.comments,
        targetId: 'com_1',
      ),
    );

    // Human warns user
    service.executeDecision(modCase.id, 'admin_1', ModerationAction.warn, 'Rude behavior');
    
    expect(modCase.status, CaseStatus.resolved);

    // User appeals
    service.fileAppeal(modCase.id, 'user_99', 'I was just joking with a friend');

    expect(modCase.status, CaseStatus.appealed);
    expect(modCase.appeal?.appealText, 'I was just joking with a friend');
  });
}
