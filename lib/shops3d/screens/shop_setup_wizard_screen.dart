import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../backend/finance/commerce_service.dart';
import '../../shared/location/geo_services.dart';
import '../../shared/theme/app_theme.dart';
import '../../social_hub/biz_commerce/checkout_screen.dart' show formatMoney;
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/shop_stage_view.dart';

const _suggestedCategories = [
  'Fashion', 'Sneakers', 'Beauty', 'Electronics', 'Home', 'Jewelry', 'Art', 'Sports', 'Kids', 'Food',
];

/// `/shops/setup` — guided setup for a seller's 3D shop:
/// 1 Identity · 2 Stage · 3 Products · 4 Preview & open.
/// Each step saves as you continue, so a seller can leave and come back.
class ShopSetupWizardScreen extends ConsumerStatefulWidget {
  const ShopSetupWizardScreen({super.key});

  @override
  ConsumerState<ShopSetupWizardScreen> createState() => _ShopSetupWizardScreenState();
}

class _ShopSetupWizardScreenState extends ConsumerState<ShopSetupWizardScreen> {
  static const _steps = ['Identity', 'Stage', 'Products', 'Open'];

  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _bio = TextEditingController();

  int _step = 0;
  bool _hydrated = false;
  bool _busy = false;
  List<String> _categories = [];
  StageConfig _stage = const StageConfig();
  String? _avatar;
  String? _banner;
  double? _lat;
  double? _lng;
  String? _pickupLabel;
  String? _featured;
  ShopStatus _status = ShopStatus.draft;

  PayoutStatus? _payouts;
  String? _payoutsError;

