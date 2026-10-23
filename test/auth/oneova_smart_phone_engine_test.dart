import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/auth/services/oneova_smart_phone_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OneovaSmartPhoneEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine = OneovaSmartPhoneEngine();
  });

  group('OneovaSmartPhoneEngine Normalization & Auto-Sniffing', () {
    test('Normalizes standard Kenyan daily format with leading zero (0712 345 678)', () {
      final ke = engine.findByIso('KE');
      final result = engine.parseAndNormalize(input: '0712345678', fallbackCountry: ke);

      expect(result.country.isoCode, equals('KE'));
      expect(result.e164, equals('+254712345678'));
      expect(result.nationalNumber, equals('0712345678'));
      expect(result.isValid, isTrue);
      expect(result.isComplete, isTrue);
    });

    test('Normalizes Kenyan 9-digit format without leading zero (712345678)', () {
      final ke = engine.findByIso('KE');
      final result = engine.parseAndNormalize(input: '712345678', fallbackCountry: ke);

      expect(result.country.isoCode, equals('KE'));
      expect(result.e164, equals('+254712345678'));
      expect(result.isValid, isTrue);
    });

    test('Strips duplicate country code typed in field (254712345678)', () {
      final ke = engine.findByIso('KE');
      final result = engine.parseAndNormalize(input: '254712345678', fallbackCountry: ke);

      expect(result.country.isoCode, equals('KE'));
      expect(result.e164, equals('+254712345678'));
      expect(result.isValid, isTrue);
    });

    test('Auto-sniffs US international number with + and switches country (+1 555 234 5678)', () {
      final ke = engine.findByIso('KE');
      final result = engine.parseAndNormalize(input: '+1 555 234 5678', fallbackCountry: ke);

      expect(result.wasCountryAutoSwitched, isTrue);
      expect(result.country.isoCode, equals('US'));
      expect(result.country.dialCode, equals('+1'));
      expect(result.e164, equals('+15552345678'));
      expect(result.isValid, isTrue);
    });

    test('Auto-sniffs UK international number with + and switches country (+44 7911 123456)', () {
      final ke = engine.findByIso('KE');
      final result = engine.parseAndNormalize(input: '+44 7911 123456', fallbackCountry: ke);

      expect(result.wasCountryAutoSwitched, isTrue);
      expect(result.country.isoCode, equals('GB'));
      expect(result.country.dialCode, equals('+44'));
      expect(result.e164, equals('+447911123456'));
      expect(result.isValid, isTrue);
    });

    test('Auto-sniffs Nigeria international number with 00 prefix (00234 803 123 4567)', () {
      final ke = engine.findByIso('KE');
      final result = engine.parseAndNormalize(input: '00234 803 123 4567', fallbackCountry: ke);

      expect(result.wasCountryAutoSwitched, isTrue);
      expect(result.country.isoCode, equals('NG'));
      expect(result.e164, equals('+2348031234567'));
      expect(result.isValid, isTrue);
    });
  });

  group('OneovaSmartPhoneEngine Device Memory', () {
    test('Saves and retrieves last used account on device', () async {
      await engine.saveLastUsedAccount(
        phoneE164: '+254712345678',
        countryIso: 'KE',
        displayName: 'Crown Cubahiro',
        username: 'cjcrown',
      );

      final loaded = await engine.getLastUsedAccount();
      expect(loaded, isNotNull);
      expect(loaded!.phoneE164, equals('+254712345678'));
      expect(loaded.countryIso, equals('KE'));
      expect(loaded.displayName, equals('Crown Cubahiro'));
      expect(loaded.username, equals('cjcrown'));
    });

    test('Clears last used account on device', () async {
      await engine.saveLastUsedAccount(
        phoneE164: '+254712345678',
        countryIso: 'KE',
      );
      await engine.clearLastUsedAccount();
      final loaded = await engine.getLastUsedAccount();
      expect(loaded, isNull);
    });
  });
}
