import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/ai_brain_service.dart';
import '../../backend/project_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/oneova_voice_typing_button.dart';
import '../services/ova_shared_history_service.dart';
import '../services/ova_task_center.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 1. AI AGENTS VIEW (+ Script Pre-Production Breakdown Sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _AgentSpec {
  final String id;
  final String title;
  final String subtitle;
  final String category;
  final String badge;
  final bool pinkBadge;
  final IconData icon;
  final String prompt;
  final String? secondaryRoute;
  final String? secondaryLabel;
  final bool opensBreakdown;

  const _AgentSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.category,
    required this.badge,
    this.pinkBadge = false,
    required this.icon,
    required this.prompt,
    this.secondaryRoute,
    this.secondaryLabel,
    this.opensBreakdown = false,
  });
}

const List<_AgentSpec> _kOvaAgents = [
  _AgentSpec(
    id: 'creator_coach',
    title: 'Creator Growth Coach',
    subtitle: 'Viral reel hooks, retention pacing, captions & weekly content plans.',
    category: 'Creator',
    badge: 'CORE',
    icon: Icons.trending_up_rounded,
    prompt: 'Build a high-retention 7-day Oneova reel plan with 3 viral hooks and posting times.',
  ),
  _AgentSpec(
    id: 'script_breakdown',
    title: 'Script & Pre-Production',
    subtitle: 'Extract characters, props, shot lists & create Studio storyboards.',
    category: 'Studio',
    badge: 'STUDIO',
    pinkBadge: true,
    icon: Icons.movie_creation_outlined,
    prompt: '',
    opensBreakdown: true,
    secondaryRoute: '/create/studio',
    secondaryLabel: 'Studio',
  ),
  _AgentSpec(
    id: 'workstation_remote',
    title: 'Workstation Color & Edit',
    subtitle: 'Apply LUTs, color match clips & add timeline markers remotely.',
    category: 'Studio',
    badge: 'PRO',
    icon: Icons.tune_rounded,
    prompt: 'Help me balance skin tones, match shots, and prepare a clean cinema LUT workflow.',
    secondaryRoute: '/connect',
    secondaryLabel: 'Connect PC',
  ),
  _AgentSpec(
    id: 'youtube_social',
    title: 'Channel & Trend Scout',
    subtitle: 'Research trending topics, analyze comments & draft smart replies.',
    category: 'Creator',
    badge: 'LIVE DATA',
    icon: Icons.travel_explore_rounded,
    prompt: 'Research trending short-form video topics in my niche and suggest 3 angles.',
    secondaryRoute: '/social_hub',
    secondaryLabel: 'Accounts',
  ),
  _AgentSpec(
    id: 'connected_inbox',
    title: 'Connected Accounts Agent',
    subtitle: 'Triage Gmail, Instagram, WhatsApp & business messages in one place.',
    category: 'Operations',
    badge: 'SYNC',
    icon: Icons.mark_email_unread_outlined,
    prompt: 'Help me organize and draft concise replies for my priority business messages today.',
    secondaryRoute: '/social_hub',
    secondaryLabel: 'Accounts',
  ),
  _AgentSpec(
    id: 'system_doctor',
    title: 'Autonomous System Doctor',
    subtitle: 'Verify profile schema, heal media cache & scan Oneova health.',
    category: 'Operations',
    badge: 'AUTO',
    pinkBadge: true,
    icon: Icons.health_and_safety_outlined,
    prompt: 'Run autonomous system health check and self-repair diagnostics now.',
  ),
];

class OvaAgentsView extends StatefulWidget {
  final OvaWorkspaceId workspace;
  final ValueChanged<String> onRunPrompt;

  const OvaAgentsView({
    super.key,
    required this.workspace,
    required this.onRunPrompt,
  });

  @override
  State<OvaAgentsView> createState() => _OvaAgentsViewState();
}

class _OvaAgentsViewState extends State<OvaAgentsView> {
  String _category = 'All';
  static const _categories = ['All', 'Creator', 'Studio', 'Operations'];

