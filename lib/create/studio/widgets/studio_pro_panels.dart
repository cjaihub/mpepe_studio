import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/studio_project.dart';
import '../services/studio_captions.dart';
import '../services/studio_effects.dart';
import '../services/studio_looks.dart';
import '../services/studio_media.dart';
import '../services/studio_text_templates.dart';
import 'studio_panels.dart';
import 'studio_text_widgets.dart';
import 'studio_ui.dart';

/// Oneova Looks for one clip (GPU graded, baked into the export).
class StudioLooksPanel extends StatefulWidget {
  final StudioClip clip;
  final ValueChanged<StudioClip> onLive;
  final VoidCallback onCommit;
  final VoidCallback onApplyAll;
  final VoidCallback onDone;

  const StudioLooksPanel({
    super.key,
    required this.clip,
    required this.onLive,
    required this.onCommit,
    required this.onApplyAll,
    required this.onDone,
  });

  @override
  State<StudioLooksPanel> createState() => _StudioLooksPanelState();
}

class _StudioLooksPanelState extends State<StudioLooksPanel> {
  late String _group = widget.clip.lookId == 'none' ? StudioLooks.groups.first : StudioLooks.byId(widget.clip.lookId).group;

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final items = StudioLooks.presets.where((l) => l.group == _group || l.id == 'none').toList();
    return StudioPanel(
      title: 'Looks',
      onDone: widget.onDone,
      action: StudioTextAction(icon: Icons.layers_outlined, label: 'Apply to all', onTap: widget.onApplyAll),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupTabs(groups: StudioLooks.groups, selected: _group, onPick: (g) => setState(() => _group = g)),
          SizedBox(
            height: 96,
            child: FutureBuilder<List<String>>(
              future: StudioMedia.thumbnails(clip),
              builder: (context, snap) {
                final thumbs = snap.data ?? const <String>[];
                final thumb = thumbs.isEmpty ? null : thumbs[thumbs.length ~/ 2];
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final l in items)
                      _LookTile(
                        look: l,
                        thumb: thumb,
                        selected: clip.lookId == l.id,
                        onTap: () {
                          widget.onLive(clip.copyWith(lookId: l.id, lookIntensity: 1));
                          widget.onCommit();
                        },
                      ),
                  ],
                );
              },
            ),
          ),
          if (clip.lookId != 'none')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StudioSliderRow(
                label: 'Intensity',
                value: clip.lookIntensity * 100,
                min: 0,
                max: 100,
                format: (v) => '${v.round()}',
                onChanged: (v) => widget.onLive(clip.copyWith(lookIntensity: v / 100)),
                onChangeEnd: (_) => widget.onCommit(),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _LookTile extends StatelessWidget {
  final StudioLookDef look;
  final String? thumb;
  final bool selected;
  final VoidCallback onTap;
  const _LookTile({required this.look, required this.thumb, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget img = thumb == null
        ? ColoredBox(color: context.surfaceMid)
        : Image.file(File(thumb!), fit: BoxFit.cover, cacheHeight: 160, gaplessPlayback: true);
    if (look.id != 'none') img = StudioLookFilter(look: look.look, child: img);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: selected ? AppColors.brandBlue : context.border, width: selected ? 2 : 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: look.id == 'none'
                  ? Stack(fit: StackFit.expand, children: [
                      img,
                      ColoredBox(color: AppColors.brandBlack.withValues(alpha: 0.45)),
                      const Icon(Icons.block_rounded, color: AppColors.brandWhite, size: 22),
                    ])
                  : img,
            ),
            const SizedBox(height: 4),
            Text(look.name,
                style: GoogleFonts.inter(
                  color: selected ? AppColors.brandBlue : context.textSecondary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

class _GroupTabs extends StatelessWidget {
  final List<String> groups;
  final String selected;
  final ValueChanged<String> onPick;
  const _GroupTabs({required this.groups, required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          children: [
            for (final g in groups)
              GestureDetector(
                onTap: () => onPick(g),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  child: Text(g,
                      style: GoogleFonts.inter(
                        color: g == selected ? context.textPrimary : context.textMuted,
                        fontSize: 13,
                        fontWeight: g == selected ? FontWeight.w800 : FontWeight.w600,
                      )),
                ),
              ),
          ],
        ),
      );
}

/// Timeline effects: add at the playhead, pick the selected one's strength.
class StudioEffectsPanel extends StatefulWidget {
  final StudioEffect? selected;
  final ValueChanged<String> onAdd;
  final ValueChanged<StudioEffect> onLive;
  final VoidCallback onCommit;
  final VoidCallback? onDelete;
  final VoidCallback? onStartHere;
  final VoidCallback? onEndHere;
  final VoidCallback onDone;

  const StudioEffectsPanel({
    super.key,
    required this.selected,
    required this.onAdd,
    required this.onLive,
    required this.onCommit,
    required this.onDone,
    this.onDelete,
    this.onStartHere,
    this.onEndHere,
  });

  @override
  State<StudioEffectsPanel> createState() => _StudioEffectsPanelState();
}

class _StudioEffectsPanelState extends State<StudioEffectsPanel> {
  late String _group = widget.selected == null ? StudioEffects.groups.first : (StudioEffects.byId(widget.selected!.effectId)?.group ?? StudioEffects.groups.first);

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final items = StudioEffects.all.where((e) => e.group == _group).toList();
    return StudioPanel(
      title: sel == null ? 'Effects' : (StudioEffects.byId(sel.effectId)?.name ?? 'Effect'),
      onDone: widget.onDone,
      action: sel == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.onStartHere != null) StudioTextAction(icon: Icons.start_rounded, label: 'Start', onTap: widget.onStartHere!),
              if (widget.onEndHere != null) StudioTextAction(icon: Icons.keyboard_tab_rounded, label: 'End', onTap: widget.onEndHere!),
              if (widget.onDelete != null) StudioTextAction(icon: Icons.delete_outline_rounded, label: 'Delete', onTap: widget.onDelete!),
            ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupTabs(groups: StudioEffects.groups, selected: _group, onPick: (g) => setState(() => _group = g)),
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                for (final e in items)
                  GestureDetector(
                    onTap: () {
                      if (sel != null) {
                        widget.onLive(sel.copyWith(effectId: e.id, amount: e.amount));
                        widget.onCommit();
                      } else {
                        widget.onAdd(e.id);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sel?.effectId == e.id ? AppColors.brandBlue : context.surfaceMid,
                              border: Border.all(color: sel?.effectId == e.id ? AppColors.brandBlue : context.border),
                            ),
                            child: Icon(e.icon, size: 21, color: sel?.effectId == e.id ? AppColors.brandWhite : context.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(e.name,
                              style: GoogleFonts.inter(fontSize: 10.5, color: context.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (sel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: StudioSliderRow(
                label: 'Strength',
                value: sel.amount * 100,
                min: 0,
                max: 100,
                format: (v) => '${v.round()}',
                onChanged: (v) => widget.onLive(sel.copyWith(amount: v / 100)),
                onChangeEnd: (_) => widget.onCommit(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Text('Tap an effect to add it at the playhead. It shows in the export exactly as here.',
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

/// Options picked in the auto captions sheet.
class StudioAutoCaptionChoice {
  final String language;
  final String templateId;
  final bool replaceExisting;
  const StudioAutoCaptionChoice(this.language, this.templateId, this.replaceExisting);
}

/// Language + caption style for auto captions.
Future<StudioAutoCaptionChoice?> showStudioAutoCaptionSheet(BuildContext context, {required bool hasCaptions}) {
  return showModalBottomSheet<StudioAutoCaptionChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _AutoCaptionSheet(hasCaptions: hasCaptions),
  );
}

class _AutoCaptionSheet extends StatefulWidget {
  final bool hasCaptions;
  const _AutoCaptionSheet({required this.hasCaptions});

  @override
  State<_AutoCaptionSheet> createState() => _AutoCaptionSheetState();
}

class _AutoCaptionSheetState extends State<_AutoCaptionSheet> {
  StudioLanguage _lang = studioAutoLanguage;
  String _tpl = 'ca_karaoke';
  bool _replace = true;

  @override
  Widget build(BuildContext context) {
    final templates = StudioTextTemplates.inCategory('Captions');
    final tpl = StudioTextTemplates.byId(_tpl)!;
    final sample = tpl.applyTo(StudioText.create(text: 'your words show up like this', startMs: 0, endMs: 2400, isCaption: true, words: const [
      StudioWord('your', 0, 400),
      StudioWord('words', 400, 800),
      StudioWord('show', 800, 1200),
      StudioWord('up', 1200, 1500),
      StudioWord('like', 1500, 1900),
      StudioWord('this', 1900, 2400),
    ]));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StudioSheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
            child: Row(
              children: [
                Text('Auto captions', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                StudioPrimaryButton(label: 'Generate', onTap: () => Navigator.pop(context, StudioAutoCaptionChoice(_lang.code, _tpl, _replace))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Oneova listens to the original sound, finds the language, and writes timed captions in it, word by word. Any language works, local ones too.',
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12)),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: AppColors.brandBlack, borderRadius: BorderRadius.circular(AppRadius.md)),
            clipBehavior: Clip.antiAlias,
            child: StudioTextLoopPreview(text: sample, height: 90),
          ),
          const SizedBox(height: 10),
          _title(context, 'Style'),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in templates)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _pill(context, t.name, _tpl == t.id, () => setState(() => _tpl = t.id)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _title(context, 'Spoken language'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(_lang.code == 'auto' ? Icons.travel_explore_rounded : Icons.language_rounded, color: AppColors.brandBlue),
                  title: Text(_lang.name, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    _lang.code == 'auto' ? 'Works for any language, including mixed speech' : (_lang.region.isEmpty ? 'Typed language' : _lang.region),
                    style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11.5),
                  ),
                  trailing: Text('Change', style: GoogleFonts.inter(color: AppColors.brandBlue, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  onTap: () async {
                    final l = await showStudioLanguagePicker(context, title: 'Spoken language', allowAuto: true);
                    if (l != null) setState(() => _lang = l);
                  },
                ),
                if (_lang.limited)
                  _LimitedNote(
                    text: '${_lang.name} isn\'t fully supported yet. Oneova will tell you if it can\'t caption it reliably, '
                        'and you should check the words before posting.',
                  ),
                if (widget.hasCaptions)
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    value: _replace,
                    activeTrackColor: AppColors.brandBlue,
                    title: Text('Replace current captions', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    onChanged: (v) => setState(() => _replace = v),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Detect automatically" entry of the language picker.
const studioAutoLanguage = StudioLanguage('auto', 'Detect automatically', '');

/// Searchable worldwide language list. Users can also type a language that
/// isn't listed. Languages with fewer resources are marked.
Future<StudioLanguage?> showStudioLanguagePicker(BuildContext context, {String title = 'Translate to', bool allowAuto = false}) {
  return showModalBottomSheet<StudioLanguage>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) => _LanguagePicker(title: title, allowAuto: allowAuto),
  );
}

class _LanguagePicker extends StatefulWidget {
  final String title;
  final bool allowAuto;
  const _LanguagePicker({required this.title, required this.allowAuto});

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = StudioCaptionService.languages
        .where((l) => q.isEmpty || l.name.toLowerCase().contains(q) || l.code.toLowerCase() == q)
        .toList();
    final regions = <String>{for (final l in list) l.region}.toList();
    final exact = list.any((l) => l.name.toLowerCase() == q);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StudioSheetHandle(),
          _title(context, widget.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search ${StudioCaptionService.languages.length}+ languages or type any language',
                hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 12.5),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                if (widget.allowAuto && q.isEmpty)
                  _row(context, studioAutoLanguage, subtitle: 'Any language, including local ones and mixed speech'),
                if (q.length >= 2 && !exact)
                  _row(context, StudioLanguage.custom(_q.text), subtitle: 'Use this language (not in the list, may be less accurate)', icon: Icons.edit_rounded),
                for (final r in regions) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(r, style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                  for (final l in list.where((l) => l.region == r)) _row(context, l),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, StudioLanguage l, {String? subtitle, IconData? icon}) => ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: icon != null || l.code == 'auto' ? Icon(icon ?? Icons.travel_explore_rounded, color: AppColors.brandBlue, size: 20) : null,
        title: Text(l.name, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11.5)),
        trailing: l.limited && subtitle == null
            ? Text('may be less accurate', style: GoogleFonts.inter(color: context.textMuted, fontSize: 10.5, fontWeight: FontWeight.w600))
            : null,
        onTap: () => Navigator.pop(context, l),
      );
}

class _LimitedNote extends StatelessWidget {
  final String text;
  const _LimitedNote({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.brandPink.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.brandPink),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 11.5, height: 1.35))),
          ],
        ),
      );
}

Widget _title(BuildContext context, String s) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(s, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
    );

Widget _pill(BuildContext context, String label, bool on, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: on ? AppColors.brandBlue : context.border),
        ),
        child: Text(label,
            style: GoogleFonts.inter(color: on ? AppColors.brandWhite : context.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );

/// Face & skin retouch for one clip. Skin tools work on any skin; eyes,
/// teeth and reshape follow the faces found in the clip. Baked into exports.
class StudioRetouchPanel extends StatefulWidget {
  final StudioClip clip;

  /// Faces found in the clip (null while still looking).
  final bool? facesFound;
  final ValueChanged<StudioClip> onLive;
  final VoidCallback onCommit;
  final VoidCallback onApplyAll;
  final VoidCallback onDone;

  const StudioRetouchPanel({
    super.key,
    required this.clip,
    required this.facesFound,
    required this.onLive,
    required this.onCommit,
    required this.onApplyAll,
    required this.onDone,
  });

  @override
  State<StudioRetouchPanel> createState() => _StudioRetouchPanelState();
}

class _StudioRetouchPanelState extends State<StudioRetouchPanel> {
  String _key = 'smooth';

  static const _meta = <String, (String, IconData)>{
    'smooth': ('Smooth', Icons.face_retouching_natural_rounded),
    'even': ('Even tone', Icons.blur_on_rounded),
    'bright': ('Glow', Icons.wb_sunny_outlined),
    'warm': ('Skin warmth', Icons.thermostat_rounded),
    'eyes': ('Bright eyes', Icons.visibility_outlined),
    'teeth': ('Whiten teeth', Icons.sentiment_very_satisfied_outlined),
    'slim': ('Slim face', Icons.face_outlined),
    'bigEyes': ('Bigger eyes', Icons.remove_red_eye_outlined),
    'nose': ('Slim nose', Icons.straighten_rounded),
    'chin': ('Chin', Icons.expand_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final c = widget.clip;
    final r = c.retouch;
    final signed = StudioRetouch.signedKeys.contains(_key);
    final faceTool = StudioRetouch.faceKeys.contains(_key);
    final status = switch (widget.facesFound) {
      null => 'Finding faces…',
      true => 'Face tracked',
      false => 'No face found: skin tools still work',
    };
    return StudioPanel(
      title: 'Retouch',
      onDone: widget.onDone,
      action: Row(mainAxisSize: MainAxisSize.min, children: [
        StudioTextAction(
          icon: Icons.refresh_rounded,
          label: 'Reset',
          onTap: () {
            widget.onLive(c.copyWith(retouch: const StudioRetouch()));
            widget.onCommit();
          },
        ),
        StudioTextAction(icon: Icons.layers_outlined, label: 'All clips', onTap: widget.onApplyAll),
      ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 82,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                for (final e in _meta.entries)
                  GestureDetector(
                    onTap: () => setState(() => _key = e.key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.surfaceMid,
                              border: Border.all(color: e.key == _key ? AppColors.brandBlue : context.border, width: e.key == _key ? 2 : 1),
                            ),
                            child: Icon(e.value.$2, size: 20, color: r.valueOf(e.key) != 0 ? AppColors.brandBlue : context.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(e.value.$1,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: e.key == _key ? context.textPrimary : context.textSecondary,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: StudioSliderRow(
              label: _meta[_key]!.$1,
              value: r.valueOf(_key) * 100,
              min: signed ? -100 : 0,
              max: 100,
              format: (v) => '${v.round()}',
              onChanged: (v) => widget.onLive(c.copyWith(retouch: r.withValue(_key, v / 100))),
              onChangeEnd: (_) => widget.onCommit(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Icon(widget.facesFound == true ? Icons.check_circle_rounded : Icons.face_rounded,
                    size: 14, color: widget.facesFound == true ? AppColors.brandBlue : context.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    faceTool && widget.facesFound == false ? 'This tool needs a face in the clip.' : status,
                    style: GoogleFonts.inter(color: context.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
