import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../create/studio/services/studio_agent.dart';
import '../../create/studio/services/studio_effects.dart';
import '../../create/studio/services/studio_looks.dart';
import '../../create/studio/services/studio_text_templates.dart';
import '../core/ova_tool_result.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d, [List<String>? e]) => {'type': 'string', 'description': d, 'enum': ?e};
Map<String, dynamic> _n(String d) => {'type': 'number', 'description': d};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};
Map<String, dynamic> _b(String d) => {'type': 'boolean', 'description': d};

/// Ova's hands on the Studio editor: create projects from the gallery, edit
/// (Looks, filters, adjust, face & skin retouch, speed, trim, text templates,
/// effects), auto captions in any language, translate, export to the gallery
/// and post a story. Runs headless through [StudioAgent], so it works from
/// voice while Oneova is in the background.
class OvaStudioTools {
  final Ref ref;
  OvaStudioTools(this.ref);

  StudioAgent get _agent => ref.read(studioAgentProvider);

  static const names = {
    'studio_projects',
    'studio_new_project',
    'studio_edit',
    'studio_auto_captions',
    'studio_translate_captions',
    'studio_export',
    'studio_post_story',
  };

  static const _project = 'Project id from studio_projects, or "latest" (default) for the newest';

  List<OvaToolSpec> get specs => [
        const OvaToolSpec('studio_projects', 'List the user\'s Studio video/photo editing projects (newest first) with ids and what is in them.'),
        OvaToolSpec(
          'studio_new_project',
          'Start a Studio project from the newest gallery media (no screen needed).',
          properties: {
            'kind': _s('video or photo', ['video', 'photo']),
            'count': _i('How many of the newest videos to use, 1-10 (default 1)'),
            'format': _s('Canvas: short = 9:16 Shorts/Reels, full = 16:9, square, original', ['short', 'full', 'square', 'original']),
            'title': _s('Project name'),
          },
        ),
        OvaToolSpec(
          'studio_edit',
          'Edit a Studio project; every edit is baked into the export. Actions:\n'
              '- look: name = ${StudioLooks.presets.map((l) => l.id).join('|')}; value = strength 0-1\n'
              '- filter: name = a filter id; value = strength 0-1\n'
              '- adjust: name = brightness|contrast|saturation|exposure|warmth|tint|fade|highlights|shadows|whites|blacks|vibrance|sharpen|grain|vignette; value -1..1\n'
              '- retouch (face & skin): name = smooth|even|bright|warm|eyes|teeth|slim|bigEyes|nose|chin; value 0..1 (warm, chin -1..1)\n'
              '- beauty: one-tap natural retouch, value = strength 0-1\n'
              '- speed (value 0.25-4), volume (value 0-2), mute, unmute, fill (value 1 fill / 0 fit)\n'
              '- trim: clip number, start_s and end_s in the clip\'s source seconds\n'
              '- aspect: name = short|full|square|4:5|3:4|original\n'
              '- add_text: text, optional name = text template (id or style word like neon, bold, elegant, karaoke), start_s, end_s, value = vertical position -0.9 (top) .. 0.9 (bottom)\n'
              '- caption_style: name = a caption style (${StudioTextTemplates.inCategory('Captions').map((t) => t.id).join('|')})\n'
              '- add_effect: name = ${StudioEffects.all.map((e) => e.id).join('|')}; start_s, end_s; value = strength 0-1\n'
              '- voice_clean: value 0-1 cleans speech (rumble, hiss, levels); reverse: clip number, plays it backwards; beat_sync: cuts clips to the music beat; stabilize: value 0-1 smooths camera shake\n'
              '- add_overlay: picture-in-picture of the newest gallery video (name = photo for a photo), start_s, value = size 0.08-1.5; clear_overlays\n'
              '- clear_effects, clear_text, rename (text)\n'
              'Omit clip to apply to every clip.',
          properties: {
            'project': _s(_project),
            'action': _s('What to change', StudioAgent.editActions),
            'name': _s('Look / filter / key / template / effect / aspect, depending on action'),
            'value': _n('Amount, depending on action'),
            'clip': _i('Clip number from 1; omit for all clips'),
            'start_s': _n('Start time in seconds'),
            'end_s': _n('End time in seconds'),
            'text': _s('Text for add_text or rename'),
          },
          required: ['action'],
        ),
        OvaToolSpec(
          'studio_auto_captions',
          'Write timed, word-by-word captions from the video\'s speech, in the language spoken. Works for any language, local ones too; says so when a language is not supported well.',
          properties: {
            'project': _s(_project),
            'language': _s('Spoken language code or name, or "auto" (default) to detect it'),
            'style': _s('Caption style id (e.g. ca_karaoke, ca_popwords, ca_bold, ca_clean, ca_pill)'),
          },
        ),
        OvaToolSpec(
          'studio_translate_captions',
          'Translate a project\'s captions into any language (code or name).',
          properties: {
            'project': _s(_project),
            'language': _s('Target language code or name, e.g. sw, fr, Kikuyu'),
          },
          required: ['language'],
        ),
        OvaToolSpec(
          'studio_export',
          'Render a Studio project with every edit baked in and save it to the gallery. Can take a while for long videos.',
          properties: {
            'project': _s(_project),
            'quality': _s('Short side in pixels', ['720', '1080', '1440', '2160']),
            'fps': _i('Frame rate 24-60 (default 30)'),
            'save_to_gallery': _b('Save a copy to the gallery (default true)'),
          },
        ),
        OvaToolSpec(
          'studio_post_story',
          'Export a Studio project and post it to the user\'s Oneova story (public for 24 hours).',
          properties: {'project': _s(_project)},
          risk: OvaRisk.confirm,
        ),
      ];

