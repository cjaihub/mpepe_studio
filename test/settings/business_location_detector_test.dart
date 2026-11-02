import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/user_service.dart';
import 'package:oneova/shared/location/oneova_location_detector.dart';
import 'package:oneova/settings/widgets/oneova_verification_request_sheet.dart';

void main() {
  group('AutoLocationResult & LocationDetectorService Tests', () {
    test('AutoLocationResult serializes toMap correctly', () {
      const res = AutoLocationResult(
        formattedLocation: 'Nairobi, Kenya',
        city: 'Nairobi',
        state: 'Nairobi County',
        country: 'Kenya',
        countryCode: 'KE',
        postalCode: '00100',
        phoneDialCode: '+254',
        currency: 'KES',
        latitude: -1.286389,
        longitude: 36.817223,
      );

      final map = res.toMap();
      expect(map['formattedLocation'], 'Nairobi, Kenya');
      expect(map['city'], 'Nairobi');
      expect(map['country'], 'Kenya');
      expect(map['countryCode'], 'KE');
      expect(map['phoneDialCode'], '+254');
      expect(map['currency'], 'KES');
      expect(map['latitude'], -1.286389);
      expect(map['longitude'], 36.817223);
    });

    test('OneovaLocationDetectorService maps country dial codes correctly', () {
      expect(OneovaLocationDetectorService.countryDialCodes['ke'], '+254');
      expect(OneovaLocationDetectorService.countryDialCodes['ng'], '+234');
      expect(OneovaLocationDetectorService.countryDialCodes['za'], '+27');
      expect(OneovaLocationDetectorService.countryDialCodes['us'], '+1');
      expect(OneovaLocationDetectorService.countryDialCodes['gb'], '+44');
      expect(OneovaLocationDetectorService.countryDialCodes['gh'], '+233');
    });

    test('OneovaLocationDetectorService maps currencies correctly', () {
      expect(OneovaLocationDetectorService.countryCurrencies['ke'], 'KES');
      expect(OneovaLocationDetectorService.countryCurrencies['ng'], 'NGN');
      expect(OneovaLocationDetectorService.countryCurrencies['za'], 'ZAR');
      expect(OneovaLocationDetectorService.countryCurrencies['us'], 'USD');
      expect(OneovaLocationDetectorService.countryCurrencies['gb'], 'GBP');
      expect(OneovaLocationDetectorService.countryCurrencies['gh'], 'GHS');
    });
  });

  group('OneovaAutoLocationButton Widget Tests', () {
    testWidgets('Renders icon button by default', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneovaAutoLocationButton(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
    });

    testWidgets('Renders pill tag when asPill is true', (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OneovaAutoLocationButton(
              controller: controller,
              asPill: true,
            ),
          ),
        ),
      );

      expect(find.text('Auto-detect Location'), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
    });
  });

  group('OneovaVerificationRequestSheet Tests', () {
    final testUser = AppUser(
      id: 'biz_user_1',
      email: 'biz@oneova.app',
      username: 'acmestudio',
      fullName: 'Acme Studio Africa Ltd',
      role: 'business',
      department: 'Business',
      status: 'active',
      createdAt: DateTime.now(),
      isBusiness: true,
      isVerified: false,
      location: 'Nairobi, Kenya',
      businessDetails: {
        'legalName': 'Acme Studio Africa Ltd',
        'regNumber': 'RC-998877',
        'currency': 'KES',
        'shopUrl': 'https://shop.oneova.app/acme',
      },
    );

    testWidgets('Renders Business Verification fields when isBusiness is true', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OneovaVerificationRequestSheet(
                user: testUser,
                isBusiness: true,
              ),
            ),
          ),
        ),
      );

      // Verify business title
      expect(find.text('Business Verification'), findsOneWidget);
      expect(find.text('REGISTERED BUSINESS LEGAL NAME'), findsOneWidget);
      expect(find.text('TRADING AS / BRAND NAME'), findsOneWidget);
      expect(find.text('BUSINESS REGISTRATION / TAX ID'), findsOneWidget);
      expect(find.text('HEADQUARTERS / OPERATING LOCATION'), findsOneWidget);
      expect(find.text('BUSINESS CATEGORY'), findsOneWidget);
      expect(find.text('OFFICIAL WEBSITE OR STOREFRONT URL'), findsOneWidget);
      expect(find.text('Submit Business Verification'), findsOneWidget);

      // Verify auto-detected location button is present
      expect(find.byType(OneovaAutoLocationButton), findsOneWidget);
    });
  });
}
