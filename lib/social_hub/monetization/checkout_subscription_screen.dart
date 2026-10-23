import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/monetization/models/subscription_models.dart';
import '../../../backend/monetization/services/subscription_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CheckoutSubscriptionScreen extends ConsumerWidget {
  final String creatorId;

  const CheckoutSubscriptionScreen({
    super.key,
    required this.creatorId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersAsync = ref.watch(creatorTiersProvider(creatorId));

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: tiersAsync.when(
        data: (tiers) {
          if (tiers.isEmpty) {
            return Center(child: Text('No subscriptions available.', style: TextStyle(color: context.textSecondary)));
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              Text(
                'Support the Creator',
                style: TextStyle(color: context.textPrimary, fontSize: 32, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock exclusive benefits and join the inner circle.',
                style: TextStyle(color: context.textSecondary, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ...tiers.map((t) => _buildCheckoutTier(context, ref, t)),
            ],
          );
        },
        loading: () => Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, st) => Center(child: Text('Error: $e', style: TextStyle(color: context.textPrimary))),
      ),
    );
  }

  Widget _buildCheckoutTier(BuildContext context, WidgetRef ref, SubscriptionTier tier) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 2),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tier.name, style: TextStyle(color: context.textPrimary, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(tier.description, style: TextStyle(color: context.textSecondary, fontSize: 14), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Text('\$${tier.price.toStringAsFixed(2)}', style: TextStyle(color: AppColors.brandBlue, fontSize: 48, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          Text('/ month', style: TextStyle(color: context.textMuted), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          _buildPerkRow(context, Icons.movie, 'Exclusive Videos', tier.perks.exclusiveVideos),
          _buildPerkRow(context, Icons.live_tv, 'Exclusive Live Streams', tier.perks.exclusiveLiveStreams),
          _buildPerkRow(context, Icons.chat, 'Subscriber Chat', tier.perks.subscriberChat),
          _buildPerkRow(context, Icons.shield, 'Private Community', tier.perks.privateCommunity),
          _buildPerkRow(context, Icons.timer, 'Early Access', tier.perks.earlyAccess),
          ...tier.perks.customPerks.map((p) => _buildPerkRow(context, Icons.star, p, true)),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              ref.read(subscriptionServiceProvider).subscribeToTier(tier.creatorId, tier.id);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Processing checkout...')));
              context.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Subscribe Now', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildPerkRow(BuildContext context, IconData icon, String text, bool enabled) {
    if (!enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.green, size: 24),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
