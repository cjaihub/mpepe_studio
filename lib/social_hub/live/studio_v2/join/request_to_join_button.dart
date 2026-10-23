// LIVE STUDIO v2 — RequestToJoinButton (workstream #4, SPEC §5).
//
// Landscape: full blue #2F7BFF pill. Phone ([compact]): 36 px icon button in
// a 44 px target. States: Request to join → Requested (tap cancels) → Go on
// stage (device check) → Leave stage (confirmed). Hidden for the host.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/roles/studio_join_controller.dart';
import '../theme/live_studio_tokens.dart';
import 'device_check_sheet.dart';
import 'studio_confirm_dialog.dart';

/// Visible text / Semantics labels (shared with tests).
class RequestToJoinLabels {
  RequestToJoinLabels._();
  static const String request = 'Request to join';
  static const String requested = 'Requested';
  static const String requestedHint = 'Requested. Tap to cancel your request';
  static const String goOnStage = 'Go on stage';
  static const String leave = 'Leave stage';
}

enum _ButtonState { request, requested, goOnStage, leave }

class RequestToJoinButton extends ConsumerStatefulWidget {
  const RequestToJoinButton({
    super.key,
    required this.streamId,
    required this.tokens,
    this.compact = false,
    this.autoOpenDeviceCheck = true,
  });

  final String streamId;
  final LiveStudioTokens tokens;

  /// Phone layout: icon-only 36 px button.
  final bool compact;

  /// Opens the device check as soon as the request is approved.
  final bool autoOpenDeviceCheck;

  @override
  ConsumerState<RequestToJoinButton> createState() => _RequestToJoinButtonState();
}

class _RequestToJoinButtonState extends ConsumerState<RequestToJoinButton> {
  bool _sheetOpen = false;

  StudioJoinController get _ctl => ref.read(studioJoinControllerProvider(widget.streamId).notifier);

  Future<void> _openDeviceCheck() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    try {
      await showDeviceCheckSheet(context, streamId: widget.streamId, tokens: widget.tokens);
    } finally {
      _sheetOpen = false;
    }
  }

  void _onTap(_ButtonState s) {
    HapticFeedback.lightImpact();
    switch (s) {
      case _ButtonState.request:
        unawaited(_ctl.request());
      case _ButtonState.requested:
        unawaited(_ctl.cancel());
      case _ButtonState.goOnStage:
        unawaited(_openDeviceCheck());
      case _ButtonState.leave:
        unawaited(_ctl.leaveStage(studioConfirmFor(context, widget.tokens)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = studioJoinControllerProvider(widget.streamId);
    ref.listen<StudioJoinView>(provider, (prev, next) {
      if (widget.autoOpenDeviceCheck && next.awaitingDeviceCheck && !(prev?.awaitingDeviceCheck ?? false)) {
        unawaited(_openDeviceCheck());
      }
      final err = next.error;
      if (err != null && err != prev?.error) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(err)));
        _ctl.clearError();
      }
    });
    final view = ref.watch(provider);
    if (view.phase == StudioJoinPhase.host) return const SizedBox.shrink();

    final s = switch (view.phase) {
      StudioJoinPhase.pending => _ButtonState.requested,
      StudioJoinPhase.approved => view.awaitingDeviceCheck ? _ButtonState.goOnStage : _ButtonState.leave,
      _ => _ButtonState.request,
    };
    return widget.compact
        ? _CompactButton(tokens: widget.tokens, state: s, busy: view.busy, onTap: () => _onTap(s))
        : _PillButton(tokens: widget.tokens, state: s, busy: view.busy, onTap: () => _onTap(s));
  }
}

String _semantics(_ButtonState s) => switch (s) {
      _ButtonState.request => RequestToJoinLabels.request,
      _ButtonState.requested => RequestToJoinLabels.requestedHint,
      _ButtonState.goOnStage => RequestToJoinLabels.goOnStage,
      _ButtonState.leave => RequestToJoinLabels.leave,
    };

IconData _icon(_ButtonState s, {required bool compact}) => switch (s) {
      _ButtonState.request => compact ? Icons.add : Icons.person_add_alt,
      _ButtonState.requested => Icons.close,
      _ButtonState.goOnStage => Icons.videocam,
      _ButtonState.leave => Icons.logout,
    };

/// (fill, border, foreground) per state.
(Color, Color?, Color) _colors(_ButtonState s, LiveStudioTokens t) => switch (s) {
      _ButtonState.request || _ButtonState.goOnStage => (LiveStudioAccent.blue, null, LiveStudioAccent.white),
      _ButtonState.requested => (t.glass, LiveStudioAccent.blueA(0.85), t.textHigh),
      _ButtonState.leave => (t.glass, LiveStudioWorld.pinkRim, t.textHigh),
    };

class _PillButton extends StatelessWidget {
  const _PillButton({required this.tokens, required this.state, required this.busy, required this.onTap});
  final LiveStudioTokens tokens;
  final _ButtonState state;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fill, border, fg) = _colors(state, tokens);
    final text = switch (state) {
      _ButtonState.request => RequestToJoinLabels.request,
      _ButtonState.requested => RequestToJoinLabels.requested,
      _ButtonState.goOnStage => RequestToJoinLabels.goOnStage,
      _ButtonState.leave => RequestToJoinLabels.leave,
    };
    return Semantics(
      button: true,
      enabled: !busy,
      label: _semantics(state),
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border, width: 1)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (busy)
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                else
                  Icon(_icon(state, compact: false), size: 17, color: fg),
                const SizedBox(width: 8),
                Text(text, style: LiveStudioType.s(13, FontWeight.w700, fg, letter: -0.01)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactButton extends StatelessWidget {
  const _CompactButton({required this.tokens, required this.state, required this.busy, required this.onTap});
  final LiveStudioTokens tokens;
  final _ButtonState state;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fill, border, fg) = _colors(state, tokens);
    return Semantics(
      button: true,
      enabled: !busy,
      label: _semantics(state),
      excludeSemantics: true,
      child: Tooltip(
        message: _semantics(state),
        child: InkResponse(
          onTap: busy ? null : onTap,
          radius: 22,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: border == null ? null : Border.all(color: border, width: 1),
                ),
                child: Center(
                  child: busy
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                      : Icon(_icon(state, compact: true), size: 19, color: fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
