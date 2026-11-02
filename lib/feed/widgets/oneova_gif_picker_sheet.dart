import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/gif/oneova_gif_engine.dart';
import '../../../backend/live_studio/fun/studio_fun.dart';
import '../../../backend/social/models/comment.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/animated_loading_indicator.dart';

/// Rich dual-mode GIF Picker for Comments and Live Chat.
///
/// Backed by `lsGifSearch` (GIPHY, Tenor, Noto Animated 512px, Wikimedia Commons,
/// and Oneova user-created GIFs) with 1-tap category chips and a camera
/// "Create GIF" shortcut.
class OneovaGifPickerSheet extends ConsumerStatefulWidget {
  const OneovaGifPickerSheet({super.key});

  static Future<CommentGif?> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<CommentGif>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const OneovaGifPickerSheet(),
    );
  }

  @override
  ConsumerState<OneovaGifPickerSheet> createState() => _OneovaGifPickerSheetState();
}

class _OneovaGifPickerSheetState extends ConsumerState<OneovaGifPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<StudioGif> _gifs = const [];
  bool _loading = true;
  bool _enabled = true;
  String? _error;
  int _seq = 0;
  String _selectedCategory = 'Trending';

  static const List<String> _categories = [
    'Trending',
    '🔥 Hype',
    '😂 LOL',
    '❤️ Love',
    '👏 Clap',
    '🎉 Party',
    '🤯 Wow',
    '✨ Vibe',
  ];

  @override
  void initState() {
    super.initState();
    _fetchGifs('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onCategorySelected(String cat) {
    if (_selectedCategory == cat && _searchController.text.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedCategory = cat;
      _searchController.clear();
    });
    final q = cat == 'Trending' ? '' : cat.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    _fetchGifs(q);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      setState(() => _selectedCategory = '');
      _fetchGifs(v.trim());
    });
  }

  Future<void> _fetchGifs(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });

    List<StudioGif> foundGifs = const [];

    // 1. Try Live Studio callable backend if available
    try {
      final res = await ref.read(studioGifApiProvider).search(q);
      if (res.gifs.isNotEmpty) {
        foundGifs = res.gifs;
      }
    } catch (_) {}

    // 2. Resilient fallback: Open-Source GIF Engine (Wikimedia + Curated Hype packs)
    if (foundGifs.isEmpty) {
      try {
        final openGifs = await ref.read(oneovaGifEngineProvider).search(q, category: _selectedCategory);
        if (openGifs.isNotEmpty) {
          foundGifs = openGifs.map((g) => g.toStudioGif()).toList();
        }
      } catch (e) {
        debugPrint('[OneovaGifPickerSheet] open source fallback error: $e');
      }
    }

    if (!mounted || seq != _seq) return;
    setState(() {
      _enabled = true;
      _gifs = foundGifs;
      _loading = false;
      if (foundGifs.isEmpty) {
        _error = 'No GIFs found for "$q". Try another keyword!';
      } else {
        _error = null;
      }
    });
  }

  Future<void> _openCreateGif() async {
    HapticFeedback.lightImpact();
    await context.push('/create/gif', extra: {
      'onGifCreated': (String gifUrl) {
        if (!mounted) return;
        final gif = CommentGif(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          url: gifUrl,
          w: 480,
          h: 480,
        );
        Navigator.of(context).pop(gif);
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      height: h * 0.72 + bottomInset * 0.3,
      padding: EdgeInsets.fromLTRB(14, 8, 14, 10 + bottomInset),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 4, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),

          // Header: title + Create GIF button + Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Row(
              children: [
                Text(
                  'Choose a GIF',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                // Create GIF button
                InkWell(
                  onTap: _openCreateGif,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_rounded, color: AppColors.brandPink, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          'Create GIF',
                          style: GoogleFonts.inter(
                            color: AppColors.brandPink,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Search Field
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, color: context.textSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Search trending GIFs…',
                      hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      _fetchGifs('');
                    },
                    child: Icon(Icons.close_rounded, color: context.textMuted, size: 16),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Categories horizontal bar
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final isSelected = _selectedCategory == cat;
                return GestureDetector(
                  onTap: () => _onCategorySelected(cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.brandBlue : context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isSelected ? AppColors.brandBlue : context.border,
                        width: 1.0,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        cat,
                        style: GoogleFonts.inter(
                          color: isSelected ? Colors.white : context.textSecondary,
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // GIF Grid
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _loading
                  ? const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue))
                  : !_enabled || _error != null || _gifs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gif_box_outlined, color: context.textMuted.withValues(alpha: 0.5), size: 36),
                              const SizedBox(height: 8),
                              Text(
                                !_enabled ? 'GIFs are coming soon.' : (_error ?? 'No GIFs found.'),
                                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 6,
                            mainAxisSpacing: 6,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: _gifs.length,
                          itemBuilder: (context, index) {
                            final g = _gifs[index];
                            return GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                final commentGif = CommentGif(id: g.id, url: g.url, w: g.w, h: g.h);
                                Navigator.of(context).pop(commentGif);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                child: Container(
                                  color: context.surfaceMid,
                                  child: Image.network(
                                    g.url,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, _, _) => Center(
                                      child: Icon(Icons.broken_image_rounded, color: context.textMuted, size: 20),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ),
          const SizedBox(height: 4),

          // Attribution
          Text(
            'Powered by Oneova Live Engine',
            style: GoogleFonts.inter(
              color: context.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
