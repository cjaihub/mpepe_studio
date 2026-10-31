import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../backend/money/insights_logic.dart';
import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../shared/theme/app_theme.dart';
import 'money_widgets.dart';

/// Chart blue: brand blue in light mode, a lighter step of it in dark mode so
/// lines keep 3:1 contrast on the dark surface (checked with the palette validator).
Color chartBlue(BuildContext c) => c.isDark ? Color.lerp(AppColors.brandBlue, Colors.white, 0.25)! : AppColors.brandBlue;

enum _Metric {
  views('Views', Icons.visibility_rounded),
  followers('New followers', Icons.person_add_alt_1_rounded),
  watch('Watch time', Icons.schedule_rounded),
  likes('Likes', Icons.favorite_rounded),
  comments('Comments', Icons.chat_bubble_rounded),
  shares('Shares', Icons.share_rounded),
  gifts('Gift earnings', Icons.diamond_rounded);

  const _Metric(this.label, this.icon);
  final String label;
  final IconData icon;

  num of(DayStat d) => switch (this) {
        views => d.views,
        followers => d.netFollows,
        watch => d.watchMs / 60000,
        likes => d.likes,
        comments => d.comments,
        shares => d.shares,
        gifts => d.giftDiamonds * diamondUsd,
      };

  String format(num v) => switch (this) {
        watch => watchTime((v * 60000).round()),
        gifts => money(v.toDouble(), 'USD'),
        _ => compact(v),
      };
}

/// Creator insights (`/creator/insights`): growth over time in plain words,
/// from `creator_daily` and the creator's own clips.
class CreatorInsightsScreen extends ConsumerStatefulWidget {
  const CreatorInsightsScreen({super.key});

  @override
  ConsumerState<CreatorInsightsScreen> createState() => _CreatorInsightsScreenState();
}

class _CreatorInsightsScreenState extends ConsumerState<CreatorInsightsScreen> {
  int _days = 28;
  _Metric _metric = _Metric.views;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(creatorDaysProvider(_days * 2));
    final clips = ref.watch(myClipsProvider).value ?? const <ClipStat>[];
    final followers = ref.watch(followerCountProvider).value;
    final all = async.value ?? const <DayStat>[];
    final before = all.take(all.length - min(_days, all.length)).toList();
    final now = all.skip(all.length - min(_days, all.length)).toList();
    final t = PeriodTotals.of(now);
    final p = PeriodTotals.of(before);
    final head = headline(t, p, _days);
    final tips = creatorTips(clips);

