import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../backend/monetization/models/subscription_models.dart';
import '../../../../backend/monetization/services/subscription_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class SubscriptionTierScreen extends ConsumerStatefulWidget {
  const SubscriptionTierScreen({super.key});

  @override
  ConsumerState<SubscriptionTierScreen> createState() => _SubscriptionTierScreenState();
}

class _SubscriptionTierScreenState extends ConsumerState<SubscriptionTierScreen> {
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final tiersAsync = ref.watch(creatorTiersProvider(uid));

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Subscription Tiers', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.brandBlue),
            onPressed: () {
              // Open modal to create new tier
            },
          )
        ],
      ),
      body: tiersAsync.when(
        data: (tiers) {
          if (tiers.isEmpty) {
            return Center(child: Text('No tiers defined yet.', style: TextStyle(color: context.textMuted)));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: tiers.length,
            itemBuilder: (context, index) {
              final tier = tiers[index];
              return _buildTierCard(tier);
            },
          );
        },
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, st) => Center(child: Text('Error loading tiers: $e', style: TextStyle(color: context.textPrimary))),
      ),
    );
  }

  Widget _buildTierCard(SubscriptionTier tier) {
    return Card(
      color: context.surface,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tier.name, style: TextStyle(color: context.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                Text('\$${tier.price.toStringAsFixed(2)} / mo', style: const TextStyle(color: AppColors.brandBlue, fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
            Text(tier.description, style: TextStyle(color: context.textSecondary)),
            Divider(color: context.border, height: 24),
            _buildPerkRow(Icons.movie, 'Exclusive Videos', tier.perks.exclusiveVideos),
            _buildPerkRow(Icons.live_tv, 'Exclusive Live Streams', tier.perks.exclusiveLiveStreams),
            _buildPerkRow(Icons.chat, 'Subscriber Chat', tier.perks.subscriberChat),
            _buildPerkRow(Icons.shield, 'Private Community', tier.perks.privateCommunity),
            _buildPerkRow(Icons.timer, 'Early Access', tier.perks.earlyAccess),
            ...tier.perks.customPerks.map((p) => _buildPerkRow(Icons.star, p, true)),
          ],
        ),
      ),
    );
  }

  Widget _buildPerkRow(IconData icon, String text, bool enabled) {
    if (!enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
