import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../backend/analytics/analytics_models.dart';
import '../../backend/analytics/analytics_service.dart';
import '../../backend/system/system_status_models.dart';
import '../../backend/system/system_status_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../../features/omni_command/omni_command_sheet.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AnalyticsDateRangeNotifier extends Notifier<AnalyticsDateRange> {
  @override
  AnalyticsDateRange build() => AnalyticsDateRange.last7Days;
  void update(AnalyticsDateRange range) => state = range;
}

final analyticsDateRangeProvider = NotifierProvider<AnalyticsDateRangeNotifier, AnalyticsDateRange>(
  AnalyticsDateRangeNotifier.new
);

class CustomDateRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;
  void update(DateTimeRange? range) => state = range;
}

final customDateRangeProvider = NotifierProvider<CustomDateRangeNotifier, DateTimeRange?>(
  CustomDateRangeNotifier.new
);

// The provider that fetches the actual report
final analyticsReportProvider = FutureProvider<AnalyticsReport>((ref) async {
  final rangeType = ref.watch(analyticsDateRangeProvider);
  final customRange = ref.watch(customDateRangeProvider);
  final service = ref.watch(analyticsServiceProvider);

  DateTime end = DateTime.now();
  DateTime start = end.subtract(const Duration(days: 7));

  switch (rangeType) {
    case AnalyticsDateRange.today:
      start = DateTime(end.year, end.month, end.day);
      break;
    case AnalyticsDateRange.last7Days:
      start = end.subtract(const Duration(days: 7));
      break;
    case AnalyticsDateRange.last30Days:
      start = end.subtract(const Duration(days: 30));
      break;
    case AnalyticsDateRange.last90Days:
      start = end.subtract(const Duration(days: 90));
      break;
    case AnalyticsDateRange.custom:
      if (customRange != null) {
        start = customRange.start;
        end = customRange.end;
      } else {
        // Fallback to 7 days if custom range isn't fully picked yet
        start = end.subtract(const Duration(days: 7));
      }
      break;
  }

  return service.generateReport(start, end, rangeType);
});

class AnalyticsDashboardScreen extends ConsumerWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(analyticsReportProvider);
    final currentRange = ref.watch(analyticsDateRangeProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        title: Text(
          "ANALYTICS",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          // Range Selector
          Container(
            color: context.surface,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: AnalyticsDateRange.values.map((range) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: _DateRangeChip(
                      range: range,
                      isSelected: currentRange == range,
                      onSelect: () async {
                        if (range == AnalyticsDateRange.custom) {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: Theme.of(context).colorScheme.copyWith(
                                    primary: AppColors.brandBlue,
                                    onPrimary: Colors.white,
                                    surface: context.surface,
                                    onSurface: context.textPrimary,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            ref.read(customDateRangeProvider.notifier).update(picked);
                            ref.read(analyticsDateRangeProvider.notifier).update(range);
                          }
                        } else {
                          ref.read(analyticsDateRangeProvider.notifier).update(range);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          // Dashboard Content
          Expanded(
            child: reportAsync.when(
              loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
              error: (error, stack) => Center(
                child: Text(
                  "Error loading analytics:\n$error",
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
              data: (report) => RefreshIndicator(
                color: AppColors.brandBlue,
                backgroundColor: context.surfaceMid,
                onRefresh: () async {
                  return ref.refresh(analyticsReportProvider);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(24),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          Text(
                            "DATA FROM ${DateFormat.yMd().format(report.startDate)} TO ${DateFormat.yMd().format(report.endDate)}",
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: context.textMuted,
                              letterSpacing: 1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                        ]),
                      ),
                    ),
                    
                    if (report.timeSeriesData.isNotEmpty)
                      SliverToBoxAdapter(
                        child: AnalyticsTimeSeriesChart(data: report.timeSeriesData),
                      ),

                    _buildSectionTitleSliver(context, "MESSAGING & COMMUNICATION", SystemComponent.messaging),
                    _MetricSliverGrid(metrics: report.messagesMetrics + report.responseTimeMetrics),
                    
                    _buildSectionTitleSliver(context, "CONVERSATIONS & CONTACTS", SystemComponent.database),
                    _MetricSliverGrid(metrics: report.conversationMetrics + report.contactMetrics),
                    
                    _buildSectionTitleSliver(context, "AI & AUTOMATION", SystemComponent.ai),
                    _MetricSliverGrid(metrics: report.aiUsageMetrics + report.automationMetrics),
                    
                    _buildSectionTitleSliver(context, "CHANNELS & CALLS", SystemComponent.realtime),
                    _MetricSliverGrid(metrics: report.channelMetrics + report.callMetrics),
                    
                    _buildSectionTitleSliver(context, "ENGAGEMENT", SystemComponent.notifications),
                    _MetricSliverGrid(metrics: report.userEngagementMetrics + report.notificationMetrics),
                    
                    const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: OmniCommandButton(
        omniContext: OmniContext(
          sessionId: buildOmniSessionId(),
          userId: FirebaseAuth.instance.currentUser?.uid ?? 'anonymous',
          surface: 'analytics',
        ),
      ),
    );
  }

  Widget _buildSectionTitleSliver(BuildContext context, String title, [SystemComponent? component]) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 16, left: 24, right: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: context.textSecondary,
                letterSpacing: 2.0,
              ),
            ),
            if (component != null) _SystemComponentBadge(component: component),
          ],
        ),
      ),
    );
  }
}

