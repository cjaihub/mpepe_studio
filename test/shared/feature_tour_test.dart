import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shared/services/oneova_feature_tour_service.dart';

void main() {
  group('OneovaFeatureTourService Tests', () {
    test('Tour steps count and definitions match all core app screens', () {
      final steps = OneovaFeatureTourService.steps;
      expect(steps.length, equals(7));

      expect(steps[0].title, contains('For You Reels'));
      expect(steps[0].badge, contains('01/07'));
      expect(steps[0].targetArea, equals('top_feed'));

      expect(steps[1].title, contains('Following & Biz'));
      expect(steps[1].badge, contains('02/07'));

      expect(steps[2].title, contains('Search'));
      expect(steps[2].badge, contains('03/07'));

      expect(steps[3].title, contains('Chat'));
      expect(steps[3].badge, contains('04/07'));

      expect(steps[4].title, contains('STUDIO (+)'));
      expect(steps[4].badge, contains('05/07'));

      expect(steps[5].title, contains('AI Creative Lab'));
      expect(steps[5].badge, contains('06/07'));

      expect(steps[6].title, contains('Profile'));
      expect(steps[6].badge, contains('07/07'));
    });

    test('FeatureTourCurrentStepNotifier navigates forward and backwards correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(featureTourCurrentStepProvider), equals(0));

      container.read(featureTourCurrentStepProvider.notifier).setStep(2);
      expect(container.read(featureTourCurrentStepProvider), equals(2));

      container.read(featureTourCurrentStepProvider.notifier).next();
      expect(container.read(featureTourCurrentStepProvider), equals(3));

      container.read(featureTourCurrentStepProvider.notifier).prev();
      expect(container.read(featureTourCurrentStepProvider), equals(2));

      container.read(featureTourCurrentStepProvider.notifier).setStep(0);
      container.read(featureTourCurrentStepProvider.notifier).prev();
      expect(container.read(featureTourCurrentStepProvider), equals(0)); // Should clamp to 0
    });

    test('FeatureTourVisibilityNotifier controls visibility state correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(featureTourVisibilityProvider), isFalse);

      container.read(featureTourVisibilityProvider.notifier).show();
      expect(container.read(featureTourVisibilityProvider), isTrue);

      container.read(featureTourVisibilityProvider.notifier).hide();
      expect(container.read(featureTourVisibilityProvider), isFalse);

      container.read(featureTourVisibilityProvider.notifier).setVisible(true);
      expect(container.read(featureTourVisibilityProvider), isTrue);
    });
  });
}
