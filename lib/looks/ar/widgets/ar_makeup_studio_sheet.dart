import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;

import '../../../shared/theme/app_theme.dart';
import '../builtin/builtin_effects.dart';
import '../controllers/live_ar_controller.dart';
import '../models/ar_effect.dart';
import '../tracking/ar_tracking_models.dart';

/// Opens the Makeup Studio over the camera. [captureStill] grabs a still
/// from the live camera for "Match my face"; leave it null to hide that.
Future<void> showArMakeupStudio(BuildContext context, {Future<String?> Function()? captureStill}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    builder: (_) => ArMakeupStudioSheet(captureStill: captureStill),
  );
}

enum _Area { lips, eyes, cheeks, brows, skin }

/// Advanced live makeup: every control redraws on the tracked face in real
/// time (preview, photos and recorded video), and Oneova AI can build or
/// adjust a look from words or from the user's own face.
class ArMakeupStudioSheet extends ConsumerStatefulWidget {
  final Future<String?> Function()? captureStill;

  const ArMakeupStudioSheet({super.key, this.captureStill});

  @override
  ConsumerState<ArMakeupStudioSheet> createState() => _ArMakeupStudioSheetState();
}

class _ArMakeupStudioSheetState extends ConsumerState<ArMakeupStudioSheet> {
  late ArMakeup _m;
  String _name = 'My makeup';
  _Area _area = _Area.lips;
  final _prompt = TextEditingController();
  bool _aiBusy = false;
  String? _aiStatus;

  static const _lips = [0xFFC77D78, 0xFFD46A7A, 0xFFC8102E, 0xFFFF6F61, 0xFFFF5C9E, 0xFF8E1F4A, 0xFF5E2750, 0xFF8B4A3A, 0xFF2A0A1E, 0xFFFF7A1A];
  static const _shadow = [0xFFE8C9A0, 0xFFA0673A, 0xFFD4A017, 0xFFE8A0B0, 0xFF7A3B9A, 0xFF1F2F5A, 0xFF2B2B33, 0xFF1F7A5A, 0xFF2F6FE0, 0xFFFF9EC7];
  static const _liner = [0xFF000000, 0xFF3A2410, 0xFF0C2A5A, 0xFF4A1A3A, 0xFF0F5A3A, 0xFFFFFFFF, 0xFF0C4FA8];
  static const _iris = [0xFF2F8FFF, 0xFF1FAF6B, 0xFFC88A2E, 0xFFB8D8F0, 0xFF9B5CFF, 0xFFFF1A1A, 0xFFFFC400, 0xFF00E5FF];
  static const _blush = [0xFFFFA8A0, 0xFFFF7AB6, 0xFFE8909A, 0xFFFF8A65, 0xFFC4507A, 0xFFB5734A];
  static const _brow = [0xFFA07A4A, 0xFF6B4A2E, 0xFF4A3426, 0xFF2A1E16, 0xFF111111, 0xFF7A3A1E];
  static const _skin = [0xFFF6DCCB, 0xFFEBC3A6, 0xFFD9A884, 0xFFC18A63, 0xFFA26B47, 0xFF7E4E31, 0xFF5A3420, 0xFF3E2416];

  @override
  void initState() {
    super.initState();
    final ctrl = ref.read(liveArControllerProvider.notifier);
    _m = ctrl.activeMakeup ?? const ArMakeup();
    _name = ref.read(liveArControllerProvider).active['makeup']?.name ?? 'My makeup';
    _ctrl = ctrl;
    // Track the face while the studio is open so its status is live.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.setPreviewFace(true));
  }

  late final LiveArController _ctrl;

  @override
  void dispose() {
    final ctrl = _ctrl;
    Future.microtask(() => ctrl.setPreviewFace(false));
    _prompt.dispose();
    super.dispose();
  }

  void _apply(ArMakeup m) {
    setState(() => _m = m);
    ref.read(liveArControllerProvider.notifier).setMakeup(m, name: _name);
  }

  /// Picking a color for an area that is off turns it on at a sensible strength.
  double _on(double current, double fallback) => current > 0 ? current : fallback;

  // ── AI ──────────────────────────────────────────────────────────────────

