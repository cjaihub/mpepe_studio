import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Manifest entry for an individual asset bundle (looks, effects, models, skills).
class BundleManifestEntry {
  final String id;
  final String version;
  final String bundleUrl;
  final String? etag;
  final int sizeBytes;
  final int itemCount;
  final String? contentHash;
  final DateTime? updatedAt;

  const BundleManifestEntry({
    required this.id,
    required this.version,
    required this.bundleUrl,
    this.etag,
    required this.sizeBytes,
    required this.itemCount,
    this.contentHash,
    this.updatedAt,
  });

  factory BundleManifestEntry.fromJson(Map<String, dynamic> json) {
    return BundleManifestEntry(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      bundleUrl: json['bundleUrl'] as String? ?? '',
      etag: json['etag'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      contentHash: json['contentHash'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'bundleUrl': bundleUrl,
        if (etag != null) 'etag': etag,
        'sizeBytes': sizeBytes,
        'itemCount': itemCount,
        if (contentHash != null) 'contentHash': contentHash,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };
}

/// Individual item metadata inside the manifest for fine-grained delta inspection.
class ItemManifestEntry {
  final String id;
  final String category;
  final String version;
  final String etag;
  final String url;
  final DateTime updatedAt;

  const ItemManifestEntry({
    required this.id,
    required this.category,
    required this.version,
    required this.etag,
    required this.url,
    required this.updatedAt,
  });

  factory ItemManifestEntry.fromJson(Map<String, dynamic> json) {
    return ItemManifestEntry(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      version: json['version'] as String? ?? '1.0.0',
      etag: json['etag'] as String? ?? '',
      url: json['url'] as String? ?? '',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'version': version,
        'etag': etag,
        'url': url,
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// Root catalog manifest describing all available bundles and delta entries.
class CatalogManifest {
  final int schemaVersion;
  final String manifestVersion;
  final DateTime generatedAt;
  final Map<String, BundleManifestEntry> bundles;
  final Map<String, List<ItemManifestEntry>> items;

  const CatalogManifest({
    required this.schemaVersion,
    required this.manifestVersion,
    required this.generatedAt,
    required this.bundles,
    this.items = const {},
  });

  factory CatalogManifest.fromJson(Map<String, dynamic> json) {
    final rawBundles = json['bundles'] as Map<String, dynamic>? ?? {};
    final bundlesMap = rawBundles.map(
      (k, v) => MapEntry(k, BundleManifestEntry.fromJson(v as Map<String, dynamic>)),
    );

    final rawItems = json['items'] as Map<String, dynamic>? ?? {};
    final itemsMap = rawItems.map(
      (k, v) => MapEntry(
        k,
        (v as List<dynamic>? ?? [])
            .map((item) => ItemManifestEntry.fromJson(item as Map<String, dynamic>))
            .toList(),
      ),
    );

    return CatalogManifest(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      manifestVersion: json['manifestVersion'] as String? ?? '1.0.0',
      generatedAt: json['generatedAt'] != null
          ? DateTime.tryParse(json['generatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      bundles: bundlesMap,
      items: itemsMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'manifestVersion': manifestVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'bundles': bundles.map((k, v) => MapEntry(k, v.toJson())),
        'items': items.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
      };
}

/// Status and summary of a catalog delta sync operation.
class CatalogSyncResult {
  final bool success;
  final bool isUpToDate;
  final List<String> bundlesUpdated;
  final int totalItemsSynced;
  final String? errorMessage;
  final DateTime timestamp;

  const CatalogSyncResult({
    required this.success,
    required this.isUpToDate,
    this.bundlesUpdated = const [],
    this.totalItemsSynced = 0,
    this.errorMessage,
    required this.timestamp,
  });

  factory CatalogSyncResult.upToDate() => CatalogSyncResult(
        success: true,
        isUpToDate: true,
        timestamp: DateTime.now(),
      );

  factory CatalogSyncResult.failure(String message) => CatalogSyncResult(
        success: false,
        isUpToDate: false,
        errorMessage: message,
        timestamp: DateTime.now(),
      );
}

/// High-scale catalog delivery and delta sync service.
///
/// Features:
/// 1. Cloud CDN / Firebase Hosting manifest check with HTTP ETags (`If-None-Match`).
/// 2. If 304 Not Modified, avoids re-downloading manifests and bundles (0 cloud egress / 0 Firestore reads).
/// 3. Downloads Firestore Data Bundles and ingests them via `loadBundle` into the Firestore client cache.
/// 4. Named query resolution via cached bundles for instantaneous, offline-ready UI rendering.
/// 5. Delta sync for effects, models, and skill packs with version tracking in [SharedPreferences].
class CatalogSyncService {
  final FirebaseFirestore _firestore;
  final http.Client _httpClient;
  final SharedPreferences? _prefs;
  final String _cdnBaseUrl;

  static const String prefManifestVersionKey = 'looks_catalog_manifest_version';
  static const String prefManifestEtagKey = 'looks_catalog_manifest_etag';
  static const String prefBundleEtagPrefix = 'looks_bundle_etag_';
  static const String prefLastSyncTimeKey = 'looks_catalog_last_sync_time';

  CatalogSyncService({
    FirebaseFirestore? firestore,
    http.Client? httpClient,
    this._prefs,
    String? cdnBaseUrl,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _httpClient = httpClient ?? http.Client(),
        _cdnBaseUrl = (cdnBaseUrl ?? 'https://mpepe-2b4bd.web.app').replaceAll(RegExp(r'/+$'), '');

  /// Resolves the absolute CDN URL for a manifest or bundle path.
  String _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$_cdnBaseUrl$cleanPath';
  }

  /// Performs an end-to-end delta sync of the Looks catalog.
  ///
  /// Returns [CatalogSyncResult] detailing whether updates were applied.
  Future<CatalogSyncResult> syncCatalog({bool force = false}) async {
    try {
      final manifestUrl = _resolveUrl('/bundles/manifest.json');
      final storedEtag = force ? null : _prefs?.getString(prefManifestEtagKey);

      final headers = <String, String>{
        'Accept': 'application/json',
        'If-None-Match': ?storedEtag,
      };

      final response = await _httpClient.get(Uri.parse(manifestUrl), headers: headers);

      if (response.statusCode == 304 && !force) {
        debugPrint('[CatalogSync] Manifest is up-to-date (HTTP 304).');
        await _prefs?.setString(prefLastSyncTimeKey, DateTime.now().toIso8601String());
        return CatalogSyncResult.upToDate();
      }

      if (response.statusCode != 200) {
        return CatalogSyncResult.failure(
          'Failed to fetch catalog manifest: HTTP ${response.statusCode}',
        );
      }

      final manifestJson = jsonDecode(response.body) as Map<String, dynamic>;
      final manifest = CatalogManifest.fromJson(manifestJson);
      final newManifestEtag = response.headers['etag'];

      final updatedBundles = <String>[];
      int totalItems = 0;

      // Ingest looks Firestore data bundle if changed
      final looksBundle = manifest.bundles['looks'];
      if (looksBundle != null) {
        final synced = await _syncFirestoreBundle(looksBundle, force: force);
        if (synced) {
          updatedBundles.add('looks');
          totalItems += looksBundle.itemCount;
        }
      }

      // Sync non-bundle manifests (effects, models, skills)
      for (final entry in manifest.bundles.entries) {
        if (entry.key == 'looks') continue;
        final synced = await _syncStaticBundle(entry.key, entry.value, force: force);
        if (synced) {
          updatedBundles.add(entry.key);
          totalItems += entry.value.itemCount;
        }
      }

      // Persist updated manifest metadata
      if (newManifestEtag != null) {
        await _prefs?.setString(prefManifestEtagKey, newManifestEtag);
      }
      await _prefs?.setString(prefManifestVersionKey, manifest.manifestVersion);
      await _prefs?.setString(prefLastSyncTimeKey, DateTime.now().toIso8601String());

      return CatalogSyncResult(
        success: true,
        isUpToDate: updatedBundles.isEmpty,
        bundlesUpdated: updatedBundles,
        totalItemsSynced: totalItems,
        timestamp: DateTime.now(),
      );
    } catch (e, stack) {
      debugPrint('[CatalogSync] Error syncing catalog: $e\n$stack');
      return CatalogSyncResult.failure(e.toString());
    }
  }

  /// Downloads and loads a Firestore Data Bundle directly into local Firestore cache.
  Future<bool> _syncFirestoreBundle(BundleManifestEntry bundle, {bool force = false}) async {
    final bundlePrefKey = '$prefBundleEtagPrefix${bundle.id}';
    final storedEtag = force ? null : _prefs?.getString(bundlePrefKey);

    final url = _resolveUrl(bundle.bundleUrl);
    final headers = <String, String>{
      'If-None-Match': ?storedEtag,
    };

    final response = await _httpClient.get(Uri.parse(url), headers: headers);
    if (response.statusCode == 304 && !force) {
      debugPrint('[CatalogSync] Bundle ${bundle.id} is up-to-date (HTTP 304).');
      return false;
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to download bundle ${bundle.id}: HTTP ${response.statusCode}');
    }

    final Uint8List bundleBytes = response.bodyBytes;
    debugPrint('[CatalogSync] Loading Firestore data bundle ${bundle.id} (${bundleBytes.length} bytes)...');
    
    // Ingest into Firestore client cache
    await _firestore.loadBundle(bundleBytes).stream.last;

    final newEtag = response.headers['etag'] ?? bundle.etag;
    if (newEtag != null) {
      await _prefs?.setString(bundlePrefKey, newEtag);
    }
    return true;
  }

  /// Ingests or verifies a static asset manifest (effects, models, skills).
  Future<bool> _syncStaticBundle(String category, BundleManifestEntry bundle, {bool force = false}) async {
    final bundlePrefKey = '$prefBundleEtagPrefix$category';
    final storedEtag = force ? null : _prefs?.getString(bundlePrefKey);

    if (!force && storedEtag != null && storedEtag == bundle.etag) {
      return false;
    }

    final url = _resolveUrl(bundle.bundleUrl);
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final newEtag = response.headers['etag'] ?? bundle.etag;
      if (newEtag != null) {
        await _prefs?.setString(bundlePrefKey, newEtag);
      }
      return true;
    }
    return false;
  }

  /// Loads looks from Firestore using the named query defined in the data bundle.
  /// Falls back to standard Firestore collection query if named query is not yet cached.
  Future<List<Map<String, dynamic>>> getPublishedLooks() async {
    try {
      // Attempt to load from the bundle's named query first
      final snapshot = await _firestore.namedQueryGet(
        'latest-published-looks',
        options: const GetOptions(source: Source.cache),
      );
      return snapshot.docs.map((d) => d.data()).toList();
    } catch (_) {
      // Fallback to direct collection query (with cache-first source)
      final snapshot = await _firestore
          .collection('lookCatalog')
          .where('isPublished', isEqualTo: true)
          .get(const GetOptions(source: Source.cache));
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((d) => d.data()).toList();
      }
      final serverSnapshot = await _firestore
          .collection('lookCatalog')
          .where('isPublished', isEqualTo: true)
          .get(const GetOptions(source: Source.server));
      return serverSnapshot.docs.map((d) => d.data()).toList();
    }
  }
}

/// Riverpod providers for catalog synchronization.
final catalogSyncServiceProvider = Provider<CatalogSyncService>((ref) {
  return CatalogSyncService();
});

/// Riverpod Notifier for catalog synchronization status.
class CatalogSyncStatusNotifier extends Notifier<CatalogSyncResult?> {
  @override
  CatalogSyncResult? build() => null;

  void updateStatus(CatalogSyncResult? result) => state = result;
}

final catalogSyncStatusProvider =
    NotifierProvider<CatalogSyncStatusNotifier, CatalogSyncResult?>(CatalogSyncStatusNotifier.new);
