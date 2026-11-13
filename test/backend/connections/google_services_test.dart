import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connections/google_services.dart';

void main() {
  group('GoogleLinkedAccount.fromDoc', () {
    test('reads services and their status from a server doc', () {
      final a = GoogleLinkedAccount.fromDoc('123', {
        'sub': '123',
        'email': 'me@gmail.com',
        'name': 'Me',
        'tokenStore': 'server',
        'services': {
          'gmail': {'status': 'connected'},
          'youtube': {'status': 'needsReconnect'},
          'unknownThing': {'status': 'connected'},
        },
      })!;
      expect(a.email, 'me@gmail.com');
      expect(a.isOn(GoogleService.gmail), isTrue);
      expect(a.statusOf(GoogleService.youtube), GoogleServiceStatus.needsReconnect);
      expect(a.isOn(GoogleService.youtube), isFalse);
      expect(a.statusOf(GoogleService.drive), isNull);
      expect(a.services.length, 2);
    });

    test('ignores docs the server did not write', () {
      expect(GoogleLinkedAccount.fromDoc('1', {'email': 'x@y.z', 'services': {}}), isNull);
    });

    test('falls back to the doc id and email for naming', () {
      final a = GoogleLinkedAccount.fromDoc('42', {'email': 'a@b.c', 'tokenStore': 'server'})!;
      expect(a.sub, '42');
      expect(a.displayName, 'a@b.c');
      expect(a.services, isEmpty);
    });
  });

  test('every request carries identity scopes plus only that service\'s scopes', () {
    final s = GoogleService.calendar.requestScopes;
    expect(s, containsAll(GoogleService.identityScopes));
    expect(s.where((x) => x.contains('gmail')), isEmpty);
  });
}
