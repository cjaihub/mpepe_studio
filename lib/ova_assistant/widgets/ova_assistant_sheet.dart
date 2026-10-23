import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../../shared/location/geo_services.dart';
import '../../shared/router.dart' show rootNavigatorKey;
import '../../shared/theme/app_theme.dart';
import '../core/ova_tool_result.dart';
import '../services/ova_chat_controller.dart';
import 'ova_confirm_card.dart';
import '../services/ova_device_hub.dart';
import '../media/ova_brand_voice_sheet.dart';
import '../services/ova_tool_registry.dart';
import 'ova_live_map_card.dart';
import '../../shared/widgets/live_recording_waveform.dart';

/// Ova, the Oneova assistant. Opens as a compact bottom sheet; the same
/// panel is used full screen at `/hub/ova_assistant`.
class OvaAssistantSheet {
  OvaAssistantSheet._();

  static bool _isOpen = false;

  /// True while the sheet is showing (the floating dock hides itself).
  static final ValueNotifier<bool> openState = ValueNotifier<bool>(false);

  static Future<T?> show<T>(
    BuildContext context, {
    OvaInvocationContext invocation = const OvaInvocationContext(),
    String? initialPrompt,
    bool sendInitialPrompt = false,
    Uint8List? screenContextBytes,
    String? screenContextLabel,
    bool autoStartVoice = false,
    void Function(String text)? onInsertIntoChat,
  }) {
    if (_isOpen) return Future.value(null);
    final navContext = Navigator.maybeOf(context) != null ? context : rootNavigatorKey.currentContext;
    if (navContext == null) return Future.value(null);
    _isOpen = true;
    openState.value = true;
    HapticFeedback.lightImpact();
    return showModalBottomSheet<T>(
      context: navContext,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.45),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 340),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
      builder: (_) => OvaAssistantPanel(
        isSheet: true,
        invocation: invocation,
        initialPrompt: initialPrompt,
        sendInitialPrompt: sendInitialPrompt,
        screenContextBytes: screenContextBytes,
        screenContextLabel: screenContextLabel,
        autoStartVoice: autoStartVoice,
        onInsertIntoChat: onInsertIntoChat,
      ),
    ).whenComplete(() {
      _isOpen = false;
      openState.value = false;
    });
  }
}

/// Full-screen Ova at `/hub/ova_assistant`.
class OvaAssistantScreen extends StatelessWidget {
  const OvaAssistantScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.surface,
      body: const SafeArea(child: OvaAssistantPanel(isSheet: false)),
    );
  }
}

class OvaAssistantPanel extends ConsumerStatefulWidget {
  final bool isSheet;
  final OvaInvocationContext invocation;
  final String? initialPrompt;
  final bool sendInitialPrompt;
  final Uint8List? screenContextBytes;
  final String? screenContextLabel;
  final bool autoStartVoice;
  final void Function(String text)? onInsertIntoChat;

  const OvaAssistantPanel({
    super.key,
    required this.isSheet,
    this.invocation = const OvaInvocationContext(),
    this.initialPrompt,
    this.sendInitialPrompt = false,
    this.screenContextBytes,
    this.screenContextLabel,
    this.autoStartVoice = false,
    this.onInsertIntoChat,
  });

  @override
  ConsumerState<OvaAssistantPanel> createState() => _OvaAssistantPanelState();
}

class _OvaAssistantPanelState extends ConsumerState<OvaAssistantPanel> {
  late final OvaChatController _chat;
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  // Live mic levels while Ova is listening (drives the waveform strip).
  final List<double> _voiceLevels = [];
  DateTime? _listenStart;
  bool _speechReady = false;
  Uint8List? _screenBytes;

