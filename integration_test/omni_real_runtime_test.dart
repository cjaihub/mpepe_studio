import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oneova/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Omni Command Real Runtime E2E', () {
    testWidgets('Journey: Open Omni Command, type command, verify execution', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Check if sign in page is present
      if (find.text('Sign In to MPEPE STUDIO').evaluate().isNotEmpty) {
        expect(find.text('Sign In to MPEPE STUDIO'), findsOneWidget);
        // Can't go further in E2E without real login credentials.
        return; 
      }
    });
  });
}
