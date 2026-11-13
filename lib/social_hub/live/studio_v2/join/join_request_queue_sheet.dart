// LIVE STUDIO v2 — JoinRequestQueueSheet (workstream #4, host / co-host).
//
// Live list of pending requests (Firestore stream, oldest first) with
// Approve / Decline per row. Nothing here writes Firestore: answers go
// through StudioRequestQueueController → lsRespondRequest.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/security/studio_security_models.dart';
import '../../../../backend/live_studio/roles/studio_request_queue_controller.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart' show studioFirestoreProvider;
import '../theme/live_studio_tokens.dart';

/// Semantics labels (shared with tests).
class JoinQueueLabels {
  JoinQueueLabels._();
  static const String sheet = 'Join requests';
  static const String empty = 'No requests right now';
  static String approve(String name) => 'Approve $name';
  static String decline(String name) => 'Decline $name';
}

Future<void> showJoinRequestQueueSheet(BuildContext context, {required String streamId, required LiveStudioTokens tokens}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: tokens.base.withValues(alpha: 0),
    barrierColor: LiveStudioTokens.dimTint(0.45),
    builder: (_) => JoinRequestQueueSheet(streamId: streamId, tokens: tokens),
  );
}

/// Who is on stage now (`studio/state.stage`), for the x/10 counter.
final _stageProvider = StreamProvider.autoDispose.family<StageLayout?, String>((ref, streamId) => ref
    .watch(studioFirestoreProvider)
    .doc(StudioPaths.state(streamId))
    .snapshots()
    .map((d) => d.data()?['stage'] is Map ? StageLayout.fromJson(Map<String, dynamic>.from(d.data()!['stage'] as Map)) : null));

class JoinRequestQueueSheet extends ConsumerWidget {
  const JoinRequestQueueSheet({super.key, required this.streamId, required this.tokens});

  final String streamId;
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = tokens;
    final ctlProvider = studioRequestQueueControllerProvider(streamId);
    ref.listen<StudioRequestQueueView>(ctlProvider, (prev, next) {
      final err = next.error;
      if (err != null && err != prev?.error) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
        ref.read(ctlProvider.notifier).clearError();
      }
    });
    final view = ref.watch(ctlProvider);
    final ctl = ref.read(ctlProvider.notifier);
    final async = ref.watch(studioPendingRequestsProvider(streamId));
    final pending = ctl.visible(async.value ?? const []);
    final stage = ref.watch(_stageProvider(streamId)).value;
    final onStage = stage?.headcount ?? 0;
    final full = stage?.isFull ?? false;
    final maxH = MediaQuery.sizeOf(context).height * 0.7;

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMedium))),
      );
    } else if (async.hasError && !async.hasValue) {
      body = _Message(tokens: t, icon: Icons.lock_outline, text: 'Only the host and co-hosts can see requests.');
    } else if (pending.isEmpty) {
      body = _Message(tokens: t, icon: Icons.group_outlined, text: JoinQueueLabels.empty);
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: pending.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = pending[i];
          return _RequestRow(
            tokens: t,
            request: r,
            busy: view.inFlight.contains(r.uid),
            full: full,
            onApprove: () {
              HapticFeedback.lightImpact();
              unawaited(ctl.approve(r.uid));
            },
            onDecline: () {
              HapticFeedback.lightImpact();
              unawaited(ctl.decline(r.uid));
            },
          );
        },
      );
    }

    return Semantics(
      label: JoinQueueLabels.sheet,
      container: true,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.drawerTop, t.drawerBottom],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: t.drawerBorder, width: 1)),
        ),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: t.ghostBorder, borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Text('Join requests', style: LiveStudioType.s(17, FontWeight.w700, t.textHigh, letter: -0.018)),
              const SizedBox(width: 8),
              if (pending.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: LiveStudioAccent.pink, borderRadius: BorderRadius.circular(999)),
                  child: Text('${pending.length}',
                      style: LiveStudioType.s(10, FontWeight.w800, LiveStudioAccent.white, letter: 0.06)),
                ),
              const Spacer(),
              if (stage != null)
                Semantics(
                  label: 'On stage $onStage of ${StudioLimits.maxOnStage}',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: full ? LiveStudioAccent.pinkA(0.16) : t.ghostFill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: full ? LiveStudioAccent.pink : t.ghostBorder, width: 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.groups_2_outlined, size: 14, color: full ? LiveStudioAccent.pink : t.textMedium),
                      const SizedBox(width: 4),
                      Text(full ? 'Stage full' : 'On stage $onStage/${StudioLimits.maxOnStage}',
                          style: LiveStudioType.s(11, FontWeight.w700, full ? LiveStudioAccent.pink : t.textMedium)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            _GuestModeSwitch(streamId: streamId, tokens: t),
            const SizedBox(height: 12),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }
}

