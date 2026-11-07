import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_text_animator.dart';
import '../services/studio_text_painter.dart';
import '../services/studio_text_templates.dart';
import 'studio_text_widgets.dart';
import 'studio_ui.dart';

/// Result of the text editor.
class StudioTextEdit {
  final StudioText text;

  /// Captions only: apply style and animation to every caption.
  final bool applyToAllCaptions;
  const StudioTextEdit(this.text, {this.applyToAllCaptions = false});
}

/// Full text editor: content, 100+ templates (categories, search,
/// favorites), font, colors, outline, shadow, background, animation, timing
/// and position. Returns null on cancel.
Future<StudioTextEdit?> showStudioTextEditor(
  BuildContext context,
  StudioText initial, {
  String title = 'Text',
  int initialTab = 0,
  int maxEndMs = 0,
}) {
  return showModalBottomSheet<StudioTextEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) => _StudioTextEditor(initial: initial, title: title, initialTab: initialTab, maxEndMs: maxEndMs),
  );
}

/// Template palette for the color pickers (text content colors).
const studioTextPalette = <int>[
  0xFFFFFFFF, 0xFF0B0B0F, 0xFF0C4FA8, 0xFF3D8BFF, 0xFF00E5FF, 0xFF5EF2C2, //
  0xFFB6FF3B, 0xFFFFD60A, 0xFFFFC857, 0xFFFF8A00, 0xFFFF6B6B, 0xFFFF2D87, //
  0xFF8B5CF6, 0xFFFFF4E0, 0xFF9CA3AF, 0xFF4B5563,
];

/// Fonts offered in the Font tab (every template font plus a few readable
/// families for long captions and non-Latin scripts).
List<String> studioFontChoices() => {
      'Inter',
      'Noto Sans',
      'Roboto',
      'Open Sans',
      ...StudioTextTemplates.fonts,
    }.toList();

class _StudioTextEditor extends StatefulWidget {
  final StudioText initial;
  final String title;
  final int initialTab;
  final int maxEndMs;
  const _StudioTextEditor({required this.initial, required this.title, required this.initialTab, required this.maxEndMs});

  @override
  State<_StudioTextEditor> createState() => _StudioTextEditorState();
}

class _StudioTextEditorState extends State<_StudioTextEditor> with SingleTickerProviderStateMixin {
  late final _controller = TextEditingController(text: widget.initial.text);
  late StudioText _t = widget.initial;
  late final List<String> _tabs = widget.initial.isSticker ? const ['Animate', 'Layout'] : const ['Templates', 'Font', 'Style', 'Animate', 'Layout'];
  late final TabController _tab = TabController(length: _tabs.length, vsync: this, initialIndex: widget.initialTab.clamp(0, _tabs.length - 1));
  bool _applyAll = false;

