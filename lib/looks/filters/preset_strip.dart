import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../create/studio/models/studio_project.dart';
import '../../create/studio/services/studio_color.dart';
import '../../create/studio/services/studio_looks.dart';
import '../../shared/theme/app_theme.dart';
import 'filter_reference_image.dart';
import 'oneova_presets.dart';

/// One-tap presets (filter + grade + adjustments + beauty): Favourites, Mine
/// and Oneova. Hold to preview, tap to apply, star to favourite, "Save" keeps
/// the current look as the user's own preset.
class OneovaPresetStrip extends StatefulWidget {
  final String? selectedId;
  final ValueChanged<OneovaPreset> onApply;
  final ValueChanged<OneovaPreset?>? onPreview;

  /// Saves the current look; null hides the Save button.
  final Future<OneovaPreset?> Function(String name)? onSaveCurrent;
  final ImageProvider? thumbnail;
  final bool overCamera;

  const OneovaPresetStrip({
    super.key,
    required this.selectedId,
    required this.onApply,
    this.onPreview,
    this.onSaveCurrent,
    this.thumbnail,
    this.overCamera = false,
  });

  @override
  State<OneovaPresetStrip> createState() => _OneovaPresetStripState();
}

class _OneovaPresetStripState extends State<OneovaPresetStrip> {
  final _presets = OneovaPresets.instance;
  String _tab = 'Oneova';
  ui.Image? _reference;
  String? _holding;

  @override
  void initState() {
    super.initState();
    _presets.addListener(_changed);
    _presets.load();
    if (widget.thumbnail == null) {
      FilterReferenceImage.load().then((i) {
        if (mounted) setState(() => _reference = i);
      });
    }
  }

  @override
  void dispose() {
    _presets.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Color get _fg => widget.overCamera ? AppColors.brandWhite : context.textPrimary;
  Color get _muted => widget.overCamera ? AppColors.brandWhite.withValues(alpha: 0.6) : context.textMuted;

  List<OneovaPreset> get _items => switch (_tab) {
        'Favourites' => _presets.favourites,
        'Mine' => _presets.mine,
        _ => OneovaPresets.builtIns,
      };

  Future<void> _save() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Save preset', style: GoogleFonts.inter(color: ctx.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          style: GoogleFonts.inter(color: ctx.textPrimary),
          decoration: const InputDecoration(hintText: 'Name your look'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text('Save', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || !mounted) return;
    final saved = await widget.onSaveCurrent!(name);
    if (saved != null && mounted) {
      setState(() => _tab = 'Mine');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "${saved.name}" to your presets')));
    }
  }

  void _hold(OneovaPreset? p) {
    if (_holding == p?.id) return;
    _holding = p?.id;
    widget.onPreview?.call(p);
    if (p != null) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final t in const ['Favourites', 'Mine', 'Oneova'])
                      GestureDetector(
                        onTap: () => setState(() => _tab = t),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (t == 'Favourites') ...[
                              Icon(Icons.star_rounded, size: 14, color: t == _tab ? AppColors.brandPink : _muted),
                              const SizedBox(width: 3),
                            ],
                            Text(t,
                                style: GoogleFonts.inter(
                                  color: t == _tab ? _fg : _muted,
                                  fontSize: 12.5,
                                  fontWeight: t == _tab ? FontWeight.w800 : FontWeight.w600,
                                )),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.onSaveCurrent != null)
                TextButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 16, color: AppColors.brandBlue),
                  label: Text('Save look', style: GoogleFonts.inter(color: AppColors.brandBlue, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 96,
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _tab == 'Mine' ? 'Set a filter and adjustments, then Save look' : 'Star a preset to keep it here',
                    style: GoogleFonts.inter(color: _muted, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(OneovaPreset p) {
    final selected = widget.selectedId == p.id;
    Widget img = widget.thumbnail != null
        ? Image(image: widget.thumbnail!, fit: BoxFit.cover, gaplessPlayback: true)
        : (_reference == null ? ColoredBox(color: _muted.withValues(alpha: 0.2)) : RawImage(image: _reference, fit: BoxFit.cover));
    final adjust = p.applyTo(const StudioAdjust());
    final m = StudioColor.adjustMatrix(adjust);
    if (!StudioColor.isIdentity(m)) img = ColorFiltered(colorFilter: ColorFilter.matrix(m), child: img);
    final look = StudioLooks.forLook(p.filterId, p.intensity, adjust);
    if (look != null) img = StudioLookFilter(look: look, child: img);
    final fav = _presets.isFavourite(p.id);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onApply(p);
      },
      onLongPressStart: (_) => _hold(p),
      onLongPressEnd: (_) => _hold(null),
      onLongPressCancel: () => _hold(null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          width: 66,
          child: Column(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: selected ? AppColors.brandBlue : _muted.withValues(alpha: 0.3), width: selected ? 2 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    img,
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _presets.toggleFavourite(p.id),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded,
                              size: 16, color: fav ? AppColors.brandPink : AppColors.brandWhite),
                        ),
                      ),
                    ),
                    if (!p.builtIn && _tab == 'Mine')
                      Positioned(
                        left: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => _presets.delete(p),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close_rounded, size: 15, color: AppColors.brandWhite),
                          ),
                        ),
                      ),
                    if (p.beauty > 0)
                      const Positioned(
                        left: 3,
                        bottom: 3,
                        child: Icon(Icons.face_retouching_natural, size: 13, color: AppColors.brandWhite),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: selected ? AppColors.brandBlue : _muted, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