  @override
  void initState() {
    super.initState();
    _screenBytes = widget.screenContextBytes;
    _chat = ref.read(ovaChatProvider)
      ..invocation = widget.invocation
      ..onNavigate = _navigate
      ..addListener(_onChat);
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      if (widget.sendInitialPrompt) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.initialPrompt!));
      } else {
        _input.text = widget.initialPrompt!;
      }
    }
    if (widget.autoStartVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggleVoice());
    }
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    if (_chat.onNavigate == _navigate) _chat.onNavigate = null;
    _speech.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: 220.ms, curve: Curves.easeOut);
      }
    });
  }

  // ── actions ────────────────────────────────────────────────────────────

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty || _chat.busy) return;
    HapticFeedback.lightImpact();
    if (_listening) _stopVoice();
    _chat.permissionContext = context;
    final img = _screenBytes != null ? base64Encode(_screenBytes!) : null;
    _input.clear();
    setState(() => _screenBytes = null);
    _chat.send(t, imageBase64: img);
  }

  void _navigate(String route) {
    HapticFeedback.selectionClick();
    if (widget.isSheet) {
      Navigator.of(context).pop();
      final root = rootNavigatorKey.currentContext;
      if (root != null) GoRouter.of(root).push(route);
    } else {
      context.push(route);
    }
  }

  Future<void> _runAction(OvaResultAction a) async {
    HapticFeedback.selectionClick();
    if (a.route != null) {
      _navigate(a.route!);
    } else if (a.url != null && a.url!.startsWith('ova://')) {
      await runOvaInternalUrl(ref, a.url!);
    } else if (a.url != null) {
      await launchUrl(Uri.parse(a.url!), mode: LaunchMode.externalApplication);
    } else if (a.prompt != null) {
      _send(a.prompt);
    }
  }

  void _close() {
    HapticFeedback.lightImpact();
    if (widget.isSheet) {
      Navigator.of(context).pop();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/home');
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      _stopVoice();
      return;
    }
    HapticFeedback.lightImpact();
    if (!_speechReady) {
      try {
        _speechReady = await _speech.initialize(
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
          },
          onError: (_) {
            if (mounted) setState(() => _listening = false);
          },
        );
      } catch (_) {
        _speechReady = false;
      }
    }
    if (!_speechReady) {
      if (!mounted) return;
      final mic = await Permission.microphone.status;
      if (!mounted) return;
      _snack(
        mic.isPermanentlyDenied
            ? 'Microphone is off for Oneova. Turn it on in Settings to talk to Ova.'
            : 'Voice input is not available on this device. You can still type.',
        action: mic.isPermanentlyDenied ? SnackBarAction(label: 'Settings', onPressed: openAppSettings) : null,
      );
      return;
    }
    setState(() {
      _listening = true;
      _voiceLevels.clear();
      _listenStart = DateTime.now();
    });
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      // Android reports roughly -2…10 dB; map it to 0..1 for the waveform.
      onSoundLevelChange: (level) {
        if (!mounted || !_listening) return;
        setState(() {
          _voiceLevels.add(((level + 2) / 12).clamp(0.05, 1.0));
          if (_voiceLevels.length > 140) _voiceLevels.removeRange(0, _voiceLevels.length - 140);
        });
      },
      onResult: (r) {
        if (!mounted) return;
        setState(() {
          _input.text = r.recognizedWords;
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        });
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) _send();
      },
    );
  }

  void _stopVoice() {
    _speech.stop();
    if (mounted) setState(() => _listening = false);
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isSheet) _grabber(context),
        _header(context),
        Divider(height: 1, thickness: 1, color: context.border),
        Flexible(child: _chat.isEmpty ? _emptyState(context) : _conversation(context)),
        _composer(context),
      ],
    );

    if (!widget.isSheet) return body;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border(top: BorderSide(color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.45 : 0.25), width: 1)),
          boxShadow: [
            // Soft brand glow on top of a deep ambient shadow.
            BoxShadow(
              color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.22 : 0.10),
              blurRadius: 36,
              offset: const Offset(0, -8),
            ),
            BoxShadow(
              color: AppColors.brandBlack.withValues(alpha: context.isDark ? 0.55 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          child: Stack(children: [
            if (context.isDark)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-0.8, -1.1),
                        radius: 1.1,
                        colors: [AppColors.brandBlue.withValues(alpha: 0.12), AppColors.brandBlue.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(top: false, child: body),
          ]),
        ),
      ),
    ).animate().slideY(begin: 0.06, end: 0, duration: 260.ms, curve: Curves.easeOutCubic).fadeIn(duration: 200.ms);
  }

  Widget _grabber(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
    ),
  );

  Widget _header(BuildContext context) {
    final status = _listening
        ? 'Listening…'
        : _chat.busy
        ? 'Working…'
        : 'Ready';
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            tooltip: widget.isSheet ? 'Close' : 'Back',
            onPressed: _close,
            icon: Icon(widget.isSheet ? Icons.keyboard_arrow_down_rounded : Icons.arrow_back_rounded, size: 22, color: context.textPrimary),
          ),
          const _OvaMark(size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ova',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: context.textPrimary),
                ),
                Row(
                  children: [
                    _StatusDot(active: _listening || _chat.busy),
                    const SizedBox(width: 5),
                    Text(status, style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          if (!_chat.isEmpty)
            IconButton(
              tooltip: 'New chat',
              onPressed: () {
                HapticFeedback.selectionClick();
                _chat.reset();
              },
              icon: Icon(Icons.add_comment_outlined, size: 20, color: context.textSecondary),
            ),
          if (widget.isSheet)
            IconButton(
              tooltip: 'Full screen',
              onPressed: () => _navigate('/hub/ova_assistant'),
              icon: Icon(Icons.open_in_full_rounded, size: 18, color: context.textSecondary),
            ),
          IconButton(
            tooltip: 'Brand voice',
            onPressed: () => showOvaBrandVoiceEditor(context, ref),
            icon: Icon(Icons.diamond_outlined, size: 19, color: context.textSecondary),
          ),
          IconButton(
            tooltip: 'Ova settings',
            onPressed: () => _navigate('/ova/abilities'),
            icon: Icon(Icons.tune_rounded, size: 20, color: context.textSecondary),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final inv = widget.invocation;
    final chips = <_Suggestion>[
      if (inv.contentId != null) const _Suggestion(Icons.favorite_rounded, 'Like this reel', 'like this'),
      if (inv.contentId != null) const _Suggestion(Icons.mode_comment_rounded, 'Comment on this', 'comment ', fill: true),
      if (inv.chatId != null) const _Suggestion(Icons.edit_note_rounded, 'Draft a reply', 'Help me write a friendly reply to this chat'),
      const _Suggestion(Icons.sensors_rounded, 'Go live', 'go live', accent: true),
      const _Suggestion(Icons.search_rounded, 'Search Oneova', 'search ', fill: true),
      const _Suggestion(Icons.call_rounded, 'Call someone', 'call ', fill: true),
      const _Suggestion(Icons.sms_rounded, 'Text someone', 'text  saying ', fill: true),
      const _Suggestion(Icons.timer_rounded, '5 min timer', 'set a timer for 5 minutes'),
      const _Suggestion(Icons.alarm_rounded, 'Set alarm', 'set an alarm for 7:00 am'),
      const _Suggestion(Icons.flashlight_on_rounded, 'Flashlight', 'flashlight on'),
      const _Suggestion(Icons.my_location_rounded, 'Where am I?', 'where am i'),
      const _Suggestion(Icons.photo_camera_rounded, 'Take a photo', 'take a photo'),
      const _Suggestion(Icons.upload_rounded, 'Post a video', 'upload'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How can I help?',
            style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask anything, or tell me to do something on your phone or in Oneova.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < chips.length; i++)
                _chip(context, chips[i]).animate(delay: (24 * i).ms).fadeIn(duration: 220.ms).slideY(begin: 0.15, end: 0),
            ],
          ),
          if (_screenBytes != null) ...[const SizedBox(height: 14), _screenPreview(context)],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, _Suggestion s) {
    return _Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        if (s.fill) {
          _input.text = s.prompt;
          final caret = s.prompt.indexOf('  ');
          _input.selection = TextSelection.collapsed(offset: caret >= 0 ? caret + 1 : s.prompt.length);
          _focus.requestFocus();
        } else {
          _send(s.prompt);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: s.accent ? AppColors.brandPink.withValues(alpha: 0.10) : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: s.accent ? AppColors.brandPink.withValues(alpha: 0.45) : context.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(s.icon, size: 14, color: s.accent ? AppColors.brandPink : AppColors.brandBlue),
            const SizedBox(width: 6),
            Text(
              s.label,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversation(BuildContext context) {
    final items = _chat.items;
    final waiting = _chat.busy && (items.isEmpty || items.last.kind == OvaItemKind.user);
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: widget.isSheet,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      itemCount: items.length + (waiting ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == items.length) return const _TypingDots();
        final item = items[i];
        final Widget child;
        switch (item.kind) {
          case OvaItemKind.user:
            child = _userBubble(context, item);
          case OvaItemKind.assistant:
            child = _assistantText(context, item);
          case OvaItemKind.result:
            child = _resultCard(context, item);
          case OvaItemKind.confirm:
            child = OvaConfirmCard(item: item, chat: _chat);
          case OvaItemKind.notice:
            child = _noticeCard(context, item);
        }
        return Padding(
          key: ValueKey(item.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: child.animate().fadeIn(duration: 220.ms).slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
        );
      },
    );
  }

  Widget _userBubble(BuildContext context, OvaItem item) => Align(
    alignment: Alignment.centerRight,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandBlue, Color.lerp(AppColors.brandBlue, AppColors.brandPink, 0.18)!],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(AppRadius.md),
            topRight: Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(AppRadius.md),
            bottomRight: Radius.circular(AppRadius.xs),
          ),
          boxShadow: [
            BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Text(item.text, style: GoogleFonts.inter(fontSize: 13, height: 1.35, color: AppColors.brandWhite)),
      ),
    ),
  );

  Widget _assistantText(BuildContext context, OvaItem item) {
    final style = GoogleFonts.inter(fontSize: 13, height: 1.4, color: context.textPrimary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: _OvaMark(size: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkdownBody(
                data: item.text + (item.streaming ? ' ▍' : ''),
                selectable: !item.streaming,
                onTapLink: (_, href, _) {
                  if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                },
                styleSheet: MarkdownStyleSheet(
                  p: style,
                  listBullet: style,
                  strong: style.copyWith(fontWeight: FontWeight.w700),
                  h1: style.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  h2: style.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                  h3: style.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  a: style.copyWith(color: AppColors.brandBlue, decoration: TextDecoration.underline),
                  code: GoogleFonts.jetBrainsMono(fontSize: 12, color: context.textPrimary, backgroundColor: context.surfaceMid),
                  codeblockDecoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: context.border),
                  ),
                  tableBorder: TableBorder.all(color: context.border, width: 1),
                  tableBody: style.copyWith(fontSize: 12),
                  tableHead: style.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              if (!item.streaming && item.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      _miniAction(context, Icons.content_copy_rounded, 'Copy', () {
                        Clipboard.setData(ClipboardData(text: item.text));
                        HapticFeedback.selectionClick();
                        _snack('Copied');
                      }),
                      if (widget.onInsertIntoChat != null)
                        _miniAction(context, Icons.reply_rounded, 'Use in chat', () {
                          widget.onInsertIntoChat!(item.text.trim());
                          _close();
                        }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniAction(BuildContext context, IconData icon, String label, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: context.textMuted),
          ),
        ],
      ),
    ),
  );

  Widget _cardShell(BuildContext context, {required Widget child, Color? borderColor, Color? fill}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: fill ?? context.surfaceMid,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: borderColor ?? context.border, width: 1),
    ),
    child: child,
  );

  Widget _resultCard(BuildContext context, OvaItem item) {
    final r = item.result;
    if (r == null) {
      return _cardShell(
        context,
        child: Row(
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)),
            const SizedBox(width: 10),
            Text(item.text, style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary)),
          ],
        ),
      );
    }
    final color = r.unsupported
        ? context.textMuted
        : r.ok
        ? AppColors.brandBlue
        : AppColors.brandPink;
    return _cardShell(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(r.icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    r.title ?? (r.items.isNotEmpty ? r.summary.split('\n').first.split(':').first : r.summary),
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35, color: context.textPrimary),
                  ),
                ),
              ),
              if (r.unsupported) const _Badge('NOT ON THIS PHONE'),
            ],
          ),
          if (r.imagePath != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(File(r.imagePath!), height: 160, width: double.infinity, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                _actionPill(context, Icons.ios_share_rounded, 'Share', () => _chat.registry.device.share('', filePath: r.imagePath)),
                _actionPill(context, Icons.upload_rounded, 'Post on Oneova', () => _navigate('/upload/global')),
              ],
            ),
          ],
          if (r.map != null) ...[
            const SizedBox(height: 10),
            OvaLiveMapCard(spec: r.map!, onPrompt: (p) => _send(p)),
          ],
          if (r.items.isNotEmpty) ...[const SizedBox(height: 8), for (final it in r.items) _resultRow(context, it)],
          if (r.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final a in r.actions) _actionPill(context, a.icon, a.label, () => _runAction(a))],
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(BuildContext context, OvaResultItem it) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: it.onTap == null ? null : () => _runAction(it.onTap!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            if (it.onTap == null && it.imageUrl == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.fiber_manual_record_rounded, size: 6, color: AppColors.brandBlue),
              )
            else
              CircleAvatar(
                radius: 14,
                backgroundColor: context.surface,
                backgroundImage: it.imageUrl != null ? NetworkImage(it.imageUrl!) : null,
                child: it.imageUrl == null ? Icon(it.icon, size: 14, color: AppColors.brandBlue) : null,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    it.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                  ),
                  if (it.subtitle != null)
                    Text(
                      it.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                    ),
                ],
              ),
            ),
            if (it.onTap != null) ...[
              Text(
                it.onTap!.label,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brandBlue),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: context.textMuted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionPill(BuildContext context, IconData icon, String label, VoidCallback onTap) => _Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.brandBlue),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textPrimary),
          ),
        ],
      ),
    ),
  );

  Widget _noticeCard(BuildContext context, OvaItem item) {
    final r = item.result;
    return _cardShell(
      context,
      borderColor: AppColors.brandPink.withValues(alpha: 0.35),
      fill: AppColors.brandPink.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(r?.icon ?? Icons.info_outline_rounded, size: 16, color: AppColors.brandPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.text, style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textPrimary)),
              ),
            ],
          ),
          if (r != null && r.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [for (final a in r.actions) _actionPill(context, a.icon, a.label, () => _runAction(a))]),
          ],
        ],
      ),
    );
  }

  Widget _screenPreview(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: context.surfaceMid,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: context.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: Image.memory(_screenBytes!, width: 34, height: 34, fit: BoxFit.cover),
        ),
        const SizedBox(width: 8),
        Text(
          widget.screenContextLabel ?? 'Screen attached',
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textPrimary),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
          onPressed: () => setState(() => _screenBytes = null),
        ),
      ],
    ),
  );

  /// LIVE strip while Ova listens: pulsing dot, elapsed time, waveform from
  /// the mic, and Cancel / Send so the spoken words can be sent right away.
  Widget _liveListeningStrip(BuildContext context) {
    final secs = _listenStart == null ? 0 : DateTime.now().difference(_listenStart!).inSeconds;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.brandPink.withValues(alpha: context.isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.xs)),
            child: Text('LIVE',
                style: GoogleFonts.inter(
                    fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: AppColors.brandWhite)),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.45, duration: 700.ms),
          const SizedBox(width: 8),
          Text('${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(width: 8),
          Expanded(child: LiveRecordingWaveform(levels: _voiceLevels, height: 24)),
          IconButton(
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
            onPressed: () {
              _stopVoice();
              setState(() => _input.clear());
            },
          ),
          IconButton(
            tooltip: 'Send now',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.send_rounded, size: 18, color: AppColors.brandBlue),
            onPressed: _input.text.trim().isEmpty
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _stopVoice();
                    _send();
                  },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.15, end: 0);
  }

  Widget _composer(BuildContext context) {
    final busy = _chat.busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_screenBytes != null && !_chat.isEmpty) ...[_screenPreview(context), const SizedBox(height: 8)],
          if (_listening) ...[_liveListeningStrip(context), const SizedBox(height: 8)],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                  cursorColor: AppColors.brandBlue,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _listening ? 'Listening…' : 'Ask Ova or give a command',
                    hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
                    filled: true,
                    fillColor: context.surfaceMid,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: context.border, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: context.border, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _roundButton(
                icon: _listening ? Icons.stop_rounded : Icons.mic_rounded,
                color: _listening ? AppColors.brandPink : context.surfaceMid,
                iconColor: _listening ? Colors.white : context.textPrimary,
                border: !_listening,
                tooltip: _listening ? 'Stop listening' : 'Speak',
                onTap: _toggleVoice,
                pulse: _listening,
              ),
              const SizedBox(width: 6),
              _roundButton(
                icon: busy ? Icons.stop_circle_outlined : Icons.arrow_upward_rounded,
                color: busy || _input.text.trim().isNotEmpty ? AppColors.brandBlue : AppColors.brandBlue.withValues(alpha: 0.35),
                iconColor: Colors.white,
                tooltip: busy ? 'Stop' : 'Send',
                onTap: busy
                    ? () {
                        HapticFeedback.selectionClick();
                        _chat.stop();
                      }
                    : () => _send(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required String tooltip,
    required VoidCallback onTap,
    bool border = false,
    bool pulse = false,
  }) {
    Widget b = Tooltip(
      message: tooltip,
      child: _Pressable(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border ? Border.all(color: context.border, width: 1) : null,
          ),
          child: Icon(icon, size: 19, color: iconColor),
        ),
      ),
    );
    if (pulse) {
      b = b.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.08, duration: 600.ms, curve: Curves.easeInOut);
    }
    return b;
  }
}

