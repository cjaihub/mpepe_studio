import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/messaging_repository.dart';
import '../../shared/theme/app_theme.dart';
import 'ova_media_brain.dart';

enum OvaSuggestionKind { reply, ask, media }

class OvaSuggestion {
  final OvaSuggestionKind kind;
  final String label;
  final IconData icon;

  /// Reply text to drop in the composer, or the prompt for Ova.
  final String payload;
  final MessageModel? message;
  const OvaSuggestion(this.kind, this.label, this.icon, this.payload, {this.message});
}

/// Live action suggester above the chat composer. When a new message
/// arrives, it quietly works out what you might want to do next: instant
/// on-device ideas (reminder, summary, open media with Ova), plus AI smart
/// replies when you turn them on. It never sends anything by itself.
class OvaChatSuggestionBar extends ConsumerStatefulWidget {
  final String chatId;
  final String myUid;

  /// Decrypted display text for a message (chats may be end-to-end encrypted).
  final String Function(MessageModel m) textOf;
  final bool encryptedChat;
  final ValueChanged<String> onReply;
  final ValueChanged<String> onAskOva;
  final ValueChanged<MessageModel> onOpenMedia;

  const OvaChatSuggestionBar({
    super.key,
    required this.chatId,
    required this.myUid,
    required this.textOf,
    required this.onReply,
    required this.onAskOva,
    required this.onOpenMedia,
    this.encryptedChat = false,
  });

  @override
  ConsumerState<OvaChatSuggestionBar> createState() => _OvaChatSuggestionBarState();
}

class _OvaChatSuggestionBarState extends ConsumerState<OvaChatSuggestionBar> {
  static const _prefKey = 'ova_smart_replies_enabled';

