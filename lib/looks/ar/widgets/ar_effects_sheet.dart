import 'package:path_provider/path_provider.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/oneova_file_picker.dart';
import '../controllers/live_ar_controller.dart';
import '../models/ar_effect.dart';
import '../services/ar_effect_repository.dart';
import '../builtin/builtin_effects.dart';
import 'ar_makeup_studio_sheet.dart';

/// Opens the AR effects picker over the camera. The sheet stays short so the
/// live preview keeps showing what each effect does.
Future<void> showArEffectsSheet(BuildContext context, {Future<String?> Function()? captureStill}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    builder: (_) => ArEffectsSheet(captureStill: captureStill),
  );
}

class ArEffectsSheet extends ConsumerStatefulWidget {
  /// Passed on to Makeup Studio for "Match my face".
  final Future<String?> Function()? captureStill;

  const ArEffectsSheet({super.key, this.captureStill});

  @override
  ConsumerState<ArEffectsSheet> createState() => _ArEffectsSheetState();
}

enum _Tab { explore, favorites, mine, create }

class _ArEffectsSheetState extends ConsumerState<ArEffectsSheet> {
  _Tab _tab = _Tab.explore;
  ArEffectQuery _query = const ArEffectQuery();
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = _query.copyWith(search: v.trim()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(liveArControllerProvider);
    ref.listen(liveArControllerProvider.select((s) => s.error), (_, err) {
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    });

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: context.border, width: 1),
        ),
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverToBoxAdapter(child: _header(context, ar)),
            SliverToBoxAdapter(child: _backgroundRow(context, ar)),
            SliverToBoxAdapter(child: _tabs(context)),
            ..._body(context, ar),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, LiveArState ar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Effects',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (ar.active.isNotEmpty)
                _pill(context, '${ar.active.length} on', AppColors.brandPink),
              const Spacer(),
              if (ar.hasAnything)
                TextButton(
                  onPressed: () => ref.read(liveArControllerProvider.notifier).clearAll(),
                  child: Text('Clear all', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              IconButton(
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color),
        ),
      );

  // ── Background tools ────────────────────────────────────────────────────

  Widget _backgroundRow(BuildContext context, LiveArState ar) {
    final ctrl = ref.read(liveArControllerProvider.notifier);
    final blur = ar.backgroundMode == ArBackgroundMode.blur;
    final replace = ar.backgroundMode == ArBackgroundMode.replace;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _toolChip(context, Icons.groups_rounded, 'Per person', ar.effectPerPerson,
                    () => ctrl.setEffectPerPerson(!ar.effectPerPerson)),
                _toolChip(context, Icons.blur_on_rounded, 'Blur', blur, () => ctrl.setBlur(!blur)),
                _toolChip(context, Icons.wallpaper_rounded, replace && !ar.addYourself ? (ar.backgroundLabel ?? 'Scene') : 'Background',
                    replace && !ar.addYourself, () => _pickBackground(addYourself: false)),
                _toolChip(context, Icons.palette_outlined, ar.backgroundLabel == 'Colour' ? 'Colour' : 'Colour',
                    ar.backgroundLabel == 'Colour', () => _pickColour(ctrl)),
                _toolChip(context, Icons.movie_outlined, 'Video', ar.backgroundVideoPath != null, _pickVideo),
                _toolChip(context, Icons.layers_outlined, 'Transparent', ar.transparentBackground,
                    () => ar.transparentBackground ? ctrl.clearBackground() : ctrl.setTransparentBackground()),
                _toolChip(context, Icons.person_add_alt_1_rounded, 'Add yourself', ar.addYourself,
                    () => replace ? ctrl.setAddYourself(!ar.addYourself) : _pickBackground(addYourself: true)),
                if (ar.backgroundMode != ArBackgroundMode.none)
                  _toolChip(context, Icons.layers_clear_outlined, 'Off', false, ctrl.clearBackground),
              ],
            ),
          ),
          if (blur)
            Row(
              children: [
                Text('Strength', style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
                Expanded(
                  child: Slider(
                    value: ar.blurSigma,
                    min: 2,
                    max: 40,
                    activeColor: AppColors.brandBlue,
                    onChanged: ctrl.setBlurSigma,
                  ),
                ),
              ],
            ),
          if (ar.effectPerPerson)
            Text(
              'Up to 3 people: the first person wears the first face effect you picked, the next person the next one.',
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
            ),
          if (ar.transparentBackground)
            Text(
              'Photos save as transparent PNGs. Videos record on key green so the background can be removed in any editor.',
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
            ),
          if (ar.addYourself)
            Text(
              'Pinch and drag on the preview to place yourself in the scene.',
              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
            ),
        ],
      ),
    );
  }

  static const _bgColours = <Color>[
    Color(0xFFFFFFFF), Color(0xFF111114), AppColors.brandBlue, AppColors.brandPink, Color(0xFF00B140),
    Color(0xFFF4C430), Color(0xFF7B2CBF), Color(0xFF0FA3B1), Color(0xFFF77F00), Color(0xFFEDE0D4),
  ];

  Future<void> _pickColour(LiveArController ctrl) async {
    final c = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: context.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final col in _bgColours)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, col),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: col, shape: BoxShape.circle, border: Border.all(color: ctx.border)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (c != null) await ctrl.setBackgroundColor(c);
  }

  /// A video from the phone, looping behind you (first frame for photos).
  Future<void> _pickVideo() async {
    final res = await FilePicker.pickFile(type: FileType.video);
    final path = res?.path;
    if (path == null) return;
    ui.Image? still;
    try {
      final dir = await getTemporaryDirectory();
      final frame = await OneovaMediaEngine.frame(path, ms: 0, out: '${dir.path}/bgv_${DateTime.now().millisecondsSinceEpoch}.jpg', maxSide: 1280);
      final codec = await ui.instantiateImageCodec(await File(frame).readAsBytes());
      still = (await codec.getNextFrame()).image;
    } catch (_) {}
    await ref.read(liveArControllerProvider.notifier).setBackgroundVideo(path, firstFrame: still);
  }

  Future<void> _pickBackground({required bool addYourself}) async {
    final file = await OneovaFilePicker.pickSingleFile(
      context,
      mode: OneovaFilePickerMode.photos,
      title: addYourself ? 'Pick a scene to step into' : 'Pick a background',
      actionLabel: 'Use photo',
    );
    if (file == null) return;
    await ref.read(liveArControllerProvider.notifier).setBackgroundFile(file, addYourself: addYourself);
  }

  Widget _toolChip(BuildContext context, IconData icon, String label, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? AppColors.brandBlue : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: on ? AppColors.brandBlue : context.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: on ? Colors.white : context.textPrimary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: on ? Colors.white : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tabs ────────────────────────────────────────────────────────────────

  Widget _tabs(BuildContext context) {
    const labels = {
      _Tab.explore: 'Explore',
      _Tab.favorites: 'Favorites',
      _Tab.mine: 'Mine',
      _Tab.create: 'Create with AI',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in _Tab.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(labels[t]!),
                  avatar: t == _Tab.create
                      ? Icon(Icons.auto_awesome_rounded,
                          size: 15, color: _tab == t ? Colors.white : AppColors.brandPink)
                      : null,
                  selected: _tab == t,
                  showCheckmark: false,
                  selectedColor: AppColors.brandBlue,
                  backgroundColor: context.surfaceMid,
                  side: BorderSide(color: _tab == t ? AppColors.brandBlue : context.border),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _tab == t ? Colors.white : context.textPrimary,
                  ),
                  onSelected: (_) => setState(() => _tab = t),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, LiveArState ar) {
    switch (_tab) {
      case _Tab.explore:
        final builtIn = BuiltInEffects.filter(
          search: _query.search,
          category: _query.category,
          audience: _query.audience,
        );
        return [
          SliverToBoxAdapter(child: _filters(context)),
          if (_query.category == null || _query.category == ArEffectCategory.makeup || _query.category == ArEffectCategory.eyes)
            SliverToBoxAdapter(child: _studioCard(context)),
          SliverToBoxAdapter(child: _section(context, 'Built in', '${builtIn.length} · work offline')),
          _grid(context, ar, AsyncValue.data(builtIn), empty: 'No built-in effects match.'),
          SliverToBoxAdapter(child: _section(context, 'Community', 'made with AI or uploaded')),
          _grid(context, ar, ref.watch(arEffectCatalogProvider(_query)),
              empty: _query.search.isEmpty && _query.category == null && _query.audience == null
                  ? 'No community effects yet. Create the first one with AI.'
                  : 'No community effects match. Try another word or create it with AI.'),
        ];
      case _Tab.favorites:
        return [
          _grid(context, ar, ref.watch(arFavoriteEffectsProvider),
              empty: 'Tap the heart on an effect to keep it here.'),
        ];
      case _Tab.mine:
        return [
          _grid(context, ar, ref.watch(arMyEffectsProvider),
              empty: 'Effects you create or upload show up here.'),
        ];
      case _Tab.create:
        return [
          SliverToBoxAdapter(
            child: _ArCreatePanel(
              initialPrompt: _query.search,
              onCreated: () => setState(() => _tab = _Tab.mine),
            ),
          ),
        ];
    }
  }

  Widget _section(BuildContext context, String title, String meta) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(width: 8),
            Text(meta, style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
          ],
        ),
      );

  Widget _studioCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => showArMakeupStudio(context, captureStill: widget.captureStill),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.brandBlue, shape: BoxShape.circle),
                child: const Icon(Icons.brush_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Makeup Studio',
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Lips, eyes, liner, brows, contour, smooth skin. AI builds a look from words or your face.',
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary, height: 1.3)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.brandBlue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final input = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: context.border, width: 1),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search glasses, beard, neon eyes…',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: context.surfaceMid,
              enabledBorder: input,
              focusedBorder: input.copyWith(borderSide: const BorderSide(color: AppColors.brandBlue)),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final a in ArAudience.values)
                  _filterChip(
                    context,
                    a.label,
                    (_query.audience ?? ArAudience.unisex) == a,
                    () => setState(() => _query = _query.copyWith(audience: () => a == ArAudience.unisex ? null : a)),
                  ),
                Container(width: 1, height: 20, color: context.border, margin: const EdgeInsets.symmetric(horizontal: 6)),
                for (final s in ArEffectSort.values)
                  _filterChip(context, s.label, _query.sort == s, () => setState(() => _query = _query.copyWith(sort: s))),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(context, 'All', _query.category == null,
                    () => setState(() => _query = _query.copyWith(category: () => null))),
                for (final c in ArEffectCategory.values)
                  _filterChip(context, c.label, _query.category == c,
                      () => setState(() => _query = _query.copyWith(category: () => c)),
                      icon: c.icon),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(BuildContext context, String label, bool on, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.brandBlue.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: on ? AppColors.brandBlue : context.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: on ? AppColors.brandBlue : context.textSecondary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: on ? AppColors.brandBlue : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, LiveArState ar, AsyncValue<List<ArEffect>> async, {required String empty}) {
    final favIds = ref.watch(arFavoriteIdsProvider).value ?? const <String>[];
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load effects. ${e is Exception ? '' : e}',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
          ),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.face_retouching_natural, color: context.textMuted, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    empty,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _EffectTile(
                effect: list[i],
                active: ar.isActive(list[i].id),
                loading: ar.loading.contains(list[i].id),
                favorite: favIds.contains(list[i].id),
              ),
              childCount: list.length,
            ),
          ),
        );
      },
    );
  }
}