// ── small widgets ───────────────────────────────────────────────────────

class _Suggestion {
  final IconData icon;
  final String label;
  final String prompt;
  final bool fill;
  final bool accent;
  const _Suggestion(this.icon, this.label, this.prompt, {this.fill = false, this.accent = false});
}

class _OvaMark extends StatelessWidget {
  final double size;
  const _OvaMark({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.brandBlue, AppColors.brandPink]),
    ),
    child: Icon(Icons.auto_awesome_rounded, size: size * 0.55, color: Colors.white),
  );
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: context.surface,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      border: Border.all(color: context.border),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: context.textMuted),
    ),
  );
}

/// Scales to 0.96 while pressed.
class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Pressable({required this.child, required this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => setState(() => _down = true),
    onTapCancel: () => setState(() => _down = false),
    onTapUp: (_) => setState(() => _down = false),
    onTap: widget.onTap,
    child: AnimatedScale(scale: _down ? 0.96 : 1, duration: const Duration(milliseconds: 150), child: widget.child),
  );
}

class _TypingDots extends StatelessWidget {
  const _TypingDots();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        const _OvaMark(size: 20),
        const SizedBox(width: 10),
        for (var i = 0; i < 3; i++)
          Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: context.textMuted, shape: BoxShape.circle),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true), delay: (140 * i).ms)
              .fadeIn(duration: 300.ms)
              .scaleXY(begin: 0.6, end: 1, duration: 420.ms),
      ],
    ),
  );
}

