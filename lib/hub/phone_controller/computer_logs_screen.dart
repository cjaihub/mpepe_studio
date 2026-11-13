import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import 'computer_action_log.dart';

/// Advanced activity log for computer control: every action with source,
/// app and result, filters, the encrypted history, dataset export, and the
/// built-in documentation of actions and the dataset format.
class ComputerLogsScreen extends ConsumerWidget {
  const ComputerLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          backgroundColor: context.bg,
          elevation: 0,
          toolbarHeight: 50,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
            onPressed: () => context.canPop() ? context.pop() : context.go('/auth/linked_devices'),
          ),
          titleSpacing: 0,
          title: Text(
            'Computer activity',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          bottom: TabBar(
            indicatorColor: AppColors.brandBlue,
            labelColor: AppColors.brandBlue,
            unselectedLabelColor: context.textSecondary,
            labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: const [Tab(text: 'Logs'), Tab(text: 'Docs')],
          ),
        ),
        body: const TabBarView(children: [ComputerLogPanel(), _DocsPanel()]),
      ),
    );
  }
}

/// The log list; also used inside the controller's side panel.
class ComputerLogPanel extends ConsumerStatefulWidget {
  const ComputerLogPanel({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<ComputerLogPanel> createState() => _ComputerLogPanelState();
}

class _ComputerLogPanelState extends ConsumerState<ComputerLogPanel> {
  ActionSource? _filter;
  List<ComputerActionStep>? _history;
  bool _loading = false;

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final h = await ref.read(computerActionLogProvider.notifier).loadHistory();
      if (mounted) setState(() => _history = h);
    } catch (_) {
      if (mounted) setState(() => _history = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ComputerActionStep> _merged(List<ComputerActionStep> live) {
    final seen = <String>{};
    final all = <ComputerActionStep>[];
    for (final s in [...live, ...?_history]) {
      if (seen.add(s.id)) all.add(s);
    }
    all.sort((a, b) => b.at.compareTo(a.at));
    return _filter == null ? all : all.where((s) => s.source == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(computerActionLogProvider);
    final steps = _merged(log.steps);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        on: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final s in ActionSource.values)
                        _FilterChip(
                          label: s.label,
                          on: _filter == s,
                          onTap: () => setState(() => _filter = s),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              Icon(
                log.syncing ? Icons.cloud_upload_outlined : Icons.lock_outline_rounded,
                size: 13,
                color: context.textMuted,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${steps.length} steps · encrypted on this phone',
                  style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: _loading ? null : _loadHistory,
                icon: _loading
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandBlue),
                      )
                    : const Icon(Icons.history_rounded, size: 15),
                label: Text('History', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                ),
                onPressed: steps.isEmpty
                    ? null
                    : () async {
                        HapticFeedback.selectionClick();
                        await ref.read(computerActionLogProvider.notifier).flush();
                        await ref.read(computerActionLogProvider.notifier).exportDataset(steps);
                      },
                icon: const Icon(Icons.dataset_outlined, size: 15),
                label: Text('Export', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: context.border),
        Expanded(
          child: steps.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No actions yet. Everything you or Ova do on the computer shows up here.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary, height: 1.4),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: steps.length,
                  separatorBuilder: (_, _) => Divider(height: 1, indent: 52, color: context.border),
                  itemBuilder: (context, i) => _StepTile(step: steps[i], compact: widget.compact),
                ),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, required this.compact});
  final ComputerActionStep step;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ai = step.source == ActionSource.ai;
    final failed = step.result != 'ok';
    final t = step.at;
    final time =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () => _showDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: (ai ? AppColors.brandPink : AppColors.brandBlue).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(step.icon, size: 15, color: ai ? AppColors.brandPink : AppColors.brandBlue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.summary + (step.count > 1 ? '  ×${step.count}' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: failed ? AppColors.brandPink : context.textPrimary,
                    ),
                  ),
                  if (!compact)
                    Text(
                      [step.source.label, if (step.app != null) step.app!, if (failed) step.result]
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
                    ),
                ],
              ),
            ),
            Text(
              time,
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: context.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.summary,
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ctx.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: ctx.border, width: 1.0),
                ),
                child: SelectableText(
                  const JsonEncoderIndent().convert(step.toJson()),
                  style: GoogleFonts.jetBrainsMono(fontSize: 11, color: ctx.textPrimary, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pretty-printer so the detail sheet shows readable JSON.
class JsonEncoderIndent {
  const JsonEncoderIndent();
  String convert(Object? o, [String pad = '']) {
    if (o is Map) {
      if (o.isEmpty) return '{}';
      final inner = o.entries.map((e) => '$pad  "${e.key}": ${convert(e.value, '$pad  ')}').join(',\n');
      return '{\n$inner\n$pad}';
    }
    if (o is List) return '[${o.map((e) => convert(e, pad)).join(', ')}]';
    if (o is String) return '"$o"';
    return '$o';
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.brandBlue : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.full),
            border: Border.all(color: on ? AppColors.brandBlue : context.border, width: 1.0),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: on ? AppColors.brandWhite : context.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DocsPanel extends StatelessWidget {
  const _DocsPanel();

  @override
  Widget build(BuildContext context) {
    Widget h(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Text(
            t,
            style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: context.textPrimary),
          ),
        );
    Widget p(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            t,
            style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary, height: 1.45),
          ),
        );
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: Text(a, style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: AppColors.brandBlue)),
              ),
              Expanded(
                child: Text(b, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary, height: 1.35)),
              ),
            ],
          ),
        );
    Widget code(String t) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4, bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: SelectableText(
            t,
            style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: context.textPrimary, height: 1.45),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        h('How it connects'),
        p('Your phone and computer pair once (QR, 6-digit code or the same Oneova account). '
            'After that they find each other through Oneova\'s signaling and talk directly over an '
            'encrypted WebRTC link (DTLS). When a direct path is blocked (different networks, strict '
            'routers), it goes through Oneova\'s encrypted relay once that is enabled, so it also works on mobile data.'),
        p('Pointer and scroll movements use a fast lane that drops late packets instead of waiting; '
            'clicks, keys, media and unlock use a reliable lane so nothing is lost or reordered.'),
        h('Live screen'),
        row('Tap', 'Click at that spot. Tap twice to double-click.'),
        row('Slide', 'The pointer follows your finger.'),
        row('Hold, slide', 'Drag (press, move, release).'),
        row('Hold, release', 'Right-click.'),
        row('Two fingers', 'Pinch to zoom, move to pan. Two-finger tap = right-click.'),
        h('Trackpad'),
        row('One finger', 'Move the pointer (faster strokes travel further).'),
        row('Tap', 'Click. Hold then move to drag; Drag lock keeps the button down.'),
        row('Two fingers', 'Scroll; flick to glide with momentum. Two-finger tap = right-click.'),
        row('Right edge', 'One-finger scroll rail.'),
        h('Ova Live'),
        p('Ova sees the screen about once a second and hears you. Ask in plain words (“open Safari and '
            'search for flights to Nairobi”). Ova says what it will do, acts one step at a time, and checks '
            'the screen after each step. It never types passwords and asks before anything destructive.'),
        h('Wake & unlock'),
        p('While Oneova Desktop runs it keeps the computer from idle sleep (the display can still turn '
            'off), so it stays reachable. Wake turns the display on. Unlock types your login password on '
            'the lock screen: the password is stored only on this phone behind your fingerprint, sent once '
            'inside the encrypted link, and never logged.'),
        h('Activity log'),
        p('Every action is recorded with who did it (touch, trackpad, media, voice, Ova), the front app, '
            'the result, and the goal it served. Pointer moves are merged so the log stays readable. Logs are '
            'encrypted on this phone with AES-256-GCM before they are saved to your account; only this phone '
            'holds the key. Passwords and hidden text are never recorded.'),
        h('Dataset format (oneova.computer_use.v1)'),
        p('Export writes JSONL: one episode per line, grouped by goal, steps in order. It can be used to '
            'teach or evaluate a computer-use model.'),
        code('{"schema":"oneova.computer_use.v1",\n'
            ' "goal":"open Safari and search flights",\n'
            ' "steps":[\n'
            '  {"i":0,"t":"2026-11-09T08:01:02Z","source":"ai",\n'
            '   "action":"key_combo","params":{"combo":"cmd+space"},\n'
            '   "app":"Finder","result":"ok"},\n'
            '  {"i":1,"source":"ai","action":"type_text",\n'
            '   "params":{"text":"Safari","enter":true}},\n'
            '  {"i":2,"source":"ai","action":"click",\n'
            '   "params":{"x":0.42,"y":0.08}}]}'),
        h('Actions'),
        row('click', 'x, y (0..1) optional; left / right / double'),
        row('move', 'dx, dy (relative) or x, y (absolute)'),
        row('drag', 'press at x, y → move → release'),
        row('scroll', 'dx, dy pixels (positive dy = content moves down)'),
        row('type_text', 'text, enter (redacted when secret)'),
        row('key_combo', 'combo, e.g. cmd+c'),
        row('press_key', 'enter, tab, esc, arrows…'),
        row('media_key', 'play, next, prev, mute, vol_up, vol_down'),
        row('volume_set', 'level 0–100'),
        row('wake / unlock', 'display wake; lock-screen password (never logged)'),
        row('user_said', 'what you asked (sets the goal)'),
        row('ai_said', 'what Ova answered'),
      ],
    );
  }
}
