import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../backend/ai_brain_service.dart';
import '../../backend/security/secure_api_key_vault.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../services/ova_task_center.dart';

enum OvaMediaKind { image, video, audio, pdf, document }

OvaMediaKind ovaMediaKindFor(String? mediaType, String? fileName) {
  final name = (fileName ?? '').toLowerCase();
  if (mediaType == 'image' || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.webp')) {
    return OvaMediaKind.image;
  }
  if (mediaType == 'video' || mediaType == 'video_note' || name.endsWith('.mp4') || name.endsWith('.mov')) {
    return OvaMediaKind.video;
  }
  if (mediaType == 'audio' || name.endsWith('.m4a') || name.endsWith('.mp3') || name.endsWith('.wav') || name.endsWith('.aac')) {
    return OvaMediaKind.audio;
  }
  if (name.endsWith('.pdf')) return OvaMediaKind.pdf;
  return OvaMediaKind.document;
}

String _mimeFor(OvaMediaKind kind, String path) {
  final p = path.toLowerCase();
  switch (kind) {
    case OvaMediaKind.image:
      if (p.endsWith('.png')) return 'image/png';
      if (p.endsWith('.webp')) return 'image/webp';
      return 'image/jpeg';
    case OvaMediaKind.video:
      return p.endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
    case OvaMediaKind.audio:
      if (p.endsWith('.mp3')) return 'audio/mp3';
      if (p.endsWith('.wav')) return 'audio/wav';
      if (p.endsWith('.aac')) return 'audio/aac';
      return 'audio/mp4';
    case OvaMediaKind.pdf:
      return 'application/pdf';
    case OvaMediaKind.document:
      return 'text/plain';
  }
}

/// One thing Ova can do with a file. [prompt] is what the model is asked.
class OvaMediaSkill {
  final String id;
  final String label;
  final IconData icon;
  final String prompt;
  final bool usesBrand;
  final bool accent;
  const OvaMediaSkill(this.id, this.label, this.icon, this.prompt, {this.usesBrand = false, this.accent = false});
}

/// Skills offered per media kind, in the order the reader shows them.
List<OvaMediaSkill> ovaSkillsFor(OvaMediaKind kind) {
  const caption = OvaMediaSkill('caption', 'Post caption', Icons.edit_note_rounded,
      'Write 3 short social captions for this, each with 3-5 fitting hashtags. Match the brand voice if given.',
      usesBrand: true, accent: true);
  const market = OvaMediaSkill('market', 'Marketing angle', Icons.campaign_rounded,
      'Act as a senior brand strategist. Give: the hook, target audience, best platform and format, a 1-line call to action, '
          'and one improvement to make it perform better. Match the brand voice if given.',
      usesBrand: true, accent: true);
  const translate = OvaMediaSkill('translate', 'Translate', Icons.translate_rounded,
      'Translate any text or speech in this into English (or into French if it is already English). Keep the meaning and tone.');
  switch (kind) {
    case OvaMediaKind.image:
      return const [
        OvaMediaSkill('describe', 'Describe', Icons.visibility_rounded,
            'Describe this image clearly in 3-5 sentences: what is in it, the setting, mood and anything notable.'),
        OvaMediaSkill('text', 'Extract text', Icons.text_snippet_rounded,
            'Extract all readable text in this image exactly as written, keeping line breaks. If there is none, say so.'),
        caption,
        market,
        OvaMediaSkill('quality', 'Photo tips', Icons.auto_fix_high_rounded,
            'Review this photo like a pro photographer: lighting, composition, focus, colour. Give 3 concrete edits to make it look premium.'),
        translate,
      ];
    case OvaMediaKind.video:
      return const [
        OvaMediaSkill('summary', 'Summarise', Icons.subject_rounded,
            'Summarise this video: what happens, key moments with rough timestamps, and anything said.'),
        OvaMediaSkill('transcript', 'Transcript', Icons.closed_caption_rounded,
            'Transcribe the speech in this video with rough timestamps. If there is no speech, describe the audio.'),
        OvaMediaSkill('hooks', 'Reel hooks', Icons.bolt_rounded,
            'Suggest the best 3 moments to cut as short reels (timestamps), a hook line for each, and a thumbnail idea.',
            usesBrand: true, accent: true),
        caption,
        market,
      ];
    case OvaMediaKind.audio:
      return const [
        OvaMediaSkill('transcript', 'Transcribe', Icons.closed_caption_rounded,
            'Transcribe this audio exactly. Mark different speakers if you can tell them apart.'),
        OvaMediaSkill('summary', 'Summarise', Icons.subject_rounded,
            'Summarise this voice note in 2-3 sentences and list any requests, dates or to-dos in it.'),
        OvaMediaSkill('reply', 'Suggest reply', Icons.reply_rounded,
            'Suggest 3 short, natural replies to this voice note, from casual to formal.'),
        translate,
      ];
    case OvaMediaKind.pdf:
    case OvaMediaKind.document:
      return const [
        OvaMediaSkill('summary', 'Summarise', Icons.subject_rounded,
            'Summarise this document: purpose, key points as bullets, and any dates, amounts or deadlines.'),
        OvaMediaSkill('actions', 'Action items', Icons.checklist_rounded,
            'List every action item, deadline, amount and party named in this document as a checklist.'),
        OvaMediaSkill('explain', 'Explain simply', Icons.school_rounded,
            'Explain this document in plain, simple language as if to a busy friend. Flag anything risky or unusual.'),
        OvaMediaSkill('pitch', 'Turn into post', Icons.campaign_rounded,
            'Turn the main idea of this document into a short LinkedIn-style post and a 1-line tweet. Match the brand voice if given.',
            usesBrand: true, accent: true),
        translate,
      ];
  }
}

