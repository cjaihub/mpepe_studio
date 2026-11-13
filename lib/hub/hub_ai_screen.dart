import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent_workspace/ova_agent_sync_controller.dart';
import '../agent_workspace/widgets/ova_claude_agent_workspace.dart';
import '../backend/agents/youtube_agent.dart';
import '../backend/ai_brain_service.dart';
import '../backend/remote_connect_service.dart';
import '../backend/repair/oneova_auto_updater.dart';
import '../backend/repair/oneova_self_repair_engine.dart';
import '../backend/security/oneova_ai_gateway.dart';
import '../backend/user_service.dart';
import '../feed/providers/oneova_focus_mode_provider.dart';
import '../ova_assistant/core/ova_tool_result.dart';
import '../ova_assistant/main_interface/ova_live_voice_view.dart';
import '../ova_assistant/main_interface/ova_main_drawer.dart';
import '../ova_assistant/main_interface/ova_sections_views.dart';
import '../ova_assistant/memory/ova_memory_engine.dart';
import '../ova_assistant/services/ova_adaptive_suggestions_service.dart';
import '../ova_assistant/services/ova_agentic_orchestrator.dart';
import '../ova_assistant/services/ova_chat_controller.dart' show ovaToolRegistryProvider;
import '../ova_assistant/services/ova_local_intents.dart';
import '../ova_assistant/services/ova_shared_history_service.dart';
import '../ova_assistant/services/ova_task_center.dart';
import '../ova_assistant/services/ova_thermal_watchdog.dart';
import '../ova_assistant/services/ova_tool_registry.dart' show OvaInvocationContext;
import '../shared/services/oneova_language_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/oneova_language_action_sheet.dart';
import '../shared/widgets/oneova_voice_typing_button.dart';

/// Ova Main Interface (`/hub/ai`).
///
/// Standalone full-screen Ova Workspace with slide-out navigation drawer,
/// multi-workspace conversations, AI Agents, dedicated Live Voice mode,
/// Explore templates, Library, and unified History & Activities shared with
/// the quick Ova Overlay Assistant.
class HubAiScreen extends ConsumerStatefulWidget {
  const HubAiScreen({super.key});

  @override
  ConsumerState<HubAiScreen> createState() => _HubAiScreenState();
}

