import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../backend/security/oneova_ai_gateway.dart';
import '../shared/theme/app_theme.dart';
import 'identity_service.dart';
import 'identity_vault.dart';

/// Ova ID guide: a calm helper beside every identity step.
///
/// Privacy contract: the model gets the step, the status, on-device photo check
/// results as yes/no, and the reviewer's reason. It never gets images, names,
/// ID or tax numbers, or dates of birth, and it cannot approve or submit
/// anything — its only tools read the status and open screens.
class IdGuideContext {
  const IdGuideContext({required this.screen, this.extra = const {}});
  final String screen; // hub | verify_id | business | share | my_data
  final Map<String, Object?> extra; // e.g. {'selfie_blurry': true}
}

class _Msg {
  _Msg(this.role, this.text);
  final String role; // user | assistant
  final String text;
  Map<String, String> toJson() => {'role': role, 'content': text};
}

class IdGuideAgent {
  IdGuideAgent(this.ref);
  final Ref ref;

  static const models = ['openai/gpt-6.1-terra', 'openai/gpt-6-luna', 'openai/gpt-5.4-mini'];
  static const _system = '''
You are Ova, the guide inside Oneova ID — the place where people verify who they are once and reuse it, and where business owners get the Verified Business badge.
How you talk: warm, plain, short (2–4 sentences or a short numbered list). No jargon. Reply in the user's language.
What you do: explain what each step needs and why, what happens to their data, why a check failed and how to fix it, what to do next. Use get_status before answering anything about their progress. Offer open_screen when the next step is a screen.
Facts you can rely on:
- Personal check: a photo of an ID (national ID, passport or driving licence; back side if it has one) and a selfie. A person on the review team decides, usually within a day; an AI pre-check only helps the reviewer.
- Photos are stored privately, only the review team can open them, and they are deleted 30 days after the decision. Deleting identity data stops payouts until verified again.
- Sharing: a QR code shows only the fields the person picks and expires; it can be stopped any time.
- Business: the owner must be ID-verified first. Usually needed: registration certificate, ownership record for companies, tax registration, proof of address under 3 months. Owners with 25% or more confirm and verify themselves. Requirements differ by country — say "usually needed", never give legal advice.
Hard rules: never ask for or repeat ID numbers, tax numbers, dates of birth or photos; if the user types one, tell them not to share it in chat. Never say someone is or will be approved. Never help get around a check, use someone else's documents, or edit documents. If asked something unrelated, answer briefly and steer back.''';

  final _history = <_Msg>[];

  List<Map<String, dynamic>> get _tools => [
        {
          'type': 'function',
          'function': {
            'name': 'get_status',
            'description': 'Current Oneova ID status of this user: personal check, business check, missing items. No personal data.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'open_screen',
            'description': 'Offer a button that opens a screen.',
            'parameters': {
              'type': 'object',
              'properties': {
                'screen': {'type': 'string', 'enum': ['verify_id', 'business', 'share', 'my_data', 'hub']},
                'label': {'type': 'string', 'description': 'Short button text, max 4 words'},
              },
              'required': ['screen', 'label'],
            },
          },
        },
      ];

  Map<String, Object?> _status(IdGuideContext ctx) {
    final id = ref.read(identityProvider);
    final biz = ref.read(businessIdentityProvider).value;
    return {
      'screen': ctx.screen,
      'personal': id.kyc.status,
      'personal_reason': id.kyc.lastError,
      'level': id.shownLevel,
      'has_credential': id.credentialId != null,
      'business': biz?.status ?? 'none',
      'business_level': biz?.level ?? 0,
      'business_reason': biz?.rejectReason,
      'business_country': biz?.country,
      ...ctx.extra,
    };
  }

  /// One turn. Returns the reply and an optional screen button.
  Future<({String text, String? screen, String? label})> ask(String userText, IdGuideContext ctx) async {
    _history.add(_Msg('user', _scrub(userText)));
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _system},
      ..._history.takeLast(16).map((m) => m.toJson()),
    ];
    String? screen;
    String? label;
    for (var round = 0; round < 3; round++) {
      final msg = await _complete(messages);
      final calls = (msg['tool_calls'] as List?) ?? const [];
      if (calls.isEmpty) {
        final text = '${msg['content'] ?? ''}'.trim();
        _history.add(_Msg('assistant', text));
        return (text: text.isEmpty ? 'I’m here — what would you like to do next?' : text, screen: screen, label: label);
      }
      messages.add({'role': 'assistant', 'content': msg['content'], 'tool_calls': calls});
      for (final c in calls) {
        final fn = Map<String, dynamic>.from((c as Map)['function'] as Map);
        Object? result;
        if (fn['name'] == 'get_status') {
          result = _status(ctx);
        } else if (fn['name'] == 'open_screen') {
          final args = jsonDecode('${fn['arguments'] ?? '{}'}') as Map;
          screen = '${args['screen']}';
          label = '${args['label'] ?? 'Open'}';
          result = {'shown': true};
        }
        messages.add({'role': 'tool', 'tool_call_id': c['id'], 'content': jsonEncode(result ?? {})});
      }
    }
    return (text: 'Tap the button below to continue.', screen: screen, label: label);
  }

  Future<Map<String, dynamic>> _complete(List<Map<String, dynamic>> messages) async {
    Object? lastError;
    for (final model in models) {
      try {
        final bearer = await OneovaAiGateway.bearer('');
        final res = await http
            .post(
              OneovaAiGateway.chatUri(''),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $bearer',
                'X-Title': 'Oneova ID',
                ...await OneovaAiGateway.appCheckHeader(''),
              },
              body: jsonEncode({'model': model, 'messages': messages, 'tools': _tools, 'temperature': 0.3, 'max_tokens': 500}),
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          continue;
        }
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return Map<String, dynamic>.from(((body['choices'] as List).first as Map)['message'] as Map);
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Guide unavailable: $lastError');
  }

  /// Masks long digit/letter runs so numbers typed by mistake never leave the phone.
  static String _scrub(String s) => s.replaceAllMapped(RegExp(r'\b(?=[A-Z0-9-]*\d)[A-Z0-9-]{6,}\b', caseSensitive: false), (_) => '[number hidden]');
}

