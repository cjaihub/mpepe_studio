import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import 'business_data.dart';

/// `/business/settings` — shipping, policies, low-stock line and discount codes.
class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          backgroundColor: context.bg,
          elevation: 0,
          title: Text('Store settings', style: AppTypography.pageTitle(context.textPrimary)),
          bottom: TabBar(
            indicatorColor: AppColors.brandBlue,
            labelColor: AppColors.brandBlue,
            unselectedLabelColor: context.textSecondary,
            tabs: const [Tab(text: 'Shipping & policies'), Tab(text: 'Discount codes')],
          ),
        ),
        body: const TabBarView(children: [_PoliciesTab(), _CodesTab()]),
      ),
    );
  }
}

class _PoliciesTab extends ConsumerStatefulWidget {
  const _PoliciesTab();

  @override
  ConsumerState<_PoliciesTab> createState() => _PoliciesTabState();
}

class _PoliciesTabState extends ConsumerState<_PoliciesTab> {
  final _returns = TextEditingController();
  final _shipping = TextEditingController();
  final _contact = TextEditingController();
  final _country = TextEditingController();
  bool _pickup = true;
  bool _delivery = true;
  int _low = 5;
  List<String> _countries = [];
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_returns, _shipping, _contact, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(StoreSettings s) {
    if (_loaded) return;
    _loaded = true;
    _returns.text = s.returnsPolicy;
    _shipping.text = s.shippingNote;
    _contact.text = s.contact;
    _pickup = s.pickup;
    _delivery = s.delivery;
    _low = s.lowStockAt;
    _countries = [...s.countries];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(shop3dRepositoryProvider).saveStoreSettings(StoreSettings(
            returnsPolicy: _returns.text,
            shippingNote: _shipping.text,
            contact: _contact.text,
            pickup: _pickup,
            delivery: _delivery,
            countries: _countries,
            lowStockAt: _low,
          ));
      messenger.showSnackBar(const SnackBar(content: Text('Store settings saved.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn’t save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(myShopProvider).value;
    if (shop == null) return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
    _load(shop.settings);
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: context.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: context.border)),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
      Text('How buyers get their order', style: AppTypography.sectionTitle(context.textPrimary)),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Pickup from my shop'),
        value: _pickup,
        activeTrackColor: AppColors.brandBlue,
        onChanged: (v) => setState(() => _pickup = v),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Delivery by Oneova riders'),
        subtitle: const Text('Priced live from your pickup spot to the buyer'),
        value: _delivery,
        activeTrackColor: AppColors.brandBlue,
        onChanged: (v) => setState(() => _delivery = v),
      ),
      const SizedBox(height: 8),
      Text('Countries you sell to', style: AppTypography.callout(context.textPrimary)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in _countries) InputChip(label: Text(c), onDeleted: () => setState(() => _countries.remove(c))),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _country,
            textCapitalization: TextCapitalization.characters,
            maxLength: 2,
            decoration: const InputDecoration(isDense: true, counterText: '', hintText: 'Add code, e.g. KE'),
            onSubmitted: (v) {
              final c = v.trim().toUpperCase();
              if (RegExp(r'^[A-Z]{2}$').hasMatch(c) && !_countries.contains(c)) setState(() => _countries.add(c));
              _country.clear();
            },
          ),
        ),
      ]),
      Text(_countries.isEmpty ? 'Empty means your own country only.' : '', style: AppTypography.caption(context.textMuted)),
      const SizedBox(height: 16),
      Text('Policies buyers see', style: AppTypography.sectionTitle(context.textPrimary)),
      const SizedBox(height: 8),
      TextField(controller: _returns, maxLines: 3, maxLength: 600, decoration: deco('Returns and exchanges')),
      TextField(controller: _shipping, maxLines: 2, maxLength: 300, decoration: deco('Shipping times and notes')),
      TextField(controller: _contact, maxLength: 120, decoration: deco('Contact (phone, email or hours)')),
      const SizedBox(height: 8),
      Text('Low-stock alert at $_low', style: AppTypography.callout(context.textPrimary)),
      Slider(value: _low.toDouble(), min: 0, max: 50, divisions: 50, activeColor: AppColors.brandPink, onChanged: (v) => setState(() => _low = v.round())),
      const SizedBox(height: 12),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save'),
      ),
    ]);
  }
}

