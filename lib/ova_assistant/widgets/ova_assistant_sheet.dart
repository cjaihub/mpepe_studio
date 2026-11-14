import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../../agent_workspace/widgets/ova_claude_agent_workspace.dart';
import '../../shared/audio/cloud_dictation.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/audio/speech_hub.dart';
import '../../shared/location/geo_services.dart';
import '../../shared/router.dart' show rootNavigatorKey;
import '../../shared/theme/app_theme.dart';
import '../core/ova_tool_result.dart';
import '../main_interface/ova_live_voice_view.dart';
import '../main_interface/ova_sections_views.dart' show formatRelativeTime;
import '../services/ova_chat_controller.dart';
import '../services/ova_shared_history_service.dart';
import '../services/ova_task_center.dart';
import '../services/ova_voice_session_controller.dart';
import 'ova_confirm_card.dart';
import 'ova_youtube_inline_card.dart';
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
  /// Highlights the mic (never opens it): the user taps to talk.
  final bool autoStartVoice;
  final void Function(String text)? onInsertIntoChat;

  /// Set by hosts without the app router (the system overlay): called instead
  /// of pushing [route] / popping the sheet.
  final void Function(String route)? onOpenRoute;
  final VoidCallback? onClose;

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
    this.onOpenRoute,
    this.onClose,
  });

  @override
  ConsumerState<OvaAssistantPanel> createState() => _OvaAssistantPanelState();
}

class _OvaAssistantPanelState extends ConsumerState<OvaAssistantPanel> {
  late final OvaChatController _chat;
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final SpeechHub _speech = SpeechHub.instance;
  MicLease? _micLease;
  CloudDictation? _cloud;
  bool _usingCloud = false;
  String _dictationPrefix = '';
  OvaOverlayVoiceSessionNotifier? _overlayVoiceNotifier;
  bool _listening = false;
  // Live mic levels while Ova is listening (drives the waveform strip).
  final List<double> _voiceLevels = [];
  DateTime? _listenStart;

  /// Pulses the mic for a few seconds when Ova was opened in voice mode.
  bool _voiceHint = false;

  /// True when the compact Overlay Assistant is in live Voice Mode.
  bool _voiceMode = false;

  /// True when showing the Claude-Style Synced Agent Workspace.
  bool _agentWorkspaceMode = true;

  /// Voice typing: the words as heard, kept so the clean-up can be undone.
  String? _rawDictation;
  bool _tidying = false;
  Uint8List? _screenBytes;
  String? _attachedMediaLabel;
  bool _showAttachTools = false;
  final List<String> _attachedToolChips = [];
  String _selectedPersona = 'Ova Pro';