  OvaPendingAction describe(String name, Map<String, dynamic> a) => OvaPendingAction(
        toolName: name,
        args: a,
        icon: Icons.amp_stories_outlined,
        title: 'Post to your story?',
        detail: 'Exports the ${a['project'] ?? 'latest'} Studio project and posts it for 24 hours.',
        confirmLabel: 'Post',
        hold: true,
      );

  Future<OvaToolResult> run(String name, Map<String, dynamic> a) async {
    String? s(String k) {
      final v = (a[k] ?? '').toString().trim();
      return v.isEmpty ? null : v;
    }

    double? n(String k) => a[k] is num ? (a[k] as num).toDouble() : double.tryParse(s(k) ?? '');
    int? i(String k) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k) ?? '');

    StudioAgentResult r;
    switch (name) {
      case 'studio_projects':
        final list = await _agent.projects();
        if (list.isEmpty) {
          return const OvaToolResult(
            ok: true,
            summary: 'No Studio projects yet.',
            icon: Icons.movie_edit,
            actions: [OvaResultAction(label: 'Open Studio', icon: Icons.movie_edit, route: '/create/studio')],
          );
        }
        return OvaToolResult(
          ok: true,
          title: 'Studio projects',
          summary: list.take(10).map(_agent.describe).join('\n'),
          icon: Icons.movie_edit,
          items: [
            for (final p in list.take(10))
              OvaResultItem(
                title: p.title,
                subtitle: '${p.isPhoto ? 'Photo' : '${(p.durationMs / 1000).round()}s video'} · ${p.aspect.label}',
                icon: p.isPhoto ? Icons.photo_outlined : Icons.movie_outlined,
                onTap: const OvaResultAction(label: 'Open', icon: Icons.open_in_new_rounded, route: '/create/studio'),
              ),
          ],
        );
      case 'studio_new_project':
        r = await _agent.newFromGallery(
          photo: s('kind') == 'photo',
          count: i('count') ?? 1,
          format: s('format') ?? 'short',
          title: s('title'),
        );
      case 'studio_edit':
        r = await _agent.edit(
          s('project'),
          s('action') ?? '',
          name: s('name'),
          value: n('value'),
          clip: i('clip'),
          startS: n('start_s'),
          endS: n('end_s'),
          text: s('text'),
        );
      case 'studio_auto_captions':
        r = await _agent.autoCaptions(s('project'), language: s('language') ?? 'auto', style: s('style') ?? 'ca_karaoke');
      case 'studio_translate_captions':
        r = await _agent.translateCaptions(s('project'), s('language') ?? '');
      case 'studio_export':
        r = await _agent.export(
          s('project'),
          shortSide: int.tryParse(s('quality') ?? '') ?? 1080,
          fps: (i('fps') ?? 30).clamp(24, 60),
          saveToGallery: a['save_to_gallery'] != false,
        );
      case 'studio_post_story':
        r = await _agent.postStory(s('project'));
      default:
        return OvaToolResult.fail('Unknown Studio tool $name');
    }
    if (!r.ok) return OvaToolResult.fail(r.message, icon: Icons.movie_edit);
    return OvaToolResult(
      ok: true,
      summary: r.message,
      icon: Icons.movie_edit,
      imagePath: r.project?.thumbnailPath,
      actions: const [OvaResultAction(label: 'Open Studio', icon: Icons.movie_edit, route: '/create/studio')],
    );
  }
}

final ovaStudioToolsProvider = Provider<OvaStudioTools>((ref) => OvaStudioTools(ref));