  @override
  Widget build(BuildContext context) {
    final filtered = _category == 'All'
        ? _kOvaAgents
        : _kOvaAgents.where((a) => a.category == _category).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      children: [
        Text(
          'AI Agents',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Specialized Oneova agents wired to your ${widget.workspace.shortLabel.toLowerCase()} workspace & studio tools.',
          style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),

        // Compact category filter pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _CompactFilterPill(
                    label: cat,
                    selected: _category == cat,
                    onTap: () => setState(() => _category = cat),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        for (final agent in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AgentCompactCard(
              spec: agent,
              onLaunch: () {
                HapticFeedback.lightImpact();
                if (agent.opensBreakdown) {
                  OvaScriptBreakdownSheet.show(context, workspace: widget.workspace);
                } else {
                  widget.onRunPrompt(agent.prompt);
                }
              },
              onSecondary: agent.secondaryRoute == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      context.push(agent.secondaryRoute!);
                    },
            ),
          ),
      ],
    );
  }
}

class _AgentCompactCard extends StatelessWidget {
  final _AgentSpec spec;
  final VoidCallback onLaunch;
  final VoidCallback? onSecondary;

  const _AgentCompactCard({
    required this.spec,
    required this.onLaunch,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = spec.pinkBadge ? AppColors.brandPink : AppColors.brandBlue;

    return Container(
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: context.isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(spec.icon, size: 17, color: badgeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            spec.title,
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 1.0),
                          ),
                          child: Text(
                            spec.badge,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      spec.subtitle,
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
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: onLaunch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: AppColors.brandWhite,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  icon: Icon(
                    spec.opensBreakdown ? Icons.description_outlined : Icons.bolt_rounded,
                    size: 14,
                    color: AppColors.brandWhite,
                  ),
                  label: Text(
                    spec.opensBreakdown ? 'Open Breakdown' : 'Run Agent',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandWhite,
                    ),
                  ),
                ),
              ),
              if (onSecondary != null && spec.secondaryLabel != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.border, width: 1.0),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    child: Text(
                      spec.secondaryLabel!,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Interactive Script Pre-Production & Storyboard Breakdown Sheet (Light & Dark compliant).
class OvaScriptBreakdownSheet extends ConsumerStatefulWidget {
  final OvaWorkspaceId workspace;

  const OvaScriptBreakdownSheet({
    super.key,
    required this.workspace,
  });

  static Future<void> show(
    BuildContext context, {
    OvaWorkspaceId workspace = OvaWorkspaceId.research,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OvaScriptBreakdownSheet(workspace: workspace),
    );
  }

  @override
  ConsumerState<OvaScriptBreakdownSheet> createState() => _OvaScriptBreakdownSheetState();
}

class _OvaScriptBreakdownSheetState extends ConsumerState<OvaScriptBreakdownSheet> {
  final TextEditingController _scriptCtrl = TextEditingController();
  ScriptBreakdown? _breakdown;
  bool _loading = false;
  bool _savingProject = false;

  @override
  void dispose() {
    _scriptCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyzeScript() async {
    final script = _scriptCtrl.text.trim();
    if (script.isEmpty || _loading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _breakdown = null;
    });

    final tasks = ref.read(ovaTaskCenterProvider.notifier);
    final taskId = tasks.start('Script breakdown analysis', source: 'ai_lab');
    final step = tasks.addStep(taskId, 'Extracting characters, props & shot list', Icons.movie_filter_outlined);

    try {
      final result = await ref.read(aiBrainProvider).breakdownScript(script);
      if (!mounted) return;
      setState(() {
        _breakdown = result;
        _loading = false;
      });
      final ok = result != null;
      tasks.updateStep(taskId, step, ok ? OvaStepStatus.done : OvaStepStatus.failed);
      tasks.finish(taskId, ok: ok, summary: result != null ? 'Analyzed "${result.title}" (${result.shotList.length} shots)' : 'Could not parse script');

      if (result != null) {
        await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
              query: 'Script Breakdown: ${script.length > 80 ? "${script.substring(0, 80)}…" : script}',
              response:
                  '${result.title} — Characters: ${result.characters.join(", ")}. Shots: ${result.shotList.length}.',
              source: OvaOriginSource.main,
              workspace: widget.workspace,
            );
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      tasks.updateStep(taskId, step, OvaStepStatus.failed);
      tasks.finish(taskId, ok: false, summary: 'Script breakdown failed');
    }
  }

  Future<void> _createStudioProject() async {
    final bd = _breakdown;
    if (bd == null || _savingProject) return;
    HapticFeedback.mediumImpact();
    setState(() => _savingProject = true);
    try {
      final urls = bd.shotList.map((shot) {
        final prompt =
            '${bd.title}, ${shot['shot']}, ${shot['description']}, cinematic storyboard frame, high contrast';
        return 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}?width=1280&height=720&nologo=true';
      }).toList();

      await ref.read(projectRepositoryProvider).addProject(
            StudioProject(
              id: '',
              category: 'Video',
              title: bd.title,
              status: 'Scripting',
              completedSteps: 1,
              characters: bd.characters,
              props: bd.props,
              storyboardUrls: urls,
              script: _scriptCtrl.text.trim(),
              createdAt: DateTime.now(),
            ),
          );
      await ref.read(ovaSharedHistoryProvider.notifier).saveToLibrary(
            title: 'Breakdown · ${bd.title}',
            content:
                'Characters: ${bd.characters.join(", ")}\nProps: ${bd.props.join(", ")}\nShots:\n${bd.shotList.map((s) => "- ${s['shot']}: ${s['description']}").join("\n")}',
            category: 'Script',
            workspace: widget.workspace,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            'Studio project "${bd.title}" created & saved to Library.',
            style: GoogleFonts.inter(fontSize: 12.5),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Could not create project: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingProject = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border(top: BorderSide(color: context.border, width: 1.0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: context.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.movie_creation_outlined, size: 18, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Script Pre-Production Breakdown',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, size: 19, color: context.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_breakdown == null) ...[
              Flexible(
                child: TextField(
                  controller: _scriptCtrl,
                  minLines: 6,
                  maxLines: 12,
                  onChanged: (_) => setState(() {}),
                  style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: context.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText:
                        'Paste or dictate scene script (e.g. INT. STUDIO - DAY\nCreator steps into frame with vintage camera...)',
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                    filled: true,
                    fillColor: context.surfaceMid,
                    contentPadding: const EdgeInsets.all(12),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: OneovaVoiceTypingButton(
                        controller: _scriptCtrl,
                        showTranslateAction: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: _loading || _scriptCtrl.text.trim().isEmpty ? null : _analyzeScript,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: AppColors.brandWhite,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(
                    _loading ? 'Analyzing script…' : 'Generate Shot List & Breakdown',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ] else ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _breakdown!.title,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Characters: ${_breakdown!.characters.isEmpty ? "—" : _breakdown!.characters.join(", ")}',
                              style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Props: ${_breakdown!.props.isEmpty ? "—" : _breakdown!.props.join(", ")}',
                              style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'SHOT LIST (${_breakdown!.shotList.length})',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: context.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final shot in _breakdown!.shotList)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: context.bg,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: context.border, width: 1.0),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.brandBlue.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  (shot['shot'] ?? 'SHOT').toString(),
                                  style: GoogleFonts.inter(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandBlue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (shot['description'] ?? '').toString(),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: context.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton(
                        onPressed: () => setState(() => _breakdown = null),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: context.border, width: 1.0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        ),
                        child: Text(
                          'Edit script',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: _savingProject ? null : _createStudioProject,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: AppColors.brandWhite,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        ),
                        icon: const Icon(Icons.add_box_outlined, size: 16),
                        label: Text(
                          _savingProject ? 'Saving…' : 'Create Studio Project',
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. EXPLORE VIEW
// ─────────────────────────────────────────────────────────────────────────────

class _ExploreTemplate {
  final String title;
  final String description;
  final String category;
  final IconData icon;
  final String prompt;
  final bool accent;

  const _ExploreTemplate({
    required this.title,
    required this.description,
    required this.category,
    required this.icon,
    required this.prompt,
    this.accent = false,
  });
}

const List<_ExploreTemplate> _kExploreTemplates = [
  _ExploreTemplate(
    title: '3-Second Viral Hook Generator',
    description: 'Craft scroll-stopping opening lines & visual cues for your next Reel.',
    category: 'Reels & Hooks',
    icon: Icons.bolt_rounded,
    prompt: 'Give me 5 scroll-stopping 3-second hooks with camera direction for a short video about ',
    accent: true,
  ),
  _ExploreTemplate(
    title: 'Focused Weekly Creator Planner',
    description: 'Organize shoots, edits, live streams & deep work blocks.',
    category: 'Planning',
    icon: Icons.calendar_today_outlined,
    prompt: 'Help me plan a focused week around my top 3 content and business priorities.',
  ),
  _ExploreTemplate(
    title: 'Biz Product Launch Script',
    description: 'Turn any product into a persuasive 30-second Oneova Biz showcase.',
    category: 'Business',
    icon: Icons.storefront_outlined,
    prompt: 'Write a clean 30-second Biz product showcase script with call-to-action for ',
  ),
  _ExploreTemplate(
    title: 'Cinema Look & Color Recipe',
    description: 'Design mood, contrast curves & skin-safe grading notes for your shoot.',
    category: 'Studio & Grade',
    icon: Icons.palette_outlined,
    prompt: 'Suggest a cinematic color grading recipe (contrast, warmth, halation, skin tone balance) for a moody evening reel.',
  ),
  _ExploreTemplate(
    title: 'Live Stream Run-of-Show',
    description: 'Plan interactive segments, Q&A prompts & audience engagement spikes.',
    category: 'Reels & Hooks',
    icon: Icons.sensors_rounded,
    prompt: 'Create a tight 20-minute Oneova Live run-of-show with audience engagement checkpoints.',
    accent: true,
  ),
  _ExploreTemplate(
    title: 'Brand Collaboration Pitch',
    description: 'Professional outreach note tailored to sponsors & brand partners.',
    category: 'Business',
    icon: Icons.handshake_outlined,
    prompt: 'Draft a concise, executive-grade brand collaboration pitch highlighting my creator engagement.',
  ),
];

class OvaExploreView extends StatefulWidget {
  final ValueChanged<String> onSelectPrompt;

  const OvaExploreView({
    super.key,
    required this.onSelectPrompt,
  });

  @override
  State<OvaExploreView> createState() => _OvaExploreViewState();
}

class _OvaExploreViewState extends State<OvaExploreView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _category = 'All';
  static const _categories = ['All', 'Reels & Hooks', 'Planning', 'Business', 'Studio & Grade'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final items = _kExploreTemplates.where((t) {
      final catOk = _category == 'All' || t.category == _category;
      final qOk = q.isEmpty ||
          t.title.toLowerCase().contains(q) ||
          t.description.toLowerCase().contains(q);
      return catOk && qOk;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      children: [
        Text(
          'Explore Workflows',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Ready-to-run studio workflows, growth playbooks & planning prompts.',
          style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
        ),
        const SizedBox(height: 10),
        _CompactSearchField(
          controller: _searchCtrl,
          hintText: 'Search workflows & prompts…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _CompactFilterPill(
                    label: cat,
                    selected: _category == cat,
                    onTap: () => setState(() => _category = cat),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onSelectPrompt(item.prompt);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (item.accent ? AppColors.brandPink : AppColors.brandBlue)
                            .withValues(alpha: context.isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        item.icon,
                        size: 16,
                        color: item.accent ? AppColors.brandPink : AppColors.brandBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.description,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              height: 1.3,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded, size: 13, color: context.textMuted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. LIBRARY VIEW
// ─────────────────────────────────────────────────────────────────────────────

class OvaLibraryView extends ConsumerWidget {
  final OvaWorkspaceId workspace;
  final ValueChanged<String> onUseInChat;

  const OvaLibraryView({
    super.key,
    required this.workspace,
    required this.onUseInChat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(ovaSharedHistoryProvider);
    final entries = history.library;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Library',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Saved prompts, script breakdowns & pinned Ova outputs.',
                    style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 34,
              child: ElevatedButton.icon(
                onPressed: () => _showAddLibrarySheet(context, ref, workspace),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: AppColors.brandWhite,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: Text(
                  'Save prompt',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (entries.isEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              children: [
                Icon(Icons.collections_bookmark_outlined, size: 26, color: context.textMuted),
                const SizedBox(height: 8),
                Text(
                  'Your Library is empty',
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bookmark any Ova answer or tap "Save prompt" above to keep reusable prompts & scripts handy.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: context.textSecondary),
                ),
              ],
            ),
          )
        else
          for (final item in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            item.category.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.workspace.shortLabel,
                          style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
                        ),
                        const Spacer(),
                        Text(
                          formatRelativeTime(item.createdAt),
                          style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.35,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MiniTextAction(
                          icon: Icons.send_rounded,
                          label: 'Use in chat',
                          color: AppColors.brandBlue,
                          onTap: () => onUseInChat(item.content),
                        ),
                        const SizedBox(width: 10),
                        _MiniTextAction(
                          icon: Icons.content_copy_rounded,
                          label: 'Copy',
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: item.content));
                            HapticFeedback.selectionClick();
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              SnackBar(
                                content: Text('Copied to clipboard', style: GoogleFonts.inter(fontSize: 12)),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        const Spacer(),
                        _MiniTextAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'Remove',
                          color: AppColors.brandPink,
                          onTap: () async {
                            final confirmed = await _confirmDestructiveDialog(
                              context,
                              title: 'Remove from Library?',
                              message: 'This saved item will be permanently removed from your Ova Library.',
                              confirmLabel: 'Remove',
                            );
                            if (confirmed == true) {
                              await ref.read(ovaSharedHistoryProvider.notifier).deleteLibraryItem(item.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  void _showAddLibrarySheet(BuildContext context, WidgetRef ref, OvaWorkspaceId workspace) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                  border: Border(top: BorderSide(color: context.border, width: 1.0)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Save Prompt or Note',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: titleCtrl,
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Title (e.g. Reel Hook Formula)',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                          filled: true,
                          fillColor: context.surfaceMid,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bodyCtrl,
                        minLines: 3,
                        maxLines: 6,
                        onChanged: (_) => setModalState(() {}),
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Prompt or reusable template text…',
                          hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                          filled: true,
                          fillColor: context.surfaceMid,
                          contentPadding: const EdgeInsets.all(12),
                          suffixIcon: OneovaVoiceTypingButton(
                            controller: bodyCtrl,
                            onChanged: (_) => setModalState(() {}),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 38,
                        child: ElevatedButton(
                          onPressed: bodyCtrl.text.trim().isEmpty
                              ? null
                              : () async {
                                  await ref.read(ovaSharedHistoryProvider.notifier).saveToLibrary(
                                        title: titleCtrl.text.trim().isEmpty
                                            ? 'Custom prompt'
                                            : titleCtrl.text.trim(),
                                        content: bodyCtrl.text.trim(),
                                        category: 'Prompt',
                                        workspace: workspace,
                                      );
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandBlue,
                            foregroundColor: AppColors.brandWhite,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: Text(
                            'Save to Library',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. SHARED HISTORY & ACTIVITIES VIEW
// ─────────────────────────────────────────────────────────────────────────────

class OvaHistoryView extends ConsumerStatefulWidget {
  final ValueChanged<OvaSharedThread> onOpenThread;

  const OvaHistoryView({
    super.key,
    required this.onOpenThread,
  });

  @override
  ConsumerState<OvaHistoryView> createState() => _OvaHistoryViewState();
}

class _OvaHistoryViewState extends ConsumerState<OvaHistoryView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = 'All';
  static const _filters = ['All', 'Main', 'Overlay', 'Voice', 'Activities'];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(ovaSharedHistoryProvider);
    final taskState = ref.watch(ovaTaskCenterProvider);
    final q = _searchCtrl.text.trim().toLowerCase();

    final threads = shared.threads.where((t) {
      if (_filter == 'Main' && t.source != OvaOriginSource.main) return false;
      if (_filter == 'Overlay' && t.source != OvaOriginSource.overlay) return false;
      if (_filter == 'Voice' && t.source != OvaOriginSource.voice) return false;
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) || t.preview.toLowerCase().contains(q);
    }).toList();

    final activities = taskState.tasks.where((t) {
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) || (t.summary?.toLowerCase().contains(q) ?? false);
    }).toList();

    final showActivities = _filter == 'All' || _filter == 'Activities';
    final showThreads = _filter != 'Activities';

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History & Activities',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Shared across Ova Main Workspace, Overlay Assistant & Live Voice.',
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                  ),
                ],
              ),
            ),
            if (shared.threads.isNotEmpty)
              IconButton(
                tooltip: 'Clear history',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final ok = await _confirmDestructiveDialog(
                    context,
                    title: 'Clear shared Ova history?',
                    message:
                        'All saved conversations from Ova Main and Ova Overlay will be permanently deleted.',
                    confirmLabel: 'Clear all',
                  );
                  if (ok == true) {
                    await ref.read(ovaSharedHistoryProvider.notifier).clearAllHistory();
                  }
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 19, color: AppColors.brandPink),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _CompactSearchField(
          controller: _searchCtrl,
          hintText: 'Search shared chats & activities…',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _CompactFilterPill(
                    label: f,
                    selected: _filter == f,
                    onTap: () => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Live & Recent Task Center Activities
        if (showActivities && activities.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'RECENT ACTIVITIES',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: context.textMuted,
              ),
            ),
          ),
          for (final task in activities.take(_filter == 'Activities' ? 20 : 4))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ActivityCompactRow(task: task),
            ),
          const SizedBox(height: 10),
        ],

        // Shared Conversation Threads
        if (showThreads) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'CONVERSATIONS',
              style: GoogleFonts.inter(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: context.textMuted,
              ),
            ),
          ),
          if (threads.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Column(
                children: [
                  Icon(Icons.history_rounded, size: 24, color: context.textMuted),
                  const SizedBox(height: 6),
                  Text(
                    'No conversations yet',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Chats and voice turns from both Ova Main and the Ova Overlay appear here automatically.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                  ),
                ],
              ),
            )
          else
            for (final thread in threads)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: OvaThreadCompactTile(
                  thread: thread,
                  onTap: () => widget.onOpenThread(thread),
                  onDelete: () async {
                    final ok = await _confirmDestructiveDialog(
                      context,
                      title: 'Delete conversation?',
                      message: 'Remove "${thread.title}" from shared Ova history?',
                      confirmLabel: 'Delete',
                    );
                    if (ok == true) {
                      await ref.read(ovaSharedHistoryProvider.notifier).deleteThread(thread.id);
                    }
                  },
                ),
              ),
        ],
      ],
    );
  }
}

/// Reusable compact row for a shared thread (used in History view & Home recent list).
class OvaThreadCompactTile extends StatelessWidget {
  final OvaSharedThread thread;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const OvaThreadCompactTile({
    super.key,
    required this.thread,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isAccent = thread.source == OvaOriginSource.voice;
    final badgeColor = isAccent ? AppColors.brandPink : AppColors.brandBlue;

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: context.isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(thread.source.icon, size: 14, color: badgeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Text(
                            thread.source.badgeLabel,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (thread.preview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        thread.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatRelativeTime(thread.updatedAt),
                style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete thread',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.only(left: 4),
                  constraints: const BoxConstraints(),
                  onPressed: onDelete,
                  icon: Icon(Icons.close_rounded, size: 15, color: context.textMuted),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.chevron_right_rounded, size: 16, color: context.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityCompactRow extends StatelessWidget {
  final OvaTask task;

  const _ActivityCompactRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final isRunning = task.running;
    final ok = task.status == OvaTaskStatus.done;
    final color = isRunning
        ? AppColors.brandBlue
        : (ok ? AppColors.brandBlue : AppColors.brandPink);
    final sourceLabel = task.source == 'ai_lab' ? 'Main' : 'Overlay';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          if (isRunning)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: AppColors.brandBlue),
            )
          else
            Icon(
              ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              size: 15,
              color: color,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
                if (task.summary != null && task.summary!.trim().isNotEmpty)
                  Text(
                    task.summary!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              sourceLabel,
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: context.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatRelativeTime(task.startedAt),
            style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL UI HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _CompactFilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CompactFilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : context.surface,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? AppColors.brandBlue : context.border,
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.brandWhite : context.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CompactSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _CompactSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
        prefixIcon: Icon(Icons.search_rounded, size: 17, color: context.textMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: Icon(Icons.close_rounded, size: 15, color: context.textMuted),
              ),
            OneovaVoiceTypingButton(
              controller: controller,
              iconSize: 16,
              enableLanguageDetectionToast: false,
              onChanged: onChanged,
            ),
            const SizedBox(width: 4),
          ],
        ),
        filled: true,
        fillColor: context.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.border, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.border, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
        ),
      ),
    );
  }
}

class _MiniTextAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _MiniTextAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _confirmDestructiveDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) {
  HapticFeedback.mediumImpact();
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: ctx.border, width: 1.0),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
          color: ctx.textPrimary,
        ),
      ),
      content: Text(
        message,
        style: GoogleFonts.inter(
          fontSize: 12.5,
          height: 1.4,
          color: ctx.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
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
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brandPink,
            foregroundColor: AppColors.brandWhite,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
          child: Text(
            confirmLabel,
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

String formatRelativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.month}/${time.day}';
}
