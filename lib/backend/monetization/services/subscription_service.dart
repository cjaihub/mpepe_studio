import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/subscription_models.dart';

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

final creatorTiersProvider = StreamProvider.family<List<SubscriptionTier>, String>((ref, creatorId) {
  return ref.watch(subscriptionServiceProvider).streamCreatorTiers(creatorId);
});

final userSubscriptionsProvider = StreamProvider<List<UserSubscription>>((ref) {
  return ref.watch(subscriptionServiceProvider).streamMySubscriptions();
});

class SubscriptionService {
  // ignore: unused_field
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // ignore: unused_field
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Creators: Stream all tiers they have defined
  Stream<List<SubscriptionTier>> streamCreatorTiers(String creatorId) {
    return _firestore
        .collection('creators')
        .doc(creatorId)
        .collection('subscription_tiers')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => SubscriptionTier.fromFirestore(doc)).toList());
  }

  /// Creators: Create or update a tier
  Future<void> saveTier(SubscriptionTier tier) async {
    final uid = _userId;
    if (uid == null) return;
    
    // In production, updating pricing usually creates a new Stripe Price object via Cloud Function
    await _firestore
        .collection('creators')
        .doc(uid)
        .collection('subscription_tiers')
        .doc(tier.id)
        .set(tier.toMap());
  }

  /// Subscribers: Stream active subscriptions for the current user
  Stream<List<UserSubscription>> streamMySubscriptions() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('subscriptions')
        .where('status', isEqualTo: SubscriptionStatus.active.name)
        .snapshots()
        .map((snap) => snap.docs.map((doc) => UserSubscription.fromFirestore(doc)).toList());
  }

  /// Subscribers: Request to subscribe (triggers backend billing flow)
  Future<void> subscribeToTier(String creatorId, String tierId) async {
    final uid = _userId;
    if (uid == null) return;

    // This creates an intent document. A Firebase Extension (like Stripe) picks it up,
    // generates a checkout session URL or PaymentIntent, and returns it to the client.
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('checkout_sessions')
        .add({
      'creatorId': creatorId,
      'tierId': tierId,
      'type': 'subscription',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Subscribers: Cancel a subscription (turns off auto-renew)
  Future<void> cancelSubscription(String subscriptionId) async {
    final uid = _userId;
    if (uid == null) return;

    // Trigger backend cancellation via Stripe/Apple API
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('subscriptions')
        .doc(subscriptionId)
        .update({
      'cancelAtPeriodEnd': true,
    });
  }
  
  /// Subscribers: Renew a canceled subscription
  Future<void> renewSubscription(String subscriptionId) async {
    final uid = _userId;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('subscriptions')
        .doc(subscriptionId)
        .update({
      'cancelAtPeriodEnd': false,
    });
  }
}
