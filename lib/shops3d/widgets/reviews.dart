import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../data/shop3d_repository.dart';
import 'stage_style.dart';

final productReviewsProvider = StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, productId) => ref.watch(shop3dRepositoryProvider).watchReviews(productId),
);

/// Buyer rates a delivered order (once). Ratings are written by the server.
Future<void> showReviewSheet(BuildContext context, WidgetRef ref, {required String orderId, required String productName}) {
  var stars = 5;
  final text = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Rate $productName', maxLines: 2, style: AppTypography.title2(sheet.textPrimary)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 36,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  set(() => stars = i);
                },
                icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.brandPink),
              ),
          ]),
          TextField(controller: text, maxLines: 3, maxLength: 1000, decoration: const InputDecoration(hintText: 'What did you like? (optional)')),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46)),
            onPressed: () async {
              Navigator.pop(sheet);
              try {
                await ref.read(shop3dRepositoryProvider).submitReview(orderId, stars, text.text.trim());
                messenger.showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst(RegExp(r'^\[.*?\]\s*'), ''))));
              }
            },
            child: const Text('Send review'),
          ),
        ]),
      ),
    ),
  );
}

/// One small line: ★ 4.6 (23). Nothing when there are no reviews yet.
class ReviewLine extends StatelessWidget {
  const ReviewLine({super.key, required this.rating, required this.count, required this.style});
  final double? rating;
  final int count;
  final StageStyle style;

  @override
  Widget build(BuildContext context) {
    final r = rating;
    if (r == null || r <= 0) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 12, color: AppColors.brandPink),
      const SizedBox(width: 2),
      Text(count > 0 ? '${r.toStringAsFixed(1)} ($count)' : r.toStringAsFixed(1), style: AppTypography.caption(style.fgSecondary)),
    ]);
  }
}

Widget _stars(num rating, {double size = 11}) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 5; i++)
        Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: AppColors.brandPink),
    ]);

/// Reviews of a product (verified purchases only), kept small: the newest
/// one in a single line; tap to read them all.
class ProductReviews extends ConsumerWidget {
  const ProductReviews({super.key, required this.productId, required this.style, this.rating});
  final String productId;
  final StageStyle style;
  final double? rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(productReviewsProvider(productId)).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final first = list.first;
    final avg = rating ?? list.fold<num>(0, (a, r) => a + ((r['rating'] as num?) ?? 0)) / list.length;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showAll(context, list, avg);
      },
      child: GlassPanel(
        style: style,
        radius: AppRadius.md,
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        child: Row(children: [
          const Icon(Icons.star_rounded, size: 13, color: AppColors.brandPink),
          const SizedBox(width: 3),
          Text(avg.toStringAsFixed(1), style: AppTypography.caption(style.fg).copyWith(fontWeight: FontWeight.w700)),
          Text(' · ${list.length}${list.length >= 20 ? '+' : ''}', style: AppTypography.caption(style.fgMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${first['text'] ?? ''}'.isEmpty ? 'Verified purchase reviews' : '“${first['text']}”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption(style.fgSecondary),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 16, color: style.fgMuted),
        ]),
      ),
    );
  }

  void _showAll(BuildContext context, List<Map<String, dynamic>> list, num avg) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(avg.toStringAsFixed(1), style: AppTypography.title2(sheet.textPrimary)),
              const SizedBox(width: 8),
              _stars(avg.round(), size: 14),
              const SizedBox(width: 8),
              Text('Verified purchases', style: AppTypography.caption(sheet.textSecondary)),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => Divider(height: 14, color: sheet.border),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _stars((r['rating'] as num?) ?? 0),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${r['buyerName'] ?? 'Buyer'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(sheet.textMuted)),
                      ),
                    ]),
                    if ('${r['text'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${r['text']}', style: AppTypography.small(sheet.textPrimary)),
                      ),
                  ]);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
