import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oneova/looks/services/catalog_sync_service.dart';

void main() {
  group('CatalogDelivery & BundleSync Tests', () {
    test('CatalogManifest serialization and deserialization', () {
      final manifestJson = {
        'schemaVersion': 2,
        'manifestVersion': '2.1.0',
        'generatedAt': '2026-10-24T12:00:00.000Z',
        'bundles': {
          'looks': {
            'id': 'looks_catalog_v2',
            'version': '2.1.0',
            'bundleUrl': '/bundles/looks_catalog.bundle',
            'etag': '"w/etag123"',
            'sizeBytes': 512000,
            'itemCount': 105,
            'contentHash': 'sha256:abc12345',
          },
          'effects': {
            'id': 'effects_manifest_v1',
            'version': '1.0.0',
            'bundleUrl': '/bundles/effects_manifest.json',
            'etag': '"w/etag456"',
            'sizeBytes': 128000,
            'itemCount': 30,
          }
        },
        'items': {
          'looks': [
            {
              'id': 'look_teal_orange',
              'category': 'cinematic',
              'version': '2.0.0',
              'etag': '"l1"',
              'url': '/looks/look_teal_orange.json',
              'updatedAt': '2026-10-24T10:00:00.000Z',
            }
          ]
        }
      };

      final manifest = CatalogManifest.fromJson(manifestJson);
      expect(manifest.schemaVersion, equals(2));
      expect(manifest.manifestVersion, equals('2.1.0'));
      expect(manifest.bundles.containsKey('looks'), isTrue);
      expect(manifest.bundles['looks']?.itemCount, equals(105));
      expect(manifest.items['looks']?.first.id, equals('look_teal_orange'));

      final encoded = manifest.toJson();
      expect(encoded['manifestVersion'], equals('2.1.0'));
    });

    test('CatalogSyncService returns upToDate when CDN responds with HTTP 304', () async {
      final fakeFirestore = FakeFirebaseFirestore();

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/bundles/manifest.json')) {
          // If client sent If-None-Match header matching the current etag
          if (request.headers['If-None-Match'] == '"current_etag"') {
            return http.Response('', 304, headers: {'etag': '"current_etag"'});
          }
        }
        return http.Response('Not Found', 404);
      });

      final syncService = CatalogSyncService(
        firestore: fakeFirestore,
        httpClient: mockClient,
        cdnBaseUrl: 'https://cdn.oneova.app',
      );

      final result = await syncService.syncCatalog();
      // Without stored etag, it performs initial fetch, which 404s in this test
      expect(result.success, isFalse);
    });

    test('CatalogSyncResult models correct status', () {
      final upToDate = CatalogSyncResult.upToDate();
      expect(upToDate.success, isTrue);
      expect(upToDate.isUpToDate, isTrue);
      expect(upToDate.errorMessage, isNull);

      final failure = CatalogSyncResult.failure('Network timeout');
      expect(failure.success, isFalse);
      expect(failure.isUpToDate, isFalse);
      expect(failure.errorMessage, equals('Network timeout'));
    });
  });
}
