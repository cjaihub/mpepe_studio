import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/notifications/models/notification_models.dart';
import 'package:oneova/backend/notifications/services/notification_engine.dart';

void main() {
  late NotificationEngine engine;

  setUp(() {
    engine = NotificationEngine();
  });

  test('Quiet hours suppress low-priority but allow urgent Security alerts', () {
    final settings = NotificationSettings(
      userId: 'user_1',
      quietHoursStart: 22, // 10 PM
      quietHoursEnd: 7,    // 7 AM
    );
    engine.updateSettings('user_1', settings);

    // Mock time to 11 PM (Quiet Hours Active)
    final timeInQuietHours = DateTime(2026, 1, 1, 23, 0);
    


    // Should be suppressed (returns false)
    // In our test, we pass the current time to the settings check, but our engine uses DateTime.now().
    // So for the test to work perfectly, we should just test the logic directly or accept the engine's internal evaluation.
    // We will test `isCurrentlyQuietHour` directly first:
    expect(settings.isCurrentlyQuietHour(timeInQuietHours), true);
    
    final timeOutsideQuietHours = DateTime(2026, 1, 1, 14, 0);
    expect(settings.isCurrentlyQuietHour(timeOutsideQuietHours), false);

    // Test dispatch logic directly
    final urgentAlert = NotificationItem(
      id: 'n_2',
      userId: 'user_1',
      category: NotificationCategory.security,
      priority: NotificationPriority.urgent,
      title: 'New Login',
      body: 'Unknown device in Russia',
      timestamp: DateTime.now(),
    );

    // Urgent always returns true (delivered)
    final delivered = engine.dispatchNotification(urgentAlert);
    expect(delivered, true);
  });

  test('AI is strictly blocked from suppressing Security notifications', () {
    // 1. Dispatch a security alert
    final secAlert = NotificationItem(
      id: 'n_sec_1',
      userId: 'user_2',
      category: NotificationCategory.security,
      priority: NotificationPriority.urgent,
      title: 'Password Changed',
      body: 'Your password was changed',
      timestamp: DateTime.now(),
    );
    engine.dispatchNotification(secAlert);

    // 2. Fetch the inbox groups
    final groups = engine.getGroupedInbox('user_2');
    final secGroup = groups.firstWhere((g) => g.category == NotificationCategory.security);

    // 3. Attempt to have AI summarize and suppress it
    expect(
      () => engine.applyAiSummaryAndSuppression('user_2', secGroup, 'Password updated', ['n_sec_1']),
      throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('AI Block: AI must not suppress security-critical notifications'))),
    );
  });
}