class _SystemComponentBadge extends ConsumerWidget {
  final SystemComponent component;

  const _SystemComponentBadge({required this.component});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final compHealth = status.components[component];

    if (compHealth == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Color(compHealth.colorHex).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(compHealth.colorHex).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Color(compHealth.colorHex),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            compHealth.statusDisplay.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: Color(compHealth.colorHex),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangeChip extends StatelessWidget {
  final AnalyticsDateRange range;
  final bool isSelected;
  final VoidCallback onSelect;

  const _DateRangeChip({
    required this.range,
    required this.isSelected,
    required this.onSelect,
  });

  String _getLabel() {
    switch (range) {
      case AnalyticsDateRange.today: return "Today";
      case AnalyticsDateRange.last7Days: return "7 Days";
      case AnalyticsDateRange.last30Days: return "30 Days";
      case AnalyticsDateRange.last90Days: return "90 Days";
      case AnalyticsDateRange.custom: return "Custom";
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        _getLabel(),
        style: GoogleFonts.inter(
          fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : context.textSecondary,
        ),
      ),
      backgroundColor: isSelected ? AppColors.brandBlue : context.surfaceMid,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onSelect,
    );
  }
}

class _MetricSliverGrid extends StatelessWidget {
  final List<AnalyticsMetric> metrics;

  const _MetricSliverGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.3,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return RepaintBoundary(
              child: _MetricCard(metric: metrics[index]),
            );
          },
          childCount: metrics.length,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final AnalyticsMetric metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceMid.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  metric.title.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: context.textMuted,
                    letterSpacing: 1.0,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _MetricBadge(type: metric.type),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatValue(metric.value),
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              if (metric.unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    metric.unit,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ]
            ],
          ),
        ],
      ),
    );
  }

  String _formatValue(num value) {
    if (value is int) {
      final f = NumberFormat.compact();
      return f.format(value);
    } else {
      return value.toStringAsFixed(1);
    }
  }
}

class _MetricBadge extends StatelessWidget {
  final MetricType type;

  const _MetricBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    
    switch (type) {
      case MetricType.rawCount:
        color = Colors.greenAccent;
        label = "RAW";
        break;
      case MetricType.calculated:
        color = Colors.cyanAccent;
        label = "CALC";
        break;
      case MetricType.estimated:
        color = Colors.orangeAccent;
        label = "EST";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class AnalyticsTimeSeriesChart extends StatelessWidget {
  final List<double> data;

  const AnalyticsTimeSeriesChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    List<FlSpot> spots = [];
    double maxY = 0;
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i]));
      if (data[i] > maxY) maxY = data[i];
    }

    // Add some padding to max Y
    maxY = maxY + (maxY * 0.2);
    if (maxY == 0) maxY = 10; // default

    return Container(
      height: 250,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.only(top: 24, right: 24, left: 12, bottom: 12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: data.length.toDouble() - 1,
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.brandBlue,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: data.length <= 15, // Only show dots if there aren't too many points
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.brandBlue,
                  strokeWidth: 2,
                  strokeColor: context.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.brandBlue.withValues(alpha: 0.15),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      value.toInt().toString(),
                      style: GoogleFonts.inter(color: context.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4) > 0 ? (maxY / 4) : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.border,
              strokeWidth: 1,
              dashArray: [5, 5],
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => context.surfaceMid,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((LineBarSpot touchedSpot) {
                  return LineTooltipItem(
                    touchedSpot.y.toInt().toString(),
                    GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}