  StreamSubscription<List<MessageModel>>? _sub;
  List<MessageModel> _recent = const [];
  String? _forMessageId;
  String? _dismissedFor;
  List<OvaSuggestion> _items = const [];
  bool _thinking = false;
  bool _smart = false;
  Timer? _debounce;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _smart = p.getBool(_prefKey) ?? false);
    });
    _sub = ref.read(messagingRepositoryProvider).getChatMessages(widget.chatId).listen(_onMessages, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onMessages(List<MessageModel> list) {
    _recent = list.take(10).toList();
    if (_recent.isEmpty) return;
    final last = _recent.first;
    if (last.id == _forMessageId) return;
    if (last.senderId == widget.myUid) {
      // You replied: clear the ideas for the previous message.
      _forMessageId = last.id;
      if (mounted && _items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    _retries = 0;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _compute(last));
  }

  Future<void> _compute(MessageModel last) async {
    final text = widget.textOf(last).trim();
    if (text.startsWith('🔒') && _retries < 4) {
      // Still decrypting; try again shortly.
      _retries++;
      _debounce = Timer(const Duration(milliseconds: 900), () => _compute(last));
      return;
    }
    _forMessageId = last.id;
    final local = _localIdeas(last, text);
    if (!mounted) return;
    setState(() {
      _items = local;
      _thinking = _smart && text.isNotEmpty && !text.startsWith('🔒');
    });
    if (_thinking) {
      final ai = await _aiReplies(text);
      if (!mounted || _forMessageId != last.id) return;
      setState(() {
        _thinking = false;
        _items = [...ai, ...local];
      });
    }
  }

  /// Instant, on-device ideas. Nothing leaves the phone.
  List<OvaSuggestion> _localIdeas(MessageModel m, String text) {
    final out = <OvaSuggestion>[];
    if (m.mediaUrl != null && m.mediaType != null && m.mediaType != 'location' && m.mediaType != 'gif') {
      final kind = ovaMediaKindFor(m.mediaType, m.fileName);
      final label = switch (kind) {
        OvaMediaKind.image => 'Ask Ova about this photo',
        OvaMediaKind.video => 'Summarise this video',
        OvaMediaKind.audio => 'Transcribe voice note',
        OvaMediaKind.pdf => 'Summarise this PDF',
        OvaMediaKind.document => 'Open with Ova',
      };
      out.add(OvaSuggestion(OvaSuggestionKind.media, label, Icons.auto_awesome_rounded, '', message: m));
    }
    final lower = text.toLowerCase();
    final when = RegExp(
      r'\b(today|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|at \d{1,2}(:\d{2})?\s?(am|pm)?|\d{1,2}[:h]\d{2}|\d{1,2}/\d{1,2})\b',
    );
    if (text.isNotEmpty && when.hasMatch(lower)) {
      out.add(OvaSuggestion(OvaSuggestionKind.ask, 'Set a reminder', Icons.alarm_add_rounded,
          'Set a reminder for this, using the date and time in it: "$text"'));
    }
    if (RegExp(r'https?://\S+').hasMatch(text)) {
      out.add(OvaSuggestion(OvaSuggestionKind.ask, 'Summarise link', Icons.link_rounded, 'Summarise this link for me: $text'));
    }
    if (text.length > 280) {
      out.add(OvaSuggestion(OvaSuggestionKind.ask, 'Summarise', Icons.subject_rounded, 'Summarise this message in 2 lines: "$text"'));
    }
    if (text.isNotEmpty && RegExp(r'\b(price|cost|how much|order|deliver|available|in stock|buy)\b').hasMatch(lower)) {
      out.add(OvaSuggestion(OvaSuggestionKind.ask, 'Draft sales reply', Icons.storefront_rounded,
          'A customer wrote: "$text". Draft a friendly, professional reply in my brand voice that moves toward a sale.'));
    }
    return out;
  }

  Future<List<OvaSuggestion>> _aiReplies(String last) async {
    try {
      final convo = _recent.reversed
          .map((m) => '${m.senderId == widget.myUid ? 'Me' : 'Them'}: ${widget.textOf(m)}')
          .where((l) => !l.contains('🔒'))
          .join('\n');
      final raw = await ref.read(ovaMediaBrainProvider).complete(
            'You suggest quick replies for a chat app. Reply ONLY with JSON: {"replies":["...","...","..."]}. '
                'Three short replies (max 8 words each), natural, in the same language as the last message, '
                'from casual to more formal. No emojis unless the chat uses them.',
            'Conversation (oldest first):\n$convo',
            maxTokens: 160,
          );
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (match == null) return const [];
      final replies = ((jsonDecode(match.group(0)!) as Map)['replies'] as List?)?.whereType<String>() ?? const [];
      return [
        for (final r in replies.take(3))
          if (r.trim().isNotEmpty) OvaSuggestion(OvaSuggestionKind.reply, r.trim(), Icons.reply_rounded, r.trim()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _enableSmart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Turn on Ova smart replies?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'When a message arrives, Ova sends the last few messages of the chat to its AI provider to suggest replies. '
          '${widget.encryptedChat ? 'This chat is end-to-end encrypted, so this shares those messages outside the chat. ' : ''}'
          'Nothing is sent to your contact until you tap a reply and press send. You can turn it off any time.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    (await SharedPreferences.getInstance()).setBool(_prefKey, true);
    setState(() => _smart = true);
    if (_recent.isNotEmpty && _recent.first.senderId != widget.myUid) {
      _forMessageId = null;
      _compute(_recent.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _dismissedFor != _forMessageId && (_items.isNotEmpty || _thinking);
    final showSmartOffer = !_smart && visible;
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 34,
                child: Row(children: [
                  _Orb(thinking: _thinking),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _Chip(
                              s: _items[i],
                              onTap: () {
                                HapticFeedback.selectionClick();
                                final s = _items[i];
                                switch (s.kind) {
                                  case OvaSuggestionKind.reply:
                                    widget.onReply(s.payload);
                                  case OvaSuggestionKind.ask:
                                    widget.onAskOva(s.payload);
                                  case OvaSuggestionKind.media:
                                    widget.onOpenMedia(s.message!);
                                }
                              },
                            )
                                .animate()
                                .fadeIn(delay: (50 * i).ms, duration: 240.ms)
                                .slideX(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
                          ),
                        if (_thinking && _items.isEmpty)
                          Center(
                            child: Text('Ova is thinking…',
                                style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted)),
                          ),
                        if (showSmartOffer)
                          _Chip(
                            s: const OvaSuggestion(
                                OvaSuggestionKind.ask, 'Smart replies', Icons.auto_awesome_rounded, ''),
                            subtle: true,
                            onTap: _enableSmart,
                          ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _dismissedFor = _forMessageId),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  final OvaSuggestion s;
  final VoidCallback onTap;
  final bool subtle;
  const _Chip({required this.s, required this.onTap, this.subtle = false});

  @override
  Widget build(BuildContext context) {
    final accent = s.kind != OvaSuggestionKind.reply;
    final c = accent ? AppColors.brandPink : AppColors.brandBlue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: subtle ? context.surfaceMid : c.withValues(alpha: context.isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: subtle ? context.border : c.withValues(alpha: 0.45), width: 1),
            boxShadow: subtle
                ? null
                : [BoxShadow(color: c.withValues(alpha: context.isDark ? 0.18 : 0.10), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(s.icon, size: 13, color: subtle ? context.textSecondary : c),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final bool thinking;
  const _Orb({required this.thinking});

  @override
  Widget build(BuildContext context) {
    final orb = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
        boxShadow: [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.35), blurRadius: 10)],
      ),
      child: const Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.brandWhite),
    );
    if (!thinking) return orb;
    return orb
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 0.9, end: 1.08, duration: 700.ms, curve: Curves.easeInOut);
  }
}