    return MoneyScaffold(
      title: 'Insights',
      body: RefreshIndicator(
        color: AppColors.brandBlue,
        onRefresh: () async => ref.invalidate(followerCountProvider),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _periods(),
            const SizedBox(height: 12),
            if (async.isLoading && all.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)))
            else ...[
              GrowthBanner(title: head.title, body: head.body),
              const SizedBox(height: 12),
              _tiles(t, p),
              if (followers != null) ...[
                const SizedBox(height: 12),
                MoneyCard(
                  child: MilestoneBar(
                    label: '${compact(followers)} followers · next goal ${compact(nextMilestone(followers))}',
                    value: followers,
                    goal: nextMilestone(followers),
                  ),
                ),
              ],
              const SectionTitle('Over time'),
              _chartCard(now),
            ],
            if (tips.isNotEmpty) ...[
              const SectionTitle('Tips for you'),
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
                      ).animate(delay: (80 * i).ms).fadeIn(duration: 250.ms).slideX(begin: 0.04, end: 0),
                    ],
                  ],
                ),
              ),
            ],
            SectionTitle('Your clips', trailing: Text('Tap one for details', style: TextStyle(fontSize: 11, color: context.textMuted))),
            if (clips.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Post your first clip to see how it does here.', style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
              )
            else
              MoneyCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (i, c) in ([...clips]..sort((a, b) => b.views.compareTo(a.views))).take(15).indexed) ...[
                      if (i > 0) Divider(height: 1, color: context.border, indent: 64),
                      ClipRow(clip: c, rank: i + 1),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _periods() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          for (final d in const [7, 28, 90])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('$d days'),
                selected: _days == d,
                showCheckmark: false,
                selectedColor: AppColors.brandBlue,
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _days == d ? Colors.white : context.textPrimary),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _days = d);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _tiles(PeriodTotals t, PeriodTotals p) {
    final completion = t.plays == 0 ? null : t.completes / t.plays;
    final items = [
      (_Metric.views, compact(t.views), percentChange(t.views, p.views)),
      (_Metric.watch, watchTime(t.watchMs), percentChange(t.watchMs, p.watchMs)),
      (_Metric.followers, '${t.followsNet >= 0 ? '+' : ''}${compact(t.followsNet)}', percentChange(t.followsNet, p.followsNet)),
      (_Metric.likes, compact(t.likes), percentChange(t.likes, p.likes)),
      (_Metric.comments, compact(t.comments), percentChange(t.comments, p.comments)),
      (_Metric.shares, compact(t.shares), percentChange(t.shares, p.shares)),
      (_Metric.gifts, money(t.gifts * diamondUsd, 'USD'), percentChange(t.gifts, p.gifts)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.15,
            children: [
              for (final (i, (m, value, change)) in items.indexed)
                _Tile(
                  metric: m,
                  value: value,
                  change: change,
                  selected: _metric == m,
                  onTap: () => setState(() => _metric = m),
                ).animate(delay: (40 * i).ms).fadeIn(duration: 220.ms).scaleXY(begin: 0.96, end: 1),
              _Tile.custom(
                icon: Icons.flag_rounded,
                label: 'Watched to the end',
                value: completion == null ? '—' : '${(completion * 100).round()}%',
                sub: completion == null ? 'Shows after people watch' : completion >= 0.5 ? 'People stay to the end' : 'Hook them early',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartCard(List<DayStat> days) {
    final values = days.map((d) => _metric.of(d).toDouble()).toList();
    final total = values.fold<double>(0, (a, b) => a + b);
    final bestI = values.isEmpty ? -1 : values.indexOf(values.reduce(max));
    final dayFmt = DateFormat('EEE d MMM');
    final sentence = total == 0
        ? 'No ${_metric.label.toLowerCase()} yet in these $_days days. They’ll appear here as they happen.'
        : 'Your best day was ${dayFmt.format(days[bestI].date)} with ${_metric.format(values[bestI])}${_metric == _Metric.watch ? ' watched' : ''}.';
    final line = _metric == _Metric.views || _metric == _Metric.watch;
    return MoneyCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${_metric.label} per day', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
            child: Text(sentence, style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary)),
          ),
          SizedBox(
            height: 170,
            child: Semantics(
              label: '${_metric.label} per day, total ${_metric.format(total)}',
              child: line ? _line(days, values) : _bars(days, values),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final m in _Metric.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: Icon(m.icon, size: 14, color: _metric == m ? Colors.white : context.textSecondary),
                      label: Text(m.label),
                      selected: _metric == m,
                      showCheckmark: false,
                      selectedColor: AppColors.brandBlue,
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(fontSize: 11.5, color: _metric == m ? Colors.white : context.textPrimary),
                      onSelected: (_) => setState(() => _metric = m),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  FlTitlesData _titles(List<DayStat> days, double maxY) {
    final step = max(1, (days.length / 4).ceil());
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          interval: maxY <= 0 ? 1 : maxY / 2,
          getTitlesWidget: (v, meta) => v == meta.max || v == 0 || (v - maxY / 2).abs() < 0.001
              ? Text(_metric.format(v), style: TextStyle(fontSize: 9.5, color: context.textMuted))
              : const SizedBox.shrink(),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 20,
          interval: 1,
          getTitlesWidget: (v, _) {
            final i = v.round();
            if (i < 0 || i >= days.length || (i % step != 0 && i != days.length - 1)) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(DateFormat('d MMM').format(days[i].date), style: TextStyle(fontSize: 9.5, color: context.textMuted)),
            );
          },
        ),
      ),
    );
  }

  FlGridData _grid(double maxY) => FlGridData(
        drawVerticalLine: false,
        horizontalInterval: maxY <= 0 ? 1 : maxY / 2,
        getDrawingHorizontalLine: (_) => FlLine(color: context.border, strokeWidth: 1),
      );

  Widget _line(List<DayStat> days, List<double> values) {
    final top = values.isEmpty ? 0.0 : values.reduce(max);
    final maxY = top <= 0 ? 1.0 : top * 1.15;
    final blue = chartBlue(context);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: _grid(maxY),
        borderData: FlBorderData(show: false),
        titlesData: _titles(days, maxY),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (_, idx) => [
            for (final _ in idx)
              TouchedSpotIndicatorData(
                FlLine(color: context.textMuted, strokeWidth: 1),
                FlDotData(getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: blue, strokeWidth: 2, strokeColor: context.surface)),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => context.surfaceMid,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${DateFormat('EEE d MMM').format(days[s.x.round()].date)}\n',
                  TextStyle(fontSize: 10.5, color: context.textSecondary),
                  children: [TextSpan(text: _metric.format(s.y), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.textPrimary))],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
            isCurved: true,
            preventCurveOverShooting: true,
            color: blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [blue.withValues(alpha: 0.22), blue.withValues(alpha: 0)]),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 450),
    );
  }

  Widget _bars(List<DayStat> days, List<double> values) {
    final top = values.isEmpty ? 0.0 : values.reduce(max);
    final bottom = values.isEmpty ? 0.0 : values.reduce(min);
    final maxY = top <= 0 ? 1.0 : top * 1.15;
    final minY = bottom < 0 ? bottom * 1.15 : 0.0;
    final blue = chartBlue(context);
    final width = max(2.0, min(14.0, 260 / max(1, days.length) - 2));
    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: minY,
        gridData: _grid(maxY),
        borderData: FlBorderData(show: false),
        titlesData: _titles(days, maxY),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => context.surfaceMid,
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(
              '${DateFormat('EEE d MMM').format(days[g.x].date)}\n',
              TextStyle(fontSize: 10.5, color: context.textSecondary),
              children: [TextSpan(text: _metric.format(rod.toY), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.textPrimary))],
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: values[i],
                width: width,
                // Lost followers show below the line in pink, with the value in the tooltip.
                color: values[i] < 0 ? AppColors.brandPink : blue,
                borderRadius: values[i] < 0
                    ? const BorderRadius.vertical(bottom: Radius.circular(4))
                    : const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ]),
        ],
      ),
      duration: const Duration(milliseconds: 450),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.metric, required this.value, required this.change, required this.selected, required this.onTap})
      : icon = null,
        label = null,
        sub = null;
  const _Tile.custom({required this.icon, required this.label, required this.value, required this.sub})
      : metric = null,
        change = null,
        selected = false,
        onTap = null;

  final _Metric? metric;
  final IconData? icon;
  final String? label;
  final String value;
  final String? sub;
  final int? change;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final up = (change ?? 0) >= 0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue.withValues(alpha: 0.08) : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? AppColors.brandBlue : context.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(metric?.icon ?? icon, size: 13, color: context.textSecondary),
                const SizedBox(width: 4),
                Expanded(child: Text(metric?.label ?? label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.textSecondary))),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary))),
                const SizedBox(width: 6),
                if (change != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '${up ? '▲' : '▼'} ${change!.abs()}%',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: up ? chartBlue(context) : AppColors.brandPink),
                    ),
                  ),
              ],
            ),
            if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: context.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A clip in a list, with its headline numbers.
class ClipRow extends StatelessWidget {
  const ClipRow({super.key, required this.clip, this.rank});
  final ClipStat clip;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final rate = clip.completionRate;
    return InkWell(
      onTap: () => context.push('/creator/insights/clip/${clip.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                width: 40,
                height: 52,
                color: context.surfaceMid,
                child: clip.thumbnailUrl != null && clip.thumbnailUrl!.startsWith('http')
                    ? Image.network(clip.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.movie_rounded, size: 18, color: context.textMuted))
                    : Icon(Icons.movie_rounded, size: 18, color: context.textMuted),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clip.caption.trim().isEmpty ? 'Clip from ${DateFormat('d MMM').format(clip.createdAt)}' : clip.caption.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '${compact(clip.views)} views',
                      '${compact(clip.likes)} likes',
                      if (rate != null) '${(rate * 100).round()}% finish',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ],
              ),
            ),
            if (rank != null && rank! <= 3)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.brandPink.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text('#$rank', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.brandPink)),
              ),
            Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