extension<T> on List<T> {
  Iterable<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}

final idGuideProvider = Provider((ref) => IdGuideAgent(ref));

/// Small "Ask Ova" pill that opens the guide.
class IdGuideButton extends StatelessWidget {
  const IdGuideButton({super.key, required this.guideContext});
  final IdGuideContext guideContext;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => IdGuideSheet.show(context, guideContext),
      icon: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.brandPink),
      label: Text('Ask Ova', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
      style: TextButton.styleFrom(
        backgroundColor: AppColors.brandPink.withValues(alpha: 0.10),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}

class IdGuideSheet extends ConsumerStatefulWidget {
  const IdGuideSheet({super.key, required this.guideContext});
  final IdGuideContext guideContext;

  static Future<void> show(BuildContext context, IdGuideContext ctx) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => IdGuideSheet(guideContext: ctx),
    );
  }

  @override
  ConsumerState<IdGuideSheet> createState() => _IdGuideSheetState();
}

class _Bubble {
  _Bubble(this.mine, this.text, {this.screen, this.label});
  final bool mine;
  final String text;
  final String? screen;
  final String? label;
}

class _IdGuideSheetState extends ConsumerState<IdGuideSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _bubbles = <_Bubble>[];
  bool _thinking = false;
  static const _storeKey = 'oneova_id_guide_chat_v1';

  static const _starters = {
    'hub': ['What is Oneova ID?', 'What do I need?', 'Who can see my data?'],
    'verify_id': ['What photos do I need?', 'Tips for a clear photo', 'How long does it take?'],
    'business': ['What documents for my country?', 'Who counts as an owner?', 'Why do I need my own ID first?'],
    'share': ['What will they see?', 'How do I stop a share?'],
    'my_data': ['What happens if I delete?', 'How long do you keep photos?'],
  };

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final sealed = await const FlutterSecureStorage().read(key: '${_storeKey}_$uid');
    final plain = sealed == null ? null : await IdentityVault().decrypt(sealed);
    if (plain == null || !mounted) return;
    final list = (jsonDecode(plain) as List).cast<Map>();
    setState(() => _bubbles.addAll(list.map((m) => _Bubble(m['m'] == true, '${m['t']}'))));
  }

  Future<void> _persist() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final last = _bubbles.length > 30 ? _bubbles.sublist(_bubbles.length - 30) : _bubbles;
    final sealed = await IdentityVault().encrypt(jsonEncode(last.map((b) => {'m': b.mine, 't': b.text}).toList()));
    await const FlutterSecureStorage().write(key: '${_storeKey}_$uid', value: sealed);
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _thinking) return;
    _input.clear();
    setState(() {
      _bubbles.add(_Bubble(true, t));
      _thinking = true;
    });
    _toEnd();
    try {
      final r = await ref.read(idGuideProvider).ask(t, widget.guideContext);
      if (!mounted) return;
      setState(() => _bubbles.add(_Bubble(false, r.text, screen: r.screen, label: r.label)));
      _persist();
    } catch (_) {
      if (mounted) setState(() => _bubbles.add(_Bubble(false, 'I can’t reach my brain right now. Check your connection and try again.')));
    } finally {
      if (mounted) setState(() => _thinking = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  void _open(String screen) {
    Navigator.of(context).pop();
    final route = switch (screen) {
      'verify_id' => '/wallet/verify',
      'business' => '/id/business',
      'my_data' => '/id/data',
      _ => '/id',
    };
    if (screen == 'share') {
      context.push('/id?share=1');
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final starters = _starters[widget.guideContext.screen] ?? _starters['hub']!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ova · ID guide', style: TextStyle(fontWeight: FontWeight.w800, color: context.textPrimary)),
                  Text('Never shares your photos or numbers', style: TextStyle(fontSize: 11, color: context.textSecondary)),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: context.textSecondary)),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              children: [
                if (_bubbles.isEmpty)
                  _bubble(_Bubble(false, 'Hi! I’ll walk you through verifying your identity or your business, step by step. What would you like to know?')),
                ..._bubbles.map(_bubble),
                if (_thinking)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Ova is thinking…', style: TextStyle(fontSize: 12, color: context.textMuted)),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: starters
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => _send(s)),
                      ))
                  .toList(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: InputDecoration(
                      hintText: 'Ask about any step…',
                      filled: true,
                      fillColor: context.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _thinking ? null : () => _send(_input.text),
                  style: IconButton.styleFrom(backgroundColor: AppColors.brandBlue),
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _bubble(_Bubble b) {
    return Align(
      alignment: b.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: b.mine ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.text, style: TextStyle(fontSize: 14, height: 1.35, color: b.mine ? Colors.white : context.textPrimary)),
          if (b.screen != null) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _open(b.screen!),
              style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandPink, visualDensity: VisualDensity.compact),
              child: Text(b.label ?? 'Open'),
            ),
          ],
        ]),
      ),
    );
  }
}
