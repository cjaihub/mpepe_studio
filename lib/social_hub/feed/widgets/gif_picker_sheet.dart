import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../backend/giphy_service.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class GifPickerSheet extends ConsumerStatefulWidget {
  const GifPickerSheet({super.key});

  static Future<GiphyGif?> show(BuildContext context) async {
    return showModalBottomSheet<GiphyGif>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GifPickerSheet(),
    );
  }

  @override
  ConsumerState<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends ConsumerState<GifPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<GiphyGif> _gifs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchGifs('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchGifs(query);
    });
  }

  Future<void> _fetchGifs(String query) async {
    setState(() => _isLoading = true);
    final service = ref.read(giphyServiceProvider);
    final gifs = await service.search(query);
    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header & Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.border),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search GIPHY',
                        hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: context.textMuted, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600)),
                )
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Grid
          Expanded(
            child: _isLoading
                ? const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue))
                : _gifs.isEmpty
                    ? Center(child: Text('No GIFs found', style: GoogleFonts.inter(color: context.textMuted)))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                        itemCount: _gifs.length,
                        itemBuilder: (context, index) {
                          final gif = _gifs[index];
                          return GestureDetector(
                            onTap: () => Navigator.pop(context, gif),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                gif.previewUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(color: context.surfaceMid);
                                },
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: context.surfaceMid,
                                  child: Icon(Icons.error, color: context.textMuted),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          
          // Attribution
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'POWERED BY GIPHY',
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