class _HubAiScreenState extends ConsumerState<HubAiScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _chatFocus = FocusNode();

  OvaMainSection _activeSection = OvaMainSection.home;
  OvaWorkspaceId _activeWorkspace = OvaWorkspaceId.personal;
  bool _useAgentWorkspace = true;

  /// Separate active workspace conversation state (independent from OvaOverlay).
  String? _activeThreadId;
  final List<Map<String, dynamic>> _messages = [];
  bool _isChatLoading = false;

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  void _setSection(OvaMainSection next) {
    if (_activeSection == next) return;
    final wasVoice = _activeSection == OvaMainSection.liveVoice;
    final goingVoice = next == OvaMainSection.liveVoice;
    setState(() => _activeSection = next);

    if (goingVoice && !wasVoice) {
      ref.read(oneovaFocusModeProvider.notifier).set(true);
    } else if (!goingVoice && wasVoice) {
      ref.read(oneovaFocusModeProvider.notifier).set(false);
    }
  }

  void _startNewChat() {
    HapticFeedback.lightImpact();
    if (_activeSection == OvaMainSection.liveVoice) {
      ref.read(oneovaFocusModeProvider.notifier).set(false);
    }
    if (_useAgentWorkspace) {
      ref.read(ovaAgentSyncProvider.notifier).startNewSession();
    }
    setState(() {
      _activeSection = OvaMainSection.home;
      _activeThreadId = null;
      _messages.clear();
      _isChatLoading = false;
    });
  }

  void _openSharedThread(OvaSharedThread thread) {
    HapticFeedback.selectionClick();
    if (_activeSection == OvaMainSection.liveVoice) {
      ref.read(oneovaFocusModeProvider.notifier).set(false);
    }
    final agentState = ref.read(ovaAgentSyncProvider);
    final isAgentSession = agentState.sessions.any((s) => s.id == thread.id);
    if (isAgentSession) {
      ref.read(ovaAgentSyncProvider.notifier).selectSession(thread.id);
      setState(() {
        _useAgentWorkspace = true;
        _activeSection = OvaMainSection.home;
      });
      return;
    }
    setState(() {
      _useAgentWorkspace = false;
      _activeSection = OvaMainSection.home;
      _activeWorkspace = thread.workspace;
      _activeThreadId = thread.id;
      _messages
        ..clear()
        ..addAll([
          for (final t in thread.turns) ...[
            if (t.query.isNotEmpty) {'role': 'user', 'content': t.query},
            if (t.response.isNotEmpty)
              {
                'role': 'assistant',
                'content': t.response,
                'type': 'text',
                'origin': t.source.badgeLabel,
              },
          ],
        ]);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _chatController.text).trim();
    if (text.isEmpty || _isChatLoading) return;

    HapticFeedback.lightImpact();
    _chatFocus.unfocus();

    final uid = _firebaseReady ? (FirebaseAuth.instance.currentUser?.uid ?? 'guest') : 'guest';
    _activeThreadId ??= ref.read(ovaSharedHistoryProvider.notifier).newThreadId('main');

    setState(() {
      _activeSection = OvaMainSection.home;
      _messages.add({'role': 'user', 'content': text});
      _isChatLoading = true;
      if (presetText == null) _chatController.clear();
    });
    _scrollToBottom();

    try {
      final memoryEngine = ref.read(ovaMemoryEngineProvider);
      memoryEngine.detectEmotion(text, sessionId: 'hub_ai');
      memoryEngine.updateRollingSummary(
        sessionId: 'hub_ai',
        userId: uid,
        recentTurns: AIBrainService.sanitizeChatMessages(_messages),
      );
    } catch (_) {}

    final tasks = ref.read(ovaTaskCenterProvider.notifier);
    final taskId = tasks.start(
      text.length > 64 ? '${text.substring(0, 64)}…' : text,
      source: 'ai_lab',
    );
    final stepIdx = tasks.addStep(taskId, 'Ova Main · ${_activeWorkspace.shortLabel}', Icons.auto_awesome_rounded);

    // 1. Autonomous Self-Repair & System Health Diagnostics
    final lowerText = text.toLowerCase();
    if (lowerText.contains('repair') ||
        lowerText.contains('diagnos') ||
        lowerText.contains('health check') ||
        lowerText.contains('system health') ||
        lowerText.contains('fix bug')) {
      try {
        final repairEngine = ref.read(oneOvaSelfRepairEngineProvider);
        final updater = ref.read(oneOvaAutoUpdaterProvider);
        final realUid = _firebaseReady ? FirebaseAuth.instance.currentUser?.uid : null;

        final profileResult = realUid != null ? await repairEngine.repairUserProfile(realUid) : null;
        final cacheResult = await repairEngine.repairInterfaceAndCache();
        final health = await repairEngine.runSystemHealthScan();
        final updateInfo = await updater.checkForUpdates();

        final buffer = StringBuffer()
          ..writeln('### System Health & Self-Repair Report')
          ..writeln('**Health Score:** `${health.overallScore}%` · **${health.overallStatus.name.toUpperCase()}**')
          ..writeln('')
          ..writeln('- **Cache & Pipeline:** ${cacheResult.summary}');
        if (profileResult != null) {
          buffer.writeln('- **Profile Doctor:** ${profileResult.summary}');
        }
        buffer
          ..writeln(
              '- **Build Version:** `v${OneOvaAutoUpdater.currentVersion}+${OneOvaAutoUpdater.currentBuildNumber}` (${updateInfo.hasUpdate ? "Update available: ${updateInfo.latestVersion}" : "Up to date"})')
          ..writeln('')
          ..writeln('| Subsystem | Status | Details |')
          ..writeln('|---|---|---|');
        for (final check in health.checks) {
          buffer.writeln('| ${check.component} | `${check.status.name.toUpperCase()}` | ${check.details} |');
        }

        final report = buffer.toString();
        tasks.updateStep(taskId, stepIdx, OvaStepStatus.done);
        tasks.finish(taskId, ok: true, summary: 'System health ${health.overallScore}%');

        await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
              query: text,
              response: report,
              source: OvaOriginSource.main,
              workspace: _activeWorkspace,
              threadId: _activeThreadId,
            );

        if (mounted) {
          setState(() {
            _messages.add({'role': 'assistant', 'content': report, 'type': 'text'});
            _isChatLoading = false;
          });
          _scrollToBottom();
        }
      } catch (e) {
        tasks.updateStep(taskId, stepIdx, OvaStepStatus.failed);
        tasks.finish(taskId, ok: false, summary: 'Diagnostics error');
        if (mounted) {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'content': 'Could not complete diagnostics right now: $e',
              'type': 'text',
            });
            _isChatLoading = false;
          });
        }
      }
      return;
    }

    // 1.5. Instant On-Device Commands & Navigation (works 100% offline)
    final localIntent = OvaLocalIntents.parse(text);
    if (localIntent != null) {
      final registry = ref.read(ovaToolRegistryProvider);
      final spec = registry.spec(localIntent.tool);
      if (spec != null && spec.risk == OvaRisk.safe) {
        try {
          final res = await registry.run(
            localIntent.tool,
            localIntent.args,
            context,
            const OvaInvocationContext(),
          );
          tasks.updateStep(taskId, stepIdx, res.ok ? OvaStepStatus.done : OvaStepStatus.failed);
          tasks.finish(taskId, ok: res.ok, summary: res.summary);
          await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
                query: text,
                response: res.summary,
                source: OvaOriginSource.main,
                workspace: _activeWorkspace,
                threadId: _activeThreadId,
              );
          if (mounted) {
            setState(() {
              _messages.add({
                'role': 'assistant',
                'content': res.summary,
                'type': 'text',
              });
              _isChatLoading = false;
            });
            _scrollToBottom();
            if (res.navigateTo != null) {
              context.push(res.navigateTo!);
            }
          }
          return;
        } catch (_) {
          // Fall through to standard reasoning if local tool fails
        }
      }
    }

    // 2. Multi-Step Autonomous Agentic Procedure
    final orchestrator = ref.read(ovaAgenticOrchestratorProvider);
    final procType = orchestrator.detectProcedureType(text);
    if (procType != AgenticProcedureType.generalReasoning) {
      final plan = orchestrator.createPlan(procType, text);
      final planIndex = _messages.length;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'type': 'agentic_plan',
          'plan': plan,
        });
        _isChatLoading = false;
      });
      _scrollToBottom();

      orchestrator
          .executeProcedure(
        plan: plan,
        userId: uid,
        onStepProgress: (updatedPlan, _) {
          if (mounted && planIndex < _messages.length) {
            setState(() {
              _messages[planIndex] = {
                'role': 'assistant',
                'type': 'agentic_plan',
                'plan': updatedPlan,
              };
            });
          }
        },
      )
          .then((completedPlan) async {
        tasks.updateStep(taskId, stepIdx, OvaStepStatus.done);
        tasks.finish(taskId, ok: true, summary: completedPlan.title);
        await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
              query: text,
              response: completedPlan.summary.isNotEmpty ? completedPlan.summary : completedPlan.title,
              source: OvaOriginSource.main,
              workspace: _activeWorkspace,
              threadId: _activeThreadId,
            );
        if (mounted && planIndex < _messages.length) {
          setState(() {
            _messages[planIndex] = {
              'role': 'assistant',
              'type': 'agentic_plan',
              'plan': completedPlan,
            };
          });
          ref.read(ovaThermalWatchdogProvider).pruneVisionMemory();
        }
      });
      return;
    }

    // 3. AI Brain + Studio / Channel Tools Loop
    final taskType =
        lowerText.contains('audio') || lowerText.contains('voice') ? 'audio' : 'general';
    final aiService = ref.read(aiBrainProvider);
    final remoteConnect = ref.read(remoteConnectProvider.notifier);

    try {
      var keepProcessing = true;
      var rounds = 0;
      while (keepProcessing && mounted && rounds < 5) {
        rounds++;
        final response = await aiService.processRequest(
          AIBrainService.sanitizeChatMessages(_messages),
          taskType: taskType,
          userContextPrompt:
              'You are Ova in the Oneova Main Workspace (${_activeWorkspace.label}). '
              'Give crisp, structured, actionable help tailored to creators and studio workflows.',
        );

        if (!mounted) return;

        if (response is AiTextResponse) {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'content': response.text,
              'type': 'text',
              if (response.diagnostic != null) 'diagnostic': response.diagnostic,
              if (response.diagnostic != null) 'retryPrompt': text,
            });
            _isChatLoading = false;
          });
          keepProcessing = false;
          tasks.updateStep(taskId, stepIdx, OvaStepStatus.done);
          tasks.finish(
            taskId,
            ok: true,
            summary: response.text.length > 140
                ? '${response.text.substring(0, 140)}…'
                : response.text,
          );
          await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
                query: text,
                response: response.text,
                source: OvaOriginSource.main,
                workspace: _activeWorkspace,
                threadId: _activeThreadId,
                persistToFirestore: !response.isDegraded,
              );
        } else if (response is AiWidgetResponse) {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'content': '',
              'type': 'widget',
              'widgetType': response.widgetType,
              'data': response.data,
            });
            _isChatLoading = false;
          });
          keepProcessing = false;
          tasks.updateStep(taskId, stepIdx, OvaStepStatus.done);
          tasks.finish(taskId, ok: true, summary: 'Generated visual widget');
          await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
                query: text,
                response: (response.data['title'] ?? 'Generated chart insight').toString(),
                source: OvaOriginSource.main,
                workspace: _activeWorkspace,
                threadId: _activeThreadId,
              );
        } else if (response is AiToolCallResponse) {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'content': null,
              'type': 'tool_call',
              'tool_calls': response.toolCalls,
            });
          });

          for (final call in response.toolCalls) {
            final function = call['function'] as Map<String, dynamic>? ?? const {};
            final name = (function['name'] ?? '').toString();
            final id = call['id'];
            final rawArgs = function['arguments'] as String?;
            final arguments = (rawArgs != null && rawArgs.isNotEmpty)
                ? (jsonDecode(rawArgs) as Map<String, dynamic>)
                : <String, dynamic>{};

            String toolResult;
            if (['apply_lut', 'add_marker', 'color_match', 'auto_balance', 'apply_film_emulation']
                .contains(name)) {
              remoteConnect.sendCommand('dr', name, arguments);
              toolResult = 'Executed $name on connected Studio workstation.';
            } else if (name == 'fetch_latest_comments') {
              final comments = await ref
                  .read(youtubeAgentProvider)
                  .fetchLatestComments(arguments['channel_id']?.toString() ?? '');
              toolResult = jsonEncode(comments);
            } else if (name == 'reply_to_comment') {
              final ok = await ref.read(youtubeAgentProvider).replyToComment(
                    arguments['comment_id']?.toString() ?? '',
                    arguments['text']?.toString() ?? '',
                  );
              toolResult = ok ? 'Replied to comment.' : 'Failed to reply to comment.';
            } else if (name == 'create_studio_project') {
              toolResult = await aiService.executeStudioTool(name, rawArgs ?? '{}');
            } else if (name == 'research_trending_topics') {
              final topics = await ref
                  .read(youtubeAgentProvider)
                  .researchTrendingTopics(arguments['query']?.toString() ?? '');
              toolResult = jsonEncode(topics);
            } else {
              toolResult = await aiService.executeStudioTool(name, rawArgs ?? '{}');
            }

            if (mounted) {
              setState(() {
                _messages.add({
                  'role': 'tool',
                  'content': toolResult,
                  'tool_call_id': id,
                  'name': name,
                });
              });
            }
          }
        }
      }
    } catch (e) {
      tasks.updateStep(taskId, stepIdx, OvaStepStatus.failed);
      tasks.finish(taskId, ok: false, summary: 'Request failed');
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': 'I couldn\'t complete that request right now. Please try again.',
            'type': 'text',
          });
          _isChatLoading = false;
        });
      }
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final isLiveVoice = _activeSection == OvaMainSection.liveVoice;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.bg,
      drawerEdgeDragWidth: 36,
      drawer: OvaMainDrawer(
        activeSection: _activeSection,
        activeWorkspace: _activeWorkspace,
        onNewChat: () {
          Navigator.of(context).maybePop();
          _startNewChat();
        },
        onSelectSection: (section) {
          Navigator.of(context).maybePop();
          _setSection(section);
        },
        onSelectWorkspace: (ws) {
          Navigator.of(context).maybePop();
          setState(() {
            _activeWorkspace = ws;
            if (_activeSection != OvaMainSection.home) {
              _setSection(OvaMainSection.home);
            }
          });
          if (ws == OvaWorkspaceId.research && _messages.isEmpty) {
            // Research workspace surfaces pre-production & research tools right on Home.
          }
        },
        onClose: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        bottom: isLiveVoice,
        child: isLiveVoice
            ? OvaLiveVoiceView(
                workspace: _activeWorkspace,
                onBack: () => _setSection(OvaMainSection.home),
              )
            : Column(
                children: [
                  _buildCompactHeader(context),
                  Divider(height: 1, thickness: 1, color: context.border),
                  Expanded(child: _buildActiveSectionBody(context)),
                ],
              ),
      ),
    );
  }

  Widget _buildCompactHeader(BuildContext context) {
    final profileAsync = _firebaseReady ? ref.watch(currentUserProfileProvider) : null;
    final authUser = _firebaseReady ? FirebaseAuth.instance.currentUser : null;
    final profile = profileAsync?.asData?.value;
    final displayName = (profile?.fullName.trim().isNotEmpty == true)
        ? profile!.fullName.trim()
        : (authUser?.displayName?.trim().isNotEmpty == true
            ? authUser!.displayName!.trim()
            : 'Creator');
    final photoUrl = (profile?.profilePhotoUrl?.trim().isNotEmpty == true)
        ? profile!.profilePhotoUrl
        : authUser?.photoURL;

    final remoteState = ref.watch(remoteConnectProvider);
    final onlineComputers = remoteState.computers.where((c) => c.isOnline).toList();
    final hasOnlineMac = onlineComputers.isNotEmpty;

    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to Home',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              onPressed: () {
                HapticFeedback.lightImpact();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/hub/home');
                }
              },
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: context.textPrimary),
            ),
            IconButton(
              tooltip: 'Open Ova menu',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              onPressed: () {
                HapticFeedback.lightImpact();
                _scaffoldKey.currentState?.openDrawer();
              },
              icon: Icon(Icons.notes_rounded, size: 20, color: context.textPrimary),
            ),
            const SizedBox(width: 2),
            const OvaWordmark(fontSize: 15.5, showSubtag: false),
            const SizedBox(width: 6),
            Container(
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: () => setState(() {
                      _useAgentWorkspace = true;
                      _activeSection = OvaMainSection.home;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _useAgentWorkspace
                            ? AppColors.brandBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        'Agent',
                        style: GoogleFonts.inter(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w700,
                          color: _useAgentWorkspace
                              ? AppColors.brandWhite
                              : context.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: () => setState(() {
                      _useAgentWorkspace = false;
                      _activeSection = OvaMainSection.home;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: !_useAgentWorkspace
                            ? AppColors.brandBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        'Studio',
                        style: GoogleFonts.inter(
                          fontSize: 10.2,
                          fontWeight: FontWeight.w700,
                          color: !_useAgentWorkspace
                              ? AppColors.brandWhite
                              : context.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (!_useAgentWorkspace) ...[
              _WorkspaceSelectorPill(
                activeWorkspace: _activeWorkspace,
                onSelected: (ws) => setState(() => _activeWorkspace = ws),
              ),
              const SizedBox(width: 4),
            ],
            Tooltip(
              message: hasOnlineMac
                  ? 'Open Online Device Control (${onlineComputers.first.computerName})'
                  : 'Connect or manage computers',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.full),
                onTap: () {
                  HapticFeedback.lightImpact();
                  if (hasOnlineMac) {
                    ref.read(remoteConnectProvider.notifier).setActiveComputer(onlineComputers.first.id);
                    context.push('/remote_control');
                  } else {
                    context.push('/connect');
                  }
                },
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: hasOnlineMac
                        ? AppColors.brandBlue.withValues(alpha: context.isDark ? 0.18 : 0.10)
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: hasOnlineMac
                          ? AppColors.brandBlue.withValues(alpha: 0.45)
                          : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasOnlineMac ? AppColors.brandBlue : context.textMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.desktop_mac_rounded,
                        size: 13,
                        color: hasOnlineMac ? AppColors.brandBlue : context.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Compact Live Voice pill CTA
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.full),
              onTap: () {
                HapticFeedback.lightImpact();
                _setSection(OvaMainSection.liveVoice);
              },
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: context.isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.38),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 13, color: AppColors.brandPink),
                    const SizedBox(width: 3),
                    Text(
                      'Voice',
                      style: GoogleFonts.inter(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandPink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.push('/profile/me');
              },
              child: CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.14),
                backgroundImage:
                    (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandBlue,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSectionBody(BuildContext context) {
    final mq = MediaQuery.of(context);
    final kbOpen = mq.viewInsets.bottom > 0;
    final bottomNavClearance =
        kbOpen ? 8.0 : (mq.padding.bottom > 0 ? mq.padding.bottom + 8.0 : 12.0);

    switch (_activeSection) {
      case OvaMainSection.home:
        if (_useAgentWorkspace) {
          return OvaAgentWorkspace(
            bottomClearance: bottomNavClearance,
            onOpenAuth: () => context.push('/profile/me'),
          );
        }
        return _buildHomeWorkspace(context);
      case OvaMainSection.agents:
        return OvaAgentsView(
          workspace: _activeWorkspace,
          onRunPrompt: (prompt) {
            if (_useAgentWorkspace) {
              setState(() => _activeSection = OvaMainSection.home);
              ref.read(ovaAgentSyncProvider.notifier).sendPrompt(prompt);
            } else {
              _sendMessage(prompt);
            }
          },
        );
      case OvaMainSection.explore:
        return OvaExploreView(
          onSelectPrompt: (prompt) {
            setState(() => _activeSection = OvaMainSection.home);
            if (_useAgentWorkspace && !prompt.endsWith(' ')) {
              ref.read(ovaAgentSyncProvider.notifier).sendPrompt(prompt);
              return;
            }
            if (prompt.endsWith(' ')) {
              setState(() => _useAgentWorkspace = false);
              _chatController.text = prompt;
              _chatController.selection = TextSelection.collapsed(offset: prompt.length);
              _chatFocus.requestFocus();
            } else {
              _sendMessage(prompt);
            }
          },
        );
      case OvaMainSection.library:
        return OvaLibraryView(
          workspace: _activeWorkspace,
          onUseInChat: (text) {
            setState(() => _activeSection = OvaMainSection.home);
            _chatController.text = text;
            _chatController.selection = TextSelection.collapsed(offset: text.length);
            _chatFocus.requestFocus();
          },
        );
      case OvaMainSection.history:
        return OvaHistoryView(onOpenThread: _openSharedThread);
      case OvaMainSection.liveVoice:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHomeWorkspace(BuildContext context) {
    final visibleMessages = _messages
        .where(
          (m) =>
              m['role'] == 'user' ||
              (m['role'] == 'assistant' &&
                  (m['type'] == 'text' || m['type'] == 'widget' || m['type'] == 'agentic_plan')),
        )
        .toList();

    final mq = MediaQuery.of(context);
    final kbOpen = mq.viewInsets.bottom > 0;
    final bottomNavClearance = kbOpen ? 8.0 : (mq.padding.bottom > 0 ? mq.padding.bottom + 8.0 : 72.0);

    return Stack(
      children: [
        // Subtle ambient studio aura at top right
        Positioned(
          top: -40,
          right: -30,
          child: IgnorePointer(
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandBlue.withValues(alpha: context.isDark ? 0.14 : 0.07),
                    AppColors.brandBlue.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            Expanded(
              child: visibleMessages.isEmpty
                  ? _buildHomeLanding(context)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      itemCount: visibleMessages.length + (_isChatLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == visibleMessages.length) {
                          return const _CompactThinkingRow();
                        }
                        final msg = visibleMessages[index];
                        if (msg['type'] == 'agentic_plan') {
                          return _buildAgenticPlanCard(context, msg['plan'] as AgenticProcedurePlan);
                        }
                        if (msg['type'] == 'widget' && msg['widgetType'] == 'chart') {
                          return _buildChartCard(context, msg['data'] as Map<String, dynamic>? ?? const {});
                        }
                        return _buildMessageBubble(
                          context,
                          msg['content'] as String? ?? '',
                          msg['role'] == 'user',
                          originBadge: msg['origin'] as String?,
                          diagnostic: msg['diagnostic'] as OvaAiDiagnostic?,
                          retryPrompt: msg['retryPrompt'] as String?,
                        );
                      },
                    ),
            ),
            _buildCompactComposer(context, bottomPadding: bottomNavClearance),
          ],
        ),
      ],
    );
  }

  Widget _buildHomeLanding(BuildContext context) {
    final profileAsync = _firebaseReady ? ref.watch(currentUserProfileProvider) : null;
    final authUser = _firebaseReady ? FirebaseAuth.instance.currentUser : null;
    final fullName = profileAsync?.asData?.value?.fullName ?? authUser?.displayName ?? '';
    final firstName = fullName.trim().isNotEmpty ? fullName.trim().split(' ').first : 'Creator';

    final sharedHistory = ref.watch(ovaSharedHistoryProvider);
    final taskState = ref.watch(ovaTaskCenterProvider);
    final recentThreads = sharedHistory.threads.take(4).toList();
    final adaptivePrompts = ref.watch(ovaAdaptiveSuggestionsServiceProvider).getPersonalizedPrompts();

    final hour = DateTime.now().hour;
    final salutation = hour < 12
        ? 'Good morning'
        : (hour < 18 ? 'Good afternoon' : 'Good evening');

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      children: [
        // Greeting
        Text(
          '$salutation, $firstName.',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _activeWorkspace.subtitle,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            height: 1.35,
            color: context.textSecondary,
          ),
        ),

        // Live Task Progress Banner (if an Overlay or Main task is actively running)
        if (taskState.active != null) ...[
          const SizedBox(height: 12),
          _LiveActiveTaskBanner(task: taskState.active!),
        ],

        const SizedBox(height: 14),

        // Section Header: Quick Capabilities
        Row(
          children: [
            Text(
              'WORKSPACE TOOLS',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: context.textMuted,
              ),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              onTap: () => _setSection(OvaMainSection.agents),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_forward_rounded, size: 13, color: AppColors.brandBlue),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Compact 2x2 Capability Grid
        Row(
          children: [
            Expanded(
              child: _MiniCapabilityCard(
                icon: Icons.auto_awesome_mosaic_outlined,
                title: 'Creative Studio',
                subtitle: 'Bring reel ideas to life.',
                onTap: () => _sendMessage(
                  'Give me 3 fresh, high-retention reel concepts tailored to my niche.',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniCapabilityCard(
                icon: Icons.event_note_outlined,
                title: 'Weekly Planner',
                subtitle: 'Plan shoots smarter.',
                onTap: () => _sendMessage(
                  'Help me plan a focused week around my content and business priorities.',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _MiniCapabilityCard(
                icon: Icons.movie_creation_outlined,
                title: 'Script Breakdown',
                subtitle: 'Shots, props & boards.',
                accent: true,
                onTap: () => OvaScriptBreakdownSheet.show(context, workspace: _activeWorkspace),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniCapabilityCard(
                icon: Icons.graphic_eq_rounded,
                title: 'Live Voice',
                subtitle: 'Talk hands-free now.',
                accent: true,
                onTap: () => _setSection(OvaMainSection.liveVoice),
              ),
            ),
          ],
        ),

        // Compact Smart Prompt Chips
        if (adaptivePrompts.isNotEmpty) ...[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in adaptivePrompts.take(5))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      onTap: () => _sendMessage(p.prompt),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.surface,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(p.icon, size: 13, color: AppColors.brandBlue),
                            const SizedBox(width: 6),
                            Text(
                              p.title,
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
                  ),
              ],
            ),
          ),
        ],

        // Shared Recent History & Activities (Main + Overlay + Voice)
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'RECENT HISTORY & ACTIVITIES',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: context.textMuted,
              ),
            ),
            const Spacer(),
            if (recentThreads.isNotEmpty || taskState.tasks.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                onTap: () => _setSection(OvaMainSection.history),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'History',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (recentThreads.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 17, color: context.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Shared history from Ova Main, Overlay & Voice appears here.',
                    style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                  ),
                ),
              ],
            ),
          )
        else
          for (final thread in recentThreads)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OvaThreadCompactTile(
                thread: thread,
                onTap: () => _openSharedThread(thread),
              ),
            ),
      ],
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    String text,
    bool isUser, {
    String? originBadge,
    OvaAiDiagnostic? diagnostic,
    String? retryPrompt,
  }) {
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: const BoxDecoration(
            color: AppColors.brandBlue,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppRadius.md),
              topRight: Radius.circular(AppRadius.md),
              bottomLeft: Radius.circular(AppRadius.md),
              bottomRight: Radius.circular(AppRadius.xs),
            ),
          ),
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.38,
              color: AppColors.brandWhite,
            ),
          ),
        ),
      );
    }

    final bodyStyle = GoogleFonts.inter(
      fontSize: 13,
      height: 1.42,
      color: context.textPrimary,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandBlue, AppColors.brandPink],
              ),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.brandWhite),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (originBadge != null && originBadge != 'Main')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'From $originBadge',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPink,
                        ),
                      ),
                    ),
                  MarkdownBody(
                    data: text,
                    selectable: true,
                    onTapLink: (_, href, _) {
                      if (href != null) {
                        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                      }
                    },
                    styleSheet: MarkdownStyleSheet(
                      p: bodyStyle,
                      listBullet: bodyStyle.copyWith(color: AppColors.brandBlue),
                      strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
                      h1: bodyStyle.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700),
                      h2: bodyStyle.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
                      h3: bodyStyle.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
                      code: GoogleFonts.jetBrainsMono(
                        fontSize: 11.5,
                        color: context.textPrimary,
                        backgroundColor: context.surfaceMid,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: context.border),
                      ),
                      tableBorder: TableBorder.all(color: context.border, width: 1),
                      tableHead: bodyStyle.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
                      tableBody: bodyStyle.copyWith(fontSize: 11.5),
                      blockquoteDecoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: const Border(left: BorderSide(color: AppColors.brandBlue, width: 3)),
                      ),
                    ),
                  ),
                  if (text.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _BubbleMicroAction(
                          icon: Icons.content_copy_rounded,
                          label: 'Copy',
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: text));
                            HapticFeedback.selectionClick();
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(
                                content: Text('Copied', style: GoogleFonts.inter(fontSize: 12)),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        _BubbleMicroAction(
                          icon: Icons.bookmark_add_outlined,
                          label: 'Save',
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final firstLine = text.split('\n').first.replaceAll(RegExp(r'[#*_`]'), '').trim();
                            await ref.read(ovaSharedHistoryProvider.notifier).saveToLibrary(
                                  title: firstLine.isEmpty ? 'Ova output' : firstLine,
                                  content: text,
                                  category: 'Output',
                                  workspace: _activeWorkspace,
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
                        ),
                        _BubbleMicroAction(
                          icon: Icons.volume_up_outlined,
                          label: 'Speak',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            OneovaLanguageService.instance.speak(
                              text.replaceAll(RegExp(r'[*#_`]'), ''),
                            );
                          },
                        ),
                        _BubbleMicroAction(
                          icon: Icons.translate_rounded,
                          label: 'Translate',
                          onTap: () {
                            final tempCtrl = TextEditingController(text: text);
                            OneovaLanguageActionSheet.show(
                              context,
                              controller: tempCtrl,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                  if (diagnostic != null) ...[
                    const SizedBox(height: 10),
                    _buildDiagnosticFooter(
                      context,
                      diagnostic,
                      retryPrompt: retryPrompt,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticFooter(
    BuildContext context,
    OvaAiDiagnostic diagnostic, {
    String? retryPrompt,
  }) {
    final isOffline = diagnostic.kind == OvaAiIssueKind.offline;
    final accent = isOffline ? AppColors.brandPink : AppColors.brandBlue;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOffline ? Icons.wifi_off_rounded : Icons.cloud_sync_rounded,
                size: 13,
                color: accent,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  diagnostic.badgeLabel,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            diagnostic.detail,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.32,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (retryPrompt != null && retryPrompt.trim().isNotEmpty)
                _DiagnosticActionChip(
                  icon: Icons.refresh_rounded,
                  label: 'Retry',
                  primary: true,
                  onTap: () {
                    OneovaAiGateway.resetCooldown();
                    _sendMessage(retryPrompt);
                  },
                ),
              _DiagnosticActionChip(
                icon: Icons.tune_rounded,
                label: 'AI Settings',
                onTap: () {
                  HapticFeedback.selectionClick();
                  context.push('/settings/ai');
                },
              ),
              _DiagnosticActionChip(
                icon: Icons.healing_rounded,
                label: 'Health Check',
                onTap: () => _sendMessage('Run system health check'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgenticPlanCard(BuildContext context, AgenticProcedurePlan plan) {
    final accent = plan.isComplete ? AppColors.brandPink : AppColors.brandBlue;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.auto_mode_rounded, size: 15, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      plan.isComplete ? 'Procedure complete' : 'Running autonomous steps…',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final step in plan.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: switch (step.status) {
                      AgenticStepStatus.running => const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: AppColors.brandBlue,
                          ),
                        ),
                      AgenticStepStatus.completed => const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: AppColors.brandBlue,
                        ),
                      AgenticStepStatus.failed => const Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: AppColors.brandPink,
                        ),
                      AgenticStepStatus.pending => Icon(
                          Icons.radio_button_unchecked_rounded,
                          size: 13,
                          color: context.textMuted,
                        ),
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          step.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (plan.isComplete && plan.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Text(
                plan.summary,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  height: 1.35,
                  color: context.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, Map<String, dynamic> data) {
    final title = (data['title'] ?? 'Insight').toString();
    final chartData = data['data'] as Map<String, dynamic>? ?? const {};
    final numericValues = chartData.values
        .map((v) => double.tryParse(v.toString().replaceAll(RegExp(r'[^0-9.]'), '')) ?? 1.0)
        .toList();
    final maxVal = numericValues.isEmpty
        ? 1.0
        : numericValues.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
              const Icon(Icons.bar_chart_rounded, size: 16, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (chartData.isEmpty)
            Text(
              'No metrics returned.',
              style: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
            )
          else
            for (final entry in chartData.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 68,
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: ((double.tryParse(
                                        entry.value.toString().replaceAll(RegExp(r'[^0-9.]'), ''),
                                      ) ??
                                      1.0) /
                                  maxVal)
                              .clamp(0.08, 1.0),
                          backgroundColor: context.surfaceMid,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.value.toString(),
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildCompactComposer(BuildContext context, {required double bottomPadding}) {
    final canSend = !_isChatLoading && _chatController.text.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      decoration: BoxDecoration(
        color: context.bg,
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.border, width: 1.0),
          boxShadow: context.isDark ? null : AppShadows.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                focusNode: _chatFocus,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                cursorColor: AppColors.brandBlue,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Ask Ova in ${_activeWorkspace.shortLabel}…',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            OneovaVoiceTypingButton(
              controller: _chatController,
              focusNode: _chatFocus,
              iconSize: 18,
              showTranslateAction: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Tooltip(
                message: 'Send',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: canSend ? _sendMessage : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: canSend
                          ? AppColors.brandBlue
                          : AppColors.brandBlue.withValues(alpha: 0.32),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: AppColors.brandWhite,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceSelectorPill extends StatelessWidget {
  final OvaWorkspaceId activeWorkspace;
  final ValueChanged<OvaWorkspaceId> onSelected;

  const _WorkspaceSelectorPill({
    required this.activeWorkspace,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<OvaWorkspaceId>(
      tooltip: 'Switch workspace',
      onSelected: (ws) {
        HapticFeedback.selectionClick();
        onSelected(ws);
      },
      color: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: context.border, width: 1.0),
      ),
      itemBuilder: (ctx) => [
        for (final ws in OvaWorkspaceId.values)
          PopupMenuItem<OvaWorkspaceId>(
            value: ws,
            height: 38,
            child: Row(
              children: [
                Icon(
                  ws.icon,
                  size: 16,
                  color: ws == activeWorkspace ? AppColors.brandBlue : ctx.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  ws.label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: ws == activeWorkspace ? FontWeight.w700 : FontWeight.w500,
                    color: ctx.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(activeWorkspace.icon, size: 12, color: AppColors.brandBlue),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                activeWorkspace.shortLabel,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: context.textMuted),
          ],
        ),
      ),
    );
  }
}

class _MiniCapabilityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool accent;
  final VoidCallback onTap;

  const _MiniCapabilityCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.brandPink : AppColors.brandBlue;
    return Material(
      color: context.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: context.isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveActiveTaskBanner extends StatelessWidget {
  final OvaTask task;

  const _LiveActiveTaskBanner({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Active: ${task.title}',
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
}

class _BubbleMicroAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BubbleMicroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.5, color: context.textMuted),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: context.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _DiagnosticActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: primary ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: primary ? AppColors.brandBlue : context.border,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: primary ? AppColors.brandWhite : AppColors.brandBlue,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: primary ? AppColors.brandWhite : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactThinkingRow extends StatelessWidget {
  const _CompactThinkingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 8),
          Text(
            'Ova is thinking…',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
