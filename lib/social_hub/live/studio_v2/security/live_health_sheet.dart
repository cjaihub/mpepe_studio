// LIVE STUDIO v2 — "Live health" sheet: recent security incidents for host /
// co-hosts (security workstream). Read-only; actions live on the banner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/security/studio_security_api.dart';
import '../../../../backend/live_studio/security/studio_security_models.dart';
import '../theme/live_studio_tokens.dart';
import 'security_advisory_banner.dart';

Future<void> showLiveHealthSheet(BuildContext context, {required String streamId, required LiveStudioTokens tokens}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LiveStudioAccent.clear,
      barrierColor: LiveStudioTokens.dimTint(0.45),
      builder: (_) => LiveHealthSheet(streamId: streamId, tokens: tokens),
    );

/// "3 min ago" style age.
String studioAgeLabel(int atMs, int nowMs) {
  final s = ((nowMs - atMs) / 1000).floor();
  if (s < 60) return 'just now';
  if (s < 3600) return '${s ~/ 60} min ago';
  return '${s ~/ 3600} h ago';
}

class LiveHealthSheet extends ConsumerWidget {
  const LiveHealthSheet({super.key, required this.streamId, required this.tokens, this.now});

  final String streamId;
  final LiveStudioTokens tokens;

  /// Clock override for tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final async = ref.watch(studioSecurityIncidentsProvider(streamId));
    final nowMs = (now ?? DateTime.now)().millisecondsSinceEpoch;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.drawerTop, t.drawerBottom],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: t.drawerBorder, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 4, 6),
              child: Row(
                children: [
                  Icon(Icons.health_and_safety_outlined, size: 18, color: LiveStudioAccent.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('Live health', style: LiveStudioType.s(15, FontWeight.w700, t.textHigh, letter: -0.013)),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close live health',
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => Navigator.of(context).maybePop(),
                      radius: 22,
                      child: SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, size: 20, color: t.textMedium)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Automatic checks for floods, raids and repeated abuse. Only you and your co-hosts see this.',
                style: LiveStudioType.s(12, FontWeight.w400, t.textMedium, height: 16),
              ),
            ),
            Flexible(
              child: async.when(
                loading: () => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: LiveStudioAccent.blue)),
                ),
                error: (_, _) => _Empty(tokens: t, text: 'Could not load alerts.'),
                data: (list) => list.isEmpty
                    ? _Empty(tokens: t, text: 'No security alerts. All good.')
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _IncidentRow(incident: list[i], tokens: t, nowMs: nowMs),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tokens, required this.text});
  final LiveStudioTokens tokens;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Text(text, textAlign: TextAlign.center, style: LiveStudioType.s(13, FontWeight.w500, tokens.textMedium)),
      );
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident, required this.tokens, required this.nowMs});
  final StudioSecurityIncident incident;
  final LiveStudioTokens tokens;
  final int nowMs;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final accent = studioSeverityColor(incident.severity);
    final age = studioAgeLabel(incident.atMs, nowMs);
    return Semantics(
      container: true,
      label: '${incident.severity.wire} alert, $age: ${incident.reason}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: t.ghostFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.ghostBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(studioSeverityIcon(incident.severity), size: 16, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(incident.reason, style: LiveStudioType.s(12.5, FontWeight.w500, t.textHigh, height: 17)),
            ),
            const SizedBox(width: 8),
            Text(age, style: LiveStudioType.s(11, FontWeight.w400, t.textMedium)),
          ],
        ),
      ),
    );
  }
}
