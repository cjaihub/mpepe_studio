import 'package:cloud_firestore/cloud_firestore.dart';
import '../../shared/navigation/oneova_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/live/services/live_service.dart';
import '../../shared/theme/app_theme.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/shop_stage_view.dart';

/// `/shops` — full-screen vertical feed of open 3D shops. Sellers who are
/// live right now come first; then open shops by latest activity, paged in
/// as you swipe.
class ShopsFeedScreen extends ConsumerStatefulWidget {
  const ShopsFeedScreen({super.key});

  @override
  ConsumerState<ShopsFeedScreen> createState() => _ShopsFeedScreenState();
}

class _ShopsFeedScreenState extends ConsumerState<ShopsFeedScreen> {
  final _pager = PageController();
  final List<Shop3D> _shops = [];
  final Set<String> _ids = {};
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = false;
  bool _done = false;
  Object? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Wait briefly for the live list so live sellers lead the feed; the feed
    // still opens if Live is slow.
    try {
      await ref.read(activeLiveStreamsProvider.future).timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (!mounted) return;
    final liveIds = ref.read(liveShopsProvider).keys;
    try {
      final live = await ref.read(shop3dRepositoryProvider).shopsByIds(liveIds);
      _add(live);
    } catch (_) {
      /* live-first is a bonus; the page load below reports errors */
    }
    await _more();
  }

  void _add(Iterable<Shop3D> shops) {
    for (final s in shops) {
      if (_ids.add(s.id)) _shops.add(s);
    }
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Skips pages that add nothing new (all already shown, or unnamed), so
      // the feed never stalls on its last card while more shops exist.
      for (var tries = 0; tries < 4; tries++) {
        final before = _shops.length;
        final (page, last) = await ref.read(shop3dRepositoryProvider).shopsPage(after: _cursor);
        if (!mounted) return;
        setState(() {
          _add(page);
          _cursor = last ?? _cursor;
          _done = last == null;
        });
        if (_done || _shops.length > before) break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      if (_shops.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Couldn't load more shops."),
            action: SnackBarAction(label: 'Retry', onPressed: _more),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _shops.clear();
      _ids.clear();
      _cursor = null;
      _done = false;
      _index = 0;
    });
    if (_pager.hasClients) _pager.jumpToPage(0);
    await _start();
  }

  void _close() => OneovaNav.back(context);

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveShopsProvider);

    Widget body;
    if (_shops.isEmpty && (_loading || (_error == null && !_done))) {
      body = const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2));
    } else if (_shops.isEmpty && _error != null) {
      body = _Empty(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't open 3D Shops",
        text: 'Check your connection and try again.',
        action: ('Try again', _refresh),
        onClose: _close,
      );
    } else if (_shops.isEmpty) {
      body = _Empty(
        icon: Icons.storefront_outlined,
        title: 'No shops are open yet',
        text: 'Be the first to open a 3D showroom on Oneova.',
        action: ('Open your 3D shop', () => context.push('/shops/setup')),
        onClose: _close,
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.brandBlue,
        onRefresh: _refresh,
        child: PageView.builder(
          controller: _pager,
          scrollDirection: Axis.vertical,
          itemCount: _shops.length,
          onPageChanged: (i) {
            HapticFeedback.selectionClick();
            setState(() => _index = i);
            if (i >= _shops.length - 3) _more();
          },
          itemBuilder: (context, i) {
            final shop = _shops[i];
            return ShopStageView(
              key: ValueKey('stage_${shop.id}'),
              shop: shop,
              live: live[shop.ownerId],
              active: i == _index,
              onClose: _close,
            );
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          StageFrameBackdrop(dark: context.isDark),
          body,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.text, required this.action, required this.onClose});
  final IconData icon;
  final String title;
  final String text;
  final (String, VoidCallback) action;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: 4,
            child: IconButton(
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
              onPressed: onClose,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Icon(icon, color: AppColors.brandBlue, size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text(title, style: AppTypography.title2(context.textPrimary), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(text, style: AppTypography.body(context.textSecondary), textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    onPressed: action.$2,
                    child: Text(action.$1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `/shops/:id/stage` — a single shop's stage (from the store page or a link).
class ShopStageScreen extends ConsumerWidget {
  const ShopStageScreen({super.key, required this.shopId});
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopProvider(shopId));
    final live = ref.watch(liveShopsProvider);
    void close() => context.canPop() ? context.pop() : context.go('/shops');
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          StageFrameBackdrop(dark: context.isDark),
          shop.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
            error: (_, _) => _Empty(
              icon: Icons.storefront_outlined,
              title: 'This shop is unavailable',
              text: 'It may be closed right now.',
              action: ('Browse 3D Shops', () => context.go('/shops')),
              onClose: close,
            ),
            data: (s) => s == null
                ? _Empty(
                    icon: Icons.storefront_outlined,
                    title: 'This shop is unavailable',
                    text: 'It may be closed right now.',
                    action: ('Browse 3D Shops', () => context.go('/shops')),
                    onClose: close,
                  )
                : ShopStageView(shop: s, live: live[s.ownerId], onClose: close),
          ),
        ],
      ),
    );
  }
}
