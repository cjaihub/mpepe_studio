import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/telemetry/telemetry_models.dart';
import '../backend/telemetry/telemetry_stream_provider.dart';
import '../shared/theme/app_theme.dart';

class TelemetryDashboardScreen extends ConsumerStatefulWidget {
  const TelemetryDashboardScreen({super.key});

  @override
  ConsumerState<TelemetryDashboardScreen> createState() => _TelemetryDashboardScreenState();
}

class _TelemetryDashboardScreenState extends ConsumerState<TelemetryDashboardScreen> {
  final List<TelemetryData> _history = [];
  static const int maxHistory = 30;

  @override
  Widget build(BuildContext context) {
    // Listen to the stream
    ref.listen<AsyncValue<TelemetryData?>>(telemetryStreamProvider, (previous, next) {
      if (next.value != null) {
        setState(() {
          _history.add(next.value!);
          if (_history.length > maxHistory) {
            _history.removeAt(0);
          }
        });
      }
    });

    final currentData = _history.isNotEmpty ? _history.last : null;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text(
          'Desktop Telemetry',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.white),
        ),
        backgroundColor: AppColors.darkSurface,
        elevation: 8,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: currentData == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.brandBlue),
                  SizedBox(height: 20),
                  Text("Waiting for telemetry data...", style: TextStyle(color: AppColors.textMuted)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CPU & RAM Gauges
                  Row(
                    children: [
                      Expanded(child: _buildCircularGauge("CPU Load", currentData.cpuUsagePercent, 100.0, "%", Colors.blueAccent)),
                      const SizedBox(width: 20),
                      Expanded(child: _buildCircularGauge("RAM Usage", currentData.ramUsedGb, currentData.ramTotalGb, "GB", AppColors.brandBlue)),
                    ],
                  ),
                  const SizedBox(height: 30),
                  
                  // Storage Linear Bar
                  _buildStorageBar(currentData),
                  const SizedBox(height: 30),

                  // Network Sparkline Charts
                  Text("Network Speed (Mbps)", style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  _buildNetworkChart(),
                ],
              ),
            ),
    );
  }

  Widget _buildCircularGauge(String title, double value, double max, String unit, Color color) {
    double percentage = max > 0 ? (value / max) : 0.0;
    if (percentage > 1.0) percentage = 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkSurfaceHighlight, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: percentage,
                  strokeWidth: 10,
                  backgroundColor: AppColors.darkBackground,
                  color: color,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        value.toStringAsFixed(1),
                        style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      Text(
                        unit,
                        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageBar(TelemetryData data) {
    double percentage = data.storageTotalGb > 0 ? (data.storageUsedGb / data.storageTotalGb) : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkSurfaceHighlight, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Primary Storage", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(
                "${data.storageUsedGb.toStringAsFixed(1)} / ${data.storageTotalGb.toStringAsFixed(1)} GB",
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentage,
              minHeight: 12,
              backgroundColor: AppColors.darkBackground,
              color: percentage > 0.9 ? Colors.redAccent : Colors.tealAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkChart() {
    if (_history.isEmpty) return const SizedBox();

    List<FlSpot> upSpots = [];
    List<FlSpot> downSpots = [];
    
    double maxSpeed = 10.0; // Base max

    for (int i = 0; i < _history.length; i++) {
      final up = _history[i].networkUploadMbps;
      final down = _history[i].networkDownloadMbps;
      
      if (up > maxSpeed) maxSpeed = up;
      if (down > maxSpeed) maxSpeed = down;
      
      upSpots.add(FlSpot(i.toDouble(), up));
      downSpots.add(FlSpot(i.toDouble(), down));
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.darkSurfaceHighlight, width: 2),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegend(Colors.orangeAccent, "Upload"),
              _buildLegend(Colors.cyanAccent, "Download"),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (maxHistory - 1).toDouble(),
                minY: 0,
                maxY: maxSpeed * 1.2, // Add 20% headroom
                lineBarsData: [
                  LineChartBarData(
                    spots: upSpots,
                    isCurved: true,
                    color: Colors.orangeAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: downSpots,
                    isCurved: true,
                    color: Colors.cyanAccent,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.cyanAccent.withValues(alpha: 0.1),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString(), style: const TextStyle(color: AppColors.textMuted, fontSize: 10));
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
                  getDrawingHorizontalLine: (value) => const FlLine(color: AppColors.darkSurfaceHighlight, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String text) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(text, style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
