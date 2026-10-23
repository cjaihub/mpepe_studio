// LIVE STUDIO v2 — studio background catalog (ids + labels only).
//
// A deliberately minimal reader of assets/live_studio/studio-geometry.json.
// The geometry workstream (#3) owns the full typed loader; when it lands, the
// integrator can override [studioCatalogPortProvider] with an adapter over it
// and delete [AssetStudioCatalog].

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String kStudioGeometryAsset = 'assets/live_studio/studio-geometry.json';

@immutable
class StudioCatalogEntry {
  final String id;
  final String label;
  const StudioCatalogEntry({required this.id, required this.label});

  @override
  bool operator ==(Object other) =>
      other is StudioCatalogEntry && other.id == id && other.label == label;
  @override
  int get hashCode => Object.hash(id, label);
}

/// Lists the studios a host can pick.
abstract class StudioCatalogPort {
  Future<List<StudioCatalogEntry>> load();
}

/// Parses `{ "studios": { "<id>": { "label": "…" } } }`. Missing labels fall
/// back to the id; a malformed document yields an empty list.
List<StudioCatalogEntry> parseStudioCatalog(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  if (root is! Map || root['studios'] is! Map) return const [];
  final studios = root['studios'] as Map;
  return [
    for (final e in studios.entries)
      if (e.key is String)
        StudioCatalogEntry(
          id: e.key as String,
          label: e.value is Map && (e.value as Map)['label'] is String
              ? (e.value as Map)['label'] as String
              : e.key as String,
        ),
  ];
}

class AssetStudioCatalog implements StudioCatalogPort {
  AssetStudioCatalog([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;

  @override
  Future<List<StudioCatalogEntry>> load() async =>
      parseStudioCatalog(await _bundle.loadString(kStudioGeometryAsset));
}

final studioCatalogPortProvider = Provider<StudioCatalogPort>((ref) => AssetStudioCatalog());

final studioCatalogProvider = FutureProvider<List<StudioCatalogEntry>>(
    (ref) => ref.watch(studioCatalogPortProvider).load());