/// `live_streams/{id}.allowGuestRequests` (absent = open).
final _guestsOpenProvider = StreamProvider.autoDispose.family<bool, String>((ref, streamId) => ref
    .watch(studioFirestoreProvider)
    .collection('live_streams')
    .doc(streamId)
    .snapshots()
    .map((d) => d.data()?['allowGuestRequests'] != false));

/// Solo ⇄ open to guests, in place: the live keeps its screen and stage.
class _GuestModeSwitch extends ConsumerStatefulWidget {
  const _GuestModeSwitch({required this.streamId, required this.tokens});
  final String streamId;
  final LiveStudioTokens tokens;

  @override
  ConsumerState<_GuestModeSwitch> createState() => _GuestModeSwitchState();
}

class _GuestModeSwitchState extends ConsumerState<_GuestModeSwitch> {
  bool? _pending;

  Future<void> _set(bool open) async {
    HapticFeedback.selectionClick();
    setState(() => _pending = open);
    try {
      await ref
          .read(studioCallPortProvider)
          .call(StudioSecurityWire.setJoinRequests, {'streamId': widget.streamId, 'open': open});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Could not change guest mode. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final open = _pending ?? ref.watch(_guestsOpenProvider(widget.streamId)).value ?? true;
    Widget seg(String label, IconData icon, bool value) {
      final on = open == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: on || _pending != null ? null : () => _set(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 38,
              decoration: BoxDecoration(
                color: on ? LiveStudioAccent.pink : t.ghostFill.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 16, color: on ? LiveStudioAccent.white : t.textMedium),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LiveStudioType.s(13, FontWeight.w700, on ? LiveStudioAccent.white : t.textMedium)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.ghostFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.ghostBorder, width: 1),
        ),
        child: Row(children: [
          seg('Solo', Icons.person_outline, false),
          seg('Open to guests', Icons.groups_2_outlined, true),
        ]),
      ),
      const SizedBox(height: 6),
      Text(
        open ? 'Viewers can ask to join your stage.' : 'Only you are on stage. Requests are paused.',
        style: LiveStudioType.s(12, FontWeight.w500, t.textMedium),
      ),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.tokens, required this.icon, required this.text});
  final LiveStudioTokens tokens;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 26, color: tokens.textMedium),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: LiveStudioType.s(12.5, FontWeight.w500, tokens.textMedium)),
        ]),
      );
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.tokens,
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDecline,
    this.full = false,
  });
  final LiveStudioTokens tokens;
  final JoinRequest request;
  final bool busy;

  /// The stage holds [StudioLimits.maxOnStage] people: Approve is disabled.
  final bool full;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final name = request.displayName.isEmpty ? 'Someone' : request.displayName;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: t.ghostFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.ghostBorder, width: 1),
      ),
      child: Row(children: [
        _Avatar(tokens: t, url: request.avatarUrl, name: name),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LiveStudioType.s(13.5, FontWeight.w700, t.textHigh)),
            const SizedBox(height: 2),
            Text(full ? 'Stage is full — remove someone first' : 'Wants to join the stage',
                style: LiveStudioType.s(11, FontWeight.w500, t.textMedium)),
          ]),
        ),
        if (busy)
          SizedBox(
            width: 44,
            height: 44,
            child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: t.textMedium))),
          )
        else ...[
          Semantics(
            button: true,
            label: JoinQueueLabels.decline(name),
            excludeSemantics: true,
            child: IconButton(
              onPressed: onDecline,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.close, size: 20, color: t.textMedium),
              tooltip: 'Decline',
            ),
          ),
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: JoinQueueLabels.approve(name),
            excludeSemantics: true,
            child: Material(
              color: full ? t.ghostFill : LiveStudioAccent.blue,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: full ? null : onApprove,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      widthFactor: 1,
                      child: Text('Approve',
                          style: LiveStudioType.s(12.5, FontWeight.w700, full ? t.textMedium : LiveStudioAccent.white)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.tokens, required this.url, required this.name});
  final LiveStudioTokens tokens;
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tokens.commentAvatar,
        shape: BoxShape.circle,
        border: Border.all(color: LiveStudioAccent.blue, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? Center(child: Text(initial, style: LiveStudioType.s(13, FontWeight.w700, tokens.textHigh)))
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Center(child: Text(initial, style: LiveStudioType.s(13, FontWeight.w700, tokens.textHigh))),
            ),
    );
  }
}
