import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_renderer.dart';
import 'studio_ui.dart';

/// GIF output (rendered from a small MP4, then encoded on device).
class StudioGifSettings {
  final int longSide;
  final int fps;
  const StudioGifSettings({required this.longSide, required this.fps});

  /// GIFs longer than this are trimmed (size grows fast).
  static const int maxMs = 15000;
}

/// What the user picked in the export sheet.
class StudioExportChoice {
  final StudioVideoSettings? video;
  final StudioGifSettings? gif;
  final int photoLongSide;
  final bool saveToGallery;
  final bool watermark;
  const StudioExportChoice({
    this.video,
    this.gif,
    this.photoLongSide = 0,
    required this.saveToGallery,
    this.watermark = false,
  });
}

const _resolutions = <(int, String)>[(480, '480p'), (720, '720p'), (1080, '1080p'), (1440, '2K'), (2160, '4K')];
const _frameRates = <int>[24, 25, 30, 50, 60];
const _gifSizes = <(int, String)>[(320, 'Small'), (480, 'Medium'), (640, 'Large')];
const _gifRates = <int>[8, 10, 12, 15];

/// Recommended H.264 bitrate (bps) for a short side and frame rate.
int studioRecommendedBitrate(int shortSide, int fps) {
  final base = switch (shortSide) {
    <= 480 => 2.5,
    <= 720 => 5.0,
    <= 1080 => 10.0,
    <= 1440 => 16.0,
    _ => 35.0,
  };
  return (base * (fps > 30 ? 1.5 : 1) * 1000000).round();
}

/// [allowGif] when the result stays on the device (GIFs can't be posted).
Future<StudioExportChoice?> showStudioExportSheet(BuildContext context, StudioProject project, {bool allowGif = false}) {
  return showModalBottomSheet<StudioExportChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _StudioExportSheet(project: project, allowGif: allowGif),
  );
}

class _StudioExportSheet extends StatefulWidget {
  final StudioProject project;
  final bool allowGif;
  const _StudioExportSheet({required this.project, required this.allowGif});

  @override
  State<_StudioExportSheet> createState() => _StudioExportSheetState();
}

class _StudioExportSheetState extends State<_StudioExportSheet> {
  EncoderCapabilities? _caps;
  late int _short;
  late int _fps;
  late int _bitrate;
  bool _bitrateTouched = false;
  bool _save = true;
  bool _watermark = false;
  bool _gif = false;
  int _gifSide = 480;
  int _gifFps = 12;
  int _photoLong = 2160;

  StudioProject get p => widget.project;

  int get _sourceFps {
    final f = p.maxSourceFps;
    return f <= 0 ? 30 : f.round();
  }

  bool _fpsOk(int f) => f <= math.max(_sourceFps, 30) && f <= (_caps?.maxFps ?? 60);

  bool _resolutionOk(int short) {
    final size = studioCanvasSize(p.canvasAspect, short);
    final long = math.max(size.width, size.height).toInt();
    return _caps?.supports(long, short) ?? short <= 1080;
  }

  @override
  void initState() {
    super.initState();
    final src = p.maxSourceShortSide;
    final wanted = p.exportShortSide > 0 ? p.exportShortSide : math.min(1080, src <= 0 ? 1080 : src);
    _short = _resolutions.map((r) => r.$1).lastWhere((r) => r <= math.max(wanted, 480), orElse: () => 720);
    _fps = _frameRates.lastWhere((f) => f <= _sourceFps, orElse: () => 30);
    _bitrate = studioRecommendedBitrate(_short, _fps);
    final c = p.clips.isEmpty ? null : p.clips.first;
    final srcLong = c == null
        ? 2160
        : math.max(c.sourceWidth * (c.crop.r - c.crop.l), c.sourceHeight * (c.crop.b - c.crop.t)).round();
    _photoLong = srcLong <= 0 || srcLong > 2160 ? 2160 : srcLong;
    OneovaMediaEngine.capabilities().then((c) {
      if (!mounted) return;
      setState(() {
        _caps = c;
        while (!_resolutionOk(_short) && _short > 480) {
          _short = _resolutions.lastWhere((r) => r.$1 < _short).$1;
        }
        if (!_fpsOk(_fps)) _fps = _frameRates.lastWhere(_fpsOk, orElse: () => 30);
        if (!_bitrateTouched) _bitrate = studioRecommendedBitrate(_short, _fps);
      });
    }).catchError((_) {});
  }

