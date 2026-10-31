import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../backend/money/insights_logic.dart';
import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../shared/theme/app_theme.dart';
import 'creator_insights_screen.dart';
import 'money_widgets.dart';

/// One clip's numbers in plain words (`/creator/insights/clip/:id`).
class ClipInsightsScreen extends ConsumerWidget {
  const ClipInsightsScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(clipProvider(id)).value;
    final all = ref.watch(myClipsProvider).value ?? const <ClipStat>[];
    if (clip == null) {
      return const MoneyScaffold(title: 'Clip insights', body: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)));
    }
    final others = all.where((c) => c.id != clip.id).toList();
    double avg(num Function(ClipStat) f) => others.isEmpty ? 0 : others.map(f).fold<double>(0, (a, b) => a + b) / others.length;
    final rate = clip.completionRate;
    final tips = clipTips(clip, all);

    return MoneyScaffold(
      title: 'Clip insights',
      actions: [
        IconButton(
          tooltip: 'Open clip',
          icon: Icon(Icons.play_circle_outline_rounded, size: 21, color: context.textSecondary),
          onPressed: () => context.push('/post/${clip.id}'),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          MoneyCard(
            onTap: () => context.push('/post/${clip.id}'),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    width: 54,
                    height: 72,
                    color: context.surfaceMid,
                    child: clip.thumbnailUrl != null && clip.thumbnailUrl!.startsWith('http')
                        ? Image.network(clip.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.movie_rounded, color: context.textMuted))
                        : Icon(Icons.movie_rounded, color: context.textMuted),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clip.caption.trim().isEmpty ? 'Your clip' : clip.caption.trim(),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                        [
                          'Posted ${DateFormat('d MMM y').format(clip.createdAt)}',
                          if (clip.durationMs != null) '${(clip.durationMs! / 1000).round()}s long',
                        ].join(' · '),
                        style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _Ring(rate: rate)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      _Big(label: 'Views', value: compact(clip.views), icon: Icons.visibility_rounded),
                      const SizedBox(height: 8),
                      _Big(label: 'Avg. watch', value: clip.plays == 0 ? '—' : '${clip.avgWatchSec.toStringAsFixed(1)}s', icon: Icons.schedule_rounded),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.45,
              children: [
                _Small('Likes', compact(clip.likes), Icons.favorite_rounded),
                _Small('Comments', compact(clip.comments), Icons.chat_bubble_rounded),
                _Small('Shares', compact(clip.shares), Icons.share_rounded),
                _Small('Saves', compact(clip.saves), Icons.bookmark_rounded),
                _Small('Gifts', money(clip.giftDiamonds * diamondUsd, 'USD'), Icons.diamond_rounded),
                _Small('Watch time', watchTime(clip.watchMs), Icons.timelapse_rounded),
              ],
            ),
          ),
          if (others.isNotEmpty) ...[
            SectionTitle('Compared with your other clips', trailing: Text('avg of ${others.length}', style: TextStyle(fontSize: 11, color: context.textMuted))),
            MoneyCard(
              child: Column(
                children: [
                  _Compare(label: 'Views', mine: clip.views.toDouble(), avg: avg((c) => c.views), format: (v) => compact(v)),
                  _Compare(label: 'Likes', mine: clip.likes.toDouble(), avg: avg((c) => c.likes), format: (v) => compact(v)),
                  _Compare(label: 'Shares', mine: clip.shares.toDouble(), avg: avg((c) => c.shares), format: (v) => compact(v)),
                  _Compare(label: 'Comments', mine: clip.comments.toDouble(), avg: avg((c) => c.comments), format: (v) => compact(v)),
                ],
              ),
            ),
          ],
          const SectionTitle('What this means'),
          MoneyCard(
            child: Column(
              children: [
                for (final (i, tip) in tips.indexed) ...[
                  if (i > 0) Divider(height: 18, color: context.border),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_rounded, size: 17, color: AppColors.brandPink),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tip, style: TextStyle(fontSize: 12.5, height: 1.4, color: context.textPrimary))),
                    ],
                  ).animate(delay: (80 * i).ms).fadeIn(duration: 250.ms),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.rate});
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final blue = chartBlue(context);
    return Container(
      height: 128,
      decoration: AppDecorations.card(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 70,
            height: 70,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: rate ?? 0),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(child: CircularProgressIndicator(value: v, strokeWidth: 7, strokeCap: StrokeCap.round, color: blue, backgroundColor: context.surfaceMid)),
                  Text(rate == null ? '—' : '${(v * 100).round()}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: context.textPrimary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Watched to the end', style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: AppDecorations.card(context),
      child: Row(
        children: [
          Icon(icon, size: 18, color: chartBlue(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
                Text(label, style: TextStyle(fontSize: 10.5, color: context.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Small extends StatelessWidget {
  const _Small(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: AppDecorations.card(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: context.textSecondary),
          const SizedBox(height: 3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.textPrimary)),
          Text(label, style: TextStyle(fontSize: 10, color: context.textMuted)),
        ],
      ),
    );
  }
}

/// This clip vs the creator's average, as two thin bars on one scale.
class _Compare extends StatelessWidget {
  const _Compare({required this.label, required this.mine, required this.avg, required this.format});
  final String label;
  final double mine;
  final double avg;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final top = max(1.0, max(mine, avg));
    final blue = chartBlue(context);
    Widget bar(double v, Color c) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v / top),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, f, _) => LinearProgressIndicator(value: f, minHeight: 6, color: c, backgroundColor: context.surfaceMid),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary))),
          Expanded(
            child: Column(
              children: [
                Row(children: [Expanded(child: bar(mine, blue)), SizedBox(width: 64, child: Text('This · ${format(mine)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: context.textPrimary)))]),
                const SizedBox(height: 4),
                Row(children: [Expanded(child: bar(avg, context.textMuted)), SizedBox(width: 64, child: Text('Avg · ${format(avg)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: context.textSecondary)))]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
