import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../create/studio/services/studio_looks.dart';
import '../../shared/theme/app_theme.dart';
import '../models/oneova_look.dart';
import 'filter_prefs.dart';
import 'filter_reference_image.dart';
import 'oneova_filter_library.dart';

/// One pickable grade in the browser.
class FilterItem {
  final String id;
  final String name;
  final OneovaLook? look;
  const FilterItem(this.id, this.name, this.look);

  static const none = FilterItem('none', 'None', null);
}

/// Extra groups shown before the library categories (e.g. Studio Looks).
class FilterGroup {
  final String name;
  final List<FilterItem> items;
  const FilterGroup(this.name, this.items);
}

/// Resolves any filter id (library or Studio Look) to a display item.
FilterItem filterItemFor(String id) {
  if (id == 'none') return FilterItem.none;
  final f = OneovaFilterLibrary.byId(id);
  if (f != null) return FilterItem(f.id, f.name, f.look);
  final s = StudioLooks.byId(id);
  return FilterItem(s.id, s.name, s.id == 'none' ? null : s.look);
}

/// Searchable filter strip used by the camera and the Studio editor:
/// categories, favourites and recents, hold (or hover) to preview, tap to
/// apply, and an intensity slider for the applied filter.
class OneovaFilterBrowser extends StatefulWidget {
  final String selectedId;
  final double intensity;
  final ValueChanged<String> onPick;
  final ValueChanged<double> onIntensity;
  final ValueChanged<double>? onIntensityEnd;

  /// Called with a filter id while it is held or hovered, then null.
  final ValueChanged<String?>? onPreview;

  /// Image shown in the tiles; the reference scene when null.
  final ImageProvider? thumbnail;
  final List<FilterGroup> leadingGroups;

  /// White-on-glass styling for use over the camera viewfinder.
  final bool overCamera;

  const OneovaFilterBrowser({
    super.key,
    required this.selectedId,
    required this.intensity,
    required this.onPick,
    required this.onIntensity,
    this.onIntensityEnd,
    this.onPreview,
    this.thumbnail,
    this.leadingGroups = const [],
    this.overCamera = false,
  });

  @override
  State<OneovaFilterBrowser> createState() => _OneovaFilterBrowserState();
}

class _OneovaFilterBrowserState extends State<OneovaFilterBrowser> {
  static const _fav = 'Favourites';
  static const _recent = 'Recent';
  static const _allName = 'All';

  final _search = TextEditingController();
  final _prefs = FilterPrefs.instance;
  late String _group;
  bool _searching = false;
  String? _holding;
  ui.Image? _reference;