  Shop3DRepository get _repo => ref.read(shop3dRepositoryProvider);

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _hydrate(Shop3D? s) {
    if (_hydrated) return;
    _hydrated = true;
    if (s == null) return;
    _name.text = s.name;
    _tagline.text = s.tagline;
    _bio.text = s.bio;
    _categories = [...s.categories];
    _stage = s.stage;
    _avatar = s.avatarUrl.isEmpty ? null : s.avatarUrl;
    _banner = s.bannerUrl.isEmpty ? null : s.bannerUrl;
    _lat = s.lat;
    _lng = s.lng;
    _pickupLabel = s.hasPickup ? 'Pickup location saved' : null;
    _featured = s.featuredProductId;
    _status = s.status;
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _persist() async {
    if (_name.text.trim().isEmpty) {
      _toast('Give your shop a name first.');
      setState(() => _step = 0);
      return false;
    }
    setState(() => _busy = true);
    try {
      await _repo.saveMyShop(
        name: _name.text,
        tagline: _tagline.text,
        bio: _bio.text,
        categories: _categories,
        stage: _stage,
        avatarUrl: _avatar,
        bannerUrl: _banner,
        lat: _lat,
        lng: _lng,
        featuredProductId: _featured,
      );
      return true;
    } catch (_) {
      _toast("Couldn't save your shop. Check your connection.");
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    HapticFeedback.lightImpact();
    if (!await _persist()) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      if (_step == 3) _checkPayouts();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/shops');
    }
  }

  Future<void> _checkPayouts() async {
    setState(() {
      _payouts = null;
      _payoutsError = null;
    });
    try {
      final s = await ref.read(commerceServiceProvider).payoutStatus();
      if (mounted) setState(() => _payouts = s);
    } catch (_) {
      if (mounted) setState(() => _payoutsError = "Couldn't check payouts.");
    }
  }

  Future<void> _pickImage(String kind) async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: kind == 'avatar' ? 600 : 1800,
    );
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final url = await _repo.uploadBrandImage(File(x.path), kind);
      setState(() => kind == 'avatar' ? _avatar = url : _banner = url);
    } catch (_) {
      _toast("The image didn't upload. Try a smaller one.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _usePickupHere() async {
    setState(() => _busy = true);
    try {
      final geo = GeoServices.instance;
      final why = await geo.ensureReady();
      if (why != null) {
        _toast(why);
        return;
      }
      final pos = await geo.current();
      final label = await geo.reverse(LatLng(pos.latitude, pos.longitude)).catchError((_) => null);
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _pickupLabel = label ?? 'Pickup set to your current location';
      });
    } catch (_) {
      _toast("Couldn't get your location.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setOpen(bool open) async {
    if (!open) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Close your shop?'),
          content: const Text('Buyers won’t see it in 3D Shops until you open it again. Your products stay saved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Close shop')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!await _persist()) return;
    setState(() => _busy = true);
    try {
      final next = open ? ShopStatus.open : ShopStatus.closed;
      await _repo.setMyShopStatus(next);
      if (!mounted) return;
      setState(() => _status = next);
      HapticFeedback.mediumImpact();
      _toast(open ? 'Your shop is open' : 'Your shop is closed');
    } catch (_) {
      _toast("Couldn't update your shop.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(myShopProvider);
    final catalog = ref.watch(myCatalogProvider);
    if (shop.isLoading && !_hydrated) {
      return Scaffold(
        backgroundColor: context.bg,
        body: const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
      );
    }
    _hydrate(shop.value);

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          backgroundColor: context.bg,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 50,
          leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: _back),
          title: Text('Your 3D shop', style: AppTypography.pageTitle(context.textPrimary)),
          actions: [
            if (shop.value != null)
              TextButton(
                onPressed: () => context.push('/shops/${shop.value!.id}'),
                child: const Text('View store'),
              ),
          ],
          bottom: PreferredSize(preferredSize: const Size.fromHeight(44), child: _progress()),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: switch (_step) {
              0 => _identity(),
              1 => _stageStep(catalog.value ?? const []),
              2 => _productsStep(catalog),
              _ => _openStep(catalog.value ?? const []),
            },
          ),
        ),
        bottomNavigationBar: _step == 3
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: SizedBox(
                    height: 42,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      onPressed: _busy ? null : _next,
                      child: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Save & continue', style: AppTypography.callout(Colors.white)),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _progress() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              Expanded(
                child: GestureDetector(
                  onTap: _busy || i > _step ? null : () => setState(() => _step = i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= _step ? AppColors.brandBlue : context.border,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${i + 1}  ${_steps[i]}',
                        style: AppTypography.caption(i == _step ? context.textPrimary : context.textMuted)
                            .copyWith(fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              if (i < _steps.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      );

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.brandBlue),
        ),
      );

  Widget _card(String title, String? hint, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: AppDecorations.groupedSection(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.sectionTitle(context.textPrimary)),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(hint, style: AppTypography.caption(context.textSecondary)),
            ],
            const SizedBox(height: 10),
            child,
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.03, end: 0);

  // ── Step 1: identity ───────────────────────────────────────────────────

  Widget _identity() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _card(
          'Brand',
          'How buyers recognise you on the stage.',
          Row(
            children: [
              GestureDetector(
                onTap: _busy ? null : () => _pickImage('avatar'),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: context.surfaceMid,
                  backgroundImage: _avatar != null ? NetworkImage(_avatar!) : null,
                  child: _avatar == null ? const Icon(Icons.add_a_photo_outlined, color: AppColors.brandBlue, size: 20) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _busy ? null : () => _pickImage('banner'),
                  child: Container(
                    height: 60,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: context.border),
                      image: _banner != null ? DecorationImage(image: NetworkImage(_banner!), fit: BoxFit.cover) : null,
                    ),
                    child: _banner == null
                        ? Center(child: Text('Add a banner', style: AppTypography.small(context.textSecondary)))
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        _card(
          'About',
          null,
          Column(
            children: [
              TextField(controller: _name, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: _dec('Shop name')),
              TextField(
                controller: _tagline,
                maxLength: 90,
                textCapitalization: TextCapitalization.sentences,
                decoration: _dec('Tagline', hint: 'e.g. Premium sneakers, delivered fast'),
              ),
              TextField(
                controller: _bio,
                maxLength: 600,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _dec('Story', hint: 'Who you are and what you sell'),
              ),
            ],
          ),
        ),
        _card(
          'Categories',
          'Up to 6. Buyers filter your store by these.',
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in {..._suggestedCategories, ..._categories})
                FilterChip(
                  label: Text(c),
                  selected: _categories.contains(c),
                  showCheckmark: false,
                  selectedColor: AppColors.brandBlue,
                  labelStyle: AppTypography.small(_categories.contains(c) ? Colors.white : context.textPrimary),
                  side: BorderSide(color: _categories.contains(c) ? AppColors.brandBlue : context.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => setState(() {
                    if (on && _categories.length < 6) {
                      _categories = [..._categories, c];
                    } else if (!on) {
                      _categories = _categories.where((x) => x != c).toList();
                    }
                  }),
                ),
            ],
          ),
        ),
        _card(
          'Pickup location',
          'Where riders collect orders. Delivery prices are worked out from here.',
          Row(
            children: [
              Icon(_lat != null ? Icons.check_circle_rounded : Icons.place_outlined,
                  size: 18, color: _lat != null ? AppColors.brandBlue : context.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_pickupLabel ?? 'Not set yet',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.small(context.textSecondary)),
              ),
              TextButton(onPressed: _busy ? null : _usePickupHere, child: Text(_lat == null ? 'Use my location' : 'Update')),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: stage ──────────────────────────────────────────────────────

  Widget _stageStep(List<ShopProduct> catalog) {
    Widget option<T>(String label, T value, T group, ValueChanged<T> on, {Widget? leading}) {
      final sel = value == group;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            on(value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? AppColors.brandBlue.withValues(alpha: 0.10) : context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: sel ? AppColors.brandBlue : context.border),
            ),
            child: Column(
              children: [
                ?leading,
                if (leading != null) const SizedBox(height: 6),
                Text(label, style: AppTypography.small(sel ? AppColors.brandBlue : context.textPrimary)),
              ],
            ),
          ),
        ),
      );
    }

    Widget swatch(Color c, {Color? ring}) => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: ring ?? context.border)),
        );

    final previewShop = _draftShop();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _card(
          'Backdrop',
          null,
          Row(
            children: [
              option('Studio', StageBackdrop.studio, _stage.backdrop, (v) => setState(() => _stage = _stage.copyWith(backdrop: v)),
                  leading: swatch(context.bg)),
              const SizedBox(width: 8),
              option('Midnight', StageBackdrop.midnight, _stage.backdrop,
                  (v) => setState(() => _stage = _stage.copyWith(backdrop: v)), leading: swatch(AppColors.darkBackground)),
              const SizedBox(width: 8),
              option('Daylight', StageBackdrop.daylight, _stage.backdrop,
                  (v) => setState(() => _stage = _stage.copyWith(backdrop: v)), leading: swatch(AppColors.lightBackground)),
            ],
          ),
        ),
        _card(
          'Spotlight & controls',
          null,
          Column(
            children: [
              Row(
                children: [
                  option('Oneova blue', StageAccent.blue, _stage.accent, (v) => setState(() => _stage = _stage.copyWith(accent: v)),
                      leading: swatch(AppColors.brandBlue)),
                  const SizedBox(width: 8),
                  option('Oneova pink', StageAccent.pink, _stage.accent, (v) => setState(() => _stage = _stage.copyWith(accent: v)),
                      leading: swatch(AppColors.brandPink)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  option('Buttons right', CardPlacement.right, _stage.card, (v) => setState(() => _stage = _stage.copyWith(card: v)),
                      leading: Icon(Icons.align_horizontal_right_rounded, size: 18, color: context.textSecondary)),
                  const SizedBox(width: 8),
                  option('Buttons left', CardPlacement.left, _stage.card, (v) => setState(() => _stage = _stage.copyWith(card: v)),
                      leading: Icon(Icons.align_horizontal_left_rounded, size: 18, color: context.textSecondary)),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _stage.autoRotate,
                activeTrackColor: AppColors.brandBlue,
                title: Text('Turn products slowly', style: AppTypography.callout(context.textPrimary)),
                onChanged: (v) => setState(() => _stage = _stage.copyWith(autoRotate: v)),
              ),
            ],
          ),
        ),
        _card('Preview', 'Photos only here; open the full-screen preview on the last step to see 3D.', _phonePreview(previewShop, catalog, active: false)),
      ],
    );
  }

  Shop3D _draftShop() => Shop3D(
        id: _repo.uid ?? '',
        ownerId: _repo.uid ?? '',
        name: _name.text.trim().isEmpty ? 'Your shop' : _name.text.trim(),
        tagline: _tagline.text.trim(),
        avatarUrl: _avatar ?? '',
        bannerUrl: _banner ?? '',
        categories: _categories,
        stage: _stage,
        status: _status,
        featuredProductId: _featured,
      );

  Widget _phonePreview(Shop3D shop, List<ShopProduct> catalog, {required bool active}) {
    final products = catalog.where((p) => p.active).toList();
    return Center(
      child: Container(
        width: 250,
        height: 500,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: context.border, width: 1),
          boxShadow: AppShadows.md,
        ),
        // Laid out at phone size, then scaled into the frame.
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 390,
            height: 780,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: const Size(390, 780), padding: const EdgeInsets.only(top: 12)),
              child: ShopStageView(shop: shop, preview: true, active: active, productsOverride: products),
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 3: products ───────────────────────────────────────────────────

  Widget _productsStep(AsyncValue<List<ShopProduct>> catalog) {
    return catalog.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
      error: (_, _) => Center(child: Text("Couldn't load your products.", style: AppTypography.body(context.textSecondary))),
      data: (list) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      list.isEmpty
                          ? 'Add your first product. A 3D model is optional — photos work too.'
                          : 'Drag to set the order on your stage. Star the one buyers see first.',
                      style: AppTypography.caption(context.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: () => context.push('/shops/product/new'),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Icon(Icons.inventory_2_outlined, size: 40, color: context.textMuted))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      onReorderItem: (a, b) async {
                        final ids = list.map((p) => p.id).toList();
                        final id = ids.removeAt(a);
                        ids.insert(b.clamp(0, ids.length), id);
                        try {
                          await _repo.reorderProducts(ids);
                        } catch (_) {
                          _toast("Couldn't save the new order.");
                        }
                      },
                      itemBuilder: (context, i) => _productRow(list[i], key: ValueKey(list[i].id)),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _productRow(ShopProduct p, {required Key key}) {
    final starred = _featured == p.id;
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppDecorations.card(context),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
        onTap: () => context.push('/shops/product/edit?id=${p.id}'),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: SizedBox(
            width: 48,
            height: 48,
            child: p.gallery.isEmpty
                ? ColoredBox(color: context.surfaceMid, child: Icon(Icons.image_outlined, color: context.textMuted, size: 20))
                : Image.network(p.gallery.first, fit: BoxFit.cover, cacheWidth: 150),
          ),
        ),
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.callout(context.textPrimary)),
        subtitle: Text(
          [
            formatMoney(p.price, p.currency),
            if (p.has3d) '3D',
            if (!p.active) 'Hidden',
            if (p.soldOut) 'Sold out',
          ].join(' · '),
          style: AppTypography.caption(context.textSecondary),
        ),
        trailing: IconButton(
          tooltip: starred ? 'Shown first' : 'Show first',
          icon: Icon(starred ? Icons.star_rounded : Icons.star_border_rounded,
              color: starred ? AppColors.brandPink : context.textMuted),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _featured = starred ? null : p.id);
          },
        ),
      ),
    );
  }

  // ── Step 4: preview & open ─────────────────────────────────────────────

  Widget _openStep(List<ShopProduct> catalog) {
    final sellable = catalog.where((p) => p.sellable).length;
    final checks = <(String, bool, String?, VoidCallback?)>[
      ('Shop name', _name.text.trim().isNotEmpty, null, () => setState(() => _step = 0)),
      ('Pickup location', _lat != null, 'Needed to price delivery', () => setState(() => _step = 0)),
      ('At least one product for sale', sellable > 0, '$sellable ready', () => setState(() => _step = 2)),
      (
        'Payouts',
        _payouts?.payoutsEnabled == true,
        _payoutsError ?? (_payouts == null ? 'Checking…' : (_payouts!.payoutsEnabled ? 'Ready to get paid' : 'Set up to take payments')),
        () async {
          await context.push('/biz/payouts');
          if (mounted) _checkPayouts();
        },
      ),
    ];
    final ready = checks.every((c) => c.$2);
    final open = _status == ShopStatus.open;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _phonePreview(_draftShop(), catalog, active: false),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: () async {
              if (!await _persist() || !mounted) return;
              context.push('/shops/${_repo.uid}/stage');
            },
            icon: const Icon(Icons.fullscreen_rounded, size: 18),
            label: const Text('Preview full screen with 3D'),
          ),
        ),
        const SizedBox(height: 8),
        _card(
          'Ready to open',
          null,
          Column(
            children: [
              for (final c in checks)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: c.$2 ? null : c.$4,
                  leading: Icon(c.$2 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: c.$2 ? AppColors.brandBlue : context.textMuted, size: 20),
                  title: Text(c.$1, style: AppTypography.callout(context.textPrimary)),
                  subtitle: c.$3 == null ? null : Text(c.$3!, style: AppTypography.caption(context.textSecondary)),
                  trailing: c.$2 ? null : Icon(Icons.chevron_right_rounded, color: context.textMuted),
                ),
              if (_payoutsError != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _checkPayouts, child: const Text('Check again')),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 42,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: open ? context.surfaceMid : AppColors.brandBlue,
              foregroundColor: open ? context.textPrimary : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            onPressed: _busy || (!open && !ready) ? null : () => _setOpen(!open),
            icon: Icon(open ? Icons.storefront_outlined : Icons.rocket_launch_outlined, size: 18),
            label: Text(open ? 'Close shop' : 'Open my shop'),
          ),
        ),
        const SizedBox(height: 8),
        if (open) ...[
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandPink,
                side: const BorderSide(color: AppColors.brandPink),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: () => context.push('/live/setup'),
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: const Text('Go live with your shop'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'While you’re live, your shop moves to the front of 3D Shops with a Watch live button.',
            textAlign: TextAlign.center,
            style: AppTypography.caption(context.textSecondary),
          ),
        ],
      ],
    );
  }
}
