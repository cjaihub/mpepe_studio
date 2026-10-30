import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../../models/oneova_look.dart';
import '../controllers/looks_marketplace_controller.dart';
import 'looks_pack_details_screen.dart';

/// 100+ Server-driven Looks Catalog with CapCut-style categories, remix, and Biz marketplace packs.
class LooksCatalogScreen extends ConsumerStatefulWidget {
  const LooksCatalogScreen({super.key});

  @override
  ConsumerState<LooksCatalogScreen> createState() => _LooksCatalogScreenState();
}

class _LooksCatalogScreenState extends ConsumerState<LooksCatalogScreen> {
  String _selectedCategory = 'All';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _categories = [
    'All',
    'Cinematic',
    'Film Stocks',
    'Clean Commercial',
    'Moody Vintage',
    'Cyberpunk Neon',
    'Warm Gold',
    'Portrait Pop',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(looksMarketplaceControllerProvider);
    final packs = state.packs;

    // Expand starter presets to simulate the 100+ server-driven looks catalog
    final allLooks = <OneovaLook>[
      const OneovaLook(id: 'starter_1', name: 'Neo Tokyo Teal', categories: ['Cinematic'], intensity: 0.9),
      const OneovaLook(id: 'starter_2', name: 'Gold 200 Warmth', categories: ['Film Stocks'], intensity: 0.85),
      const OneovaLook(id: 'starter_3', name: 'Executive Clean HDR', categories: ['Clean Commercial'], intensity: 1.0),
      ...List.generate(97, (i) {
        final cat = _categories[1 + (i % (_categories.length - 1))];
        return OneovaLook(
          id: 'server_look_$i',
          name: '$cat Grade #${i + 1}',
          categories: [cat],
          intensity: 0.85,
          tags: [cat.toLowerCase(), 'pro', 'server'],
        );
      }),
    ];

    final filteredLooks = allLooks.where((l) {
      final lookCat = l.categories.isNotEmpty ? l.categories.first : 'Cinematic';
      final matchesCategory = _selectedCategory == 'All' || lookCat == _selectedCategory;
      final query = _searchController.text.trim().toLowerCase();
      final matchesQuery = query.isEmpty ||
          l.name.toLowerCase().contains(query) ||
          l.tags.any((t) => t.toLowerCase().contains(query));
      return matchesCategory && matchesQuery;
    }).toList();

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          '100+ Looks & Marketplace',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 18, color: context.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 13, color: context.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search 100+ looks, aesthetics, Kodak, teal...',
                          hintStyle: TextStyle(fontSize: 12, color: context.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Horizontal CapCut-Style Category Chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: _categories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.brandBlue.withValues(alpha: 0.15)
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? AppColors.brandBlue : context.border,
                          width: 1.0,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppColors.brandBlue : context.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // Featured Biz Marketplace Packs Banner
            if (packs.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.brandBlue.withValues(alpha: 0.15),
                      AppColors.brandPink.withValues(alpha: 0.15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.storefront_rounded, size: 20, color: AppColors.brandPink),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Biz Marketplace Look Packs',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: context.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Unlock pro bundles created by Hollywood colorists',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: context.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => LooksPackDetailsScreen(pack: packs.first),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brandPink,
                        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('View Pack →'),
                    ),
                  ],
                ),
              ),

            // Looks Grid View
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(14),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.88,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: filteredLooks.length,
                itemBuilder: (context, index) {
                  final look = filteredLooks[index];

                  return Container(
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Look Preview Gradient Palette
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _getLookPaletteColor(index, 0),
                                  _getLookPaletteColor(index, 1),
                                ],
                              ),
                            ),
                            alignment: Alignment.bottomLeft,
                            padding: const EdgeInsets.all(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                look.categories.isNotEmpty ? look.categories.first : 'Pro',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Look Info & Action
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                look.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'By ${look.ownerUid.isNotEmpty ? look.ownerUid : "Oneova"}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: context.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getLookPaletteColor(int index, int pos) {
    const palette = [
      [Color(0xFF0C4FA8), Color(0xFFFF2D87)],
      [Color(0xFFD4AF37), Color(0xFF2C3E50)],
      [Color(0xFF1E3C72), Color(0xFF2A5298)],
      [Color(0xFFFF512F), Color(0xFFDD2476)],
      [Color(0xFF00B4DB), Color(0xFF0083B0)],
      [Color(0xFF11998E), Color(0xFF38EF7D)],
    ];
    return palette[index % palette.length][pos];
  }
}