class _CodesTab extends ConsumerWidget {
  const _CodesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, String currency, [DiscountCode? c]) async {
    final code = TextEditingController(text: c?.code ?? '');
    final pct = TextEditingController(text: c?.percentOff?.toString() ?? '');
    final amount = TextEditingController(text: c?.amountOff?.toString() ?? '');
    final min = TextEditingController(text: c?.minSpend?.toString() ?? '');
    final uses = TextEditingController(text: c?.maxUses?.toString() ?? '');
    var days = 7;
    var active = c?.active ?? true;
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(c == null ? 'New discount code' : 'Edit ${c.code}', style: AppTypography.title2(sheet.textPrimary)),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                enabled: c == null,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. LIVE20'),
              ),
              Row(children: [
                Expanded(child: TextField(controller: pct, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '% off'))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'or ${currency.toUpperCase()} off'),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: min,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Minimum spend'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: uses, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max uses'))),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final d in const [1, 7, 30, 0])
                  ChoiceChip(label: Text(d == 0 ? 'No end' : '$d day${d == 1 ? '' : 's'}'), selected: days == d, onSelected: (_) => set(() => days = d)),
              ]),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                activeTrackColor: AppColors.brandBlue,
                onChanged: (v) => set(() => active = v),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46)),
                onPressed: () async {
                  final p = int.tryParse(pct.text.trim());
                  final a = num.tryParse(amount.text.trim());
                  if ((p == null || p <= 0 || p > 90) && (a == null || a <= 0)) {
                    messenger.showSnackBar(const SnackBar(content: Text('Set a % off (1–90) or an amount off.')));
                    return;
                  }
                  Navigator.pop(sheet);
                  try {
                    await ref.read(shop3dRepositoryProvider).saveCode(
                          code: code.text,
                          percentOff: p != null && p > 0 ? p : null,
                          amountOff: p != null && p > 0 ? null : a,
                          currency: currency,
                          minSpend: num.tryParse(min.text.trim()),
                          maxUses: int.tryParse(uses.text.trim()),
                          endsAt: days == 0 ? null : DateTime.now().add(Duration(days: days)),
                          active: active,
                        );
                    messenger.showSnackBar(const SnackBar(content: Text('Code saved.')));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text('Couldn’t save the code: $e')));
                  }
                },
                child: const Text('Save code'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codes = ref.watch(myCodesProvider).value ?? const <DiscountCode>[];
    final products = ref.watch(myCatalogProvider).value ?? const <ShopProduct>[];
    final currency = products.isNotEmpty ? products.first.currency : 'usd';
    return Scaffold(
      backgroundColor: context.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brandBlue,
        foregroundColor: Colors.white,
        onPressed: () => _edit(context, ref, currency),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New code'),
      ),
      body: codes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Create codes to share in your lives, posts and chats. Checkout checks and applies them.',
                    textAlign: TextAlign.center, style: AppTypography.body(context.textSecondary)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: codes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = codes[i];
                final ended = c.endsAt != null && c.endsAt!.isBefore(DateTime.now());
                final usedUp = c.maxUses != null && c.uses >= c.maxUses!;
                return Material(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: ListTile(
                    leading: Icon(Icons.confirmation_number_outlined, color: c.active && !ended && !usedUp ? AppColors.brandBlue : context.textMuted),
                    title: Text(c.code, style: AppTypography.callout(context.textPrimary).copyWith(letterSpacing: 1.2)),
                    subtitle: Text(
                      '${c.summary} · used ${c.uses}${c.maxUses != null ? '/${c.maxUses}' : ''}'
                      '${!c.active ? ' · paused' : ended ? ' · ended' : c.endsAt != null ? ' · ends ${c.endsAt!.day}/${c.endsAt!.month}' : ''}',
                      style: AppTypography.caption(context.textSecondary),
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: Icon(Icons.delete_outline_rounded, color: context.textMuted),
                      onPressed: () => ref.read(shop3dRepositoryProvider).deleteCode(c.code),
                    ),
                    onTap: () => _edit(context, ref, currency, c),
                  ),
                );
              },
            ),
    );
  }
}
