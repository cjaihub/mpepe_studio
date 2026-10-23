import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/router.dart';
import '../../shared/theme/app_theme.dart';
import '../ova_guard_service.dart';

/// Starts Ova Guard and shows a "Was this you?" banner over the whole app
/// while a high-risk security event is waiting for an answer.
class OvaGuardWatcher extends ConsumerStatefulWidget {
  final Widget child;
  const OvaGuardWatcher({super.key, required this.child});

  @override
  ConsumerState<OvaGuardWatcher> createState() => _OvaGuardWatcherState();
}

class _OvaGuardWatcherState extends ConsumerState<OvaGuardWatcher> {
  final Set<String> _dismissed = {};
  String? _confirmingSecure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(ovaGuardServiceProvider).start();
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _pending(List<QueryDocumentSnapshot<Map<String, dynamic>>> events) {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    for (final e in events) {
      final d = e.data();
      final at = d['at'];
      if (d['status'] != 'open' || _dismissed.contains(e.id)) continue;
      if (at is Timestamp && at.toDate().isBefore(weekAgo)) continue;
      return e;
    }
    return null;
  }

  Future<void> _act(String eventId, Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      _dismissed.add(eventId);
    } catch (e) {
      debugPrint('[OvaGuard] alert action: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirmingSecure = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(ovaGuardEventsProvider).value ?? const [];
    final event = _pending(events);
    if (event == null) return widget.child;
    final e = event.data();
    final reasons = (e['reasons'] as List?)?.cast<String>() ?? const [];
    final confirming = _confirmingSecure == event.id;
    final guard = ref.read(ovaGuardServiceProvider);

    return Stack(children: [
      widget.child,
      Positioned(
        left: 12,
        right: 12,
        top: MediaQuery.paddingOf(context).top + 8,
        child: Material(
          color: context.surface,
          elevation: 8,
          shadowColor: AppColors.brandBlack.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.6), width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.gpp_maybe_rounded, size: 18, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Ova Guard · ${e['title'] ?? 'Unusual activity'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: context.textMuted),
                  onPressed: () => setState(() => _dismissed.add(event.id)),
                ),
              ]),
              if (reasons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('${reasons.first}. Was this you?',
                      style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: context.textSecondary)),
                ),
              const SizedBox(height: 4),
              Row(children: [
                TextButton(
                  onPressed: _busy ? null : () => _act(event.id, () => guard.confirm(event.id)),
                  child: Text('Yes, it was me',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _dismissed.add(event.id));
                    ref.read(routerProvider).push('/profile/security');
                  },
                  child: Text('Details', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.brandBlue)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPink,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: _busy
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          if (!confirming) {
                            setState(() => _confirmingSecure = event.id);
                            return;
                          }
                          _act(event.id, () => guard.secureAccount(eventId: event.id));
                        },
                  child: Text(confirming ? 'Tap again: sign out everywhere' : 'Secure my account',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}
