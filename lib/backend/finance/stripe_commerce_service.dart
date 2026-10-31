import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart';
import 'stripe_config.dart';

/// Live delivery price for one product to one spot (server `quoteDelivery`).
class DeliveryQuote {
  final String id;
  final double fee;
  final String currency;
  final double distanceKm;
  final int durationMin;

  const DeliveryQuote({required this.id, required this.fee, required this.currency, required this.distanceKm, required this.durationMin});
}

/// Seller / rider payout account state (server `stripePayoutStatus`).
class PayoutStatus {
  final bool connected;
  final bool payoutsEnabled;
  final bool detailsSubmitted;
  const PayoutStatus({this.connected = false, this.payoutsEnabled = false, this.detailsSubmitted = false});
}

/// What the buyer sees after the Payment Sheet closes.
enum CheckoutOutcome { paid, cancelled }

final stripeCommerceServiceProvider = Provider<StripeCommerceService>((ref) => StripeCommerceService());

/// Oneova Biz payments on Stripe (see functions/src/commerce/stripeEscrow.ts).
/// The app only holds the publishable key; prices, delivery fees and the
/// escrow release are all decided on the server.
class StripeCommerceService {
  final FirebaseFunctions _fn = FirebaseFunctions.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _ready = false;

  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final res = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data ?? const {});
    return Map<String, dynamic>.from(res.data);
  }

  /// Sets the publishable key: the build's `STRIPE_PUBLISHABLE_KEY`, else the
  /// server's `stripeConfig`. Throws a friendly StateError when not set up.
  Future<void> ensureReady() async {
    if (_ready) return;
    var key = StripeConfig.publishableKey;
    if (!key.startsWith('pk_')) {
      final cfg = await _call('stripeConfig');
      key = (cfg['publishableKey'] ?? '').toString();
    }
    if (!key.startsWith('pk_')) throw StateError('Payments are being set up. Please try again soon.');
    Stripe.publishableKey = key;
    Stripe.merchantIdentifier = 'merchant.com.oneova.app';
    await Stripe.instance.applySettings();
    _ready = true;
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

  /// Creates the order on the server and shows Stripe's Payment Sheet.
  /// Returns the order id with the outcome; the order turns "paid" when
  /// Stripe's webhook confirms the payment.
  Future<(String, CheckoutOutcome)> checkout({
    required BuildContext context,
    required String productId,
    int quantity = 1,
    String? quoteId,
    String? address,
  }) async {
    await ensureReady();
    final r = await _call('createOrderCheckout', {
      'productId': productId,
      'quantity': quantity,
      if (quoteId != null) 'quoteId': quoteId,
      if (address != null) 'address': address,
    });
    final orderId = r['orderId'] as String;
    if (!context.mounted) return (orderId, CheckoutOutcome.cancelled);
    final dark = Theme.of(context).brightness == Brightness.dark;
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        merchantDisplayName: 'Oneova',
        paymentIntentClientSecret: r['clientSecret'] as String,
        customerId: r['customerId'] as String,
        customerEphemeralKeySecret: r['ephemeralKey'] as String,
        style: dark ? ThemeMode.dark : ThemeMode.light,
        googlePay: PaymentSheetGooglePay(
          merchantCountryCode: 'US',
          currencyCode: (r['currency'] as String).toUpperCase(),
          testEnv: kDebugMode,
        ),
        appearance: const PaymentSheetAppearance(
          colors: PaymentSheetAppearanceColors(primary: AppColors.brandBlue),
          shapes: PaymentSheetShape(borderRadius: 12),
        ),
      ),
    );
    try {
      await Stripe.instance.presentPaymentSheet();
      return (orderId, CheckoutOutcome.paid);
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        // Leaves no held money behind: the unpaid order is cancelled.
        _call('cancelOrder', {'orderId': orderId}).ignore();
        return (orderId, CheckoutOutcome.cancelled);
      }
      rethrow;
    }
  }

  /// Opens Stripe's onboarding so a seller or rider can receive payouts.
  Future<void> startPayoutOnboarding({String? countryCode}) async {
    final r = await _call('stripeConnectOnboard', {if (countryCode != null) 'country': countryCode});
    final url = Uri.parse(r['url'] as String);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<PayoutStatus> payoutStatus() async {
    final r = await _call('stripePayoutStatus');
    return PayoutStatus(
      connected: r['connected'] == true,
      payoutsEnabled: r['payoutsEnabled'] == true,
      detailsSubmitted: r['detailsSubmitted'] == true,
    );
  }

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
