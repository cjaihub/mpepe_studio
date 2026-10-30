import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_renderer.dart';
import 'studio_ui.dart';

/// What the user picked in the export sheet.
class StudioExportChoice {
  final StudioVideoSettings? video;
  final int photoLongSide;
  final bool saveToGallery;
  const StudioExportChoice({this.video, this.photoLongSide = 0, required this.saveToGallery});
}

const _resolutions = <(int, String)>[(480, '480p'), (720, '720p'), (1080, '1080p'), (1440, '2K'), (2160, '4K')];
const _frameRates = <int>[24, 25, 30, 50, 60];

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

Future<StudioExportChoice?> showStudioExportSheet(BuildContext context, StudioProject project) {
  return showModalBottomSheet<StudioExportChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _StudioExportSheet(project: project),
  );
}

class _StudioExportSheet extends StatefulWidget {
  final StudioProject project;
  const _StudioExportSheet({required this.project});

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
  int _photoLong = 2160;

  StudioProject get p => widget.project;

  int get _sourceFps {
    final f = p.maxSourceFps;
    return f <= 0 ? 30 : f.round();
  }

  List<int> get _fpsOptions {
    final opts = _frameRates.where((f) => f <= math.max(_sourceFps, 24)).toList();
    final cap = _caps?.maxFps ?? 60;
    return opts.where((f) => f <= cap).toList();
  }

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
        if (!_fpsOptions.contains(_fps) && _fpsOptions.isNotEmpty) _fps = _fpsOptions.last;
        if (!_bitrateTouched) _bitrate = studioRecommendedBitrate(_short, _fps);
      });
    }).catchError((_) {});
  }

  String _mb(double bytes) => bytes >= 1024 * 1024 * 1024
      ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StudioSheetHandle(),
            Text(p.isPhoto ? 'Export photo' : 'Export video',
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (p.isPhoto) ..._photoOptions() else ..._videoOptions(),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('Save a copy to gallery',
                      style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Switch.adaptive(value: _save, activeTrackColor: AppColors.brandBlue, onChanged: (v) => setState(() => _save = v)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: StudioPrimaryButton(
                label: 'Export',
                icon: Icons.ios_share_rounded,
                onTap: () => Navigator.pop(
                  context,
                  StudioExportChoice(
                    video: p.isPhoto ? null : StudioVideoSettings(shortSide: _short, fps: _fps, bitrate: _bitrate),
                    photoLongSide: _photoLong,
                    saveToGallery: _save,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String title, String trailing) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(title, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            Flexible(
              child: Text(trailing,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Widget _steps<T>({required List<(T, String)> options, required T value, required bool Function(T) enabled, required ValueChanged<T> onPick}) {
    return Row(
      children: [
        for (final o in options)
          Expanded(
            child: GestureDetector(
              onTap: enabled(o.$1) ? () => onPick(o.$1) : null,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o.$1 == value ? AppColors.brandBlue : context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: o.$1 == value ? AppColors.brandBlue : context.border),
                ),
                child: Text(
                  o.$2,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: o.$1 == value
                        ? AppColors.brandWhite
                        : (enabled(o.$1) ? context.textPrimary : context.textMuted.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _videoOptions() {
    final size = studioCanvasSize(p.canvasAspect, _short);
    final secs = p.durationMs / 1000;
    final bytes = (_bitrate + 128000) * secs / 8;
    final src = p.maxSourceShortSide;
    final upscaled = src > 0 && _short > src;
    final recommended = studioRecommendedBitrate(_short, _fps);
    return [
      _label('Resolution', '${size.width.toInt()} × ${size.height.toInt()}${upscaled ? '  ·  above source ($src p)' : ''}'),
      _steps<int>(
        options: _resolutions,
        value: _short,
        enabled: _resolutionOk,
        onPick: (v) => setState(() {
          _short = v;
          if (!_bitrateTouched) _bitrate = studioRecommendedBitrate(_short, _fps);
        }),
      ),
      if (_caps != null && !_resolutionOk(2160))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Greyed sizes are beyond this phone\'s video encoder.',
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 10.5)),
        ),
      const SizedBox(height: 14),
      _label('Frame rate', 'Source: $_sourceFps fps'),
      _steps<int>(
        options: [for (final f in _frameRates) (f, '$f')],
        value: _fps,
        enabled: _fpsOptions.contains,
        onPick: (v) => setState(() {
          _fps = v;
          if (!_bitrateTouched) _bitrate = studioRecommendedBitrate(_short, _fps);
        }),
      ),
      const SizedBox(height: 14),
      _label('Bitrate', 'Recommended ${(recommended / 1000000).toStringAsFixed(1)} Mbps'),
      StudioSliderRow(
        label: 'Mbps',
        value: _bitrate / 1000000,
        min: 1,
        max: 60,
        format: (v) => v.toStringAsFixed(v < 10 ? 1 : 0),
        onChanged: (v) => setState(() {
          _bitrateTouched = true;
          _bitrate = (v * 1000000).round();
        }),
      ),
      const SizedBox(height: 6),
      Center(
        child: Text(
          'H.264 MP4 · ${studioClock(p.durationMs)} · Estimated file size ${_mb(bytes)}',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 8),
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
      _label('Size', '$w × $h  ·  JPEG'),
      _steps<int>(
        options: options,
        value: _photoLong,
        enabled: (v) => v <= srcLong,
        onPick: (v) => setState(() => _photoLong = v),
      ),
      const SizedBox(height: 10),
    ];
  }
}