  String _mb(double bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

  void _retune() {
    if (!_bitrateTouched) _bitrate = studioRecommendedBitrate(_short, _fps);
  }

  StudioExportChoice _choice() => StudioExportChoice(
        video: p.isPhoto || _gif ? null : StudioVideoSettings(shortSide: _short, fps: _fps, bitrate: _bitrate),
        gif: _gif ? StudioGifSettings(longSide: _gifSide, fps: _gifFps) : null,
        photoLongSide: _photoLong,
        saveToGallery: _save,
        watermark: _watermark,
      );

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StudioSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(children: [
                if (p.isPhoto || !widget.allowGif)
                  Expanded(
                    child: Text(p.isPhoto ? 'Export photo' : 'Export video',
                        style: GoogleFonts.inter(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                  )
                else
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Tabs(
                        labels: const ['Video', 'GIF'],
                        index: _gif ? 1 : 0,
                        onPick: (i) => setState(() => _gif = i == 1),
                      ),
                    ),
                  ),
                _ExportButton(onTap: () => Navigator.pop(context, _choice())),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.isPhoto) ..._photoOptions() else if (_gif) ..._gifOptions() else ..._videoOptions(),
                    const SizedBox(height: 6),
                    _ToggleRow(
                      icon: Icons.branding_watermark_outlined,
                      title: 'Watermark',
                      subtitle: 'Small Oneova mark in the corner',
                      value: _watermark,
                      onChanged: (v) => setState(() => _watermark = v),
                    ),
                    _ToggleRow(
                      icon: Icons.photo_library_outlined,
                      title: 'Save a copy to gallery',
                      subtitle: 'Keep the file on this phone',
                      value: _save,
                      onChanged: (v) => setState(() => _save = v),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String title, String trailing, {Color? trailingColor}) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(trailing,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                      color: trailingColor ?? context.textMuted, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  List<Widget> _videoOptions() {
    final size = studioCanvasSize(p.canvasAspect, _short);
    final secs = p.durationMs / 1000;
    final bytes = (_bitrate + 128000) * secs / 8;
    final src = p.maxSourceShortSide;
    final upscaled = src > 0 && _short > src;
    final recommended = studioRecommendedBitrate(_short, _fps);
    const bitrateStops = <(int, String)>[(2, '2'), (5, '5'), (10, '10'), (20, '20'), (35, '35'), (60, '60')];
    final mbps = _bitrate / 1000000;
    return [
      _label('Resolution', upscaled ? 'Above your source ($src p)' : '${size.width.toInt()} × ${size.height.toInt()}',
          trailingColor: upscaled ? AppColors.brandPink : null),
      _StopSlider<int>(
        stops: _resolutions,
        value: _short,
        enabled: _resolutionOk,
        onPick: (v) => setState(() {
          _short = v;
          _retune();
        }),
      ),
      if (_caps != null && !_resolutionOk(2160))
        Text('Faded sizes are beyond this phone\'s video encoder.',
            style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
      const SizedBox(height: 16),
      _label('Frame rate', _fps > 30 ? 'Smoother motion' : 'Source $_sourceFps fps'),
      _StopSlider<int>(
        stops: [for (final f in _frameRates) (f, '$f')],
        value: _fps,
        enabled: _fpsOk,
        onPick: (v) => setState(() {
          _fps = v;
          _retune();
        }),
      ),
      const SizedBox(height: 16),
      _label('Bitrate (Mbps)', 'Recommended for this video: ${(recommended / 1000000).toStringAsFixed(recommended < 10000000 ? 1 : 0)}'),
      _StopSlider<int>(
        stops: bitrateStops,
        value: bitrateStops.reduce((a, b) => (a.$1 - mbps).abs() <= (b.$1 - mbps).abs() ? a : b).$1,
        enabled: (_) => true,
        marker: recommended / 1000000,
        onPick: (v) => setState(() {
          _bitrateTouched = true;
          _bitrate = v * 1000000;
        }),
      ),
      if (_bitrateTouched && (_bitrate - recommended).abs() > 500000)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _bitrateTouched = false;
              _retune();
            }),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16, color: AppColors.brandBlue),
            label: Text('Use recommended',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
          ),
        ),
      const SizedBox(height: 12),
      _SizeCard(
        primary: 'Estimated file size: ${_mb(bytes)}',
        secondary: 'MP4 · H.264 · ${studioClock(p.durationMs)} · ${_resolutions.firstWhere((r) => r.$1 == _short).$2} · $_fps fps',
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _gifOptions() {
    final ms = math.min(p.durationMs, StudioGifSettings.maxMs);
    final aspect = p.canvasAspect;
    final w = aspect >= 1 ? _gifSide : (_gifSide * aspect).round();
    final h = aspect >= 1 ? (_gifSide / aspect).round() : _gifSide;
    // Rough: ~0.35 bytes per pixel per frame after LZW on typical footage.
    final bytes = w * h * 0.35 * (ms / 1000) * _gifFps;
    return [
      _label('Size', '$w × $h'),
      _StopSlider<int>(stops: _gifSizes, value: _gifSide, enabled: (_) => true, onPick: (v) => setState(() => _gifSide = v)),
      const SizedBox(height: 16),
      _label('Frame rate', 'Lower = smaller file'),
      _StopSlider<int>(
        stops: [for (final f in _gifRates) (f, '$f')],
        value: _gifFps,
        enabled: (_) => true,
        onPick: (v) => setState(() => _gifFps = v),
      ),
      const SizedBox(height: 12),
      _SizeCard(
        primary: 'Estimated file size: ${_mb(bytes)}',
        secondary: p.durationMs > StudioGifSettings.maxMs
            ? 'GIF · first ${StudioGifSettings.maxMs ~/ 1000} s · loops'
            : 'GIF · ${studioClock(p.durationMs)} · loops',
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _photoOptions() {
    final clip = p.clips.first;
    final srcLong = math.max(clip.sourceWidth * (clip.crop.r - clip.crop.l), clip.sourceHeight * (clip.crop.b - clip.crop.t)).round();
    final options = <(int, String)>[
      (1080, 'Standard'),
      (2160, 'High'),
      (srcLong, 'Original'),
    ];
    final long = math.min(_photoLong, srcLong);
    final aspect = p.canvasAspect;
    final w = aspect >= 1 ? long : (long * aspect).round();
    final h = aspect >= 1 ? (long / aspect).round() : long;
    return [
      _label('Size', '$w × $h · JPEG'),
      _StopSlider<int>(
        stops: options,
        value: _photoLong,
        enabled: (v) => v <= srcLong,
        onPick: (v) => setState(() => _photoLong = v),
      ),
      const SizedBox(height: 12),
    ];
  }
}

/// A slider that snaps to labelled stops; faded stops can't be picked.
class _StopSlider<T> extends StatelessWidget {
  const _StopSlider({required this.stops, required this.value, required this.enabled, required this.onPick, this.marker});

  final List<(T, String)> stops;
  final T value;
  final bool Function(T) enabled;
  final ValueChanged<T> onPick;

  /// Optional "recommended" tick, in the same units as the stop values (num only).
  final double? marker;

  int get _index => math.max(0, stops.indexWhere((s) => s.$1 == value));

  void _pick(int i) {
    final i2 = i.clamp(0, stops.length - 1);
    if (!enabled(stops[i2].$1)) return;
    if (stops[i2].$1 != value) {
      HapticFeedback.selectionClick();
      onPick(stops[i2].$1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = stops.length;
    double? markerPos;
    if (marker != null && stops.first.$1 is num) {
      final vals = [for (final s in stops) (s.$1 as num).toDouble()];
      final m = marker!.clamp(vals.first, vals.last);
      for (var i = 0; i < n - 1; i++) {
        if (m <= vals[i + 1]) {
          markerPos = (i + (m - vals[i]) / (vals[i + 1] - vals[i])) / (n - 1);
          break;
        }
      }
    }
    return LayoutBuilder(builder: (context, box) {
      const pad = 12.0;
      final track = box.maxWidth - pad * 2;
      return Column(children: [
        SizedBox(
          height: 36,
          child: Stack(alignment: Alignment.center, children: [
            if (markerPos != null)
              Positioned(
                left: pad + track * markerPos - 1,
                top: 6,
                child: Container(
                  width: 2,
                  height: 24,
                  decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(1)),
                ),
              ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.brandBlue,
                inactiveTrackColor: context.surfaceMid,
                thumbColor: Colors.white,
                overlayColor: AppColors.brandBlue.withValues(alpha: 0.12),
                activeTickMarkColor: Colors.white.withValues(alpha: 0.9),
                inactiveTickMarkColor: context.textMuted.withValues(alpha: 0.5),
                tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2.5),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11, elevation: 3),
                trackShape: const RoundedRectSliderTrackShape(),
                padding: const EdgeInsets.symmetric(horizontal: pad),
              ),
              child: Slider(
                value: _index.toDouble(),
                min: 0,
                max: (n - 1).toDouble(),
                divisions: n - 1,
                onChanged: (v) => _pick(v.round()),
              ),
            ),
          ]),
        ),
        Row(children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _pick(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    stops[i].$2,
                    textAlign: i == 0 ? TextAlign.left : (i == n - 1 ? TextAlign.right : TextAlign.center),
                    maxLines: 1,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: i == _index ? FontWeight.w800 : FontWeight.w600,
                      color: i == _index
                          ? AppColors.brandBlue
                          : (enabled(stops[i].$1) ? context.textSecondary : context.textMuted.withValues(alpha: 0.45)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]);
    });
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.index, required this.onPick});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onPick(i);
            },
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(labels[i],
                    style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: i == index ? context.textPrimary : context.textMuted)),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: i == index ? 22 : 0,
                  height: 3,
                  decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(2)),
                ),
              ]),
            ),
          ),
      ]);
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Export',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
              borderRadius: BorderRadius.circular(AppRadius.full),
              boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text('Export', style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      );
}

class _SizeCard extends StatelessWidget {
  const _SizeCard({required this.primary, required this.secondary});
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.22)),
        ),
        child: Row(children: [
          const Icon(Icons.sd_storage_outlined, size: 20, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(primary, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5)),
            ]),
          ),
        ]),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 20, color: context.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
              Text(subtitle, style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5)),
            ]),
          ),
          Switch.adaptive(value: value, activeTrackColor: AppColors.brandBlue, onChanged: onChanged),
        ]),
      );
}
