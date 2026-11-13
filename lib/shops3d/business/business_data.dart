import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';

/// The seller's orders (newest first).
final sellerOrdersProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(shop3dRepositoryProvider).watchSellerOrders(limit: 400),
);

final myCodesProvider = StreamProvider.autoDispose<List<DiscountCode>>(
  (ref) => ref.watch(shop3dRepositoryProvider).watchMyCodes(),
);

final myDailyStatsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(shop3dRepositoryProvider).watchDailyStats(days: 180),
);

/// Order statuses where money has been paid and the seller still has work.
const toPrepareStatuses = {'paid'};
const inDeliveryStatuses = {'assigned', 'in_transit', 'releasing'};
const paidStatuses = {'paid', 'assigned', 'in_transit', 'releasing', 'completed'};

DateTime? orderTime(Map<String, dynamic> o) {
  final t = o['createdAt'];
  try {
    return (t as dynamic)?.toDate() as DateTime?;
  } catch (_) {
    return null;
  }
}

num orderItems(Map<String, dynamic> o) => (o['itemsAmount'] as num?) ?? (o['totalAmount'] as num?) ?? 0;

/// Products at or under the seller's low-stock line.
List<ShopProduct> lowStock(List<ShopProduct> products, int line) => [
      for (final p in products)
        if (p.active && p.stock != null && p.stock! <= line) p,
    ];

String fulfilmentLabel(String? step) => switch (step) {
      'packed' => 'Packed',
      'ready' => 'Ready',
      'shipped' => 'Shipped',
      _ => 'New',
    };

/// The next fulfilment step and its button label, or null when done.
(String, String)? nextFulfilment(String? step) => switch (step) {
      null || 'new' => ('packed', 'Mark packed'),
      'packed' => ('ready', 'Mark ready'),
      'ready' => ('shipped', 'Mark shipped'),
      _ => null,
    };
