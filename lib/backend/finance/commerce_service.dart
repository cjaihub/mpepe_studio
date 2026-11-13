import '../../shops3d/data/share_ref.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pay/oneova_pay_service.dart';
import '../pay/oneova_pay_sheet.dart';

export '../pay/oneova_pay_service.dart' show PayoutStatus;

/// Live delivery price for one product to one spot (server `quoteDelivery`).
class DeliveryQuote {
  final String id;
  final double fee;
  final String currency;
  final double distanceKm;
  final int durationMin;

  const DeliveryQuote({required this.id, required this.fee, required this.currency, required this.distanceKm, required this.durationMin});
}

/// What the buyer sees after Oneova Pay closes.
enum CheckoutOutcome { paid, cancelled }

final commerceServiceProvider = Provider<CommerceService>((ref) => CommerceService(ref.read(oneovaPayServiceProvider)));

/// Oneova Biz orders on Oneova Pay (functions/src/commerce/orderEscrow.ts).
/// Prices, delivery fees and the escrow release are all decided on the server.
class CommerceService {
  CommerceService(this._pay);
  final OneovaPayService _pay;
  final FirebaseFunctions _fn = FirebaseFunctions.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final res = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data ?? const {});
    return Map<String, dynamic>.from(res.data);
  }

  Future<DeliveryQuote> quote({required String productId, required double lat, required double lng}) async {
    final r = await _call('quoteDelivery', {
      'productId': productId,
      'dropoff': {'lat': lat, 'lng': lng},
    });
    return DeliveryQuote(
      id: r['quoteId'] as String,
      fee: (r['fee'] as num).toDouble(),
      currency: r['currency'] as String,
      distanceKm: (r['distanceKm'] as num).toDouble(),
      durationMin: (r['durationMin'] as num).toInt(),
    );
  }

  /// Creates the order on the server, then pays it with Oneova Pay. The order
  /// turns "paid" only when the payment partner confirms the money.
  Future<(String, CheckoutOutcome)> checkout({
    required BuildContext context,
    required String productId,
    int quantity = 1,
    String? quoteId,
    String? address,
    String? variantId,
    String? title,
    Map<String, String>? customization,
    String? code,
  }) async {
    final r = await _call('createOrderCheckout', {
      'productId': productId,
      'quantity': quantity,
      'shareCode': ?ShareRef.current,
      'variantId': ?variantId,
      if (customization != null && customization.isNotEmpty) 'customization': customization,
      'code': ?code,
      'quoteId': ?quoteId,
      'address': ?address,
    });
    final orderId = r['orderId'] as String;
    if (!context.mounted) return (orderId, CheckoutOutcome.cancelled);
    final paid = await showOneovaPaySheet(
      context,
      purpose: 'order',
      refId: orderId,
      amountMinor: (r['totalMinor'] as num).toInt(),
      currency: r['currency'] as String,
      title: title ?? 'Your order',
    );
    if (paid?.succeeded == true) return (orderId, CheckoutOutcome.paid);
    // Closed without paying: the unpaid order is cancelled (a late approval
    // is still recorded by the server and refunded or applied).
    _call('cancelOrder', {'orderId': orderId}).ignore();
    return (orderId, CheckoutOutcome.cancelled);
  }

  Future<PayoutStatus> payoutStatus() => _pay.payoutStatus();

  Future<void> acceptDelivery(String orderId) => _call('acceptDelivery', {'orderId': orderId});
  Future<void> startJourney(String orderId) => _call('startJourney', {'orderId': orderId});
  Future<void> confirmDelivery(String orderId, String code) => _call('confirmDelivery', {'orderId': orderId, 'code': code});
  Future<void> cancelOrder(String orderId) => _call('cancelOrder', {'orderId': orderId});

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchOrder(String orderId) =>
      _db.collection('orders').doc(orderId).snapshots();

  /// Handover code, readable by the rider and the seller only.
  Stream<String?> watchHandoverCode(String orderId) => _db
      .collection('order_secrets')
      .doc(orderId)
      .snapshots()
      .map((d) => d.data()?['handoverCode'] as String?);

  /// The signed-in person's orders (as buyer, seller or rider), newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> myOrders() => _db
      .collection('orders')
      .where('participants', arrayContains: FirebaseAuth.instance.currentUser?.uid ?? '-')
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots();
}