/// Natural-language brand kit (users/{uid}/brand_kit/default) that Ova's
/// marketing skills follow.
final ovaBrandVoiceProvider = StreamProvider.autoDispose<String>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value('');
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('brand_kit')
      .doc('default')
      .snapshots()
      .map((d) => (d.data()?['voice'] as String?) ?? '');
});

Future<void> saveOvaBrandVoice(String voice) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance.collection('users').doc(uid).collection('brand_kit').doc('default').set({
    'voice': voice.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

class OvaMediaException implements Exception {
  final String message;
  const OvaMediaException(this.message);
  @override
  String toString() => message;
}

final ovaMediaBrainProvider = Provider<OvaMediaBrain>(
  (ref) => OvaMediaBrain(ref, ref.watch(aiBrainProvider), ref.watch(secureKeyVaultProvider)),
);

/// Multimodal understanding for chat media. Gemini (direct key) reads images,
/// video, audio and PDFs natively; OpenRouter is used for images and PDFs
/// when only an OpenRouter key is set. Work runs as an Ova task, so it keeps
/// going (and reports in the floating dock) after the reader is closed.
class OvaMediaBrain {
  OvaMediaBrain(this._ref, this._brain, this._vault);

  final Ref _ref;
  final AIBrainService _brain;
  final SecureKeyVault _vault;

  static const _maxInlineBytes = 18 * 1024 * 1024;
  static const _openRouterModel = 'google/gemini-2.5-flash';

  /// Runs [skill] (or a free-form [question]) on [file] as a background task.
  Future<String> run({
    required File file,
    required OvaMediaKind kind,
    OvaMediaSkill? skill,
    String? question,
    String? fileLabel,
  }) async {
    final tasks = _ref.read(ovaTaskCenterProvider.notifier);
    final title = '${skill?.label ?? 'Ask'} · ${fileLabel ?? _kindLabel(kind)}';
    final taskId = tasks.start(title, source: 'media');
    final step = tasks.addStep(taskId, 'Reading the ${_kindLabel(kind).toLowerCase()}', Icons.visibility_rounded);
    try {
      var brand = '';
      if (skill?.usesBrand ?? false) {
        brand = await _ref.read(ovaBrandVoiceProvider.future).timeout(const Duration(seconds: 3), onTimeout: () => '');
      }
      final instruction = [
        skill?.prompt ?? question ?? 'Describe this.',
        if (question != null && skill != null) 'User note: $question',
        if (brand.isNotEmpty) 'Brand voice to follow: $brand',
      ].join('\n\n');
      final out = await _analyze(file, kind, instruction);
      tasks.updateStep(taskId, step, OvaStepStatus.done);
      tasks.finish(taskId, ok: true, summary: _firstLine(out));
      return out;
    } catch (e) {
      tasks.updateStep(taskId, step, OvaStepStatus.failed);
      tasks.finish(taskId, ok: false, summary: e.toString());
      rethrow;
    }
  }

  /// Short text-only completion (live chat suggestions). Throws when no key.
  Future<String> complete(String system, String user, {int maxTokens = 300}) async {
    final gKey = await _vault.getGeminiApiKey();
    if (gKey.isNotEmpty) {
      final model = await _vault.getPreferredGeminiModel();
      final res = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$gKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': system},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': user},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.6, 'maxOutputTokens': maxTokens},
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) throw OvaMediaException('Ova error (${res.statusCode}).');
      final parts = (jsonDecode(res.body)['candidates']?[0]?['content']?['parts'] as List?) ?? const [];
      return parts.map((p) => p['text'] ?? '').join().trim();
    }
    var orKey = _brain.openRouterKey;
    if (orKey.isEmpty) orKey = await _vault.getOpenRouterApiKey();
    if (!OneovaAiGateway.canCall(orKey)) throw const OvaMediaException('no_key');
    final res = await http
        .post(
          OneovaAiGateway.chatUri(orKey),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await OneovaAiGateway.bearer(orKey)}',
            'HTTP-Referer': 'https://oneova.studio',
            'X-Title': 'Oneova',
          },
          body: jsonEncode({
            'model': _openRouterModel,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw OvaMediaException('Ova error (${res.statusCode}).');
    return (jsonDecode(res.body)['choices']?[0]?['message']?['content'] as String?)?.trim() ?? '';
  }

  String _kindLabel(OvaMediaKind k) => switch (k) {
        OvaMediaKind.image => 'Photo',
        OvaMediaKind.video => 'Video',
        OvaMediaKind.audio => 'Voice note',
        OvaMediaKind.pdf => 'PDF',
        OvaMediaKind.document => 'Document',
      };

  String _firstLine(String s) {
    final line = s.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => s.trim());
    return line.length > 90 ? '${line.substring(0, 89)}…' : line;
  }

  Future<String> _analyze(File file, OvaMediaKind kind, String instruction) async {
    final size = await file.length();
    if (size > _maxInlineBytes) {
      throw const OvaMediaException('This file is over 18 MB, too large for Ova to read in one go.');
    }
    final mime = _mimeFor(kind, file.path);
    final bytes = await file.readAsBytes();
    final data = base64Encode(bytes);
    const system = 'You are Ova, the premium creative and brand assistant inside the Oneova app. '
        'Answer in clean plain text with short paragraphs or "-" bullets, no markdown headings, no preamble.';

    final gKey = await _vault.getGeminiApiKey();
    if (gKey.isNotEmpty) {
      final model = await _vault.getPreferredGeminiModel();
      final res = await http
          .post(
            Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$gKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': system},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'inlineData': {'mimeType': mime, 'data': data},
                    },
                    {'text': instruction},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 2048},
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) throw OvaMediaException('Ova vision error (${res.statusCode}).');
      final parts = (jsonDecode(res.body)['candidates']?[0]?['content']?['parts'] as List?) ?? const [];
      final text = parts.map((p) => p['text'] ?? '').join().trim();
      if (text.isEmpty) throw const OvaMediaException('Ova could not read this file.');
      return text;
    }

    var orKey = _brain.openRouterKey;
    if (orKey.isEmpty) orKey = await _vault.getOpenRouterApiKey();
    if (!OneovaAiGateway.canCall(orKey)) {
      throw const OvaMediaException('Add a Gemini or OpenRouter key in Settings → AI to let Ova read media.');
    }
    final Map<String, dynamic> part = switch (kind) {
      OvaMediaKind.image => {
          'type': 'image_url',
          'image_url': {'url': 'data:$mime;base64,$data'},
        },
      OvaMediaKind.pdf => {
          'type': 'file',
          'file': {'filename': 'document.pdf', 'file_data': 'data:$mime;base64,$data'},
        },
      OvaMediaKind.audio => {
          'type': 'input_audio',
          'input_audio': {'data': data, 'format': mime.split('/').last},
        },
      _ => throw const OvaMediaException('Video and documents need a Gemini key (Settings → AI).'),
    };
    final res = await http
        .post(
          OneovaAiGateway.chatUri(orKey),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await OneovaAiGateway.bearer(orKey)}',
            'HTTP-Referer': 'https://oneova.studio',
            'X-Title': 'Oneova',
          },
          body: jsonEncode({
            'model': _openRouterModel,
            'messages': [
              {'role': 'system', 'content': system},
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': instruction},
                  part,
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) throw OvaMediaException('Ova vision error (${res.statusCode}).');
    final text = (jsonDecode(res.body)['choices']?[0]?['message']?['content'] as String?)?.trim() ?? '';
    if (text.isEmpty) throw const OvaMediaException('Ova could not read this file.');
    return text;
  }
}
