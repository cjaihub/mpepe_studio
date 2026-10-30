import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova/settings/screens/legal_policies_screen.dart';
import 'package:oneova/settings/services/platform_docs_cms_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  const allowedFirestoreKeys = <String>{
    'id',
    'docType',
    'category',
    'policyTab',
    'title',
    'badge',
    'isAccentBadge',
    'inShort',
    'readTime',
    'version',
    'effectiveDate',
    'order',
    'isPublished',
    'sections',
    'htmlOverride',
    'updatedAt',
    'updatedByUid',
    'updatedByName',
    'changeNote',
  };

  group('OneovaPlatformDocsCatalog & Firestore Rules Schema Parity', () {
    test('All 18 baseline docs conform to firestore.rules schema and brand rules', () {
      const defaults = OneovaPlatformDocsCatalog.defaults;
      expect(defaults.length, 18);

      final featureDocs = defaults.where((d) => d.docType == 'feature').toList();
      final ruleDocs = defaults.where((d) => d.docType != 'feature').toList();
      expect(featureDocs.length, 10);
      expect(ruleDocs.length, 8);

      final ids = <String>{};
      for (final doc in defaults) {
        expect(ids.add(doc.id), isTrue, reason: 'Duplicate doc id: ${doc.id}');
        expect(doc.id.length, inInclusiveRange(1, 80));
        expect(['feature', 'policy', 'regulation'], contains(doc.docType));
        expect(doc.category.length, inInclusiveRange(1, 80));
        expect(doc.policyTab.length, lessThanOrEqualTo(40));
        expect(doc.title.length, inInclusiveRange(1, 160));
        expect(doc.badge.length, lessThanOrEqualTo(40));
        expect(doc.inShort.length, lessThanOrEqualTo(800));
        expect(doc.readTime.length, lessThanOrEqualTo(40));
        expect(doc.version.length, lessThanOrEqualTo(32));
        expect(doc.effectiveDate.length, lessThanOrEqualTo(64));
        expect(doc.order, inInclusiveRange(-1000, 100000));
        expect(doc.sections.length, inInclusiveRange(1, 40));

        // Brand check: never Mpepe / Oneover / Onerova
        final combined = '${doc.title} ${doc.inShort}'.toLowerCase();
        expect(combined.contains('mpepe'), isFalse);
        expect(combined.contains('oneover'), isFalse);
        expect(combined.contains('onerova'), isFalse);

        final map = doc.toFirestoreMap(
          actorUid: 'admin_uid_01',
          actorName: 'Oneova Founder',
          note: 'Schema verification',
        );
        expect(map.keys.toSet(), equals(allowedFirestoreKeys));
      }
    });
  });

  group('PlatformDocsCmsService Real-Time Cloud Sync & Fallback', () {
    late FakeFirebaseFirestore fakeFirestore;
    late PlatformDocsCmsService service;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      service = PlatformDocsCmsService(firestore: fakeFirestore);
    });

    test('Overrides baseline doc in real time, filters drafts, and appends new cloud docs',
        () async {
      final initial = await service.watchMergedDocs(includeDrafts: false).first;
      expect(initial.length, 18);
      expect(initial.every((d) => !d.isLiveFromCloud), isTrue);

      // 1. Publish a live cloud update to Terms of Service
      await fakeFirestore.collection('platform_cms_docs').doc('policy-terms-of-service').set({
        'id': 'policy-terms-of-service',
        'docType': 'policy',
        'category': 'Legal & Terms',
        'policyTab': 'terms',
        'title': 'Terms of Service — Live Updated Edition',
        'badge': 'UPDATED LIVE',
        'isAccentBadge': true,
        'inShort': 'Live updated creator terms synced across Oneova App & Website.',
        'readTime': '6 min read',
        'version': 'v2.4',
        'effectiveDate': 'November 1, 2026',
        'order': 102,
        'isPublished': true,
        'sections': [
          {
            'heading': '1. 100% Creator IP Ownership',
            'summary': 'Creators keep full ownership of every reel, look, and broadcast.',
            'callout': 'Synced live in real time.',
            'bullets': ['Zero hidden fees', 'Local consumer rights preserved'],
          },
        ],
        'htmlOverride': '',
        'updatedAt': Timestamp.now(),
        'updatedByUid': 'admin_1',
        'updatedByName': 'Oneova Admin',
        'changeNote': 'Clarified regional payout SLA',
      });

      final afterOverride = await service.watchMergedDocs(includeDrafts: false).first;
      final liveTerms = afterOverride.firstWhere((d) => d.id == 'policy-terms-of-service');
      expect(liveTerms.isLiveFromCloud, isTrue);
      expect(liveTerms.version, 'v2.4');
      expect(liveTerms.title, 'Terms of Service — Live Updated Edition');

      // 2. Save an unpublished draft -> hidden from public, visible to admins
      await fakeFirestore.collection('platform_cms_docs').doc('feature-upcoming-draft').set({
        'id': 'feature-upcoming-draft',
        'docType': 'feature',
        'category': 'AI & Automation',
        'policyTab': '',
        'title': 'Unreleased Studio Feature Draft',
        'badge': 'DRAFT',
        'isAccentBadge': false,
        'inShort': 'Internal draft.',
        'readTime': '3 min read',
        'version': 'v0.9',
        'effectiveDate': 'December 2026',
        'order': 999,
        'isPublished': false,
        'sections': const [],
        'htmlOverride': '',
        'updatedAt': Timestamp.now(),
        'updatedByUid': 'admin_1',
        'updatedByName': 'Oneova Admin',
        'changeNote': 'Drafting',
      });

      final publicDocs = await service.watchMergedDocs(includeDrafts: false).first;
      final adminDocs = await service.watchMergedDocs(includeDrafts: true).first;
      expect(publicDocs.any((d) => d.id == 'feature-upcoming-draft'), isFalse);
      expect(adminDocs.any((d) => d.id == 'feature-upcoming-draft'), isTrue);

      // 3. Delete cloud override -> falls back cleanly to baseline default
      await service.deleteCloudDoc('policy-terms-of-service');
      final afterDelete = await service.watchMergedDocs(includeDrafts: false).first;
      final revertedTerms = afterDelete.firstWhere((d) => d.id == 'policy-terms-of-service');
      expect(revertedTerms.isLiveFromCloud, isFalse);
      expect(revertedTerms.version, 'v1.0');
    });
  });

  group('LegalPoliciesScreen Dual-Mode (Light & Dark) Widget Verification', () {
    Widget buildTestableScreen({
      required Brightness brightness,
      required FakeFirebaseFirestore firestore,
      bool isAdmin = false,
      String? initialTab,
    }) {
      final service = PlatformDocsCmsService(firestore: firestore);
      return ProviderScope(
        overrides: [
          platformDocsCmsServiceProvider.overrideWithValue(service),
          isPlatformDocsAdminProvider.overrideWith((ref) => Stream<bool>.value(isAdmin)),
        ],
        child: MaterialApp(
          theme: brightness == Brightness.dark
              ? ThemeData.dark(useMaterial3: true)
              : ThemeData.light(useMaterial3: true),
          home: LegalPoliciesScreen(initialTab: initialTab),
        ),
      );
    }

    testWidgets('Renders cleanly in Light Mode & switches to Platform Features track',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      await tester.binding.setSurfaceSize(const Size(430, 932));

      await tester.pumpWidget(
        buildTestableScreen(
          brightness: Brightness.light,
          firestore: fakeFirestore,
          isAdmin: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rules, Docs & Legal'), findsOneWidget);
      expect(find.textContaining('Rules & Regulations'), findsOneWidget);
      expect(find.textContaining('Platform Features'), findsOneWidget);
      expect(find.text('Live CMS'), findsNothing);

      // Switch to Platform Features track
      await tester.tap(find.textContaining('Platform Features'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -280));
      await tester.pumpAndSettle();

      expect(find.text('4K Live Broadcast Studio & PK Stage'), findsOneWidget);
    });

    testWidgets('Renders cleanly in Dark Mode with Admin Live CMS control & search filter',
        (tester) async {
      final fakeFirestore = FakeFirebaseFirestore();
      await tester.binding.setSurfaceSize(const Size(430, 932));

      await tester.pumpWidget(
        buildTestableScreen(
          brightness: Brightness.dark,
          firestore: fakeFirestore,
          isAdmin: true,
        ),
      );
      await tester.pumpAndSettle();

      // Admin sees Live CMS trigger button
      expect(find.text('Live CMS'), findsOneWidget);

      // Search filters rules dynamically
      await tester.enterText(find.byType(TextField), 'POPIA');
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -280));
      await tester.pumpAndSettle();

      expect(find.text('African & Global Regulatory Compliance Framework'), findsOneWidget);
    });
  });
}