  // Templates tab state.
  final _search = TextEditingController();
  String _category = 'All';
  Set<String> _favorites = {};
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initial.isCaption) _category = 'Captions';
    StudioTemplatePrefs.favorites().then((f) => mounted ? setState(() => _favorites = f) : null);
    StudioTemplatePrefs.recent().then((r) => mounted ? setState(() => _recent = r) : null);
    _controller.addListener(() => setState(() => _t = _t.copyWith(text: _controller.text)));
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _type(StudioTypeStyle Function(StudioTypeStyle) f) => setState(() => _t = _t.copyWith(type: f(_t.type)));
  void _anim(StudioTextAnim Function(StudioTextAnim) f) => setState(() => _t = _t.copyWith(anim: f(_t.anim)));

  void _done() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.pop(context);
      return;
    }
    if (_t.templateId != null) StudioTemplatePrefs.markUsed(_t.templateId!);
    Navigator.pop(context, StudioTextEdit(_t.copyWith(text: text), applyToAllCaptions: _applyAll));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height * 0.82;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: height - bottom * 0.6,
        child: Column(
          children: [
            const StudioSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
              child: Row(
                children: [
                  Text(widget.title, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (widget.initial.isCaption) ...[
                    Text('All captions', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                    Switch.adaptive(
                      value: _applyAll,
                      activeTrackColor: AppColors.brandBlue,
                      onChanged: (v) => setState(() => _applyAll = v),
                    ),
                  ],
                  StudioPrimaryButton(label: 'Done', onTap: _done),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: widget.initial.text.isEmpty,
                maxLines: 3,
                minLines: 1,
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14),
                decoration: _fieldDecoration(context, widget.initial.isSticker ? 'Sticker' : 'Enter text'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.brandBlack, borderRadius: BorderRadius.circular(AppRadius.md)),
              clipBehavior: Clip.antiAlias,
              child: StudioTextLoopPreview(text: _t.text.trim().isEmpty ? _t.copyWith(text: 'Your text') : _t, height: 112),
            ),
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: context.textPrimary,
              unselectedLabelColor: context.textMuted,
              indicatorColor: AppColors.brandBlue,
              dividerColor: context.border,
              labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: [for (final t in _tabs) Tab(text: t, height: 40)],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  for (final t in _tabs)
                    switch (t) {
                      'Templates' => _templatesTab(),
                      'Font' => _fontTab(),
                      'Style' => _styleTab(),
                      'Animate' => _animateTab(),
                      _ => _layoutTab(),
                    },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Templates ──────────────────────────────────────────────────────────

  List<StudioTextTemplate> _visibleTemplates() {
    final q = _search.text;
    Iterable<StudioTextTemplate> list = StudioTextTemplates.all;
    switch (_category) {
      case 'All':
        break;
      case 'Favorites':
        list = list.where((t) => _favorites.contains(t.id));
      case 'Recent':
        list = [for (final id in _recent) ?StudioTextTemplates.byId(id)];
      default:
        list = list.where((t) => t.category == _category);
    }
    return list.where((t) => t.matches(q)).toList();
  }

  Widget _templatesTab() {
    final list = _visibleTemplates();
    final cats = ['All', 'Favorites', 'Recent', ...StudioTextTemplates.categories];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
            decoration: _fieldDecoration(context, 'Search ${StudioTextTemplates.all.length} templates').copyWith(
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
            ),
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _chip(
                    c,
                    selected: _category == c,
                    icon: c == 'Favorites' ? Icons.star_rounded : (c == 'Recent' ? Icons.history_rounded : null),
                    onTap: () => setState(() => _category = c),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    _category == 'Favorites'
                        ? 'Tap the star on a template to keep it here.'
                        : (_category == 'Recent' ? 'Templates you use show up here.' : 'No templates match.'),
                    style: GoogleFonts.inter(color: context.textMuted, fontSize: 12.5),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _templateTile(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _templateTile(StudioTextTemplate tpl) {
    final selected = _t.templateId == tpl.id;
    final fav = _favorites.contains(tpl.id);
    final sample = StudioText(id: 'tpl_${tpl.id}', text: tpl.sample, startMs: 0, endMs: 1, size: tpl.size, type: tpl.type);
    return GestureDetector(
      onTap: () => setState(() => _t = tpl.applyTo(_t)),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: selected ? AppColors.brandBlue : context.border, width: selected ? 2 : 1),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 18),
                child: FittedBox(child: StudioTextLayer(text: sample, canvasWidth: 300)),
              ),
            ),
            Positioned(
              left: 6,
              right: 24,
              bottom: 4,
              child: Text(
                tpl.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w600),
              ),
            ),
            if (!tpl.anim.isStatic)
              const Positioned(left: 5, top: 5, child: Icon(Icons.animation_rounded, size: 11, color: AppColors.textSecondary)),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  final f = await StudioTemplatePrefs.toggleFavorite(tpl.id);
                  if (mounted) setState(() => _favorites = f);
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 16, color: fav ? AppColors.brandPink : AppColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Font ───────────────────────────────────────────────────────────────

  Widget _fontTab() {
    final s = _t.type;
    final fonts = studioFontChoices();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SizedBox(
          height: 96,
          child: GridView.builder(
            scrollDirection: Axis.horizontal,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.42),
            itemCount: fonts.length,
            itemBuilder: (_, i) {
              final f = fonts[i];
              final selected = s.font == f;
              return GestureDetector(
                onTap: () => _type((x) => x.copyWith(font: f)),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: selected ? AppColors.brandBlue : context.border, width: selected ? 2 : 1),
                  ),
                  child: Text(
                    f,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioTextPainter.font(f, fontSize: 13, weight: 600).copyWith(color: context.textPrimary),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _label('Weight'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in const [(300, 'Light'), (400, 'Regular'), (500, 'Medium'), (600, 'Semibold'), (700, 'Bold'), (800, 'Heavy'), (900, 'Black')])
              _chip(w.$2, selected: s.weight == w.$1, onTap: () => _type((x) => x.copyWith(weight: w.$1))),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip('Italic', icon: Icons.format_italic_rounded, selected: s.italic, onTap: () => _type((x) => x.copyWith(italic: !x.italic))),
            _chip('ALL CAPS', icon: Icons.text_fields_rounded, selected: s.uppercase, onTap: () => _type((x) => x.copyWith(uppercase: !x.uppercase))),
            _chip('Left', icon: Icons.format_align_left_rounded, selected: s.align == 0, onTap: () => _type((x) => x.copyWith(align: 0))),
            _chip('Center', icon: Icons.format_align_center_rounded, selected: s.align == 1, onTap: () => _type((x) => x.copyWith(align: 1))),
            _chip('Right', icon: Icons.format_align_right_rounded, selected: s.align == 2, onTap: () => _type((x) => x.copyWith(align: 2))),
          ],
        ),
        const SizedBox(height: 8),
        StudioSliderRow(
          label: 'Size',
          value: _t.size * 100,
          min: 2,
          max: 22,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => setState(() => _t = _t.copyWith(size: v / 100)),
        ),
        StudioSliderRow(
          label: 'Spacing',
          value: s.letterSpacing * 100,
          min: -10,
          max: 50,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => _type((x) => x.copyWith(letterSpacing: v / 100)),
        ),
        StudioSliderRow(
          label: 'Line height',
          value: s.lineHeight,
          min: 0.8,
          max: 1.8,
          format: (v) => v.toStringAsFixed(2),
          onChanged: (v) => _type((x) => x.copyWith(lineHeight: v)),
        ),
      ],
    );
  }

  // ── Style ──────────────────────────────────────────────────────────────

  Widget _styleTab() {
    final s = _t.type;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _label('Color'),
        _Swatches(selected: s.color, onPick: (c) => _type((x) => x.copyWith(color: c))),
        const SizedBox(height: 12),
        _label('Gradient'),
        _Swatches(selected: s.color2, allowNone: true, onPick: (c) => _type((x) => x.copyWith(color2: c))),
        const SizedBox(height: 12),
        _label('Outline'),
        StudioSliderRow(
          label: 'Width',
          value: s.stroke * 100,
          min: 0,
          max: 30,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => _type((x) => x.copyWith(stroke: v / 100)),
        ),
        if (s.stroke > 0) _Swatches(selected: s.strokeColor, onPick: (c) => _type((x) => x.copyWith(strokeColor: c))),
        const SizedBox(height: 12),
        Row(
          children: [
            _label('Shadow'),
            const Spacer(),
            _chip('Glow', icon: Icons.light_mode_outlined, selected: s.glow, onTap: () => _type((x) => x.copyWith(glow: !x.glow))),
          ],
        ),
        StudioSliderRow(
          label: s.glow ? 'Glow' : 'Blur',
          value: s.shadowBlur * 100,
          min: 0,
          max: 100,
          format: (v) => v.toStringAsFixed(0),
          onChanged: (v) => _type((x) => x.copyWith(shadowBlur: v / 100)),
        ),
        if (!s.glow) ...[
          StudioSliderRow(
            label: 'Offset X',
            value: s.shadowDx * 100,
            min: -20,
            max: 20,
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) => _type((x) => x.copyWith(shadowDx: v / 100)),
          ),
          StudioSliderRow(
            label: 'Offset Y',
            value: s.shadowDy * 100,
            min: -20,
            max: 20,
            format: (v) => v.toStringAsFixed(0),
            onChanged: (v) => _type((x) => x.copyWith(shadowDy: v / 100)),
          ),
        ],
        _Swatches(
          selected: s.shadowColor | 0xFF000000,
          onPick: (c) => _type((x) => x.copyWith(shadowColor: s.glow ? c : (c & 0x00FFFFFF) | 0xB3000000)),
        ),
        const SizedBox(height: 12),
        _label('Background'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final b in StudioTextBg.values) _chip(b.label, selected: s.bg == b, onTap: () => _type((x) => x.copyWith(bg: b)))],
        ),
        if (s.bg != StudioTextBg.none) ...[
          const SizedBox(height: 8),
          _Swatches(
            selected: s.bgColor | 0xFF000000,
            onPick: (c) => _type((x) => x.copyWith(bgColor: (c & 0x00FFFFFF) | (x.bgColor & 0xFF000000))),
          ),
          StudioSliderRow(
            label: 'Opacity',
            value: ((s.bgColor >> 24) & 0xFF) / 255 * 100,
            min: 0,
            max: 100,
            format: (v) => '${v.round()}%',
            onChanged: (v) => _type((x) => x.copyWith(bgColor: (x.bgColor & 0x00FFFFFF) | ((v / 100 * 255).round() << 24))),
          ),
        ],
        if (_t.isCaption) ...[
          const SizedBox(height: 12),
          _label('Spoken word highlight'),
          _Swatches(selected: s.highlightColor, allowNone: true, onPick: (c) => _type((x) => x.copyWith(highlightColor: c))),
        ],
      ],
    );
  }

  // ── Animate ────────────────────────────────────────────────────────────

  Widget _animRow(String title, List<StudioAnimDef> defs, String selected, ValueChanged<String> onPick) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(title),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final d in defs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _chip(d.label, selected: selected == d.id, onTap: () => onPick(d.id)),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _animateTab() {
    final a = _t.anim;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _animRow('In', StudioTextAnimator.ins, a.inId, (id) => _anim((x) => x.copyWith(inId: id))),
        if (a.inId != 'none')
          StudioSliderRow(
            label: 'In time',
            value: a.inMs / 1000,
            min: 0.1,
            max: 3,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) => _anim((x) => x.copyWith(inMs: (v * 1000).round())),
          ),
        const SizedBox(height: 10),
        _animRow('Out', StudioTextAnimator.outs, a.outId, (id) => _anim((x) => x.copyWith(outId: id))),
        if (a.outId != 'none')
          StudioSliderRow(
            label: 'Out time',
            value: a.outMs / 1000,
            min: 0.1,
            max: 3,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) => _anim((x) => x.copyWith(outMs: (v * 1000).round())),
          ),
        const SizedBox(height: 10),
        _animRow('Loop', StudioTextAnimator.loops, a.loopId, (id) => _anim((x) => x.copyWith(loopId: id))),
        if (a.loopId != 'none')
          StudioSliderRow(
            label: 'Cycle',
            value: a.loopMs / 1000,
            min: 0.3,
            max: 5,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) => _anim((x) => x.copyWith(loopMs: (v * 1000).round())),
          ),
      ],
    );
  }

  // ── Layout ─────────────────────────────────────────────────────────────

  Widget _layoutTab() {
    const spots = [
      (-0.7, -0.75), (0.0, -0.75), (0.7, -0.75), //
      (-0.7, 0.0), (0.0, 0.0), (0.7, 0.0), //
      (-0.7, 0.62), (0.0, 0.62), (0.7, 0.62),
    ];
    final dur = _t.endMs - _t.startMs;
    final maxDur = widget.maxEndMs > _t.startMs ? widget.maxEndMs - _t.startMs : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _label('Position'),
        Center(
          child: SizedBox(
            width: 120,
            height: 120 * 16 / 9 * 0.6,
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.9,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final p in spots)
                  GestureDetector(
                    onTap: () => setState(() => _t = _t.copyWith(x: p.$1, y: p.$2)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: (_t.x - p.$1).abs() < 0.05 && (_t.y - p.$2).abs() < 0.05
                            ? AppColors.brandBlue
                            : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(color: context.border),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        StudioSliderRow(
          label: 'Rotate',
          value: _t.rotation,
          min: -180,
          max: 180,
          format: (v) => '${v.round()}°',
          onChanged: (v) => setState(() => _t = _t.copyWith(rotation: (v / 1).roundToDouble())),
        ),
        StudioSliderRow(
          label: 'Size',
          value: _t.size * 100,
          min: 2,
          max: _t.isSticker ? 40 : 22,
          format: (v) => v.toStringAsFixed(1),
          onChanged: (v) => setState(() => _t = _t.copyWith(size: v / 100)),
        ),
        if (maxDur > 300)
          StudioSliderRow(
            label: 'Duration',
            value: dur / 1000,
            min: 0.3,
            max: maxDur / 1000,
            format: (v) => '${v.toStringAsFixed(1)}s',
            onChanged: (v) => setState(() => _t = _t.copyWith(endMs: _t.startMs + (v * 1000).round())),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _t = _t.copyWith(rotation: 0, x: 0, y: _t.isCaption ? 0.62 : 0)),
            icon: Icon(Icons.restart_alt_rounded, size: 16, color: context.textSecondary),
            label: Text('Reset position', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── Bits ───────────────────────────────────────────────────────────────

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _chip(String label, {required bool selected, required VoidCallback onTap, IconData? icon}) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandBlue : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: selected ? AppColors.brandBlue : context.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? AppColors.brandWhite : context.textSecondary),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: GoogleFonts.inter(
                    color: selected ? AppColors.brandWhite : context.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      );
}

InputDecoration _fieldDecoration(BuildContext context, String hint) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: context.surfaceMid,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.brandBlue),
      ),
    );

class _Swatches extends StatelessWidget {
  final int selected;
  final bool allowNone;
  final ValueChanged<int> onPick;
  const _Swatches({required this.selected, required this.onPick, this.allowNone = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (allowNone)
            _dot(
              context,
              selected == 0,
              () => onPick(0),
              child: Icon(Icons.block_rounded, size: 16, color: context.textMuted),
              color: context.surfaceMid,
            ),
          for (final c in studioTextPalette) _dot(context, selected == c, () => onPick(c), color: Color(c)),
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, bool on, VoidCallback onTap, {required Color color, Widget? child}) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: on ? AppColors.brandBlue : context.border, width: on ? 2.5 : 1),
          ),
          child: child,
        ),
      );
}