  @override
  void initState() {
    super.initState();
    _screenBytes = widget.screenContextBytes;
    _voiceMode = widget.autoStartVoice;
    _agentWorkspaceMode =
        !widget.autoStartVoice && widget.onInsertIntoChat == null;
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overlayVoiceNotifier = ref.read(ovaOverlayVoiceSessionProvider.notifier);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChat);
    if (_chat.onNavigate == _navigate) _chat.onNavigate = null;
    if (_voiceMode) {
      try {
        _overlayVoiceNotifier?.endSession();
      } catch (_) {}
    }
    unawaited(_speech.cancel(this));
    unawaited(_cloud?.dispose());
    unawaited(_micLease?.release());
    _micLease = null;
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
    final rawText = (text ?? _input.text).trim();
    if (rawText.isEmpty && _screenBytes == null) return;
    if (_chat.busy) return;
    HapticFeedback.lightImpact();
    if (_listening) unawaited(_stopVoice(commitCloud: false));
    _chat.permissionContext = context;
    final img = _screenBytes != null ? base64Encode(_screenBytes!) : null;
    final prefixParts = <String>[
      if (_selectedPersona != 'Ova Pro') 'Persona: $_selectedPersona',
      ..._attachedToolChips,
    ];
    final effectivePrompt = prefixParts.isNotEmpty
        ? '[${prefixParts.join(" | ")}]\n${rawText.isEmpty ? "Analyze attached media" : rawText}'
        : (rawText.isEmpty ? 'Analyze attached media' : rawText);
    _input.clear();
    setState(() {
      _screenBytes = null;
      _attachedMediaLabel = null;
      _showAttachTools = false;
      _attachedToolChips.clear();
    });
    _chat.send(effectivePrompt, imageBase64: img);
  }

  Future<void> _pickAttachmentImage(ImageSource source) async {
    try {
      HapticFeedback.selectionClick();
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1440,
        imageQuality: 84,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _screenBytes = bytes;
        _attachedMediaLabel =
            source == ImageSource.camera ? 'Camera Snap' : picked.name;
        _showAttachTools = false;
      });
    } catch (e) {
      if (mounted) _snack('Could not attach image: $e');
    }
  }

  Future<void> _attachClipboardSnippet() async {
    HapticFeedback.selectionClick();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = data?.text?.trim() ?? '';
    if (txt.isEmpty) {
      if (mounted) _snack('Clipboard is empty.');
      return;
    }
    final preview = txt.length > 64 ? '${txt.substring(0, 64)}…' : txt;
    setState(() {
      final chip = 'Clipboard: $preview';
      if (!_attachedToolChips.contains(chip)) {
        _attachedToolChips.add(chip);
      }
      _showAttachTools = false;
    });
  }

  void _toggleAttachedToolChip(String label) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_attachedToolChips.contains(label)) {
        _attachedToolChips.remove(label);
      } else {
        _attachedToolChips.add(label);
      }
    });
  }

  void _navigate(String route) {
    HapticFeedback.selectionClick();
    if (widget.onOpenRoute != null) {
      widget.onOpenRoute!(route);
    } else if (widget.isSheet) {
      Navigator.of(context).pop();
      final root = rootNavigatorKey.currentContext;
      if (root != null) GoRouter.of(root).push(route);
    } else {
      context.push(route);
    }
  }

  Future<void> _runAction(OvaResultAction a) async {
    HapticFeedback.selectionClick();
    if (a.url == 'ova://retry_last') {
      await _chat.retryLast();
      return;
    }
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
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (widget.isSheet) {
      Navigator.of(context).pop();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/home');
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stopVoice(commitCloud: true);
      return;
    }
    HapticFeedback.lightImpact();

    PermissionStatus? mic;
    try {
      mic = await Permission.microphone.request();
    } catch (_) {
      mic = null;
    }
    if (!mounted) return;
    if (mic != null && !mic.isGranted) {
      _snack(
        mic.isPermanentlyDenied
            ? 'Microphone is off for Oneova. Turn it on in Settings to talk to Ova.'
            : 'Microphone permission is needed to talk to Ova.',
        action: mic.isPermanentlyDenied ? SnackBarAction(label: 'Settings', onPressed: openAppSettings) : null,
      );
      return;
    }

    final got = await MicCoordinator.instance.acquire(
      MicUser.voiceTyping,
      onPreempted: () async {
        await _stopVoice(commitCloud: false, releaseLease: false);
        _micLease = null;
      },
      onInterruption: (i) {
        if (i == MicInterruption.heldByOtherApp && _listening && mounted) {
          _snack('Another app is using the microphone. Dictation paused.');
          unawaited(_stopVoice(commitCloud: true));
        }
      },
    );
    if (got is MicBusy) {
      if (mounted) _snack(got.message);
      return;
    }
    _micLease = got as MicLease;
    if (!mounted) {
      await _micLease?.release();
      _micLease = null;
      return;
    }

    final existing = _input.text.trim();
    _dictationPrefix = existing.isNotEmpty ? '$existing ' : '';
    _usingCloud = false;

    setState(() {
      _listening = true;
      _voiceHint = false;
      _rawDictation = null;
      _voiceLevels.clear();
      _listenStart = DateTime.now();
    });

    final started = await _speech.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      onStatus: (s) {
        if (!mounted || !_listening || _usingCloud) return;
        if (s == 'done' || s == 'notListening' || s == 'preempted') {
          unawaited(_stopVoice(commitCloud: false));
        }
      },
      onError: (err) {
        if (!mounted || !_listening || _usingCloud) return;
        if (err.errorMsg == 'error_no_match' || err.errorMsg == 'error_speech_timeout') {
          unawaited(_stopVoice(commitCloud: false));
        } else {
          unawaited(_startCloudDictation());
        }
      },
      // Android reports roughly -2…10 dB; map it to 0..1 for the waveform.
      onSoundLevel: (level) {
        if (!mounted || !_listening || _usingCloud) return;
        setState(() {
          _voiceLevels.add(((level + 2) / 12).clamp(0.05, 1.0));
          if (_voiceLevels.length > 140) _voiceLevels.removeRange(0, _voiceLevels.length - 140);
        });
      },
      onResult: (r) {
        if (!mounted || !_listening || _usingCloud) return;
        final combined = '$_dictationPrefix${r.recognizedWords}';
        setState(() {
          _input.text = combined;
          _input.selection = TextSelection.collapsed(offset: _input.text.length);
        });
        // Voice typing: words go into the field and get tidied; the user sends.
        if (r.finalResult && combined.trim().isNotEmpty) _tidyDictation(combined.trim());
      },
    );
    if (!started && mounted && _listening) {
      await _startCloudDictation();
    }
  }

  Future<void> _startCloudDictation() async {
    if (_usingCloud || !mounted || !_listening) return;
    await _speech.cancel(this);
    _usingCloud = true;
    _cloud ??= CloudDictation();
    final ok = await _cloud!.start(
      autoStopOnSilence: true,
      onLevel: (level) {
        if (!mounted || !_listening || !_usingCloud) return;
        setState(() {
          _voiceLevels.add(level.clamp(0.05, 1.0));
          if (_voiceLevels.length > 140) _voiceLevels.removeRange(0, _voiceLevels.length - 140);
        });
      },
      onSilenceCommit: () => unawaited(_stopVoice(commitCloud: true)),
    );
    if (!ok) {
      _usingCloud = false;
      if (mounted) {
        _snack('Voice input is not available on this device. You can still type.');
      }
      await _stopVoice(commitCloud: false);
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Punctuation, filler words and small fixes via the `voiceTidy` function
  /// (Vertex AI). Keeps the raw words if that fails; one tap undoes it.
  Future<void> _tidyDictation(String raw) async {
    setState(() => _tidying = true);
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('voiceTidy').call<Map<String, dynamic>>({'text': raw});
      final clean = (res.data['text'] as String?)?.trim() ?? '';
      if (!mounted) return;
      if (clean.isNotEmpty && clean != raw && _input.text.trim() == raw) {
        setState(() {
          _rawDictation = raw;
          _input.text = clean;
          _input.selection = TextSelection.collapsed(offset: clean.length);
        });
      }
    } catch (_) {
      // Raw dictation stays in the field.
    } finally {
      if (mounted) setState(() => _tidying = false);
    }
  }

  void _undoTidy() {
    final raw = _rawDictation;
    if (raw == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _input.text = raw;
      _input.selection = TextSelection.collapsed(offset: raw.length);
      _rawDictation = null;
    });
  }

  Future<void> _stopVoice({bool commitCloud = true, bool releaseLease = true}) async {
    final wasCloud = _usingCloud;
    _usingCloud = false;
    if (mounted && _listening) setState(() => _listening = false);
    await _speech.stop(this);
    if (wasCloud) {
      if (commitCloud) {
        if (mounted) setState(() => _tidying = true);
        try {
          final words = (await _cloud?.stopAndTranscribe() ?? '').trim();
          if (mounted && words.isNotEmpty) {
            final combined = '$_dictationPrefix$words';
            setState(() {
              _input.text = combined;
              _input.selection = TextSelection.collapsed(offset: combined.length);
            });
            await _tidyDictation(combined.trim());
          }
        } catch (_) {
          // Keep existing input.
        } finally {
          if (mounted) setState(() => _tidying = false);
        }
      } else {
        await _cloud?.cancel();
      }
    }
    if (releaseLease) {
      final lease = _micLease;
      _micLease = null;
      await lease?.release();
    }
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
      mainAxisSize: widget.isSheet ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (widget.isSheet) _grabber(context),
        _header(context),
        Divider(height: 1, thickness: 1, color: context.border),
        if (_voiceMode)
          Flexible(
            child: SingleChildScrollView(
              child: OvaOverlayVoiceCard(
                invocation: widget.invocation,
                onSwitchToText: () {
                  if (mounted) setState(() => _voiceMode = false);
                },
                onCloseOverlay: _close,
                onNavigateRoute: _navigate,
              ),
            ),
          )
        else if (_agentWorkspaceMode)
          if (widget.isSheet)
            SizedBox(
              height: (media.size.height * 0.70).clamp(360.0, 680.0),
              child: OvaAgentWorkspace(
                compactSheet: true,
                screenContextLabel: widget.screenContextLabel,
                onOpenConnectWorkstation: () => _navigate('/connect'),
              ),
            )
          else
            Expanded(
              child: OvaAgentWorkspace(
                screenContextLabel: widget.screenContextLabel,
                onOpenConnectWorkstation: () => _navigate('/connect'),
              ),
            )
        else ...[
          Flexible(child: _chat.isEmpty ? _emptyState(context) : _conversation(context)),
          _composer(context),
        ],
      ],
    );

    if (!widget.isSheet) return body;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.80),
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
    padding: const EdgeInsets.only(top: 7, bottom: 2),
    child: Container(
      width: 34,
      height: 4,
      decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
    ),
  );

  void _setVoiceMode(bool enable) {
    if (_voiceMode == enable) return;
    HapticFeedback.selectionClick();
    if (enable && _listening) {
      unawaited(_stopVoice(commitCloud: false));
    } else if (!enable) {
      ref.read(ovaOverlayVoiceSessionProvider.notifier).endSession();
    }
    setState(() => _voiceMode = enable);
  }

  Widget _header(BuildContext context) {
    final status = _voiceMode
        ? 'Voice overlay'
        : (_agentWorkspaceMode
            ? 'Synced Multi-Agent'
            : (_listening
                ? 'Listening…'
                : (_chat.busy ? 'Working…' : 'Quick overlay')));
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 2),
          IconButton(
            tooltip: widget.isSheet ? 'Close' : 'Back',
            visualDensity: VisualDensity.compact,
            onPressed: _close,
            icon: Icon(widget.isSheet ? Icons.keyboard_arrow_down_rounded : Icons.arrow_back_rounded, size: 21, color: context.textPrimary),
          ),
          const _OvaMark(size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ova',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: context.textPrimary),
                ),
                Row(
                  children: [
                    _StatusDot(active: _voiceMode || _agentWorkspaceMode || _listening || _chat.busy),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Compact [Agent | Quick | Voice] Mode Segmented Switcher
          Container(
            height: 28,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OverlayModeChip(
                  icon: Icons.hub_rounded,
                  label: 'Agent',
                  selected: !_voiceMode && _agentWorkspaceMode,
                  onTap: () {
                    _setVoiceMode(false);
                    setState(() => _agentWorkspaceMode = true);
                  },
                ),
                _OverlayModeChip(
                  icon: Icons.bolt_rounded,
                  label: 'Quick',
                  selected: !_voiceMode && !_agentWorkspaceMode,
                  onTap: () {
                    _setVoiceMode(false);
                    setState(() => _agentWorkspaceMode = false);
                  },
                ),
                _OverlayModeChip(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Voice',
                  selected: _voiceMode,
                  accent: true,
                  onTap: () => _setVoiceMode(true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (!_voiceMode && !_agentWorkspaceMode && !_chat.isEmpty)
            IconButton(
              tooltip: 'Clear quick chat',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                HapticFeedback.selectionClick();
                _chat.reset();
              },
              icon: Icon(Icons.refresh_rounded, size: 18, color: context.textSecondary),
            ),
          if (widget.isSheet)
            IconButton(
              tooltip: 'Open Ova Main Workspace',
              visualDensity: VisualDensity.compact,
              onPressed: () => _navigate('/hub/ai'),
              icon: Icon(Icons.dashboard_customize_outlined, size: 17, color: context.textSecondary),
            ),
          IconButton(
            tooltip: 'Ova settings',
            visualDensity: VisualDensity.compact,
            onPressed: () => _navigate('/ova/abilities'),
            icon: Icon(Icons.tune_rounded, size: 18, color: context.textSecondary),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final inv = widget.invocation;
    final sharedHistory = ref.watch(ovaSharedHistoryProvider);
    final taskCenter = ref.watch(ovaTaskCenterProvider);
    final recentShared = sharedHistory.threads.take(2).toList();
    final recentTasks = taskCenter.tasks.take(2).toList();
    final chips = <_Suggestion>[
      // Mobile money in one tap (Wallet tab: balance, add money, withdraw).
      const _Suggestion(Icons.account_balance_wallet_rounded, 'My wallet', '', accent: true, route: '/hub/wallet'),
      if (inv.contentId != null) const _Suggestion(Icons.favorite_rounded, 'Like this reel', 'like this'),
      if (inv.contentId != null) const _Suggestion(Icons.mode_comment_rounded, 'Comment on this', 'comment ', fill: true),
      if (inv.chatId != null) const _Suggestion(Icons.edit_note_rounded, 'Draft a reply', 'Help me write a friendly reply to this chat'),
      const _Suggestion(Icons.sensors_rounded, 'Go live', 'go live', accent: true),
      const _Suggestion(Icons.search_rounded, 'Search Oneova', 'search ', fill: true),
      const _Suggestion(Icons.call_rounded, 'Call someone', 'call ', fill: true),
      const _Suggestion(Icons.sms_rounded, 'Text someone', 'text  saying ', fill: true),
      const _Suggestion(Icons.timer_rounded, '5 min timer', 'set a timer for 5 minutes'),
      const _Suggestion(Icons.flashlight_on_rounded, 'Flashlight', 'flashlight on'),
      const _Suggestion(Icons.my_location_rounded, 'Where am I?', 'where am i'),
      const _Suggestion(Icons.photo_camera_rounded, 'Take a photo', 'take a photo'),
      const _Suggestion(Icons.upload_rounded, 'Post a video', 'upload'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Quick actions on this screen',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: context.textPrimary,
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                onTap: () => showOvaBrandVoiceEditor(context, ref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.diamond_outlined, size: 13, color: AppColors.brandBlue),
                      const SizedBox(width: 4),
                      Text(
                        'Brand tone',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < chips.length; i++)
                _chip(context, chips[i]).animate(delay: (20 * i).ms).fadeIn(duration: 200.ms).slideY(begin: 0.12, end: 0),
            ],
          ),
          if (recentShared.isNotEmpty || recentTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'RECENT ACTIVITY',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: context.textMuted,
                  ),
                ),
                const Spacer(),
                if (widget.isSheet)
                  InkWell(
                    onTap: () => _navigate('/hub/ai'),
                    child: Text(
                      'Open Workspace →',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (final task in recentTasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        task.running
                            ? Icons.sync_rounded
                            : (task.status == OvaTaskStatus.failed
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded),
                        size: 13,
                        color: task.status == OvaTaskStatus.failed
                            ? AppColors.brandPink
                            : AppColors.brandBlue,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${task.source == 'ai_lab' ? 'Main' : 'Overlay'} · ${formatRelativeTime(task.startedAt)}',
                        style: GoogleFonts.inter(fontSize: 10, color: context.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            for (final thread in recentShared)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () {
                    _input.text = thread.title;
                    _input.selection = TextSelection.collapsed(offset: _input.text.length);
                    _focus.requestFocus();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        Icon(thread.source.icon, size: 13, color: AppColors.brandBlue),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${thread.source.badgeLabel} · ${formatRelativeTime(thread.updatedAt)}',
                          style: GoogleFonts.inter(fontSize: 10, color: context.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
          if (_screenBytes != null) ...[const SizedBox(height: 12), _screenPreview(context)],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, _Suggestion s) {
    return _Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        if (s.route != null) {
          Navigator.of(context).maybePop();
          final nav = rootNavigatorKey.currentContext;
          if (nav != null) GoRouter.of(nav).go(s.route!);
          return;
        }
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

  Widget _userBubble(BuildContext context, OvaItem item) {
    final ytVideoId = OvaYouTubeInlineCard.extractVideoId(item.text);
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
            if (ytVideoId != null) OvaYouTubeInlineCard(videoId: ytVideoId),
          ],
        ),
      ),
    );
  }

  Widget _assistantText(BuildContext context, OvaItem item) {
    final style = GoogleFonts.inter(fontSize: 13, height: 1.4, color: context.textPrimary);
    final ytVideoId = OvaYouTubeInlineCard.extractVideoId(item.text);
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
              if (ytVideoId != null) OvaYouTubeInlineCard(videoId: ytVideoId),
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
    final isInfo = r?.ok == true;
    final accent = isInfo ? AppColors.brandBlue : AppColors.brandPink;
    return _cardShell(
      context,
      borderColor: accent.withValues(alpha: 0.35),
      fill: accent.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(r?.icon ?? Icons.info_outline_rounded, size: 15, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (r?.title != null && r!.title!.trim().isNotEmpty) ...[
                      Text(
                        r.title!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      item.text,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r != null && r.actions.isNotEmpty) ...[
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
          _attachedMediaLabel ?? widget.screenContextLabel ?? 'Screen attached',
          style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textPrimary),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
          onPressed: () => setState(() {
            _screenBytes = null;
            _attachedMediaLabel = null;
          }),
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
              unawaited(_stopVoice(commitCloud: false));
              setState(() => _input.clear());
            },
          ),
          IconButton(
            tooltip: 'Send now',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.send_rounded, size: 18, color: AppColors.brandBlue),
            onPressed: (_input.text.trim().isEmpty && !_usingCloud)
                ? null
                : () async {
                    HapticFeedback.lightImpact();
                    await _stopVoice(commitCloud: true);
                    if (mounted) _send();
                  },
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.15, end: 0);
  }

  Widget _avatarPersonaBar(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL ?? '';
    final displayName = (user?.displayName ?? '').trim();
    final initial = displayName.isNotEmpty
        ? displayName.characters.first.toUpperCase()
        : (user?.email?.isNotEmpty == true ? user!.email!.characters.first.toUpperCase() : 'U');
    final personas = <({String id, String label, IconData icon})>[
      (id: 'Ova Core', label: 'Ova Core', icon: Icons.auto_awesome_rounded),
      (id: 'Director', label: 'Director', icon: Icons.movie_filter_rounded),
      (id: 'Coder', label: 'Coder', icon: Icons.terminal_rounded),
      (id: 'Strategist', label: 'Strategist', icon: Icons.trending_up_rounded),
      (id: 'Mac Agent', label: 'Mac Agent', icon: Icons.laptop_mac_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Animated AI Avatar Orb + Persona indicator
            Container(
              padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: _chat.busy ? AppColors.brandPink : AppColors.brandBlue.withValues(alpha: 0.55),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.brandBlue, AppColors.brandPink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.brandWhite),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _chat.busy ? AppColors.brandPink : AppColors.brandBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.surface, width: 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selectedPersona,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            for (final p in personas) ...[
              if (p.id != _selectedPersona)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedPersona = p.id);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: context.border, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(p.icon, size: 11.5, color: context.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            p.label,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(width: 4),
            // User avatar badge
            Container(
              padding: const EdgeInsets.fromLTRB(3, 2, 7, 2),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.border, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: AppColors.brandBlue,
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? Text(
                            initial,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandWhite,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    displayName.isNotEmpty ? displayName.split(' ').first : 'You',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachToolsBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _attachToolTile(
              context,
              icon: Icons.photo_library_outlined,
              label: 'Photo',
              accent: AppColors.brandBlue,
              onTap: () => _pickAttachmentImage(ImageSource.gallery),
            ),
            const SizedBox(width: 6),
            _attachToolTile(
              context,
              icon: Icons.photo_camera_outlined,
              label: 'Camera',
              accent: AppColors.brandPink,
              onTap: () => _pickAttachmentImage(ImageSource.camera),
            ),
            const SizedBox(width: 6),
            _attachToolTile(
              context,
              icon: Icons.content_paste_rounded,
              label: 'Clipboard',
              accent: AppColors.brandBlue,
              onTap: _attachClipboardSnippet,
            ),
            const SizedBox(width: 6),
            _attachToolTile(
              context,
              icon: Icons.travel_explore_rounded,
              label: 'Web Search',
              accent: AppColors.brandBlue,
              active: _attachedToolChips.contains('Web Search'),
              onTap: () => _toggleAttachedToolChip('Web Search'),
            ),
            const SizedBox(width: 6),
            _attachToolTile(
              context,
              icon: Icons.laptop_mac_rounded,
              label: 'My Computer',
              accent: AppColors.brandPink,
              active: _attachedToolChips.contains('My Computer'),
              onTap: () => _toggleAttachedToolChip('My Computer'),
            ),
            const SizedBox(width: 6),
            _attachToolTile(
              context,
              icon: Icons.auto_fix_high_rounded,
              label: 'Studio Grade',
              accent: AppColors.brandBlue,
              active: _attachedToolChips.contains('Studio Grade'),
              onTap: () => _toggleAttachedToolChip('Studio Grade'),
            ),
            const SizedBox(width: 6),
            _attachToolTile(
              context,
              icon: Icons.record_voice_over_rounded,
              label: 'Voice Avatar',
              accent: AppColors.brandPink,
              active: _voiceMode,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _showAttachTools = false);
                _setVoiceMode(!_voiceMode);
              },
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 160.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _attachToolTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: context.isDark ? 0.22 : 0.12) : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: active ? accent : context.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: active ? accent : context.textPrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? accent : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final busy = _chat.busy;
    final hasInput = _input.text.trim().isNotEmpty || _screenBytes != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatarPersonaBar(context),
          if (_showAttachTools) _attachToolsBar(context),
          if (_attachedToolChips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final chip in _attachedToolChips)
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 3, 5, 3),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.45), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 11, color: AppColors.brandBlue),
                          const SizedBox(width: 3),
                          Text(
                            chip,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _toggleAttachedToolChip(chip),
                            child: Icon(Icons.close_rounded, size: 12, color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_screenBytes != null && !_chat.isEmpty) ...[_screenPreview(context), const SizedBox(height: 8)],
          if (_listening) ...[_liveListeningStrip(context), const SizedBox(height: 8)],
          if (_tidying || _rawDictation != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(_tidying ? Icons.auto_fix_high_rounded : Icons.check_circle_rounded, size: 13, color: AppColors.brandBlue),
                const SizedBox(width: 6),
                Text(_tidying ? 'Cleaning up what you said…' : 'Cleaned up',
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
                const Spacer(),
                if (_rawDictation != null)
                  GestureDetector(
                    onTap: _undoTidy,
                    child: Text('Undo', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                  ),
              ]),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _roundButton(
                icon: _showAttachTools ? Icons.close_rounded : Icons.add_rounded,
                color: _showAttachTools
                    ? AppColors.brandBlue.withValues(alpha: 0.16)
                    : context.surfaceMid,
                iconColor: _showAttachTools ? AppColors.brandBlue : context.textPrimary,
                border: true,
                tooltip: 'Attach & Agent Tools',
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _showAttachTools = !_showAttachTools);
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() => _rawDictation = null),
                  style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                  cursorColor: AppColors.brandBlue,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _listening
                        ? 'Listening… speak naturally'
                        : (_voiceHint ? 'Tap the mic to talk' : 'Ask $_selectedPersona or attach media/tools…'),
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                    filled: true,
                    fillColor: context.surfaceMid,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: _input.text.trim().length > 6 && !_tidying
                        ? IconButton(
                            tooltip: 'AI Polish prompt',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.auto_fix_high_rounded, size: 15, color: AppColors.brandBlue),
                            onPressed: () => _tidyDictation(_input.text.trim()),
                          )
                        : null,
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
                iconColor: _listening ? AppColors.brandWhite : context.textPrimary,
                border: !_listening,
                tooltip: _listening ? 'Stop listening' : 'Dictate',
                onTap: _toggleVoice,
                pulse: _listening || _voiceHint,
              ),
              const SizedBox(width: 6),
              _roundButton(
                icon: busy ? Icons.stop_circle_outlined : Icons.arrow_upward_rounded,
                color: busy || hasInput ? AppColors.brandBlue : AppColors.brandBlue.withValues(alpha: 0.35),
                iconColor: AppColors.brandWhite,
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

  /// Opens this screen instead of sending a prompt.
  final String? route;
  const _Suggestion(this.icon, this.label, this.prompt, {this.fill = false, this.accent = false, this.route});
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

/// Compact pill segment inside the `[Chat | Voice]` switcher in Ova Overlay Assistant.
class _OverlayModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool accent;
  final VoidCallback onTap;

  const _OverlayModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = accent ? AppColors.brandPink : AppColors.brandBlue;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? activeBg : AppColors.brandWhite.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected ? AppColors.brandWhite : context.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? AppColors.brandWhite : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
