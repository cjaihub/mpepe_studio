import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/experimentation_models.dart';

final experimentationServiceProvider = Provider<ExperimentationService>((ref) {
  return ExperimentationService();
});

class ExperimentationService {
  Future<TrialVideo> getTrialVideo(String id) async {
    // Mocking a backend fetch
    await Future.delayed(const Duration(milliseconds: 200));
    return TrialVideo(
      id: id,
      creatorId: 'me',
      videoUrl: 'https://example.com/trial.mp4',
      title: 'Testing New Format',
      status: TrialStatus.active,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      config: const TestAudienceConfig(
        targetViews: 500,
        followersOnly: true,
      ),
      metrics: const TrialMetrics(
        views: 342,
        watchTime: Duration(minutes: 145),
        completionRate: 0.72,
        likes: 85,
        comments: 12,
        shares: 4,
        follows: 2,
        audienceResponseScore: 0.85, // High positive response
      ),
    );
  }

  Future<List<TrialVideo>> getActiveTrials() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      await getTrialVideo('trial_123'),
    ];
  }

  Future<void> publishTrial(String id) async {
    // 1. Validates the user owns the trial
    // 2. Converts the TrialVideo to a public Post record
    // 3. Removes 'isTrial' constraint on the media
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> discardTrial(String id) async {
    // Destroys the trial record and media
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> scheduleTrial(String id, DateTime publishDate) async {
    // Sets the status to scheduled, backend will auto-publish
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> expandDistribution(String id, TestAudienceConfig newConfig) async {
    // Expands the test audience pool safely
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