/// Handles `ova://` links on result cards (special access screens).
Future<void> runOvaInternalUrl(WidgetRef ref, String url) async {
  final hub = ref.read(ovaDeviceHubProvider);
  if (url.startsWith('ova://navigate')) {
    final q = Uri.parse(url).queryParameters;
    final lat = double.tryParse(q['lat'] ?? '');
    final lng = double.tryParse(q['lng'] ?? '');
    if (lat != null && lng != null) await GeoServices.instance.openNavigation(LatLng(lat, lng), mode: q['mode'] ?? 'driving');
    return;
  }
  switch (url) {
    case 'ova://location_settings':
      await Geolocator.openLocationSettings();
    case 'ova://network_settings':
      if (OvaDeviceHub.supported) {
        await hub.openPanel('internet');
      } else {
        await openAppSettings();
      }
    case 'ova://dnd_access':
      await hub.openDndAccess();
    case 'ova://notification_access':
      await hub.openNotificationAccess();
  }
}

/// Status dot: steady blue when ready, breathing pink while Ova works.
class _StatusDot extends StatelessWidget {
  final bool active;
  const _StatusDot({required this.active});

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.brandPink : AppColors.brandBlue,
        boxShadow: [
          BoxShadow(color: (active ? AppColors.brandPink : AppColors.brandBlue).withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
    );
    if (!active) return dot;
    return dot.animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 1, end: 0.35, duration: 650.ms);
  }
}
