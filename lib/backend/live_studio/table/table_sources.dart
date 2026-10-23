// LIVE STUDIO v2 — data the table renders (workstream #5).
//
// - Goods (decision Q5): the host's Biz `products` first, falling back to the
//   per-stream `live_streams/{id}/products`. The server resolves which one
//   is on the table (`GoodsRef`); this reads the product it points to.
// - Watch catalog (decision Q7): ONLY admin-curated `live_watch_catalog`
//   entries. Read-only for clients; no free-form URLs anywhere.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../contracts/studio_contracts.dart';

// ─── Goods ───────────────────────────────────────────────────────────────────

@immutable
class TableGoodsItem {
  const TableGoodsItem({
    required this.source,
    required this.productId,
    required this.name,
    this.description = '',
    this.price,
    this.currency = 'USD',
    this.imageUrl = '',
    this.productUrl = '',
  });

  final GoodsSource source;
  final String productId;
  final String name;
  final String description;
  final num? price;
  final String currency;
  final String imageUrl;
  final String productUrl;

  /// Biz products use `name` (search) or `title` (Biz feed).
  factory TableGoodsItem.fromDoc(GoodsSource source, String id, Map<String, dynamic> d) =>
      TableGoodsItem(
        source: source,
        productId: id,
        name: _s(d['name']).isNotEmpty ? _s(d['name']) : _s(d['title']),
        description: _s(d['description']),
        price: d['price'] is num ? d['price'] as num : num.tryParse(_s(d['price'])),
        currency: _s(d['currency']).isEmpty ? 'USD' : _s(d['currency']),
        imageUrl: _s(d['imageUrl']),
        productUrl: _s(d['productUrl']),
      );

  String get formattedPrice => formatTablePrice(price, currency);
}

String _s(Object? v) => v is String ? v.trim() : '';

/// "$12.50", "TSh 5,000" … Empty when there is no price.
String formatTablePrice(num? price, String currency) {
  if (price == null) return '';
  try {
    final f = NumberFormat.simpleCurrency(name: currency.isEmpty ? 'USD' : currency.toUpperCase());
    return f.format(price);
  } catch (_) {
    return '$currency ${price.toStringAsFixed(2)}';
  }
}

abstract class TableGoodsStore {
  /// The product a [GoodsRef] points to; null when it does not exist.
  Stream<TableGoodsItem?> watch(String streamId, GoodsRef ref);
}

class FirestoreTableGoodsStore implements TableGoodsStore {
  FirestoreTableGoodsStore([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  Stream<TableGoodsItem?> watch(String streamId, GoodsRef ref) {
    final path = ref.source == GoodsSource.biz
        ? 'products/${ref.productId}'
        : '${StudioPaths.streams}/$streamId/products/${ref.productId}';
    return _db.doc(path).snapshots().map((d) {
      final data = d.data();
      return data == null ? null : TableGoodsItem.fromDoc(ref.source, d.id, data);
    });
  }
}

final tableGoodsStoreProvider = Provider<TableGoodsStore>((ref) => FirestoreTableGoodsStore());

/// (streamId, source wire, productId).
typedef TableGoodsKey = (String, String, String);

final tableGoodsProvider =
    StreamProvider.autoDispose.family<TableGoodsItem?, TableGoodsKey>((ref, key) {
  final (streamId, source, productId) = key;
  return ref
      .watch(tableGoodsStoreProvider)
      .watch(streamId, GoodsRef(source: GoodsSource.fromWire(source), productId: productId));
});

// ─── Watch catalog ───────────────────────────────────────────────────────────

@immutable
class WatchCatalogEntry {
  const WatchCatalogEntry({
    required this.id,
    required this.kind,
    this.title = '',
    this.subtitle = '',
    this.posterUrl = '',
    this.hlsUrl = '',
    this.rightsHolder = '',
    this.territories = const [],
    this.validFromMs,
    this.validUntilMs,
  });

  final String id;
  final TableMode kind; // match | movie
  final String title;
  final String subtitle;
  final String posterUrl;
  final String hlsUrl;
  final String rightsHolder;
  final List<String> territories;
  final int? validFromMs;
  final int? validUntilMs;

  factory WatchCatalogEntry.fromDoc(String id, Map<String, dynamic> d) => WatchCatalogEntry(
        id: id,
        kind: d['kind'] == 'movie'
            ? TableMode.movie
            : d['kind'] == 'match'
                ? TableMode.match
                : TableMode.goods, // invalid kind → never available
        title: _s(d['title']),
        subtitle: _s(d['subtitle']),
        posterUrl: _s(d['posterUrl']),
        hlsUrl: _s(d['hlsUrl']),
        rightsHolder: _s(d['rightsHolder']),
        territories: [
          if (d['territories'] is List)
            for (final t in d['territories'] as List)
              if (t is String) t,
        ],
        validFromMs: _ms(d['validFrom']),
        validUntilMs: _ms(d['validUntil']),
      );

  /// Same rules as the server (`validateCatalogEntry` in table_logic.ts).
  bool isAvailableAt(int nowMs, {TableMode? mode}) {
    if (!kind.isWatchParty) return false;
    if (mode != null && mode != kind) return false;
    if (!hlsUrl.startsWith('https://')) return false;
    if (rightsHolder.isEmpty || territories.isEmpty) return false;
    if (validFromMs != null && nowMs < validFromMs!) return false;
    if (validUntilMs != null && nowMs >= validUntilMs!) return false;
    return true;
  }
}

int? _ms(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch;
  return null;
}

abstract class WatchCatalogStore {
  Stream<WatchCatalogEntry?> watchEntry(String id);

  /// Entries of [kind] (match | movie), unfiltered.
  Stream<List<WatchCatalogEntry>> watchKind(TableMode kind);
}

class FirestoreWatchCatalogStore implements WatchCatalogStore {
  FirestoreWatchCatalogStore([FirebaseFirestore? db]) : _db = db ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  @override
  Stream<WatchCatalogEntry?> watchEntry(String id) =>
      _db.doc('${StudioPaths.watchCatalog}/$id').snapshots().map((d) {
        final data = d.data();
        return data == null ? null : WatchCatalogEntry.fromDoc(d.id, data);
      });

  @override
  Stream<List<WatchCatalogEntry>> watchKind(TableMode kind) => _db
      .collection(StudioPaths.watchCatalog)
      .where('kind', isEqualTo: kind.wire)
      .limit(25)
      .snapshots()
      .map((q) => [for (final d in q.docs) WatchCatalogEntry.fromDoc(d.id, d.data())]);
}

final watchCatalogStoreProvider = Provider<WatchCatalogStore>((ref) => FirestoreWatchCatalogStore());

/// Wall clock for client-side catalog filtering (display only; the server
/// re-validates with its own clock).
final tableNowMsProvider = Provider<int Function()>((ref) => () => DateTime.now().millisecondsSinceEpoch);

final watchCatalogEntryProvider =
    StreamProvider.autoDispose.family<WatchCatalogEntry?, String>((ref, id) =>
        ref.watch(watchCatalogStoreProvider).watchEntry(id));

/// Currently available entries of a watch mode, for the host's picker.
final watchCatalogAvailableProvider =
    StreamProvider.autoDispose.family<List<WatchCatalogEntry>, TableMode>((ref, kind) {
  final now = ref.watch(tableNowMsProvider);
  return ref.watch(watchCatalogStoreProvider).watchKind(kind).map(
      (list) => [for (final e in list) if (e.isAvailableAt(now(), mode: kind)) e]);
});
