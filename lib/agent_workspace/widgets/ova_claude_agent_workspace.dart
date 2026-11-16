import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../desktop_agent/macos_mouse_ffi.dart';
import '../../ova_assistant/services/ova_shared_history_service.dart';
import '../../shared/services/oneova_language_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/theme_provider.dart';
import '../ova_agent_models.dart';
import '../ova_agent_sync_controller.dart';
import '../ova_wispr_flow_service.dart';
import 'oneova_workstation_auth_dialog.dart';
import '../../hub/phone_controller/widgets/computer_sidebar_card.dart';
import 'ova_live_input_deck.dart' show OvaWisprStudioView;

/// Executive Autonomous Agentic, Wispr Voice Flow & Live Trackpad/Keyboard
/// Workstation Studio — synced in real time across Oneova Desktop & Mobile.
typedef OvaAgentWorkspace = OvaClaudeAgentWorkspace;

class OvaClaudeAgentWorkspace extends ConsumerStatefulWidget {
  final bool compactSheet;
  final bool showSessionSidebar;
  final double bottomClearance;
  final String? initialPrompt;
  final String? screenContextLabel;
  final VoidCallback? onOpenConnectWorkstation;
  final VoidCallback? onDisconnect;
  final VoidCallback? onToggleBridges;
  final VoidCallback? onOpenAuth;

  const OvaClaudeAgentWorkspace({
    super.key,
    this.compactSheet = false,
    this.showSessionSidebar = false,
    this.bottomClearance = 10.0,
    this.initialPrompt,
    this.screenContextLabel,
    this.onOpenConnectWorkstation,
    this.onDisconnect,
    this.onToggleBridges,
    this.onOpenAuth,
  });

  @override
  ConsumerState<OvaClaudeAgentWorkspace> createState() =>
      _OvaClaudeAgentWorkspaceState();
}

