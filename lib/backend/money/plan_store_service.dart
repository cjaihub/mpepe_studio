import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'money_models.dart';

/// Play subscription product per plan (base plans `monthly` and `yearly`).
/// Same ids as PLAN_PRODUCTS in functions/src/creator/planSubscriptions.ts.
const planProductIds = <OneovaPlan, String>{
  OneovaPlan.plus: 'oneova_plus',
  OneovaPlan.pro: 'oneova_pro',
  OneovaPlan.biz: 'oneova_biz',
};

OneovaPlan? planForProduct(String id) => planProductIds.entries.where((e) => e.value == id).map((e) => e.key).firstOrNull;

/// One price the person can pick: a plan on a monthly or yearly base plan.
class PlanOffer {
  final OneovaPlan plan;
  final bool yearly;
  final ProductDetails product;
  const PlanOffer(this.plan, this.yearly, this.product);

  String get price => product.price;
  double get rawPrice => product.rawPrice;
  String get currency => product.currencyCode;
}

final planStoreServiceProvider = Provider<PlanStoreService>((ref) {
  final s = PlanStoreService();
  ref.onDispose(s.dispose);
  return s;
});

/// Oneova Plus / Pro / Biz with Google Play subscriptions. Every purchase is
/// checked on the server (`verifySubscriptionPurchase`), which acknowledges it
/// and writes `subscriptions/{uid}`; the app only completes it after that.
class PlanStoreService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<({bool ok, String message})>.broadcast();

  Stream<({bool ok, String message})> get events => _events.stream;

  void _listen() {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('[Plans] stream error: $e'));
  }

  Future<List<PlanOffer>> loadOffers() async {
    _listen();
    if (!await _iap.isAvailable()) throw StateError('Google Play is not available on this device.');
    final res = await _iap.queryProductDetails(planProductIds.values.toSet());
    final offers = <PlanOffer>[];
    for (final p in res.productDetails) {
      final plan = planForProduct(p.id);
      if (plan == null) continue;
      var yearly = false;
      if (p is GooglePlayProductDetails && p.subscriptionIndex != null) {
        final offer = p.productDetails.subscriptionOfferDetails![p.subscriptionIndex!];
        // Skip promo offers; show the plain base-plan prices.
        if (offer.offerId != null) continue;
        yearly = offer.basePlanId.contains('year') || offer.pricingPhases.any((ph) => ph.billingPeriod == 'P1Y');
      }
      offers.add(PlanOffer(plan, yearly, p));
    }
    if (offers.isEmpty) throw StateError('Plans are being set up. Please check back soon.');
    return offers;
  }

  /// The person's current Play subscription, needed to switch plans in place.
  Future<GooglePlayPurchaseDetails?> _current() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final past = await addition.queryPastPurchases();
    return past.pastPurchases.where((p) => planForProduct(p.productID) != null).firstOrNull;
  }

  Future<void> buy(PlanOffer offer, {required OneovaPlan currentPlan}) async {
    _listen();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to choose a plan.');
    final old = currentPlan == OneovaPlan.free ? null : await _current();
    final PurchaseParam param;
    if (old != null && offer.product is GooglePlayProductDetails) {
      final upgrade = offer.plan.index > currentPlan.index;
      param = GooglePlayPurchaseParam(
        productDetails: offer.product,
        applicationUserName: uid,
        changeSubscriptionParam: ChangeSubscriptionParam(
          oldPurchaseDetails: old,
          // Upgrades start now (prorated); downgrades wait for the next renewal.
          replacementMode: upgrade ? ReplacementMode.chargeProratedPrice : ReplacementMode.deferred,
        ),
      );
    } else {
      param = PurchaseParam(productDetails: offer.product, applicationUserName: uid);
    }
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Re-checks past purchases (after reinstalling or on a new phone).
  Future<void> restore() async {
    _listen();
    await _iap.restorePurchases(applicationUserName: FirebaseAuth.instance.currentUser?.uid);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (planForProduct(p.productID) == null) continue;
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add((ok: true, message: 'Payment pending. Your plan turns on as soon as it completes.'));
        case PurchaseStatus.error:
          _events.add((ok: false, message: p.error?.message ?? 'The purchase did not go through.'));
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.canceled:
          _events.add((ok: false, message: ''));
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('verifySubscriptionPurchase').call<Map<String, dynamic>>({
        'purchaseToken': p.verificationData.serverVerificationData,
      });
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
      if (p.status == PurchaseStatus.purchased && res.data['active'] == true) {
        _events.add((ok: true, message: 'Welcome to Oneova ${_name(res.data['plan'])}!'));
      }
    } on FirebaseFunctionsException catch (e) {
      _events.add((ok: false, message: e.message ?? 'We’ll turn on your plan as soon as Google Play confirms it.'));
    } catch (e) {
      debugPrint('[Plans] verify failed: $e');
    }
  }

  String _name(Object? plan) => switch (plan) { 'plus' => 'Plus', 'pro' => 'Pro', 'biz' => 'Biz', _ => '' };

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
