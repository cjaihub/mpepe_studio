import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../backend/monetization/models/monetization_models.dart';
import '../../../../backend/monetization/services/monetization_service.dart';
import '../../../../backend/finance/services/ledger_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import 'widgets/smart_income_channel_view.dart';

enum _MonetizationViewMode {
  smartIncome('Smart Income Channel', Icons.auto_graph_rounded),
  features('Payouts & Features', Icons.account_balance_wallet_rounded);

  final String label;
  final IconData icon;
  const _MonetizationViewMode(this.label, this.icon);
}

class MonetizationDashboard extends ConsumerStatefulWidget {
  const MonetizationDashboard({super.key});

  @override
  ConsumerState<MonetizationDashboard> createState() => _MonetizationDashboardState();
}

class _MonetizationDashboardState extends ConsumerState<MonetizationDashboard> {
  _MonetizationViewMode _mode = _MonetizationViewMode.smartIncome;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(creatorMonetizationProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textPrimary, size: 18),
          onPressed: () {
            HapticFeedback.lightImpact();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        title: Text(
          'Income & Monetization',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          // Segmented Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: context.surface,
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                children: _MonetizationViewMode.values.map((mode) {
                  final isSelected = mode == _mode;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _mode = mode);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.brandBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              mode.icon,
                              size: 14,
                              color: isSelected ? Colors.white : context.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              mode.label,
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.8),

          // Body View
          Expanded(
            child: _mode == _MonetizationViewMode.smartIncome
                ? const SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: SmartIncomeChannelView(),
                  )
                : profileAsync.when(
                    data: (profile) => _buildDashboard(context, ref, profile),
                    loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
                    error: (e, st) => Center(
                      child: Text('Error loading monetization data: $e', style: TextStyle(color: context.textPrimary)),
                    ),
                  ),
          ),
        ],
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
          style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
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
          style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        // Render Eligible but inactive features
        ...MonetizationFeatureType.values.where((type) {
          final status = profile.features[type]?.status ?? MonetizationStatus.eligible;
          return status == MonetizationStatus.eligible;
        }).map((type) => _buildFeatureCard(
              context,
              ref,
              type,
              MonetizationFeature(type: type, status: MonetizationStatus.eligible),
            )),
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
          const Text('Total Ledger Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          balanceAsync.when(
            data: (balance) => Text(
              '\$${balance.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
            ),
            loading: () => const AnimatedLoadingIndicator(color: Colors.white),
            error: (_, _) => const Text('Error', style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pending Payout: \$${profile.pendingPayout.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brandBlue),
                child: const Text('Withdraw'),
              ),
            ],
          ),
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
        subtitle: Text(
          isActive ? 'Active & earning' : 'Ready to enable',
          style: TextStyle(color: isActive ? Colors.greenAccent : context.textMuted),
        ),
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