  @override
  void initState() {
    super.initState();
    _prefs.load();
    _prefs.addListener(_onPrefs);
    final sel = OneovaFilterLibrary.byId(widget.selectedId);
    _group = sel?.category ?? (widget.leadingGroups.isNotEmpty ? widget.leadingGroups.first.name : OneovaFilterLibrary.categories.first);
    if (widget.thumbnail == null) {
      FilterReferenceImage.load().then((img) {
        if (mounted) setState(() => _reference = img);
      });
    }
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    _search.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Color get _fg => widget.overCamera ? AppColors.brandWhite : context.textPrimary;
  Color get _muted => widget.overCamera ? AppColors.brandWhite.withValues(alpha: 0.6) : context.textMuted;
  Color get _field => widget.overCamera ? AppColors.brandWhite.withValues(alpha: 0.12) : context.surfaceMid;

  List<String> get _groups => [
        _fav,
        _recent,
        for (final g in widget.leadingGroups) g.name,
        _allName,
        ...OneovaFilterLibrary.categories,
      ];

  List<FilterItem> _libItems(Iterable<OneovaFilter> list) => [for (final f in list) FilterItem(f.id, f.name, f.look)];

  List<FilterItem> get _items {
    final q = _search.text.trim();
    if (q.isNotEmpty) {
      final lead = [
        for (final g in widget.leadingGroups)
          for (final i in g.items)
            if (i.name.toLowerCase().contains(q.toLowerCase())) i,
      ];
      return [...lead, ..._libItems(OneovaFilterLibrary.search(q))];
    }
    switch (_group) {
      case _fav:
        return [for (final id in _prefs.favourites) filterItemFor(id)];
      case _recent:
        return [for (final id in _prefs.recent) filterItemFor(id)];
      case _allName:
        return _libItems(OneovaFilterLibrary.all);
    }
    for (final g in widget.leadingGroups) {
      if (g.name == _group) return g.items;
    }
    return _libItems(OneovaFilterLibrary.inCategory(_group));
  }

  void _pick(FilterItem item) {
    HapticFeedback.selectionClick();
    widget.onPick(item.id);
    _prefs.markUsed(item.id);
  }

  void _hold(String? id) {
    if (_holding == id) return;
    setState(() => _holding = id);
    widget.onPreview?.call(id);
    if (id != null) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final selected = widget.selectedId;
    final hold = _holding == null ? null : filterItemFor(_holding!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hold != null && hold.look != null) _referenceCard(hold),
        _topRow(selected),
        if (!_searching) _groupTabs(),
        SizedBox(
          height: 92,
          child: items.isEmpty
              ? Center(
                  child: Text(
                    _search.text.isNotEmpty
                        ? 'No filters match "${_search.text.trim()}"'
                        : _group == _fav
                            ? 'Tap the star to keep a filter here'
                            : 'Filters you use show up here',
                    style: GoogleFonts.inter(color: _muted, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: items.length + 1,
                  itemBuilder: (context, i) {
                    final item = i == 0 ? FilterItem.none : items[i - 1];
                    return _tile(item, selected == item.id);
                  },
                ),
        ),
        if (selected != 'none')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text('Intensity', style: GoogleFonts.inter(color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.5,
                      activeTrackColor: AppColors.brandBlue,
                      inactiveTrackColor: widget.overCamera ? AppColors.brandWhite.withValues(alpha: 0.25) : context.border,
                      thumbColor: AppColors.brandWhite,
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8, elevation: 2),
                    ),
                    child: Slider(
                      value: widget.intensity.clamp(0.0, 1.0),
                      onChanged: widget.onIntensity,
                      onChangeEnd: widget.onIntensityEnd,
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text('${(widget.intensity * 100).round()}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(color: _fg, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _topRow(String selected) {
    final fav = selected != 'none' && _prefs.isFavourite(selected);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _search,
                onTap: () => setState(() => _searching = true),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => setState(() => _searching = _search.text.isNotEmpty),
                style: GoogleFonts.inter(color: _fg, fontSize: 13),
                cursorColor: AppColors.brandBlue,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _field,
                  hintText: 'Search ${OneovaFilterLibrary.all.length} filters',
                  hintStyle: GoogleFonts.inter(color: _muted, fontSize: 12.5),
                  prefixIcon: Icon(Icons.search_rounded, color: _muted, size: 18),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  suffixIcon: _search.text.isEmpty && !_searching
                      ? null
                      : GestureDetector(
                          onTap: () {
                            _search.clear();
                            FocusScope.of(context).unfocus();
                            setState(() => _searching = false);
                          },
                          child: Icon(Icons.close_rounded, color: _muted, size: 18),
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          if (selected != 'none')
            IconButton(
              tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
              onPressed: () {
                HapticFeedback.selectionClick();
                _prefs.toggleFavourite(selected);
              },
              icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded, color: fav ? AppColors.brandPink : _fg, size: 22),
            ),
        ],
      ),
    );
  }

  Widget _groupTabs() => SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final g in _groups)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _group = g);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (g == _fav) ...[
                        Icon(Icons.star_rounded, size: 14, color: g == _group ? AppColors.brandPink : _muted),
                        const SizedBox(width: 3),
                      ],
                      Text(g,
                          style: GoogleFonts.inter(
                            color: g == _group ? _fg : _muted,
                            fontSize: 12.5,
                            fontWeight: g == _group ? FontWeight.w800 : FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _thumb() {
    final t = widget.thumbnail;
    if (t != null) return Image(image: t, fit: BoxFit.cover, gaplessPlayback: true);
    final r = _reference;
    if (r == null) return ColoredBox(color: _field);
    return RawImage(image: r, fit: BoxFit.cover);
  }

  Widget _tile(FilterItem item, bool selected) {
    Widget img = _thumb();
    if (item.look != null) img = StudioLookFilter(look: item.look, child: img);
    final fav = item.id != 'none' && _prefs.isFavourite(item.id);
    return MouseRegion(
      onEnter: (_) => item.look == null ? null : _hold(item.id),
      onExit: (_) => _hold(null),
      child: GestureDetector(
        onTap: () => _pick(item),
        onLongPressStart: item.look == null ? null : (_) => _hold(item.id),
        onLongPressEnd: (_) => _hold(null),
        onLongPressCancel: () => _hold(null),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 62,
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: selected ? AppColors.brandBlue : (widget.overCamera ? AppColors.brandWhite.withValues(alpha: 0.2) : context.border),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      img,
                      if (item.look == null) ...[
                        ColoredBox(color: AppColors.brandBlack.withValues(alpha: 0.45)),
                        const Icon(Icons.block_rounded, color: AppColors.brandWhite, size: 22),
                      ],
                      if (fav)
                        const Positioned(
                          top: 2,
                          right: 2,
                          child: Icon(Icons.star_rounded, size: 12, color: AppColors.brandPink),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: selected ? AppColors.brandBlue : _muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Before / after of the held filter on the reference scene.
  Widget _referenceCard(FilterItem item) {
    final r = _reference;
    Widget base = widget.thumbnail != null
        ? Image(image: widget.thumbnail!, fit: BoxFit.cover, gaplessPlayback: true)
        : (r == null ? ColoredBox(color: _field) : RawImage(image: r, fit: BoxFit.cover));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brandBlue, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(child: Stack(fit: StackFit.expand, children: [base, _caption('Before')])),
            const SizedBox(width: 1.5),
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                StudioLookFilter(look: item.look, child: base),
                _caption(item.name),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caption(String text) => Positioned(
        left: 6,
        bottom: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.brandBlack.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(text, style: GoogleFonts.inter(color: AppColors.brandWhite, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      );
}