class _OvaClaudeAgentWorkspaceState
    extends ConsumerState<OvaClaudeAgentWorkspace> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final OvaWisprFlowService _wispr = OvaWisprFlowService();

  final Set<String> _attachedContexts = {};
  bool _showAttachTray = false;
  Uint8List? _attachedMediaThumb;
  String? _attachedMediaName;
  List<double> _waveformBars = List<double>.filled(18, 0.08);
  Timer? _recordingTicker;
  int _recordingSeconds = 0;
  bool _wisprRecording = false;
  bool _wisprProcessing = false;
  bool _polishingDraft = false;

  bool _showSlashCommands = false;
  int _lastTurnCount = 0;

  // Layout adjustability & Oneova Agent workspace controls
  double _sidebarWidth = 260.0;
  bool _sidebarCollapsed = false;
  double _artifactPanelWidth = 430.0;
  double _composerHeight = 118.0;
  bool _composerExpanded = false;

  // Built-in in-conversation search ("Find in Chat" ⌘F)
  bool _showInChatSearch = false;
  String _inChatSearchQuery = '';
  final TextEditingController _inChatSearchController =
      TextEditingController();
  final FocusNode _inChatSearchFocus = FocusNode();
  int _activeSearchMatchIndex = 0;
  final List<int> _searchMatchTurnIndices = [];

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static const List<({String cmd, String label, String prompt, IconData icon})>
      _slashCommands = [
    (
      cmd: '/search',
      label: 'Search the live web for fresh facts, links & citations',
      prompt: 'Search the web for: ',
      icon: Icons.public_rounded,
    ),
    (
      cmd: '/find',
      label: 'Search workspace files, code & scripts',
      prompt: 'Search workspace files for: ',
      icon: Icons.search_rounded,
    ),
    (
      cmd: '/inspect',
      label: 'Full Mac health, display, cursor & active apps',
      prompt:
          'Inspect my connected Mac workstation health, display resolution, cursor coordinates, foreground window, running apps, and disk space.',
      icon: Icons.monitor_heart_outlined,
    ),
    (
      cmd: '/screen',
      label: 'Capture live screen & open window context',
      prompt:
          'Capture my Mac screen context, visible windows, and clipboard preview, then summarize what is currently open.',
      icon: Icons.screenshot_monitor_rounded,
    ),
    (
      cmd: '/windows',
      label: 'List every visible macOS application window',
      prompt:
          'List all open application windows on my Mac and organize them by app.',
      icon: Icons.web_asset_rounded,
    ),
    (
      cmd: '/type',
      label: 'Type or paste polished text into active Mac app',
      prompt: 'Type into my currently focused Mac window: ',
      icon: Icons.keyboard_rounded,
    ),
    (
      cmd: '/click',
      label: 'Move mouse or click UI coordinates on Mac',
      prompt: 'Perform this mouse action on my Mac: ',
      icon: Icons.mouse_rounded,
    ),
    (
      cmd: '/applescript',
      label: 'Automate any macOS app via AppleScript',
      prompt: 'Automate my Mac using AppleScript to: ',
      icon: Icons.integration_instructions_outlined,
    ),
    (
      cmd: '/terminal',
      label: 'Execute zsh command on Mac & inspect output',
      prompt: 'Run this terminal check on my Mac: ',
      icon: Icons.terminal_rounded,
    ),
    (
      cmd: '/files',
      label: 'Inspect Desktop & project directory files',
      prompt: 'List the files and folders in ~/Desktop and summarize them.',
      icon: Icons.folder_open_rounded,
    ),
    (
      cmd: '/nle',
      label: 'Studio NLE timeline save & export prep',
      prompt:
          'Save my active NLE timeline project and prepare a pre-export checklist.',
      icon: Icons.movie_creation_outlined,
    ),
    (
      cmd: '/plan',
      label: 'Build autonomous multi-step execution plan',
      prompt: 'Break down and execute a step-by-step plan for: ',
      icon: Icons.checklist_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null &&
        widget.initialPrompt!.trim().isNotEmpty) {
      _inputController.text = widget.initialPrompt!.trim();
    }
    if (widget.screenContextLabel != null &&
        widget.screenContextLabel!.trim().isNotEmpty) {
      _attachedContexts.add('Screen: ${widget.screenContextLabel!}');
    }
    _inputController.addListener(_handleComposerTextChange);
  }

  @override
  void dispose() {
    _recordingTicker?.cancel();
    unawaited(_wispr.dispose());
    _inputController.removeListener(_handleComposerTextChange);
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    _inChatSearchController.dispose();
    _inChatSearchFocus.dispose();
    super.dispose();
  }

  void _toggleInChatSearch() {
    setState(() {
      _showInChatSearch = !_showInChatSearch;
      if (_showInChatSearch) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _inChatSearchFocus.requestFocus();
        });
      } else {
        _inChatSearchQuery = '';
        _inChatSearchController.clear();
        _searchMatchTurnIndices.clear();
      }
    });
  }

  void _performInChatSearch(String query, List<OvaAgentTurn> turns) {
    final q = query.trim().toLowerCase();
    setState(() {
      _inChatSearchQuery = q;
      _searchMatchTurnIndices.clear();
      if (q.isNotEmpty) {
        for (var i = 0; i < turns.length; i++) {
          final t = turns[i];
          final textMatch = t.text.toLowerCase().contains(q);
          final thinkMatch =
              t.thinkingSteps.any((s) => s.toLowerCase().contains(q));
          final artMatch = t.artifacts.any((a) =>
              a.title.toLowerCase().contains(q) ||
              a.content.toLowerCase().contains(q));
          if (textMatch || thinkMatch || artMatch) {
            _searchMatchTurnIndices.add(i);
          }
        }
        _activeSearchMatchIndex = 0;
      }
    });
    if (_searchMatchTurnIndices.isNotEmpty) {
      _scrollToTurnIndex(_searchMatchTurnIndices[0]);
    }
  }

  void _nextSearchMatch() {
    if (_searchMatchTurnIndices.isEmpty) return;
    setState(() {
      _activeSearchMatchIndex =
          (_activeSearchMatchIndex + 1) % _searchMatchTurnIndices.length;
    });
    _scrollToTurnIndex(_searchMatchTurnIndices[_activeSearchMatchIndex]);
  }

  void _previousSearchMatch() {
    if (_searchMatchTurnIndices.isEmpty) return;
    setState(() {
      _activeSearchMatchIndex = (_activeSearchMatchIndex -
              1 +
              _searchMatchTurnIndices.length) %
          _searchMatchTurnIndices.length;
    });
    _scrollToTurnIndex(_searchMatchTurnIndices[_activeSearchMatchIndex]);
  }

  void _scrollToTurnIndex(int index) {
    if (!_scrollController.hasClients) return;
    final turns = ref.read(ovaAgentSyncProvider).turns;
    if (turns.isEmpty) return;
    final ratio = (index / turns.length).clamp(0.0, 1.0);
    final target = _scrollController.position.maxScrollExtent * ratio;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
    );
  }

  void _handleComposerTextChange() {
    final text = _inputController.text;
    final shouldShow = text.startsWith('/') && !text.contains(' ');
    if (shouldShow != _showSlashCommands && mounted) {
      setState(() => _showSlashCommands = shouldShow);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Wispr Flow Voice Dictation & Polish Lifecycle (Mac + Mobile)
  // ---------------------------------------------------------------------------

  Future<void> _toggleWisprMic() async {
    if (_wisprProcessing) return;
    if (_wisprRecording) {
      await _finishWisprRecordingAndCommit();
      return;
    }

    HapticFeedback.lightImpact();
    final wsState = ref.read(ovaAgentSyncProvider);
    final res = await _wispr.startRecording(
      autoStopOnSilence: wsState.handsFreeWispr,
      onLevel: (lvl) {
        if (!mounted || !_wisprRecording) return;
        setState(() {
          _waveformBars = [..._waveformBars.sublist(1), lvl];
        });
      },
      onAutoSilenceCommit: () {
        if (mounted && _wisprRecording) {
          unawaited(_finishWisprRecordingAndCommit());
        }
      },
      onPreemptedByCall: () {
        if (!mounted) return;
        _recordingTicker?.cancel();
        setState(() {
          _wisprRecording = false;
          _recordingSeconds = 0;
        });
      },
    );

    if (!res.started) {
      if (mounted && res.error != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              res.error!,
              style: GoogleFonts.inter(fontSize: 12),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.brandPink,
          ),
        );
      }
      return;
    }

    _recordingTicker?.cancel();
    setState(() {
      _wisprRecording = true;
      _recordingSeconds = 0;
      _waveformBars = List<double>.filled(18, 0.12);
    });
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _wisprRecording) {
        setState(() => _recordingSeconds++);
      }
    });
  }

  Future<void> _cancelWisprRecording() async {
    HapticFeedback.lightImpact();
    _recordingTicker?.cancel();
    await _wispr.cancel();
    if (!mounted) return;
    setState(() {
      _wisprRecording = false;
      _wisprProcessing = false;
      _recordingSeconds = 0;
      _waveformBars = List<double>.filled(18, 0.08);
    });
  }

  Future<void> _finishWisprRecordingAndCommit() async {
    _recordingTicker?.cancel();
    if (!mounted) return;
    setState(() {
      _wisprRecording = false;
      _wisprProcessing = true;
    });

    final wsState = ref.read(ovaAgentSyncProvider);
    final notifier = ref.read(ovaAgentSyncProvider.notifier);

    try {
      final result = await _wispr.stopAndTranscribe(
        style: 'auto',
        activeWindow: wsState.workstationActiveWindow ?? '',
        deviceId: wsState.workstationDeviceId,
      );

      if (!mounted) return;
      setState(() {
        _wisprProcessing = false;
        _recordingSeconds = 0;
        _waveformBars = List<double>.filled(18, 0.08);
      });

      if (result.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'No speech detected — try speaking closer to your microphone.',
              style: GoogleFonts.inter(fontSize: 12),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      HapticFeedback.selectionClick();
      final text = result.polishedText;

      switch (wsState.wisprTarget) {
        case OvaWisprTarget.macCursor:
          final ok = await notifier.injectWisprToMacCursor(text);
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  ok
                      ? 'Wispr typed into ${wsState.workstationActiveWindow ?? "Mac"}: "${text.length > 48 ? "${text.substring(0, 48)}…" : text}"'
                      : 'Mac offline — placed polished speech in composer instead.',
                  style: GoogleFonts.inter(fontSize: 12),
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.brandBlue,
              ),
            );
            if (!ok) {
              _appendToComposer(text);
            }
          }
        case OvaWisprTarget.autoSendAgent:
          notifier.recordWisprHistoryItem(
            text: text,
            targetLabel: 'Voice → Agent',
          );
          await _submitPrompt(text);
        case OvaWisprTarget.composer:
          notifier.recordWisprHistoryItem(
            text: text,
            targetLabel: 'Composer',
          );
          _appendToComposer(text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wisprProcessing = false;
        _recordingSeconds = 0;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Wispr transcription notice: $e',
            style: GoogleFonts.inter(fontSize: 12),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.brandPink,
        ),
      );
    }
  }

  void _appendToComposer(String text) {
    final cur = _inputController.text.trim();
    final combined = cur.isEmpty ? text : '$cur $text';
    _inputController.text = combined;
    _inputController.selection =
        TextSelection.collapsed(offset: combined.length);
    _inputFocus.requestFocus();
    setState(() {});
  }

  Future<void> _polishDraftInComposer() async {
    final draft = _inputController.text.trim();
    if (draft.isEmpty || _polishingDraft) return;
    HapticFeedback.selectionClick();
    setState(() => _polishingDraft = true);
    try {
      final wsState = ref.read(ovaAgentSyncProvider);
      final polished = await _wispr.tidyOrTransformText(
        text: draft,
        activeWindow: wsState.workstationActiveWindow ?? '',
        deviceId: wsState.workstationDeviceId,
      );
      if (mounted && polished.isNotEmpty) {
        _inputController.text = polished;
        _inputController.selection =
            TextSelection.collapsed(offset: polished.length);
      }
    } finally {
      if (mounted) setState(() => _polishingDraft = false);
    }
  }

  Future<void> _submitPrompt([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    final wsState = ref.read(ovaAgentSyncProvider);
    final chips = <String>[
      ..._attachedContexts,
      if (_attachedContexts.contains('Active Window') &&
          wsState.workstationActiveWindow != null)
        'Active Window: ${wsState.workstationActiveWindow}',
      if (_attachedContexts.contains('Workstation Host') &&
          wsState.workstationName != null)
        'Host: ${wsState.workstationName}',
    ];

    if (preset == null) {
      _inputController.clear();
    }
    setState(() => _showSlashCommands = false);

    await ref.read(ovaAgentSyncProvider.notifier).sendPrompt(
          text,
          contextChips: chips,
          screenContextLabel: widget.screenContextLabel,
        );
    _scrollToBottom();
  }

  Future<void> _confirmDeleteSession(OvaAgentSession session) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          'Delete Agent Session?',
          style: GoogleFonts.inter(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          'This removes "${session.title}" from both Mobile and Desktop.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: ctx.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ctx.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: AppColors.brandWhite,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(ovaAgentSyncProvider.notifier).deleteSession(session.id);
    }
  }

  void _openMobileSessionsDrawer(OvaAgentWorkspaceState state) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: sheetCtx.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: sheetCtx.border, width: 1.0),
          ),
          child: SafeArea(
            top: false,
            child: _SessionListPane(
              isSheet: true,
              onSessionSelected: () => Navigator.pop(sheetCtx),
              onDeleteSession: (s) async {
                Navigator.pop(sheetCtx);
                await _confirmDeleteSession(s);
              },
            ),
          ),
        );
      },
    );
  }

  void _openArtifactSheet(OvaAgentArtifact artifact) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.80,
          decoration: BoxDecoration(
            color: sheetCtx.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: sheetCtx.border, width: 1.0),
          ),
          child: SafeArea(
            top: false,
            child: _ArtifactInspectorPane(
              artifact: artifact,
              onClose: () => Navigator.pop(sheetCtx),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaAgentSyncProvider);
    if (state.turns.length != _lastTurnCount) {
      _lastTurnCount = state.turns.length;
      _scrollToBottom();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideDesktop =
            widget.showSessionSidebar && constraints.maxWidth >= 880;
        final canDockArtifact = wideDesktop &&
            constraints.maxWidth >= 1140 &&
            state.inspectedArtifact != null;

        return Focus(
          autofocus: false,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              final isMeta = HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed;
              if (isMeta && event.logicalKey == LogicalKeyboardKey.keyF) {
                _toggleInChatSearch();
                return KeyEventResult.handled;
              }
              if (isMeta && event.logicalKey == LogicalKeyboardKey.keyB) {
                if (wideDesktop) {
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed);
                  return KeyEventResult.handled;
                }
              }
              if (isMeta && event.logicalKey == LogicalKeyboardKey.keyK) {
                ref.read(ovaAgentSyncProvider.notifier).startNewSession();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (_showInChatSearch) {
                  setState(() => _showInChatSearch = false);
                  return KeyEventResult.handled;
                }
                if (_showSlashCommands) {
                  setState(() => _showSlashCommands = false);
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wideDesktop && !_sidebarCollapsed) ...[
                SizedBox(
                  width: _sidebarWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.surface,
                      border: Border(
                        right: BorderSide(color: context.border, width: 1.0),
                      ),
                    ),
                    child: _SessionListPane(
                      isSheet: false,
                      onDeleteSession: _confirmDeleteSession,
                      onCollapse: () => setState(() => _sidebarCollapsed = true),
                    ),
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _sidebarWidth = (_sidebarWidth + details.delta.dx)
                            .clamp(200.0, 420.0);
                      });
                    },
                    child: Container(
                      width: 5,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 1,
                          color: context.border,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Container(
                  color: context.bg,
                  child: Column(
                    children: [
                      _buildExecutiveCommandHeader(
                        context,
                        state,
                        showDrawerBtn: !wideDesktop,
                        isSidebarCollapsed: wideDesktop && _sidebarCollapsed,
                        onToggleSidebar: () => setState(
                          () => _sidebarCollapsed = !_sidebarCollapsed,
                        ),
                      ),
                      if (_showInChatSearch)
                        _buildInChatSearchBar(context, state),
                      if (state.errorBanner != null)
                        _buildErrorBanner(context, state.errorBanner!),
                      if (state.isBusy &&
                          state.viewMode == OvaWorkspaceViewMode.agentChat)
                        _buildBackgroundActivityPill(context, state),
                      Expanded(
                        child: switch (state.viewMode) {
                          OvaWorkspaceViewMode.wisprStudio => OvaWisprStudioView(
                              isRecording: _wisprRecording,
                              isProcessing: _wisprProcessing,
                              waveformBars: _waveformBars,
                              recordingSeconds: _recordingSeconds,
                              onToggleMic: _toggleWisprMic,
                              onCancelMic: _cancelWisprRecording,
                              wisprService: _wispr,
                              onInsertToComposer: (txt) {
                                ref
                                    .read(ovaAgentSyncProvider.notifier)
                                    .setViewMode(OvaWorkspaceViewMode.agentChat);
                                _appendToComposer(txt);
                              },
                              onSendToAgent: (txt) {
                                ref
                                    .read(ovaAgentSyncProvider.notifier)
                                    .setViewMode(OvaWorkspaceViewMode.agentChat);
                                _submitPrompt(txt);
                              },
                            ),
                          // Mouse/keyboard controls moved out of the chat:
                          // they live in the sidebar's Computer card.
                          OvaWorkspaceViewMode.agentChat ||
                          OvaWorkspaceViewMode.inputDeck => state.turns.isEmpty
                              ? _buildAgentLanding(context, state)
                              : _buildTimeline(
                                  context,
                                  state,
                                  dockArtifacts: canDockArtifact,
                                ),
                        },
                      ),
                      if (state.viewMode == OvaWorkspaceViewMode.agentChat) ...[
                        if (_showSlashCommands) _buildSlashMenu(context),
                        _buildExecutiveComposer(context, state),
                      ],
                    ],
                  ),
                ),
              ),
              if (canDockArtifact) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _artifactPanelWidth =
                            (_artifactPanelWidth - details.delta.dx)
                                .clamp(320.0, 720.0);
                      });
                    },
                    child: Container(
                      width: 5,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 1,
                          color: context.border,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: _artifactPanelWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.surface,
                      border: Border(
                        left: BorderSide(color: context.border, width: 1.0),
                      ),
                    ),
                    child: _ArtifactInspectorPane(
                      artifact: state.inspectedArtifact!,
                      onClose: () => ref
                          .read(ovaAgentSyncProvider.notifier)
                          .inspectArtifact(null),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Top Executive Command Bar (Surfaces, Full Computer Access, Sync & Modes)
  // ---------------------------------------------------------------------------

  void _openChatToolsSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: sheetCtx.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border.all(color: sheetCtx.border, width: 1.0),
        ),
        child: SafeArea(
          top: false,
          child: Consumer(
            builder: (ctx, ref, _) {
              final s = ref.watch(ovaAgentSyncProvider);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat tools',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ctx.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildWebSearchPill(ctx, s),
                        _buildMemoriesPill(ctx, s),
                        _buildFullAccessPill(ctx, s),
                        _buildSyncBadge(ctx, s),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildExecutiveCommandHeader(
    BuildContext context,
    OvaAgentWorkspaceState state, {
    required bool showDrawerBtn,
    bool isSidebarCollapsed = false,
    VoidCallback? onToggleSidebar,
  }) {
    final notifier = ref.read(ovaAgentSyncProvider.notifier);
    final activeTitle = state.activeSession?.title ?? 'New Agent Thread';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        children: [
          // Sidebar Toggle (⌘B)
          if (isSidebarCollapsed) ...[
            Tooltip(
              message: 'Show chats sidebar (⌘B)',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: onToggleSidebar,
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: const Icon(
                    Icons.view_sidebar_outlined,
                    size: 15,
                    color: AppColors.brandBlue,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (showDrawerBtn) ...[
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _openMobileSessionsDrawer(state),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.view_sidebar_outlined, size: 14),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text(
                        activeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (!showDrawerBtn && state.activeSession != null) ...[
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => _promptRenameSession(state),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 130),
                      child: Text(
                        activeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.edit_outlined,
                        size: 12, color: context.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Compact Agent Mode Popover Menu: [ ⚡ Auto Agent ▾ ]
          _buildCompactModeMenu(context, state, notifier),
          const SizedBox(width: 6),

          const Spacer(),

          // Clean header: find + one tools button. Web search, memories,
          // computer access and sync live in the tools sheet; computer
          // controls live in the sidebar, not in the chat.
          _HeaderIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Find in chat (⌘F)',
            active: _showInChatSearch,
            onTap: _toggleInChatSearch,
          ),
          const SizedBox(width: 6),
          _HeaderIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Chat tools',
            onTap: () => _openChatToolsSheet(),
          ),
          const SizedBox(width: 6),

          // Artifacts badge
          if (state.allArtifacts.isNotEmpty) ...[
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                final art = state.inspectedArtifact ?? state.allArtifacts.last;
                if (MediaQuery.of(context).size.width >= 1140 &&
                    widget.showSessionSidebar) {
                  notifier.inspectArtifact(art);
                } else {
                  _openArtifactSheet(art);
                }
              },
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.38),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.code_rounded,
                        size: 14, color: AppColors.brandPink),
                    const SizedBox(width: 4),
                    Text(
                      '${state.allArtifacts.length}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandPink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Theme Toggle (☀️ / 🌙)
          Tooltip(
            message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                final current = ref.read(themeProvider);
                ref.read(themeProvider.notifier).setThemeMode(
                      current == ThemeMode.light
                          ? ThemeMode.dark
                          : ThemeMode.light,
                    );
              },
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  size: 15,
                  color: context.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Account / Mobile Auth Profile Pill
          Tooltip(
            message: state.authUid != null
                ? 'Account: ${state.displayAccountName} (Click to manage)'
                : 'Sign In with Mobile Account',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                HapticFeedback.lightImpact();
                if (widget.onOpenAuth != null) {
                  widget.onOpenAuth!();
                } else {
                  OneovaWorkstationAuthDialog.show(context);
                }
              },
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: state.authUid != null
                        ? AppColors.brandBlue.withValues(alpha: 0.35)
                        : context.border,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppColors.brandBlue, AppColors.brandPink],
                        ),
                        image: state.authPhotoUrl != null &&
                                state.authPhotoUrl!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(state.authPhotoUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: state.authPhotoUrl == null ||
                              state.authPhotoUrl!.isEmpty
                          ? Text(
                              state.accountAvatarInitial,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        state.displayAccountName.split(' ').first,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.authUid != null
                            ? const Color(0xFF10B981)
                            : AppColors.brandPink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // New Chat Button [ + New ]
          Tooltip(
            message: 'New chat (⌘K)',
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () {
                HapticFeedback.lightImpact();
                notifier.startNewSession();
              },
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 15, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      'New',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // More Options Menu (⋮)
          if (widget.onDisconnect != null || widget.onToggleBridges != null) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              tooltip: 'Workstation Options',
              icon: Icon(Icons.more_vert_rounded,
                  size: 17, color: context.textSecondary),
              color: context.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: context.border, width: 1.0),
              ),
              onSelected: (val) {
                if (val == 'bridges') {
                  widget.onToggleBridges?.call();
                } else if (val == 'disconnect') {
                  widget.onDisconnect?.call();
                }
              },
              itemBuilder: (ctx) => [
                if (widget.onToggleBridges != null)
                  PopupMenuItem(
                    value: 'bridges',
                    height: 34,
                    child: Row(
                      children: [
                        const Icon(Icons.memory_rounded,
                            size: 15, color: AppColors.brandBlue),
                        const SizedBox(width: 8),
                        Text('Hardware & Bridges',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: ctx.textPrimary)),
                      ],
                    ),
                  ),
                if (widget.onDisconnect != null)
                  PopupMenuItem(
                    value: 'disconnect',
                    height: 34,
                    child: Row(
                      children: [
                        const Icon(Icons.link_off_rounded,
                            size: 15, color: AppColors.brandPink),
                        const SizedBox(width: 8),
                        Text('Disconnect Workstation',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: AppColors.brandPink)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactModeMenu(
    BuildContext context,
    OvaAgentWorkspaceState state,
    OvaAgentSyncNotifier notifier,
  ) {
    return PopupMenuButton<dynamic>(
      tooltip: 'Agent Persona & Effort Level',
      color: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: context.border, width: 1.0),
      ),
      onSelected: (item) {
        if (item is OvaAgentMode) {
          notifier.setAgentMode(item);
        } else if (item is OvaAgentEffort) {
          notifier.setEffort(item);
        }
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(state.selectedMode.icon, size: 14, color: AppColors.brandBlue),
            const SizedBox(width: 5),
            Text(
              state.selectedMode.label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down_rounded,
                size: 16, color: context.textSecondary),
          ],
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 24,
          child: Text(
            'AGENT PERSONA',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: ctx.textMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final m in OvaAgentMode.values)
          PopupMenuItem<OvaAgentMode>(
            value: m,
            height: 34,
            child: Row(
              children: [
                Icon(m.icon,
                    size: 14,
                    color: state.selectedMode == m
                        ? AppColors.brandBlue
                        : ctx.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: state.selectedMode == m
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: state.selectedMode == m
                          ? AppColors.brandBlue
                          : ctx.textPrimary,
                    ),
                  ),
                ),
                if (state.selectedMode == m)
                  const Icon(Icons.check_rounded,
                      size: 14, color: AppColors.brandBlue),
              ],
            ),
          ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          enabled: false,
          height: 24,
          child: Text(
            'THINKING EFFORT',
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: ctx.textMuted,
              letterSpacing: 0.6,
            ),
          ),
        ),
        for (final eff in OvaAgentEffort.values)
          PopupMenuItem<OvaAgentEffort>(
            value: eff,
            height: 32,
            child: Row(
              children: [
                Icon(eff.icon,
                    size: 14,
                    color: state.selectedEffort == eff
                        ? AppColors.brandBlue
                        : ctx.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    eff.label,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: state.selectedEffort == eff
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: state.selectedEffort == eff
                          ? AppColors.brandBlue
                          : ctx.textPrimary,
                    ),
                  ),
                ),
                if (state.selectedEffort == eff)
                  const Icon(Icons.check_rounded,
                      size: 14, color: AppColors.brandBlue),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMemoriesPill(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final count = state.memories.length;
    return Tooltip(
      message:
          'Shared Account Memories ($count) — Synced across Mobile & Mac in real time',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _showMemoriesSheet(context, state),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: count > 0
                ? AppColors.brandBlue.withValues(alpha: 0.10)
                : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: count > 0
                  ? AppColors.brandBlue.withValues(alpha: 0.35)
                  : context.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.psychology_rounded,
                size: 14,
                color: count > 0 ? AppColors.brandBlue : context.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Memory${count > 0 ? ' ($count)' : ''}',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: count > 0 ? FontWeight.w700 : FontWeight.w600,
                  color: count > 0 ? AppColors.brandBlue : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMemoriesSheet(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final keyCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final searchCtrl = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final filter = searchCtrl.text.toLowerCase().trim();
            final filtered = state.memories.where((m) {
              if (filter.isEmpty) return true;
              return m.key.toLowerCase().contains(filter) ||
                  m.content.toLowerCase().contains(filter);
            }).toList();

            return Dialog(
              backgroundColor: ctx.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: ctx.border, width: 1.0),
              ),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 540, maxHeight: 600),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.brandBlue.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Icon(Icons.psychology_rounded,
                                size: 18, color: AppColors.brandBlue),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Shared Account Memories',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: ctx.textPrimary,
                                  ),
                                ),
                                Text(
                                  'Synced across Mobile and Mac in real time',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: ctx.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: searchCtrl,
                        onChanged: (_) => setDlgState(() {}),
                        style: GoogleFonts.inter(
                            fontSize: 12.5, color: ctx.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: ctx.surfaceMid,
                          hintText: 'Search stored memories...',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 16),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            borderSide:
                                BorderSide(color: ctx.border, width: 1.0),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            borderSide:
                                BorderSide(color: ctx.border, width: 1.0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  state.memories.isEmpty
                                      ? 'No memories stored yet.\nTeach Ova preferences or ask the agent to remember facts!'
                                      : 'No memories matching "$filter"',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: ctx.textMuted,
                                    height: 1.4,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (_, idx) {
                                  final m = filtered[idx];
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: ctx.surfaceMid,
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.sm),
                                      border: Border.all(
                                          color: ctx.border, width: 1.0),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    m.key,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          AppColors.brandBlue,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 5,
                                                            vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: ctx.border,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              AppRadius.xs),
                                                    ),
                                                    child: Text(
                                                      m.originDevice ==
                                                              'mobile'
                                                          ? '📱 Mobile'
                                                          : '💻 Mac',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            ctx.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                m.content,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11.5,
                                                  color: ctx.textPrimary,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 16,
                                              color: ctx.textMuted),
                                          splashRadius: 16,
                                          onPressed: () async {
                                            await ref
                                                .read(ovaAgentSyncProvider
                                                    .notifier)
                                                .deleteUserMemory(m.id);
                                            setDlgState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Text(
                        'ADD MEMORY',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: ctx.textMuted,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: keyCtrl,
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: ctx.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: ctx.surfaceMid,
                                hintText: 'Key (e.g. project_root)',
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  borderSide: BorderSide(
                                      color: ctx.border, width: 1.0),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: contentCtrl,
                              style: GoogleFonts.inter(
                                  fontSize: 12, color: ctx.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: ctx.surfaceMid,
                                hintText: 'Content or preference',
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  borderSide: BorderSide(
                                      color: ctx.border, width: 1.0),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                            ),
                            onPressed: () async {
                              final k = keyCtrl.text.trim();
                              final c = contentCtrl.text.trim();
                              if (k.isNotEmpty && c.isNotEmpty) {
                                await ref
                                    .read(ovaAgentSyncProvider.notifier)
                                    .saveUserMemory(k, c);
                                keyCtrl.clear();
                                contentCtrl.clear();
                                setDlgState(() {});
                              }
                            },
                            child: Text(
                              'Save',
                              style: GoogleFonts.inter(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFullAccessPill(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final full = state.fullComputerAccess;
    return Tooltip(
      message: full
          ? 'Full Computer Access ON: Agent runs mouse, keyboard, AppleScript, terminal & file tools autonomously.'
          : 'Supervised Mode: Agent asks approval before mutating Mac tools.',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: () {
          HapticFeedback.mediumImpact();
          ref
              .read(ovaAgentSyncProvider.notifier)
              .setFullComputerAccess(!full);
        },
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: full
                ? AppColors.brandPink.withValues(alpha: 0.13)
                : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: full
                  ? AppColors.brandPink.withValues(alpha: 0.48)
                  : context.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                full ? Icons.bolt_rounded : Icons.shield_outlined,
                size: 13,
                color: full ? AppColors.brandPink : context.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                full ? 'FULL ACCESS' : 'SUPERVISED',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: full ? AppColors.brandPink : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncBadge(BuildContext context, OvaAgentWorkspaceState state) {
    final online = state.workstationOnline;
    final hasWorkstation = state.workstationDeviceId != null;
    final winSuffix =
        online && (state.workstationActiveWindow?.isNotEmpty ?? false)
            ? ' • ${state.workstationActiveWindow}'
            : '';
    final label = online
        ? 'LIVE • ${state.workstationName ?? "Mac"}$winSuffix'
        : (hasWorkstation ? 'MAC OFFLINE' : 'CLOUD');
    final accent = online ? AppColors.brandBlue : context.textSecondary;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: (!_isDesktop && !online)
          ? () {
              if (widget.onOpenConnectWorkstation != null) {
                widget.onOpenConnectWorkstation!();
              } else {
                context.push('/connect');
              }
            }
          : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: online
              ? AppColors.brandBlue.withValues(alpha: 0.12)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: online
                ? AppColors.brandBlue.withValues(alpha: 0.40)
                : context.border,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6.5,
              height: 6.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? AppColors.brandPink : context.textMuted,
              ),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptRenameSession(OvaAgentWorkspaceState state) async {
    final session = state.activeSession;
    if (session == null) return;
    final textCtrl = TextEditingController(text: session.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          'Rename Thread',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Enter thread title...',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: ctx.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: ctx.border, width: 1.0),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
              borderSide: BorderSide(color: AppColors.brandBlue, width: 1.2),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(textCtrl.text.trim()),
            child: Text('Rename', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && newTitle != session.title) {
      await ref.read(ovaAgentSyncProvider.notifier).renameSession(session.id, newTitle);
    }
  }

  Widget _buildWebSearchPill(BuildContext context, OvaAgentWorkspaceState state) {
    final active = state.webSearchEnabled;
    return Tooltip(
      message: active
          ? 'Web Search is ON: Agent grounds responses with live web results & citations'
          : 'Web Search is OFF: Tap to ground responses with live web search',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: () {
          ref.read(ovaAgentSyncProvider.notifier).toggleWebSearch();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
          decoration: BoxDecoration(
            color: active
                ? AppColors.brandBlue.withValues(alpha: 0.16)
                : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(
              color: active ? AppColors.brandBlue : context.border,
              width: 1.0,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.brandBlue.withValues(alpha: 0.25),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_rounded,
                size: 13,
                color: active ? AppColors.brandBlue : context.textMuted,
              ),
              const SizedBox(width: 4.5),
              Text(
                'Search Web',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? AppColors.brandBlue : context.textSecondary,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Container(
                  width: 5.5,
                  height: 5.5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandBlue,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInChatSearchBar(BuildContext context, OvaAgentWorkspaceState state) {
    final totalMatches = _searchMatchTurnIndices.length;
    final currentMatch = totalMatches > 0 ? _activeSearchMatchIndex + 1 : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(
          bottom: BorderSide(color: context.border, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 16, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inChatSearchController,
              focusNode: _inChatSearchFocus,
              style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Find in thread (⌘F)...',
                hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (q) => _performInChatSearch(q, state.turns),
              onSubmitted: (_) => _nextSearchMatch(),
            ),
          ),
          if (_inChatSearchQuery.isNotEmpty) ...[
            Text(
              '$currentMatch of $totalMatches',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: totalMatches > 0 ? context.textSecondary : AppColors.brandPink,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Previous match (Shift+Enter)',
              onPressed: totalMatches > 0 ? () => _previousSearchMatch() : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Next match (Enter)',
              onPressed: totalMatches > 0 ? () => _nextSearchMatch() : null,
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            tooltip: 'Close search (Esc)',
            onPressed: _toggleInChatSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundActivityPill(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final activeStep = state.activePlan
        .where((p) => p.status == OvaPlanStepStatus.inProgress)
        .firstOrNull;
    final latestAction = state.recentActions.firstOrNull;
    final statusText = activeStep != null
        ? 'Working on it · ${activeStep.title}'
        : (latestAction != null
            ? 'Working on it · ${latestAction.summary}'
            : 'Thinking…');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.30),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: AppColors.brandPink,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.brandPink.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(
            color: AppColors.brandPink.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: AppColors.brandPink,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
          InkWell(
            onTap: () => ref.read(ovaAgentSyncProvider.notifier).clearError(),
            child: Icon(Icons.close_rounded, size: 15, color: context.textMuted),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Executive Agent Studio Landing (Calm, Focused, Low-Distraction)
  // ---------------------------------------------------------------------------

  Widget _buildAgentLanding(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final mode = state.selectedMode;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  gradient: const LinearGradient(
                    colors: [AppColors.brandBlue, AppColors.brandPink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  mode.icon,
                  size: 18,
                  color: AppColors.brandWhite,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ova ${mode.label}',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Works silently in the background across your app, maps, studio, and paired computer.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: context.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in _slashCommands.take(4))
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.full),
                onTap: () {
                  if (item.prompt.endsWith(' ')) {
                    _inputController.text = item.prompt;
                    _inputController.selection = TextSelection.collapsed(
                      offset: item.prompt.length,
                    );
                    _inputFocus.requestFocus();
                  } else {
                    _submitPrompt(item.prompt);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.icon, size: 14, color: AppColors.brandBlue),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Structured Agent Conversation Timeline
  // ---------------------------------------------------------------------------

  Widget _buildTimeline(
    BuildContext context,
    OvaAgentWorkspaceState state, {
    required bool dockArtifacts,
  }) {
    final sessionId = state.activeSessionId;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: state.turns.length,
      itemBuilder: (context, index) {
        final turn = state.turns[index];
        final isLatest = index == state.turns.length - 1;
        return Padding(
          key: ValueKey(turn.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: turn.isUser
              ? _UserTurnCard(turn: turn)
              : _AssistantAgentTurnCard(
                  turn: turn,
                  isLatest: isLatest,
                  workstationOnline: state.workstationOnline,
                  onTypeOnMac: (txt) => ref
                      .read(ovaAgentSyncProvider.notifier)
                      .injectWisprToMacCursor(txt),
                  onApproveTool: (toolId, approved) {
                    if (sessionId == null) return;
                    ref.read(ovaAgentSyncProvider.notifier).decideToolApproval(
                          sessionId: sessionId,
                          turn: turn,
                          toolCallId: toolId,
                          approved: approved,
                        );
                  },
                  onOpenArtifact: (art) {
                    if (dockArtifacts) {
                      ref
                          .read(ovaAgentSyncProvider.notifier)
                          .inspectArtifact(art);
                    } else {
                      _openArtifactSheet(art);
                    }
                  },
                  onSelectFollowUp: _submitPrompt,
                ),
        ).animate().fadeIn(duration: 180.ms);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 5. Slash Menu + Executive Multi-Modal & Wispr Voice Composer Dock
  // ---------------------------------------------------------------------------

  Widget _buildSlashMenu(BuildContext context) {
    final query = _inputController.text.toLowerCase();
    final filtered = _slashCommands
        .where((c) => c.cmd.startsWith(query) || query == '/')
        .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in filtered)
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _showSlashCommands = false);
                if (c.prompt.endsWith(' ')) {
                  _inputController.text = c.prompt;
                  _inputController.selection = TextSelection.collapsed(
                    offset: c.prompt.length,
                  );
                } else {
                  _inputController.clear();
                  _submitPrompt(c.prompt);
                }
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Row(
                  children: [
                    Icon(c.icon, size: 15, color: AppColors.brandBlue),
                    const SizedBox(width: 8),
                    Text(
                      c.cmd,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.label,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExecutiveComposer(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final notifier = ref.read(ovaAgentSyncProvider.notifier);
    final busy = state.isBusy;
    final hasDraft = _inputController.text.trim().isNotEmpty;
    final effectiveHeight = _composerExpanded
        ? 240.0
        : (_composerHeight - 52.0).clamp(44.0, 320.0);

    return Container(
      padding: EdgeInsets.fromLTRB(
        10,
        5,
        10,
        widget.compactSheet ? 10 : widget.bottomClearance,
      ),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 4, 8, 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _wisprRecording
                    ? AppColors.brandPink.withValues(alpha: 0.65)
                    : context.border,
                width: 1.0,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Draggable Top Resize Handle for Vertical Composer Height Adjustment
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: (details) {
                      setState(() {
                        _composerHeight = (_composerHeight - details.delta.dy)
                            .clamp(84.0, 360.0);
                      });
                    },
                    child: Container(
                      height: 10,
                      alignment: Alignment.center,
                      child: Container(
                        width: 36,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: context.border,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                    ),
                  ),
                ),

                // Live Wispr Audio Waveform Banner when recording or transcribing!
                if (_wisprRecording || _wisprProcessing) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 7),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: AppColors.brandPink.withValues(alpha: 0.45),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.graphic_eq_rounded,
                          size: 14,
                          color: AppColors.brandPink,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _wisprProcessing
                              ? 'Wispr AI polishing…'
                              : 'Wispr ${state.wisprTarget.shortLabel} • ${_recordingSeconds}s',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandPink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 16,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                for (var i = 0; i < _waveformBars.length; i++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 0.9),
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 80),
                                        height: _wisprRecording
                                            ? (3.0 + _waveformBars[i] * 13.0)
                                            : 4.0,
                                        decoration: BoxDecoration(
                                          color: i.isEven
                                              ? AppColors.brandPink
                                              : AppColors.brandBlue,
                                          borderRadius: BorderRadius.circular(
                                              AppRadius.full),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (_wisprRecording) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: _cancelWisprRecording,
                            child: Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: context.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Clean Context Attachment Row (low-distraction)
                Row(
                  children: [
                    Tooltip(
                      message: 'Attach tools, media, files & Mac context',
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _showAttachTray = !_showAttachTray);
                        },
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        child: Container(
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: _showAttachTray
                                ? AppColors.brandBlue.withValues(alpha: 0.16)
                                : context.surface,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: _showAttachTray
                                  ? AppColors.brandBlue
                                  : context.border,
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _showAttachTray
                                    ? Icons.close_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 13.5,
                                color: _showAttachTray
                                    ? AppColors.brandBlue
                                    : context.textPrimary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Attach',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _showAttachTray
                                      ? AppColors.brandBlue
                                      : context.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final custom in _attachedContexts) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: _ContextTogglePill(
                                  icon: Icons.attach_file_rounded,
                                  label: custom.length > 26
                                      ? '${custom.substring(0, 26)}…'
                                      : custom,
                                  active: true,
                                  onTap: () => setState(
                                    () => _attachedContexts.remove(custom),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _composerExpanded
                          ? 'Collapse composer'
                          : 'Expand composer',
                      child: InkWell(
                        onTap: () => setState(
                          () => _composerExpanded = !_composerExpanded,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: context.surface,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(color: context.border, width: 1.0),
                          ),
                          child: Icon(
                            _composerExpanded
                                ? Icons.unfold_less_rounded
                                : Icons.unfold_more_rounded,
                            size: 13,
                            color: context.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showAttachTray) ...[
                  const SizedBox(height: 6),
                  _buildAttachToolsTray(context, state),
                ],
                if (_attachedMediaThumb != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                      decoration: BoxDecoration(
                        color: context.surface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: context.border, width: 1.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            child: Image.memory(
                              _attachedMediaThumb!,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _attachedMediaName ?? 'Attached Image',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() {
                              if (_attachedMediaName != null) {
                                _attachedContexts
                                    .remove('Media: $_attachedMediaName');
                              }
                              _attachedMediaThumb = null;
                              _attachedMediaName = null;
                            }),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: context.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                SizedBox(
                  height: effectiveHeight,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (_isDesktop &&
                          event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        _submitPrompt();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      minLines: null,
                      maxLines: null,
                      expands: true,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        height: 1.35,
                        color: context.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        hintText: state.workstationOnline
                            ? 'Chat naturally, click Mic for Wispr voice, or type / for full Mac commands…'
                            : 'Ask Ova Agent, click Mic for Wispr voice typing, or type / for workflows…',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: context.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

            // Composer Footer: Effort Selector + Wispr Target Pill + Polish + Universal Mic + Send/Stop
            Row(
              children: [
                PopupMenuButton<OvaAgentEffort>(
                  tooltip: 'Reasoning effort',
                  color: context.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    side: BorderSide(color: context.border, width: 1.0),
                  ),
                  onSelected: (eff) {
                    HapticFeedback.selectionClick();
                    notifier.setEffort(eff);
                  },
                  itemBuilder: (ctx) => [
                    for (final eff in OvaAgentEffort.values)
                      PopupMenuItem(
                        value: eff,
                        height: 36,
                        child: Row(
                          children: [
                            Icon(
                              eff.icon,
                              size: 15,
                              color: state.selectedEffort == eff
                                  ? AppColors.brandBlue
                                  : ctx.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              eff.label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: state.selectedEffort == eff
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: ctx.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          state.selectedEffort.icon,
                          size: 13,
                          color: AppColors.brandBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          state.selectedEffort.label,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 5),

                // Wispr Output Target Selector (Composer | Auto-Send | Mac Cursor)
                PopupMenuButton<OvaWisprTarget>(
                  tooltip: 'Wispr Mic Output Target',
                  color: context.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    side: BorderSide(color: context.border, width: 1.0),
                  ),
                  onSelected: (t) {
                    HapticFeedback.selectionClick();
                    notifier.setWisprTarget(t);
                  },
                  itemBuilder: (ctx) => [
                    for (final t in OvaWisprTarget.values)
                      PopupMenuItem(
                        value: t,
                        height: 36,
                        child: Row(
                          children: [
                            Icon(
                              t.icon,
                              size: 15,
                              color: state.wisprTarget == t
                                  ? AppColors.brandPink
                                  : ctx.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t.label,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: state.wisprTarget == t
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: ctx.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: state.wisprTarget == OvaWisprTarget.macCursor
                          ? AppColors.brandPink.withValues(alpha: 0.12)
                          : context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: state.wisprTarget == OvaWisprTarget.macCursor
                            ? AppColors.brandPink.withValues(alpha: 0.45)
                            : context.border,
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          state.wisprTarget.icon,
                          size: 12.5,
                          color: state.wisprTarget == OvaWisprTarget.macCursor
                              ? AppColors.brandPink
                              : context.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          state.wisprTarget.shortLabel,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: state.wisprTarget == OvaWisprTarget.macCursor
                                ? AppColors.brandPink
                                : context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 1-Tap Wispr AI Polish on typed composer text
                if (hasDraft) ...[
                  Tooltip(
                    message: 'Wispr AI Polish draft',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      onTap: _polishingDraft ? null : _polishDraftInComposer,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: context.surface,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_polishingDraft)
                              const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: AppColors.brandPink,
                                ),
                              )
                            else
                              const Icon(
                                Icons.auto_fix_high_rounded,
                                size: 13.5,
                                color: AppColors.brandPink,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              'Polish',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],

                // Universal Wispr Voice Mic Button (Works on Mac USB.MIC + Mobile!)
                Tooltip(
                  message: _wisprRecording
                      ? 'Stop & commit (${state.wisprTarget.label})'
                      : 'Wispr Voice Mic (${state.wisprTarget.label})',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: _toggleWisprMic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _wisprRecording
                            ? AppColors.brandPink
                            : context.surface,
                        border: Border.all(
                          color: _wisprRecording
                              ? AppColors.brandPink
                              : context.border,
                          width: 1.0,
                        ),
                        boxShadow: _wisprRecording
                            ? [
                                BoxShadow(
                                  color: AppColors.brandPink
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: _wisprProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brandPink,
                              ),
                            )
                          : Icon(
                              _wisprRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              size: 17,
                              color: _wisprRecording
                                  ? AppColors.brandWhite
                                  : AppColors.brandPink,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                if (busy)
                  SizedBox(
                    height: 34,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPink,
                        foregroundColor: AppColors.brandWhite,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        notifier.stopCurrentTurn();
                      },
                      icon: const Icon(Icons.stop_rounded, size: 15),
                      label: Text(
                        'Stop',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: AppColors.brandWhite,
                        padding: EdgeInsets.zero,
                      ),
                      tooltip: 'Send instruction',
                      onPressed: () => _submitPrompt(),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  void _toggleContext(String key) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_attachedContexts.contains(key)) {
        _attachedContexts.remove(key);
      } else {
        _attachedContexts.add(key);
      }
    });
  }

  Future<void> _attachClipboardContext() async {
    String txt = '';
    if (_isDesktop && Platform.isMacOS) {
      txt = (await MacOSMouseController.readClipboard()).trim();
    } else {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      txt = clip?.text?.trim() ?? '';
    }
    if (txt.isEmpty) return;
    final snippet = txt.length > 80 ? '${txt.substring(0, 80)}…' : txt;
    setState(() {
      _attachedContexts.add('Clipboard: $snippet');
      _showAttachTray = false;
    });
  }

  Future<void> _pickWorkspaceMedia(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (xfile == null || !mounted) return;
      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      final name = xfile.name.isNotEmpty
          ? xfile.name
          : (source == ImageSource.camera ? 'Camera Shot' : 'Photo');
      setState(() {
        _attachedMediaThumb = bytes;
        _attachedMediaName = name;
        _attachedContexts.add('Media: $name');
        _showAttachTray = false;
      });
    } catch (_) {}
  }

  Future<void> _promptAttachFileContext() async {
    HapticFeedback.selectionClick();
    final ctrl = TextEditingController();
    final val = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          'Attach File, Code Path or URL',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'e.g. ~/Desktop/notes.md or https://...',
            hintStyle: GoogleFonts.inter(fontSize: 12.5, color: ctx.textMuted),
            filled: true,
            fillColor: ctx.surfaceMid,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: ctx.border, width: 1),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: ctx.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: AppColors.brandWhite,
            ),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text(
              'Attach',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (val != null && val.isNotEmpty && mounted) {
      setState(() {
        _attachedContexts.add('File: $val');
        _showAttachTray = false;
      });
    }
  }

  Widget _buildAttachToolsTray(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    final notifier = ref.read(ovaAgentSyncProvider.notifier);
    Widget tile({
      required IconData icon,
      required String label,
      required Color accent,
      required VoidCallback onTap,
      bool active = false,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? accent.withValues(alpha: context.isDark ? 0.22 : 0.12)
                : context.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active ? accent : context.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13.5,
                color: active ? accent : context.textPrimary,
              ),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tile(
              icon: Icons.photo_library_outlined,
              label: 'Photo / Screen',
              accent: AppColors.brandBlue,
              onTap: () => _pickWorkspaceMedia(ImageSource.gallery),
            ),
            if (!_isDesktop) ...[
              const SizedBox(width: 6),
              tile(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                accent: AppColors.brandPink,
                onTap: () => _pickWorkspaceMedia(ImageSource.camera),
              ),
            ],
            const SizedBox(width: 6),
            tile(
              icon: Icons.folder_open_rounded,
              label: 'File / Path',
              accent: AppColors.brandBlue,
              onTap: _promptAttachFileContext,
            ),
            const SizedBox(width: 6),
            tile(
              icon: Icons.content_paste_rounded,
              label: 'Clipboard',
              accent: AppColors.brandPink,
              onTap: _attachClipboardContext,
            ),
            const SizedBox(width: 6),
            tile(
              icon: Icons.window_rounded,
              label: 'Active Window',
              accent: AppColors.brandBlue,
              active: _attachedContexts.contains('Active Window'),
              onTap: () => _toggleContext('Active Window'),
            ),
            const SizedBox(width: 6),
            tile(
              icon: Icons.memory_rounded,
              label: 'Mac Telemetry',
              accent: AppColors.brandPink,
              active: _attachedContexts.contains('Workstation Host'),
              onTap: () => _toggleContext('Workstation Host'),
            ),
            const SizedBox(width: 6),
            tile(
              icon: Icons.public_rounded,
              label: 'Web Search',
              accent: AppColors.brandBlue,
              active: state.webSearchEnabled,
              onTap: () {
                HapticFeedback.selectionClick();
                notifier.setWebSearchEnabled(!state.webSearchEnabled);
              },
            ),
            const SizedBox(width: 6),
            tile(
              icon: Icons.terminal_rounded,
              label: 'Slash Workflows',
              accent: AppColors.brandPink,
              active: _showSlashCommands,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _showSlashCommands = !_showSlashCommands;
                  _showAttachTray = false;
                });
              },
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 150.ms).slideY(begin: 0.06, end: 0);
  }
}

// =============================================================================
// Sub-Widgets: Capability Cards, Mode Chips, Session Sidebar, Turns, Tools &
// Artifact Inspector
// =============================================================================

class _ContextTogglePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ContextTogglePill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.brandBlue.withValues(alpha: 0.14)
              : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          border: Border.all(
            color: active ? AppColors.brandBlue : context.border,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11.5,
              color: active ? AppColors.brandBlue : context.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.brandBlue : context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionListPane extends ConsumerStatefulWidget {
  final bool isSheet;
  final VoidCallback? onSessionSelected;
  final Future<void> Function(OvaAgentSession session) onDeleteSession;
  final VoidCallback? onCollapse;

  const _SessionListPane({
    required this.isSheet,
    this.onSessionSelected,
    required this.onDeleteSession,
    this.onCollapse,
  });

  @override
  ConsumerState<_SessionListPane> createState() => _SessionListPaneState();
}

class _SessionListPaneState extends ConsumerState<_SessionListPane> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _promptRenameSession(BuildContext context, OvaAgentSession s) async {
    final textCtrl = TextEditingController(text: s.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          'Rename Thread',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Enter thread title...',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: ctx.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: ctx.border, width: 1.0),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
              borderSide: BorderSide(color: AppColors.brandBlue, width: 1.2),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(textCtrl.text.trim()),
            child: Text('Rename', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && newTitle != s.title) {
      await ref.read(ovaAgentSyncProvider.notifier).renameSession(s.id, newTitle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaAgentSyncProvider);
    final notifier = ref.read(ovaAgentSyncProvider.notifier);

    final filtered = state.sessions.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.title.toLowerCase().contains(_searchQuery) ||
          s.lastPreview.toLowerCase().contains(_searchQuery);
    }).toList();

    // Group sessions chronologically: Pinned, Today, Yesterday, Previous 7 Days, Older
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final sevenDaysStart = todayStart.subtract(const Duration(days: 7));

    final pinned = <OvaAgentSession>[];
    final today = <OvaAgentSession>[];
    final yesterday = <OvaAgentSession>[];
    final prev7Days = <OvaAgentSession>[];
    final older = <OvaAgentSession>[];

    for (final s in filtered) {
      if (s.pinned) {
        pinned.add(s);
      } else if (s.updatedAt.isAfter(todayStart)) {
        today.add(s);
      } else if (s.updatedAt.isAfter(yesterdayStart)) {
        yesterday.add(s);
      } else if (s.updatedAt.isAfter(sevenDaysStart)) {
        prev7Days.add(s);
      } else {
        older.add(s);
      }
    }

    final groups = <MapEntry<String, List<OvaAgentSession>>>[
      if (pinned.isNotEmpty) MapEntry('PINNED', pinned),
      if (today.isNotEmpty) MapEntry('TODAY', today),
      if (yesterday.isNotEmpty) MapEntry('YESTERDAY', yesterday),
      if (prev7Days.isNotEmpty) MapEntry('PREVIOUS 7 DAYS', prev7Days),
      if (older.isNotEmpty) MapEntry('OLDER', older),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Row(
            children: [
              const Icon(
                Icons.hub_rounded,
                size: 16,
                color: AppColors.brandBlue,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Agent Threads',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: BorderSide(color: context.border, width: 1.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  onPressed: () {
                    notifier.startNewSession();
                    widget.onSessionSelected?.call();
                  },
                  icon: const Icon(
                    Icons.add_rounded,
                    size: 14,
                    color: AppColors.brandBlue,
                  ),
                  label: Text(
                    'New',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ),
              if (widget.onCollapse != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Collapse sidebar (⌘B)',
                  child: IconButton(
                    icon: const Icon(Icons.view_sidebar_outlined, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: widget.onCollapse,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Search past chats textfield
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: context.surfaceMid,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                hintText: 'Search past chats...',
                hintStyle: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                prefixIcon: Icon(Icons.search_rounded, size: 14, color: context.textMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 13),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border, width: 1.0),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
                  borderSide: BorderSide(color: AppColors.brandBlue, width: 1.2),
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: context.border),
        Expanded(
          child: state.sessions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Threads started on Mac or Mobile sync here automatically in real time.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: context.textMuted,
                      ),
                    ),
                  ),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text(
                          'No chats matching "$_searchQuery"',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: context.textMuted,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      itemCount: groups.fold<int>(0, (sum, g) => sum + 1 + g.value.length),
                      itemBuilder: (context, idx) {
                        var cursor = 0;
                        for (final g in groups) {
                          if (idx == cursor) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                              child: Text(
                                g.key,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: context.textMuted,
                                ),
                              ),
                            );
                          }
                          cursor += 1;
                          final listIdx = idx - cursor;
                          if (listIdx < g.value.length) {
                            final s = g.value[listIdx];
                            final selected = s.id == state.activeSessionId;
                            final live = s.status != 'idle';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                                onTap: () {
                                  notifier.selectSession(s.id);
                                  widget.onSessionSelected?.call();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.brandBlue.withValues(alpha: 0.12)
                                        : context.surfaceMid,
                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.brandBlue
                                          : context.border,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            s.originDevice == 'mac'
                                                ? Icons.desktop_mac_rounded
                                                : Icons.smartphone_rounded,
                                            size: 12.5,
                                            color: selected
                                                ? AppColors.brandBlue
                                                : context.textMuted,
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              s.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                color: context.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (live)
                                            Container(
                                              width: 7,
                                              height: 7,
                                              margin: const EdgeInsets.only(right: 4),
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: AppColors.brandPink,
                                              ),
                                            ),
                                          PopupMenuButton<String>(
                                            tooltip: 'Thread options',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                                            icon: Icon(
                                              Icons.more_horiz_rounded,
                                              size: 14,
                                              color: context.textMuted,
                                            ),
                                            color: context.surface,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(AppRadius.md),
                                              side: BorderSide(color: context.border, width: 1.0),
                                            ),
                                            onSelected: (action) {
                                              if (action == 'rename') {
                                                _promptRenameSession(context, s);
                                              } else if (action == 'pin') {
                                                notifier.togglePinSession(s);
                                              } else if (action == 'delete') {
                                                widget.onDeleteSession(s);
                                              }
                                            },
                                            itemBuilder: (ctx) => [
                                              PopupMenuItem(
                                                value: 'rename',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined, size: 14, color: ctx.textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('Rename', style: GoogleFonts.inter(fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'pin',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      s.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                                                      size: 14,
                                                      color: s.pinned ? AppColors.brandBlue : ctx.textSecondary,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(s.pinned ? 'Unpin' : 'Pin', style: GoogleFonts.inter(fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                height: 32,
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.brandPink),
                                                    const SizedBox(width: 8),
                                                    Text('Delete', style: GoogleFonts.inter(fontSize: 12, color: AppColors.brandPink)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (s.lastPreview.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          s.lastPreview,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            color: context.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }
                          cursor += g.value.length;
                        }
                        return const SizedBox.shrink();
                      },
                    ),
        ),

        // User Account & Mobile Sync Footer Tile
        Divider(color: context.border, height: 1),
        InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            OneovaWorkstationAuthDialog.show(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            color: context.surfaceMid,
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                    image: state.authPhotoUrl != null &&
                            state.authPhotoUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(state.authPhotoUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: state.authPhotoUrl == null ||
                          state.authPhotoUrl!.isEmpty
                      ? Text(
                          state.accountAvatarInitial,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              state.displayAccountName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.verified_rounded,
                              size: 11, color: AppColors.brandBlue),
                        ],
                      ),
                      Text(
                        state.authUsername != null &&
                                state.authUsername!.isNotEmpty
                            ? '@${state.authUsername} • Mobile Synced'
                            : (state.authEmail ?? 'Oneova Account'),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: context.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 16,
                  color: context.textSecondary,
                ),
              ],
            ),
          ),
        ),
        ComputerSidebarCard(onNavigate: widget.onSessionSelected),
      ],
    );
  }
}

class _UserTurnCard extends StatelessWidget {
  final OvaAgentTurn turn;
  const _UserTurnCard({required this.turn});

  @override
  Widget build(BuildContext context) {
    final fromMac = turn.originDevice == 'mac';
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fromMac
                      ? Icons.desktop_mac_rounded
                      : Icons.smartphone_rounded,
                  size: 11,
                  color: context.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  fromMac ? 'From Mac' : 'From Mobile',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: context.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: const BoxDecoration(
                color: AppColors.brandBlue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.md),
                  topRight: Radius.circular(AppRadius.md),
                  bottomLeft: Radius.circular(AppRadius.md),
                  bottomRight: Radius.circular(AppRadius.xs),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (turn.contextChips.isNotEmpty) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final c in turn.contextChips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.brandWhite.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              c,
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brandWhite,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                  ],
                  SelectableText(
                    turn.text,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.38,
                      color: AppColors.brandWhite,
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
}

class _AssistantAgentTurnCard extends StatefulWidget {
  final OvaAgentTurn turn;
  final bool isLatest;
  final bool workstationOnline;
  final ValueChanged<String> onTypeOnMac;
  final void Function(String toolCallId, bool approved) onApproveTool;
  final void Function(OvaAgentArtifact artifact) onOpenArtifact;
  final void Function(String prompt) onSelectFollowUp;

  const _AssistantAgentTurnCard({
    required this.turn,
    required this.isLatest,
    required this.workstationOnline,
    required this.onTypeOnMac,
    required this.onApproveTool,
    required this.onOpenArtifact,
    required this.onSelectFollowUp,
  });

  @override
  State<_AssistantAgentTurnCard> createState() =>
      _AssistantAgentTurnCardState();
}

class _AssistantAgentTurnCardState extends State<_AssistantAgentTurnCard> {
  bool _thinkingOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.turn;
    final bodyStyle = GoogleFonts.inter(
      fontSize: 13,
      height: 1.44,
      color: context.textPrimary,
    );

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.brandBlue, AppColors.brandPink],
                  ),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 12,
                  color: AppColors.brandWhite,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  t.subagent?.label ?? 'Ova Agent',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
              ),
              _TurnStatusBadge(status: t.status),
            ],
          ),

          if (t.thinkingSteps.isNotEmpty || t.status == 'thinking') ...[
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => setState(() => _thinkingOpen = !_thinkingOpen),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.psychology_rounded,
                          size: 14,
                          color: t.status == 'thinking'
                              ? AppColors.brandPink
                              : AppColors.brandBlue,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            t.status == 'thinking'
                                ? 'Reasoning across live workstation context…'
                                : 'Thought for ${(t.thinkingDurationMs / 1000).toStringAsFixed(1)}s • ${t.thinkingSteps.length} step${t.thinkingSteps.length == 1 ? "" : "s"}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondary,
                            ),
                          ),
                        ),
                        Icon(
                          _thinkingOpen
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 15,
                          color: context.textMuted,
                        ),
                      ],
                    ),
                    if (_thinkingOpen || t.status == 'thinking') ...[
                      const SizedBox(height: 6),
                      for (final step in t.thinkingSteps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• ',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppColors.brandBlue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  step,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],

          if (t.toolCalls.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final tc in t.toolCalls)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _ToolExecutionCard(
                  call: tc,
                  onDecision: (approved) =>
                      widget.onApproveTool(tc.id, approved),
                ),
              ),
          ],

          if (t.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            MarkdownBody(
              data: t.text,
              selectable: true,
              onTapLink: (_, href, _) {
                if (href != null) {
                  launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              styleSheet: MarkdownStyleSheet(
                p: bodyStyle,
                listBullet: bodyStyle.copyWith(color: AppColors.brandBlue),
                strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
                h1: bodyStyle.copyWith(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
                h2: bodyStyle.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
                h3: bodyStyle.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
                code: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: context.textPrimary,
                  backgroundColor: context.surfaceMid,
                ),
                codeblockDecoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                tableBorder: TableBorder.all(color: context.border, width: 1.0),
              ),
            ),
          ],

          if (t.artifacts.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final art in t.artifacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => widget.onOpenArtifact(art),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: AppColors.brandBlue.withValues(alpha: 0.40),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Icon(
                            art.icon,
                            size: 15,
                            color: AppColors.brandBlue,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                art.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                              Text(
                                '${art.kind.toUpperCase()} • ${art.language} • Tap to inspect',
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  color: context.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: AppColors.brandBlue,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],

          // Micro Actions (Copy, Speak, Type into Mac Cursor!)
          if (t.text.trim().isNotEmpty && !t.isBusy) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: t.text));
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Copied agent response',
                          style: GoogleFonts.inter(fontSize: 12),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.content_copy_rounded,
                          size: 12.5,
                          color: context.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Copy',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    OneovaLanguageService.instance.speak(
                      t.text.replaceAll(RegExp(r'[*#_`]'), ''),
                    );
                  },
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.volume_up_outlined,
                          size: 13,
                          color: context.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Speak',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.workstationOnline) ...[
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTypeOnMac(t.text);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.desktop_mac_rounded,
                            size: 12.5,
                            color: AppColors.brandBlue,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Paste on Mac',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],

          if (widget.isLatest && t.followUps.isNotEmpty && !t.isBusy) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in t.followUps)
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: () => widget.onSelectFollowUp(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        border: Border.all(color: context.border, width: 1.0),
                      ),
                      child: Text(
                        f,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TurnStatusBadge extends StatelessWidget {
  final String status;
  const _TurnStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == 'completed') return const SizedBox.shrink();
    final (label, accent) = switch (status) {
      'thinking' => ('THINKING', AppColors.brandPink),
      'awaiting_approval' => ('NEEDS APPROVAL', AppColors.brandPink),
      'running_tools' => ('RUNNING ON MAC', AppColors.brandBlue),
      'synthesizing' => ('SYNTHESIZING', AppColors.brandBlue),
      _ => (status.toUpperCase(), context.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != 'awaiting_approval') ...[
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: accent),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolExecutionCard extends StatefulWidget {
  final OvaAgentToolCall call;
  final ValueChanged<bool> onDecision;

  const _ToolExecutionCard({
    required this.call,
    required this.onDecision,
  });

  @override
  State<_ToolExecutionCard> createState() => _ToolExecutionCardState();
}

class _ToolExecutionCardState extends State<_ToolExecutionCard> {
  bool _outputExpanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.call;
    final needsApproval = c.status == OvaToolCallStatus.awaitingApproval;
    final running = c.status == OvaToolCallStatus.running ||
        c.status == OvaToolCallStatus.pendingMac ||
        c.status == OvaToolCallStatus.approved;
    final borderColor = needsApproval
        ? AppColors.brandPink.withValues(alpha: 0.55)
        : context.border;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                c.icon,
                size: 15,
                color:
                    needsApproval ? AppColors.brandPink : AppColors.brandBlue,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  c.title,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
              if (c.durationMs != null)
                Text(
                  '${c.durationMs}ms',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: context.textMuted,
                  ),
                ),
              const SizedBox(width: 6),
              if (running)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AppColors.brandBlue,
                  ),
                )
              else
                Icon(
                  switch (c.status) {
                    OvaToolCallStatus.completed => Icons.check_circle_rounded,
                    OvaToolCallStatus.awaitingApproval => Icons.shield_outlined,
                    OvaToolCallStatus.denied ||
                    OvaToolCallStatus.error =>
                      Icons.cancel_outlined,
                    _ => Icons.schedule_rounded,
                  },
                  size: 14,
                  color: switch (c.status) {
                    OvaToolCallStatus.completed => AppColors.brandBlue,
                    OvaToolCallStatus.awaitingApproval ||
                    OvaToolCallStatus.denied ||
                    OvaToolCallStatus.error =>
                      AppColors.brandPink,
                    _ => context.textMuted,
                  },
                ),
            ],
          ),
          if (c.args.isNotEmpty) ...[
            const SizedBox(height: 5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Text(
                '${c.name}(${c.args.entries.map((e) => "${e.key}: ${e.value}").join(", ")})',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: context.textSecondary,
                ),
              ),
            ),
          ],

          if (needsApproval) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Permission required before running on Mac',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandPink,
                    ),
                  ),
                ),
                SizedBox(
                  height: 30,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      side: BorderSide(color: context.border, width: 1.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onDecision(false);
                    },
                    child: Text(
                      'Deny',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 30,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: AppColors.brandWhite,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onDecision(true);
                    },
                    icon: const Icon(Icons.check_rounded, size: 13),
                    label: Text(
                      'Approve & Run',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (c.output != null && c.output!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => _outputExpanded = !_outputExpanded),
              child: Row(
                children: [
                  Text(
                    _outputExpanded ? 'Hide tool output' : 'View tool output',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  if (c.approvedBy != null)
                    Text(
                      ' • Approved on ${c.approvedBy}',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        color: context.textMuted,
                      ),
                    ),
                  const Spacer(),
                  Icon(
                    _outputExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 14,
                    color: AppColors.brandBlue,
                  ),
                ],
              ),
            ),
            if (_outputExpanded) ...[
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 190),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    c.output!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      height: 1.35,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _ArtifactInspectorPane extends ConsumerWidget {
  final OvaAgentArtifact artifact;
  final VoidCallback onClose;

  const _ArtifactInspectorPane({
    required this.artifact,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Icon(artifact.icon, size: 16, color: AppColors.brandBlue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artifact.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      '${artifact.kind.toUpperCase()} • ${artifact.language}',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy artifact',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: artifact.content));
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Copied "${artifact.title}"',
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: Icon(
                  Icons.content_copy_rounded,
                  size: 16,
                  color: context.textSecondary,
                ),
              ),
              if (!isDesktop)
                IconButton(
                  tooltip: 'Save to Ova Library',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await ref
                        .read(ovaSharedHistoryProvider.notifier)
                        .saveToLibrary(
                          title: artifact.title,
                          content: artifact.content,
                          category: 'Agent',
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Saved to Ova Library',
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    Icons.bookmark_add_outlined,
                    size: 17,
                    color: context.textSecondary,
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // Multi-artifact tab bar
        Builder(
          builder: (ctx) {
            final all = ref.watch(ovaAgentSyncProvider).allArtifacts;
            if (all.length <= 1) return const SizedBox.shrink();
            return Container(
              height: 34,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                itemCount: all.length,
                itemBuilder: (ctx, idx) {
                  final a = all[idx];
                  final isActive = a.id == artifact.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => ref.read(ovaAgentSyncProvider.notifier).inspectArtifact(a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? context.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: isActive ? context.border : Colors.transparent,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              a.icon,
                              size: 12,
                              color: isActive ? AppColors.brandBlue : context.textMuted,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                                color: isActive ? context.textPrimary : context.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        Divider(height: 1, thickness: 1, color: context.border),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: artifact.kind == 'markdown' || artifact.kind == 'plan'
                ? MarkdownBody(
                    data: artifact.content,
                    selectable: true,
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: SelectableText(
                      artifact.content,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        height: 1.42,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Compact 30×30 icon button for the clean chat header.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppColors.brandBlue.withValues(alpha: 0.15)
                : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active ? AppColors.brandBlue : context.border,
              width: 1.0,
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: active ? AppColors.brandBlue : context.textPrimary,
          ),
        ),
      ),
    );
  }
}
