import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../backend/monetization/models/monetization_models.dart';
import '../../../../backend/monetization/services/monetization_service.dart';
import '../../../../backend/finance/services/ledger_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class MonetizationDashboard extends ConsumerWidget {
  const MonetizationDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(creatorMonetizationProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Monetization Hub', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: profileAsync.when(
        data: (profile) => _buildDashboard(context, ref, profile),
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (e, st) => Center(child: Text('Error loading monetization data: $e', style: TextStyle(color: context.textPrimary))),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, WidgetRef ref, CreatorMonetizationProfile profile) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Revenue Summary derived from immutable ledger
        _buildRevenueCard(profile, ref),
        const SizedBox(height: 24),
        
        Text(
          'Active Features',
          style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        // Render Active Features First
        ...MonetizationFeatureType.values.where((type) {
          final status = profile.features[type]?.status ?? MonetizationStatus.notEligible;
          return status == MonetizationStatus.active;
        }).map((type) => _buildFeatureCard(context, ref, type, profile.features[type]!)),
        
        const SizedBox(height: 24),
        Text(
          'Eligible to Unlock',
          style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        // Render Eligible but inactive features
        ...MonetizationFeatureType.values.where((type) {
          // Assume eligible if not mapped, for demonstration purposes. In reality, backend sets eligibility.
          final status = profile.features[type]?.status ?? MonetizationStatus.eligible;
          return status == MonetizationStatus.eligible;
        }).map((type) => _buildFeatureCard(context, ref, type, MonetizationFeature(type: type, status: MonetizationStatus.eligible))),
        
      ],
    );
  }

  Widget _buildRevenueCard(CreatorMonetizationProfile profile, WidgetRef ref) {
    final balanceAsync = ref.watch(currentBalanceProvider);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.brandBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Ledger Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          balanceAsync.when(
            data: (balance) => Text('\$${balance.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
            loading: () => const AnimatedLoadingIndicator(color: Colors.white),
            error: (_, _) => const Text('Error', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pending Payout: \$${profile.pendingPayout.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brandBlue),
                child: const Text('Withdraw'),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, WidgetRef ref, MonetizationFeatureType type, MonetizationFeature feature) {
    final isActive = feature.status == MonetizationStatus.active;
    
    String title = type.name.replaceAll(RegExp(r'(?<!^)(?=[A-Z])'), ' ');
    title = title[0].toUpperCase() + title.substring(1);
    
    IconData iconData = Icons.monetization_on;
    if (type == MonetizationFeatureType.subscriptions) iconData = Icons.star;
    if (type == MonetizationFeatureType.digitalProducts) iconData = Icons.shopping_bag;
    if (type == MonetizationFeatureType.premiumSeries) iconData = Icons.movie;
    if (type == MonetizationFeatureType.brandCollaborations) iconData = Icons.handshake;

    return Card(
      color: context.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? AppColors.brandBlue.withValues(alpha: 0.2) : context.surfaceMid,
          child: Icon(iconData, color: isActive ? AppColors.brandBlue : context.textMuted),
        ),
        title: Text(title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        subtitle: Text(isActive ? 'Active & earning' : 'Ready to enable', style: TextStyle(color: isActive ? Colors.greenAccent : context.textMuted)),
        trailing: Switch(
          value: isActive,
          activeThumbColor: AppColors.brandBlue,
          onChanged: (val) {
            if (val) {
              ref.read(monetizationServiceProvider).enableFeature(type);
            } else {
              ref.read(monetizationServiceProvider).disableFeature(type);
            }
          },
        ),
      ),
    );
  }
}
