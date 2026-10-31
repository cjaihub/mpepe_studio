import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Lifetime coins gifted needed for each gifter level (index = level).
/// Same table as GIFTER_LEVELS in functions/src/coins/coinEconomy.ts.
const gifterLevels = [0, 50, 200, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000];

int gifterLevelFor(num lifetimeCoins) {
  var level = 0;
  for (var i = 0; i < gifterLevels.length; i++) {
    if (lifetimeCoins >= gifterLevels[i]) level = i;
  }
  return level;
}

/// Coins still needed to reach the next level, or null at the top.
int? coinsToNextLevel(num lifetimeCoins) {
  final level = gifterLevelFor(lifetimeCoins);
  if (level >= gifterLevels.length - 1) return null;
  return (gifterLevels[level + 1] - lifetimeCoins).ceil();
}

/// Play product ids of the coin packs (consumable). Coins credited per pack
/// are decided on the server (COIN_PACKS); these labels only order the list.
const coinPackIds = <String>{'coins_70', 'coins_350', 'coins_700', 'coins_1400', 'coins_3500', 'coins_7000', 'coins_17500'};

/// Coins shown per pack, bonus included (must match COIN_PACKS on the server).
const coinPackCoins = <String, int>{
  'coins_70': 70,
  'coins_350': 350,
  'coins_700': 720,
  'coins_1400': 1470,
  'coins_3500': 3750,
  'coins_7000': 7700,
  'coins_17500': 19600,
};

/// Live coin balance of the signed-in person (`wallets/{uid}`).
final coinBalanceProvider = StreamProvider<int>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(0);
  return FirebaseFirestore.instance
      .collection('wallets')
      .doc(uid)
      .snapshots()
      .map((d) => (d.data()?['balanceCoins'] as num?)?.toInt() ?? 0);
});

/// Lifetime coins gifted by [uid] (`gifter_stats/{uid}`), for level badges.
final gifterCoinsProvider = StreamProvider.family<int, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('gifter_stats')
      .doc(uid)
      .snapshots()
      .map((d) => (d.data()?['lifetimeCoins'] as num?)?.toInt() ?? 0);
});

final coinStoreServiceProvider = Provider<CoinStoreService>((ref) {
  final s = CoinStoreService();
  ref.onDispose(s.dispose);
  return s;
});

/// Buying Oneova Coins with Google Play Billing. Every purchase is checked
/// on the server (`verifyCoinPurchase`) before coins are added, and only
/// then completed, so a purchase interrupted by a crash is finished the next
/// time the store opens.
class CoinStoreService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<String>.broadcast();

  /// Friendly messages about purchases ("+720 coins added").
  Stream<String> get events => _events.stream;

  void _ensureListening() {
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      debugPrint('[CoinStore] purchase stream error: $e');
    });
  }

  Future<List<ProductDetails>> loadPacks() async {
    _ensureListening();
    if (!await _iap.isAvailable()) throw StateError('Google Play is not available on this device.');
    final res = await _iap.queryProductDetails(coinPackIds);
    if (res.productDetails.isEmpty) throw StateError('Coin packs are being set up. Please check back soon.');
    final packs = res.productDetails.toList()
      ..sort((a, b) => (coinPackCoins[a.id] ?? 0).compareTo(coinPackCoins[b.id] ?? 0));
    return packs;
  }

  Future<void> buy(ProductDetails pack) async {
    _ensureListening();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to buy coins.');
    // The account id ties the Play purchase to this Oneova account on the server.
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: pack, applicationUserName: uid),
      autoConsume: false,
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add('Payment pending. Coins arrive as soon as it completes.');
        case PurchaseStatus.error:
          _events.add(p.error?.message ?? 'The purchase did not go through.');
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('verifyCoinPurchase').call<Map<String, dynamic>>({
        'productId': p.productID,
        'purchaseToken': p.verificationData.serverVerificationData,
      });
      final coins = (res.data['coins'] as num?)?.toInt() ?? 0;
      if (res.data['alreadyCredited'] != true) _events.add('+$coins coins added');
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    } on FirebaseFunctionsException catch (e) {
      // Not completed: Play redelivers it and we try again next time.
      _events.add(e.message ?? 'We’ll add your coins as soon as Google Play confirms the payment.');
    } catch (e) {
      debugPrint('[CoinStore] verify failed: $e');
    }
  }

  /// Sends a gift to a person (not in a live). Returns the new balance.
  Future<int> sendGift({required String toUid, required String giftId, int qty = 1, String? message}) async {
    final res = await FirebaseFunctions.instance.httpsCallable('sendUserGift').call<Map<String, dynamic>>({
      'toUid': toUid,
      'giftId': giftId,
      'qty': qty,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    });
    return (res.data['balanceCoins'] as num?)?.toInt() ?? 0;
  }

  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