class _EffectTile extends ConsumerWidget {
  final ArEffect effect;
  final bool active;
  final bool loading;
  final bool favorite;

  const _EffectTile({
    required this.effect,
    required this.active,
    required this.loading,
    required this.favorite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = effect.thumbUrl;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(liveArControllerProvider.notifier).toggle(effect);
      },
      onLongPress: effect.attribution.isEmpty && effect.license.isEmpty ? null : () => _showCredit(context),
      child: Column(
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: active ? AppColors.brandBlue : context.border,
                  width: active ? 2 : 1,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: BuiltInEffects.byId(effect.id)?.hasArt == true
                        ? _BuiltInThumb(id: effect.id)
                        : thumb != null
                            ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.contain)
                            : effect.kind == ArEffectKind.vfx
                                ? _vfxThumb(effect.id)
                                : _makeupSwatch(effect.makeup),
                  ),
                  if (loading)
                    const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        try {
                          await ref.read(arEffectRepositoryProvider).setFavorite(effect.id, !favorite);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Sign in to save favorites.')),
                            );
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 15,
                          color: favorite ? AppColors.brandPink : context.textMuted,
                        ),
                      ),
                    ),
                  ),
                  if (effect.is3d)
                    Positioned(
                      left: 3,
                      bottom: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.brandBlue, borderRadius: BorderRadius.circular(4)),
                        child: Text('3D', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    )
                  else if (effect.kind == ArEffectKind.vfx)
                    Positioned(
                      left: 3,
                      bottom: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(4)),
                        child: Text('VFX', style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    )
                  else if (effect.source == 'ai')
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Icon(Icons.auto_awesome_rounded, size: 11, color: AppColors.brandPink),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            effect.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w500, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Credit for openly licensed models and art (long-press a tile).
  void _showCredit(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text(effect.name, style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: ctx.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (effect.attribution.isNotEmpty)
              Text(effect.attribution, style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary)),
            if (effect.license.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('License: ${effect.license}', style: GoogleFonts.inter(fontSize: 12, color: ctx.textMuted)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _makeupSwatch(ArMakeup m) {
    final colors = [
      if (m.lipOpacity > 0) m.lipColor,
      if (m.eyeOpacity > 0 || m.eyeGlow > 0) m.eyeColor,
      if (m.blushOpacity > 0) m.blushColor,
      if (m.linerOpacity > 0) m.linerColor,
      if (m.browOpacity > 0) m.browColor,
    ];
    if (colors.isEmpty) return const Icon(Icons.brush_outlined, color: AppColors.brandBlue);
    return Center(
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        alignment: WrapAlignment.center,
        children: [
          for (final c in colors)
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }

  Widget _vfxThumb(String id) {
    final icon = switch (id) {
      'builtin_vfx_neon_aura' => Icons.accessibility_new_rounded,
      'builtin_vfx_cyber_hud' => Icons.radar_rounded,
      'builtin_vfx_angel_glow' => Icons.flare_rounded,
      'builtin_vfx_soul_clone' => Icons.switch_account_rounded,
      'builtin_vfx_hand_sparks' => Icons.back_hand_rounded,
      _ => Icons.auto_fix_high_rounded,
    };
    return Center(
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppColors.brandBlue, AppColors.brandPink],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

/// "Type to create": describe an effect and the server builds it on Vertex AI,
/// then it is turned on live as soon as it exists. Users can also upload
/// their own transparent PNG.
class _ArCreatePanel extends ConsumerStatefulWidget {
  final String initialPrompt;
  final VoidCallback onCreated;

  const _ArCreatePanel({required this.initialPrompt, required this.onCreated});

  @override
  ConsumerState<_ArCreatePanel> createState() => _ArCreatePanelState();
}

class _ArCreatePanelState extends ConsumerState<_ArCreatePanel> {
  late final TextEditingController _prompt = TextEditingController(text: widget.initialPrompt);
  ArAudience _audience = ArAudience.unisex;
  bool _publish = true;
  bool _busy = false;
  String? _status;

  // Upload fields
  ArEffectCategory _uploadCategory = ArEffectCategory.glasses;
  ArAnchor _uploadAnchor = ArAnchor.eyes;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _prompt.text.trim();
    if (text.length < 3) {
      setState(() => _status = 'Describe the effect in a few words.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _status = 'Designing your effect…';
    });
    try {
      final repo = ref.read(arEffectRepositoryProvider);
      final id = await repo.generate(prompt: text, audience: _audience, publish: _publish);
      final effect = await repo.fetch(id);
      if (effect != null) {
        await ref.read(liveArControllerProvider.notifier).toggle(effect);
      }
      if (!mounted) return;
      setState(() => _status = 'Ready: "${effect?.name ?? 'effect'}" is on. Find it under Mine.');
      HapticFeedback.mediumImpact();
      widget.onCreated();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _status = e.message ?? 'Could not create that effect.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not create that effect. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final file = await OneovaFilePicker.pickSingleFile(
      context,
      mode: OneovaFilePickerMode.photos,
      allowedExtensions: const ['png'],
      title: 'Pick a transparent PNG',
      actionLabel: 'Use image',
    );
    if (file == null || !mounted) return;
    if (!file.path.toLowerCase().endsWith('.png')) {
      setState(() => _status = 'Use a PNG with a transparent background.');
      return;
    }
    final name = _prompt.text.trim().isEmpty ? 'My effect' : _prompt.text.trim();
    setState(() {
      _busy = true;
      _status = 'Uploading…';
    });
    try {
      final repo = ref.read(arEffectRepositoryProvider);
      final id = await repo.createFromUpload(
        file: File(file.path),
        name: name.length > 40 ? name.substring(0, 40) : name,
        category: _uploadCategory,
        anchor: _uploadAnchor,
        audience: _audience,
        publish: _publish,
      );
      final effect = await repo.fetch(id);
      if (effect != null) await ref.read(liveArControllerProvider.notifier).toggle(effect);
      if (!mounted) return;
      setState(() => _status = 'Uploaded and on.');
      widget.onCreated();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _status = e.message ?? 'Upload failed.');
    } catch (_) {
      if (mounted) setState(() => _status = 'Upload failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: context.border, width: 1),
    );
    final label = GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textSecondary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _prompt,
            enabled: !_busy,
            minLines: 2,
            maxLines: 3,
            maxLength: 200,
            style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'e.g. neon pink cat-eye glasses, gold crown, glowing blue eyes, '
                  'thick black beard, beach sunset background',
              hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: context.surfaceMid,
              enabledBorder: input,
              disabledBorder: input,
              focusedBorder: input.copyWith(borderSide: const BorderSide(color: AppColors.brandBlue)),
            ),
          ),
          Text('For', style: label),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final a in ArAudience.values)
                ChoiceChip(
                  label: Text(a.label),
                  selected: _audience == a,
                  showCheckmark: false,
                  selectedColor: AppColors.brandBlue,
                  backgroundColor: context.surfaceMid,
                  side: BorderSide(color: _audience == a ? AppColors.brandBlue : context.border),
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _audience == a ? Colors.white : context.textPrimary,
                  ),
                  onSelected: _busy ? null : (_) => setState(() => _audience = a),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _publish,
            activeTrackColor: AppColors.brandBlue,
            onChanged: _busy ? null : (v) => setState(() => _publish = v),
            title: Text('Share in the public catalog',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
            subtitle: Text('Others can find, use and favorite it.',
                style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
          ),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: _busy ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('Generate effect', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
            ),
          const SizedBox(height: 14),
          Divider(color: context.border, height: 1),
          const SizedBox(height: 12),
          Text('Or upload your own PNG (name it in the box above)', style: label),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ArEffectCategory>(
                  initialValue: _uploadCategory,
                  isDense: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Category',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: input,
                    border: input,
                  ),
                  items: [
                    for (final c in ArEffectCategory.values.where((c) => c != ArEffectCategory.makeup))
                      DropdownMenuItem(value: c, child: Text(c.label, style: GoogleFonts.inter(fontSize: 12.5))),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _uploadCategory = v ?? _uploadCategory),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<ArAnchor>(
                  initialValue: _uploadAnchor,
                  isDense: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Attach to',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: input,
                    border: input,
                  ),
                  items: [
                    for (final a in ArAnchor.values)
                      DropdownMenuItem(value: a, child: Text(a.label, style: GoogleFonts.inter(fontSize: 12.5))),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _uploadAnchor = v ?? _uploadAnchor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandBlue,
                side: const BorderSide(color: AppColors.brandBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: _busy ? null : _upload,
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: Text('Upload PNG effect', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picker tile art for a built-in effect, drawn on device.
class _BuiltInThumb extends StatelessWidget {
  final String id;

  const _BuiltInThumb({required this.id});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: BuiltInEffects.thumb(id),
      builder: (context, snap) => snap.hasData
          ? RawImage(image: snap.data, fit: BoxFit.contain)
          : const SizedBox.shrink(),
    );
  }
}
