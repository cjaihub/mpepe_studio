import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/camera_smart_lock_state.dart';

/// Collapsible Pro Manual Controls deck on the camera viewfinder:
/// EV Bias, ISO, Shutter Speed, Kelvin White Balance, and Manual Focus Peaking.
class CameraProControlsDeck extends StatefulWidget {
  final CameraSmartLockState state;
  final CameraController? cameraController;
  final ValueChanged<double> onEvChanged;
  final ValueChanged<int?> onIsoChanged;
  final ValueChanged<double?> onShutterChanged;
  final void Function(String mode, {int? kelvin}) onWbChanged;
  final ValueChanged<double?> onFocusChanged;
  /// Focus peaking toggle; the button is hidden when null.
  final VoidCallback? onTogglePeaking;
  final VoidCallback onClose;

  const CameraProControlsDeck({
    super.key,
    required this.state,
    this.cameraController,
    required this.onEvChanged,
    required this.onIsoChanged,
    required this.onShutterChanged,
    required this.onWbChanged,
    required this.onFocusChanged,
    this.onTogglePeaking,
    required this.onClose,
  });

  @override
  State<CameraProControlsDeck> createState() => _CameraProControlsDeckState();
}

class _CameraProControlsDeckState extends State<CameraProControlsDeck> {
  String _activeTab = 'EV'; // 'EV', 'ISO', 'SHUTTER', 'WB', 'FOCUS'

  static const List<int?> _isoOptions = [null, 50, 100, 200, 400, 800, 1600, 3200];
  static const List<double?> _shutterOptions = [
    null,
    1 / 8000,
    1 / 4000,
    1 / 2000,
    1 / 1000,
    1 / 500,
    1 / 250,
    1 / 125,
    1 / 60,
    1 / 30,
    1 / 24,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        border: Border.all(color: Colors.white24, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, color: AppColors.brandBlue, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Camera Controls',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Subnav Pills: friendly labels
          Row(
            children: const [
              ('EV', 'Brightness'),
              ('ISO', 'Light'),
              ('SHUTTER', 'Speed'),
              ('WB', 'Tone'),
              ('FOCUS', 'Focus'),
            ].map((item) {
              final tab = item.$1;
              final label = item.$2;
              final isSelected = _activeTab == tab;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _activeTab = tab);
                    },
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.brandBlue : Colors.white10,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Active Panel Content
          _buildActivePanel(context),
        ],
      ),
    ).animate().slideY(begin: 0.1, duration: 200.ms).fadeIn(duration: 200.ms);
  }

  Widget _buildActivePanel(BuildContext context) {
    return switch (_activeTab) {
      'EV' => _buildEvPanel(),
      'ISO' => _buildIsoPanel(),
      'SHUTTER' => _buildShutterPanel(),
      'WB' => _buildWbPanel(),
      'FOCUS' => _buildFocusPanel(),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildEvPanel() {
    final ev = widget.state.exposureBias;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Exposure Compensation',
              style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70),
            ),
            Text(
              '${ev >= 0 ? '+' : ''}${ev.toStringAsFixed(1)} EV',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ev != 0 ? AppColors.brandPink : Colors.white,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.brandBlue,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: ev,
            min: -3.0,
            max: 3.0,
            divisions: 60,
            onChanged: widget.onEvChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildIsoPanel() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _isoOptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, idx) {
          final opt = _isoOptions[idx];
          final isSelected = widget.state.iso == opt;
          return InkWell(
            onTap: () => widget.onIsoChanged(opt),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : Colors.white10,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : Colors.white24,
                  width: 1.0,
                ),
              ),
              child: Text(
                opt == null ? 'AUTO' : '$opt',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShutterPanel() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _shutterOptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (ctx, idx) {
          final opt = _shutterOptions[idx];
          final isSelected = widget.state.shutterSeconds == opt;
          String label;
          if (opt == null) {
            label = 'AUTO';
          } else {
            final denom = (1.0 / opt).round();
            label = '1/${denom}s';
          }
          return InkWell(
            onTap: () => widget.onShutterChanged(opt),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : Colors.white10,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : Colors.white24,
                  width: 1.0,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWbPanel() {
    final modes = [
      ('auto', 'Auto', null),
      ('daylight', 'Daylight (5600K)', 5600),
      ('cloudy', 'Cloudy (6500K)', 6500),
      ('tungsten', 'Tungsten (3200K)', 3200),
      ('fluorescent', 'Fluor (4000K)', 4000),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: modes.map((m) {
        final isSelected = widget.state.whiteBalanceMode == m.$1;
        return InkWell(
          onTap: () => widget.onWbChanged(m.$1, kelvin: m.$3),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandBlue : Colors.white10,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: isSelected ? AppColors.brandBlue : Colors.white24,
                width: 1.0,
              ),
            ),
            child: Text(
              m.$2,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFocusPanel() {
    final dist = widget.state.focusDistance ?? 0.5;
    final isManual = widget.state.focusDistance != null;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  isManual ? 'Focus Distance: ${(dist * 100).toInt()}%' : 'Auto Focus',
                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => widget.onFocusChanged(isManual ? null : 0.5),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 24),
                    backgroundColor: Colors.white12,
                  ),
                  child: Text(
                    isManual ? 'Auto' : 'Manual',
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
                  ),
                ),
              ],
            ),
            if (widget.onTogglePeaking != null)
            TextButton.icon(
              onPressed: widget.onTogglePeaking,
              icon: Icon(
                Icons.center_focus_strong_rounded,
                size: 13,
                color: widget.state.isFocusPeakingEnabled ? AppColors.brandPink : Colors.white70,
              ),
              label: Text(
                'Peaking',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: widget.state.isFocusPeakingEnabled ? AppColors.brandPink : Colors.white70,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: const Size(0, 24),
              ),
            ),
          ],
        ),
        if (isManual)
          Row(
            children: [
              Text('Close-up', style: GoogleFonts.inter(fontSize: 10, color: Colors.white60)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.brandBlue,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    trackHeight: 3.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: dist,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => widget.onFocusChanged(v),
                  ),
                ),
              ),
              Text('Far', style: GoogleFonts.inter(fontSize: 10, color: Colors.white60)),
            ],
          ),
      ],
    );
  }
}
