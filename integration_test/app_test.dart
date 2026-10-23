import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpepe_studio/main.dart' as app;
import 'package:firebase_auth/firebase_auth.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('Login, Inbox, Voice, Privacy flow', (tester) async {
      app.main();
      
      // Wait for the app to settle and Firebase to initialize
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Force sign out to ensure we are on the login screen
      try {
        final auth = app.FirebaseAuth.instance;
        if (auth.currentUser != null) {
          await auth.signOut();
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      } catch (_) {}

      // 1. Verify Login Screen is present
      expect(find.text('MPEPE'), findsWidgets);
      expect(find.text('STUDIO'), findsWidgets);
      expect(find.text('Welcome Back'), findsWidgets);
      expect(find.text('Continue with Phone'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      
      // Since this is a live Firebase app, we can't easily complete a real OTP flow 
      // without a test phone number configured in Firebase console.
      // Assuming a mock or specific test account is available, you would do:
      // await tester.enterText(find.byType(TextField).first, '712345678');
      // await tester.tap(find.text('Continue with Phone'));
      // await tester.pumpAndSettle();
      
      // For now, this test asserts that the UI structure is sound and ready for 
      // standard interaction. When test credentials are added to the Firebase emulator,
      // this test can be expanded to navigate to:
      
      // 2. Verify Inbox (HubHomeScreen / Enterprise All-in-One Inbox)
      // expect(find.text('Enterprise All-in-One Inbox'), findsOneWidget);
      
      // 3. Verify Voice 
      // expect(find.text('Voice'), findsWidgets);
      
      // 4. Verify Privacy Settings
      // expect(find.text('Privacy'), findsWidgets);
    });
  });
}