  Future<void> _ai({required bool useFace}) async {
    final prompt = _prompt.text.trim();
    if (!useFace && prompt.length < 2) {
      setState(() => _aiStatus = 'Describe the look you want, e.g. "soft pink date night".');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _aiBusy = true;
      _aiStatus = useFace ? 'Reading your skin tone and features…' : 'Designing your look…';
    });
    try {
      String? image;
      if (useFace) {
        final path = await widget.captureStill?.call();
        if (path == null) throw StateError('no_capture');
        image = await _jpegBase64(path);
      }
      final res = await FirebaseFunctions.instance
          .httpsCallable('arMakeupSuggest', options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call<Map<String, dynamic>>({
        if (prompt.isNotEmpty) 'prompt': prompt,
        'image': ?image,
        if (!_m.isEmpty) 'current': _m.toJson(),
      });
      final data = res.data;
      final look = ArMakeup.fromMap((data['makeup'] as Map?)?.cast<String, dynamic>());
      _name = (data['name'] as String?) ?? 'AI look';
      _apply(look);
      HapticFeedback.mediumImpact();
      if (mounted) {
        final tip = (data['tip'] as String?) ?? '';
        setState(() => _aiStatus = '$_name is on. ${tip.isEmpty ? 'Fine-tune it below.' : tip}');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _aiStatus = e.message ?? 'AI could not build that look.');
    } on StateError {
      if (mounted) setState(() => _aiStatus = 'Could not grab a frame from the camera. Try again.');
    } catch (_) {
      if (mounted) setState(() => _aiStatus = 'AI makeup is unavailable right now. Try again.');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// Downscales a camera still to a 512 px JPEG (base64) for the AI call.
  static Future<String> _jpegBase64(String path) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: 512);
    final frame = (await codec.getNextFrame()).image;
    final rgba = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    final pic = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: rgba!.buffer,
      numChannels: 4,
    );
    frame.dispose();
    return base64Encode(img.encodeJpg(pic, quality: 80));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(liveArControllerProvider.notifier);
    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: context.border, width: 1),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Makeup Studio',
                    style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary)),
                const SizedBox(width: 8),
                ValueListenableBuilder<ArFrame?>(
                  valueListenable: ctrl.frame,
                  builder: (context, f, _) => _FaceStatus(faces: f?.faces.length ?? 0),
                ),
                const Spacer(),
                if (!_m.isEmpty)
                  TextButton(
                    onPressed: () {
                      _name = 'My makeup';
                      _apply(const ArMakeup());
                    },
                    child: Text('Remove', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            _aiCard(context),
            const SizedBox(height: 12),
            _looksRow(context),
            const SizedBox(height: 12),
            _areaTabs(context),
            const SizedBox(height: 8),
            ..._controls(context),
          ],
        ),
      ),
    );
  }

  Widget _aiCard(BuildContext context) {
    final input = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: context.border, width: 1),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.brandPink),
              const SizedBox(width: 6),
              Text('Oneova AI makeup artist',
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _prompt,
            enabled: !_aiBusy,
            maxLength: 300,
            style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: 'e.g. soft glam for a wedding, bold red lips, make the blush lighter',
              hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: context.surface,
              enabledBorder: input,
              disabledBorder: input,
              focusedBorder: input.copyWith(borderSide: const BorderSide(color: AppColors.brandBlue)),
            ),
            onSubmitted: (_) => _ai(useFace: false),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: _aiBusy ? null : () => _ai(useFace: false),
                    icon: _aiBusy
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.brush_rounded, size: 16),
                    label: Text(_m.isEmpty ? 'Create look' : 'Apply change',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              if (widget.captureStill != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandBlue,
                        side: const BorderSide(color: AppColors.brandBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      onPressed: _aiBusy ? null : () => _ai(useFace: true),
                      icon: const Icon(Icons.face_retouching_natural, size: 16),
                      label: Text('Match my face', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _aiStatus ??
                (widget.captureStill != null
                    ? 'Match my face sends one camera frame to Oneova AI to pick shades. It is not saved.'
                    : 'Describe a look and AI sets every control for you.'),
            style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _looksRow(BuildContext context) {
    final looks = BuiltInEffects.all.where((b) => b.effect.kind == ArEffectKind.makeup).map((b) => b.effect).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Start from a look', style: _label(context)),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: looks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final e = looks[i];
              final on = _name == e.name;
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.full),
                onTap: () {
                  HapticFeedback.selectionClick();
                  _name = e.name;
                  _apply(e.makeup);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: on ? AppColors.brandBlue.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: on ? AppColors.brandBlue : context.border, width: 1),
                  ),
                  child: Row(
                    children: [
                      _dot(e.makeup.lipOpacity > 0 ? e.makeup.lipColor : (e.makeup.eyeOpacity > 0 ? e.makeup.eyeColor : const Color(0xFFE8C9A0))),
                      const SizedBox(width: 6),
                      Text(e.name,
                          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: on ? AppColors.brandBlue : context.textSecondary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _areaTabs(BuildContext context) {
    const labels = {
      _Area.lips: ('Lips', Icons.mood_rounded),
      _Area.eyes: ('Eyes', Icons.remove_red_eye_outlined),
      _Area.cheeks: ('Cheeks', Icons.blur_circular_rounded),
      _Area.brows: ('Brows', Icons.horizontal_rule_rounded),
      _Area.skin: ('Skin', Icons.face_retouching_natural),
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final a in _Area.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: Icon(labels[a]!.$2, size: 15, color: _area == a ? Colors.white : context.textSecondary),
                label: Text(labels[a]!.$1),
                selected: _area == a,
                showCheckmark: false,
                selectedColor: AppColors.brandBlue,
                backgroundColor: context.surfaceMid,
                side: BorderSide(color: _area == a ? AppColors.brandBlue : context.border),
                labelStyle: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _area == a ? Colors.white : context.textPrimary,
                ),
                onSelected: (_) => setState(() => _area = a),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _controls(BuildContext context) {
    final m = _m;
    switch (_area) {
      case _Area.lips:
        return [
          _swatches(context, 'Lip color', _lips, m.lipColor, m.lipOpacity > 0,
              (c) => _apply(m.copyWith(lipColor: c, lipOpacity: _on(m.lipOpacity, 0.6)))),
          _slider(context, 'Intensity', m.lipOpacity, (v) => _apply(m.copyWith(lipOpacity: v))),
          _slider(context, 'Gloss', m.lipGloss, (v) => _apply(m.copyWith(lipGloss: v))),
        ];
      case _Area.eyes:
        return [
          _swatches(context, 'Eyeshadow', _shadow, m.shadowColor, m.shadowOpacity > 0,
              (c) => _apply(m.copyWith(shadowColor: c, shadowOpacity: _on(m.shadowOpacity, 0.45)))),
          _slider(context, 'Shadow intensity', m.shadowOpacity, (v) => _apply(m.copyWith(shadowOpacity: v))),
          _swatches(context, 'Eyeliner', _liner, m.linerColor, m.linerOpacity > 0,
              (c) => _apply(m.copyWith(linerColor: c, linerOpacity: _on(m.linerOpacity, 0.85)))),
          _slider(context, 'Liner intensity', m.linerOpacity, (v) => _apply(m.copyWith(linerOpacity: v))),
          _slider(context, 'Liner thickness', m.linerWidth, (v) => _apply(m.copyWith(linerWidth: v))),
          _slider(context, 'Wing', m.linerWing, (v) => _apply(m.copyWith(linerWing: v))),
          _swatches(context, 'Eye color (lenses)', _iris, m.eyeColor, m.eyeOpacity > 0 || m.eyeGlow > 0,
              (c) => _apply(m.copyWith(eyeColor: c, eyeOpacity: _on(m.eyeOpacity, 0.7)))),
          _slider(context, 'Lens intensity', m.eyeOpacity, (v) => _apply(m.copyWith(eyeOpacity: v))),
          _slider(context, 'Glow', m.eyeGlow, (v) => _apply(m.copyWith(eyeGlow: v))),
        ];
      case _Area.cheeks:
        return [
          _swatches(context, 'Blush', _blush, m.blushColor, m.blushOpacity > 0,
              (c) => _apply(m.copyWith(blushColor: c, blushOpacity: _on(m.blushOpacity, 0.4)))),
          _slider(context, 'Blush intensity', m.blushOpacity, (v) => _apply(m.copyWith(blushOpacity: v))),
          _slider(context, 'Contour', m.contourOpacity, (v) => _apply(m.copyWith(contourOpacity: v))),
          _slider(context, 'Highlight', m.highlightOpacity, (v) => _apply(m.copyWith(highlightOpacity: v))),
        ];
      case _Area.brows:
        return [
          _swatches(context, 'Brow color', _brow, m.browColor, m.browOpacity > 0,
              (c) => _apply(m.copyWith(browColor: c, browOpacity: _on(m.browOpacity, 0.45)))),
          _slider(context, 'Intensity', m.browOpacity, (v) => _apply(m.copyWith(browOpacity: v))),
          _slider(context, 'Thickness', m.browWidth, (v) => _apply(m.copyWith(browWidth: v))),
        ];
      case _Area.skin:
        return [
          _slider(context, 'Smooth skin', m.smoothing, (v) => _apply(m.copyWith(smoothing: v))),
          _swatches(context, 'Foundation shade', _skin, m.foundationColor, m.foundationOpacity > 0,
              (c) => _apply(m.copyWith(foundationColor: c, foundationOpacity: _on(m.foundationOpacity, 0.25)))),
          _slider(context, 'Coverage', m.foundationOpacity, (v) => _apply(m.copyWith(foundationOpacity: v))),
        ];
    }
  }

  TextStyle _label(BuildContext context) =>
      GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textSecondary);

  Widget _dot(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
      );

  Widget _swatches(BuildContext context, String label, List<int> colors, Color current, bool enabled, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _label(context)),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: colors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final c = Color(colors[i]);
                final selected = enabled && current.toARGB32() == c.toARGB32();
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onPick(c);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.brandBlue : context.border,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(BuildContext context, String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: _label(context))),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            activeColor: AppColors.brandBlue,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text('${(value * 100).round()}',
              textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
        ),
      ],
    );
  }
}

/// "Face tracked" / "Looking for a face" pill, driven by live tracking.
class _FaceStatus extends StatelessWidget {
  final int faces;

  const _FaceStatus({required this.faces});

  @override
  Widget build(BuildContext context) {
    final ok = faces > 0;
    final color = ok ? AppColors.brandBlue : AppColors.brandPink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.center_focus_weak_rounded, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            ok ? (faces > 1 ? '$faces FACES' : 'FACE TRACKED') : 'LOOKING FOR A FACE',
            style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color),
          ),
        ],
      ),
    );
  }
}
