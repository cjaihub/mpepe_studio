import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../identity/widgets/oneova_verified_badge.dart';
import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/live_commerce.dart' show showLiveDealEditor;
import 'business_data.dart';

/// `/business` — the seller's home: today at a glance, quick actions, and
/// every store tool in one place.
class BusinessPortalScreen extends ConsumerWidget {
  const BusinessPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(myShopProvider);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.storefront_rounded, color: AppColors.brandBlue),
          const SizedBox(width: 8),
          Text('Business', style: AppTypography.pageTitle(context.textPrimary)),
        ]),
      ),
      body: shopAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        error: (_, _) => _Empty(
          icon: Icons.wifi_off_rounded,
          title: 'Couldn’t open your business',
          text: 'Check your connection and try again.',
        ),
        data: (shop) => shop == null
            ? _Empty(
                icon: Icons.add_business_rounded,
                title: 'Open your shop',
                text: 'Set up your 3D showroom, add products and start selling live.',
                action: ('Set up my shop', () => context.push('/shops/setup')),
              )
            : _Portal(shop: shop),
      ),
    );
  }
}

class _Portal extends ConsumerWidget {
  const _Portal({required this.shop});
  final Shop3D shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(sellerOrdersProvider).value ?? const [];
    final products = ref.watch(myCatalogProvider).value ?? const <ShopProduct>[];
    final daily = ref.watch(myDailyStatsProvider).value ?? const [];
    final now = DateTime.now();
    final today = [
      for (final o in orders)
        if (paidStatuses.contains(o['status']) && (orderTime(o)?.isAfter(DateTime(now.year, now.month, now.day)) ?? false)) o,
    ];
    final currency = products.isNotEmpty ? products.first.currency : (orders.isNotEmpty ? '${orders.first['currency']}' : 'usd');
    final salesToday = today.fold<num>(0, (a, o) => a + orderItems(o));
    final toPrepare = orders.where((o) => toPrepareStatuses.contains(o['status'])).length;
    final low = lowStock(products, shop.settings.lowStockAt).length;
    final todayKey = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final viewsToday = daily.where((d) => d['day'] == todayKey).fold<num>(0, (a, d) => a + ((d['views'] as num?) ?? 0));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _ShopHeader(shop: shop),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.75,
          children: [
            _Stat(icon: Icons.payments_outlined, label: 'Sales today', value: formatMoney(salesToday, currency), color: AppColors.brandBlue),
            _Stat(
              icon: Icons.inventory_outlined,
              label: 'To prepare',
              value: '$toPrepare',
              color: toPrepare > 0 ? AppColors.brandPink : AppColors.brandBlue,
              onTap: () => context.push('/business/orders'),
            ),
            _Stat(
              icon: Icons.warning_amber_rounded,
              label: 'Low stock',
              value: '$low',
              color: low > 0 ? AppColors.brandPink : AppColors.brandBlue,
              onTap: () => context.push('/business/inventory'),
            ),
            _Stat(icon: Icons.visibility_outlined, label: 'Visitors today', value: '$viewsToday', color: AppColors.brandBlue,
                onTap: () => context.push('/business/insights')),
          ],
        ),
        const SizedBox(height: 18),
        Text('Quick actions', style: AppTypography.sectionTitle(context.textPrimary)),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _Quick(icon: Icons.sensors_rounded, label: 'Go live', color: AppColors.brandPink, onTap: () => context.push('/live/setup?mode=studio')),
            _Quick(icon: Icons.add_box_outlined, label: 'Add product', onTap: () => context.push('/shops/product/new')),
            _Quick(icon: Icons.collections_bookmark_outlined, label: '3D models', onTap: () => context.push('/shops/models')),
            _Quick(icon: Icons.local_fire_department_rounded, label: 'Live deal', onTap: () => showLiveDealEditor(context, ref, shop)),
            _Quick(icon: Icons.view_in_ar_rounded, label: 'My stage', onTap: () => context.push('/shops/${shop.id}/stage')),
            _Quick(icon: Icons.share_outlined, label: 'Store page', onTap: () => context.push('/shops/${shop.id}')),
          ]),
        ),
        const SizedBox(height: 18),
        Text('Manage', style: AppTypography.sectionTitle(context.textPrimary)),
        const SizedBox(height: 6),
        _Section(children: [
          _Row(icon: Icons.receipt_long_outlined, title: 'Orders', subtitle: toPrepare > 0 ? '$toPrepare to prepare' : 'All caught up',
              onTap: () => context.push('/business/orders')),
          _Row(icon: Icons.inventory_2_outlined, title: 'Products & inventory', subtitle: '${products.length} products',
              onTap: () => context.push('/business/inventory')),
          _Row(icon: Icons.discount_outlined, title: 'Discount codes', subtitle: 'Codes buyers enter at checkout',
              onTap: () => context.push('/business/settings?tab=codes')),
          _Row(icon: Icons.insights_rounded, title: 'Insights', subtitle: 'Sales, visitors and best sellers',
              onTap: () => context.push('/business/insights')),
        ]),
        const SizedBox(height: 12),
        _Section(children: [
          _Row(icon: Icons.brush_outlined, title: 'Store look', subtitle: 'Name, logo, stage and colors', onTap: () => context.push('/shops/setup')),
          _Row(icon: Icons.local_shipping_outlined, title: 'Shipping & policies', subtitle: 'Pickup, delivery, returns, contact',
              onTap: () => context.push('/business/settings')),
          _Row(icon: Icons.account_balance_wallet_outlined, title: 'Payouts', subtitle: 'Your balance and payout methods',
              onTap: () => context.push('/biz/payouts')),
        ]),
      ],
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.shop});
  final Shop3D shop;

  @override
  Widget build(BuildContext context) {
    final open = shop.status == ShopStatus.open;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandBlue.withValues(alpha: 0.75), AppColors.brandPink.withValues(alpha: 0.85)]),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: Colors.white24,
          backgroundImage: shop.avatarUrl.startsWith('http') ? NetworkImage(shop.avatarUrl) : null,
          child: shop.avatarUrl.startsWith('http')
              ? null
              : Text(shop.name.isEmpty ? '?' : shop.name.characters.first.toUpperCase(), style: AppTypography.title2(Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.title3(Colors.white))),
              if (shop.verified) ...[const SizedBox(width: 4), OneovaVerifiedBadge(kind: VerifiedKind.business, level: shop.verifiedLevel, size: 16)],
            ]),
            const SizedBox(height: 2),
            Text(
              '${open ? 'Open' : (shop.status == ShopStatus.draft ? 'Draft' : 'Closed')}'
              '${shop.rating != null && shop.reviewCount > 0 ? ' · ★ ${shop.rating!.toStringAsFixed(1)} (${shop.reviewCount})' : ''}',
              style: AppTypography.caption(Colors.white70),
            ),
          ]),
        ),
        if (!shop.verified)
          TextButton(
            style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.brandBlue, visualDensity: VisualDensity.compact),
            onPressed: () => context.push('/id/business'),
            child: const Text('Get verified'),
          ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: context.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textSecondary))),
              ]),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: AppTypography.metric(context.textPrimary).copyWith(fontSize: 20)),
              ),
            ]),
          ),
        ),
      );
}

class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.onTap, this.color = AppColors.brandBlue});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: SizedBox(
            width: 76,
            child: Column(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textPrimary)),
            ]),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.border),
        ),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) Divider(height: 1, indent: 54, color: context.border),
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.brandBlue),
        title: Text(title, style: AppTypography.callout(context.textPrimary)),
        subtitle: Text(subtitle, style: AppTypography.caption(context.textSecondary)),
        trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
        onTap: onTap,
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: AppColors.brandBlue),
            const SizedBox(height: 12),
            Text(title, style: AppTypography.title2(context.textPrimary), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(text, style: AppTypography.body(context.textSecondary), textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white),
                onPressed: action!.$2,
                child: Text(action!.$1),
              ),
            ],
          ]),
        ),
      );
}
