// LIVE STUDIO v2 — DeviceCheckSheet (workstream #4): camera preview + mic
// level before an approved guest goes on stage. "Go on stage" releases the
// preview tracks, then publishes through the room port
// (StudioJoinController.goOnStage → setCameraEnabled / setMicEnabled).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/live_studio/roles/studio_join_controller.dart';
import '../theme/live_studio_tokens.dart';
import 'device_preview.dart';

/// Semantics labels (shared with tests).
class DeviceCheckLabels {
  DeviceCheckLabels._();
  static const String sheet = 'Camera and mic check';
  static const String goOnStage = 'Go on stage';
  static const String notNow = 'Not now';
  static const String camOn = 'Camera on';
  static const String camOff = 'Camera off';
  static const String micOn = 'Microphone on';
  static const String micOff = 'Microphone off';
  static const String openSettings = 'Open settings';
  static const String micLevel = 'Microphone level';
}

/// Opens the device check. Resolves true when the guest went on stage.
Future<bool> showDeviceCheckSheet(BuildContext context, {required String streamId, required LiveStudioTokens tokens}) async {
  HapticFeedback.lightImpact();
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: tokens.base.withValues(alpha: 0),
    barrierColor: LiveStudioTokens.dimTint(0.45),
    builder: (_) => DeviceCheckSheet(streamId: streamId, tokens: tokens),
  );
  return r ?? false;
}

enum _Stage { asking, ready }

class DeviceCheckSheet extends ConsumerStatefulWidget {
  const DeviceCheckSheet({super.key, required this.streamId, required this.tokens});

  final String streamId;
  final LiveStudioTokens tokens;

  @override
  ConsumerState<DeviceCheckSheet> createState() => _DeviceCheckSheetState();
}

class _DeviceCheckSheetState extends ConsumerState<DeviceCheckSheet> {
  late StudioDevicePreview _preview = ref.read(studioDevicePreviewFactoryProvider)();
  _Stage _stage = _Stage.asking;
  StudioDevicePermissions? _perm;
  bool _camOn = true;
  bool _micOn = true;
  bool _going = false;
  bool _released = false;
  String? _deviceError;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    StudioDevicePermissions p;
    try {
      p = await _preview.requestPermissions();
    } catch (_) {
      p = const StudioDevicePermissions(camera: StudioDevicePermission.denied, microphone: StudioDevicePermission.denied);
    }
    if (!mounted) return;
    setState(() {
      _perm = p;
      _camOn = p.cameraOk;
      _micOn = p.micOk;
      _stage = _Stage.ready;
    });
    await _apply();
  }

  Future<void> _apply() async {
    final p = _perm;
    if (p == null || _released) return;
    try {
      await _preview.setCamera(_camOn && p.cameraOk);
      await _preview.setMic(_micOn && p.micOk);
      if (mounted) setState(() => _deviceError = null);
    } catch (_) {
      if (mounted) setState(() => _deviceError = 'Could not open your camera or mic. Another app may be using it.');
    }
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    await _preview.dispose();
  }

  @override
  void dispose() {
    unawaited(_release());
    super.dispose();
  }

  Future<void> _toggleCam() async {
    HapticFeedback.lightImpact();
    setState(() => _camOn = !_camOn);
    await _apply();
  }

  Future<void> _toggleMic() async {
    HapticFeedback.lightImpact();
    setState(() => _micOn = !_micOn);
    await _apply();
  }

  Future<void> _go() async {
    final p = _perm;
    if (p == null || _going) return;
    HapticFeedback.lightImpact();
    setState(() => _going = true);
    await _release(); // free the camera / mic for the room
    await ref
        .read(studioJoinControllerProvider(widget.streamId).notifier)
        .goOnStage(micOn: _micOn && p.micOk, camOn: _camOn && p.cameraOk);
    if (!mounted) return;
    final view = ref.read(studioJoinControllerProvider(widget.streamId));
    if (view.publishing) {
      Navigator.of(context).pop(true);
    } else {
      // Publishing failed: reopen a fresh preview so the guest can retry.
      setState(() {
        _going = false;
        _released = false;
        _preview = ref.read(studioDevicePreviewFactoryProvider)();
      });
      await _apply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final p = _perm;
    final error = ref.watch(studioJoinControllerProvider(widget.streamId).select((v) => v.error));
    final canGo = p != null && (p.cameraOk || p.micOk) && !_going;
    final anyPermanent = p != null &&
        (p.camera == StudioDevicePermission.permanentlyDenied || p.microphone == StudioDevicePermission.permanentlyDenied);

    return Semantics(
      label: DeviceCheckLabels.sheet,
      container: true,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.drawerTop, t.drawerBottom],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: t.drawerBorder, width: 1)),
        ),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.paddingOf(context).bottom),
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
            Text("You're approved", style: LiveStudioType.s(17, FontWeight.w700, t.textHigh, letter: -0.018)),
            const SizedBox(height: 4),
            Text('Check your camera and mic before going on stage.',
                style: LiveStudioType.s(12.5, FontWeight.w500, t.textMedium)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: AspectRatio(aspectRatio: 4 / 3, child: _previewBox(t, p, anyPermanent)),
            ),
            const SizedBox(height: 12),
            _MicLevelBar(tokens: t, level: _preview.micLevel, active: _micOn && (p?.micOk ?? false)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ToggleChip(
                    tokens: t,
                    on: _camOn && (p?.cameraOk ?? false),
                    enabled: p?.cameraOk ?? false,
                    iconOn: Icons.videocam,
                    iconOff: Icons.videocam_off,
                    labelOn: DeviceCheckLabels.camOn,
                    labelOff: DeviceCheckLabels.camOff,
                    onTap: _toggleCam,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ToggleChip(
                    tokens: t,
                    on: _micOn && (p?.micOk ?? false),
                    enabled: p?.micOk ?? false,
                    iconOn: Icons.mic,
                    iconOff: Icons.mic_off,
                    labelOn: DeviceCheckLabels.micOn,
                    labelOff: DeviceCheckLabels.micOff,
                    onTap: _toggleMic,
                  ),
                ),
              ],
            ),
            if (_deviceError != null || error != null) ...[
              const SizedBox(height: 10),
              Text(_deviceError ?? error!, style: LiveStudioType.s(12, FontWeight.w500, t.systemText)),
            ],
            if (anyPermanent) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  button: true,
                  label: DeviceCheckLabels.openSettings,
                  excludeSemantics: true,
                  child: TextButton.icon(
                    onPressed: () => unawaited(_preview.openSettings()),
                    style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: t.shareToTableText),
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: Text(DeviceCheckLabels.openSettings,
                        style: LiveStudioType.s(13, FontWeight.w600, t.shareToTableText)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    tokens: t,
                    label: DeviceCheckLabels.notNow,
                    primary: false,
                    onTap: _going ? null : () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    tokens: t,
                    label: DeviceCheckLabels.goOnStage,
                    primary: true,
                    busy: _going,
                    onTap: canGo ? _go : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewBox(LiveStudioTokens t, StudioDevicePermissions? p, bool anyPermanent) {
    Widget child;
    if (_stage == _Stage.asking || p == null) {
      child = _PreviewMessage(icon: Icons.videocam_outlined, text: 'Asking for camera and mic access…');
    } else if (!p.cameraOk) {
      child = _PreviewMessage(
        icon: Icons.videocam_off,
        text: p.camera == StudioDevicePermission.permanentlyDenied
            ? 'Camera access is off. Turn it on in Settings to be seen.'
            : 'Camera access was denied. You can still join with your mic.',
      );
    } else if (!_camOn) {
      child = const _PreviewMessage(icon: Icons.videocam_off, text: 'Camera is off. People will see your avatar.');
    } else {
      child = _preview.buildVideo() ??
          const _PreviewMessage(icon: Icons.videocam_outlined, text: 'Starting camera…');
    }
    if (p != null && !p.micOk) {
      child = Stack(fit: StackFit.expand, children: [
        child,
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: LiveStudioWorld.tagPill, borderRadius: BorderRadius.circular(5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.mic_off, size: 12, color: LiveStudioAccent.muteIcon),
              const SizedBox(width: 4),
              Text(
                p.microphone == StudioDevicePermission.permanentlyDenied ? 'Mic off in Settings' : 'Mic access denied',
                style: LiveStudioType.s(10.5, FontWeight.w600, LiveStudioWorld.textHigh),
              ),
            ]),
          ),
        ),
      ]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LiveStudioWorld.screen,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LiveStudioAccent.blueA(0.6), width: 1),
        ),
        child: child,
      ),
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 28, color: LiveStudioWorld.textMedium),
            const SizedBox(height: 8),
            Text(text,
                textAlign: TextAlign.center,
                style: LiveStudioType.s(12.5, FontWeight.w500, LiveStudioWorld.textMedium, height: 17)),
          ]),
        ),
      );
}

class _MicLevelBar extends StatelessWidget {
  const _MicLevelBar({required this.tokens, required this.level, required this.active});
  final LiveStudioTokens tokens;
  final Stream<double> level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: DeviceCheckLabels.micLevel,
      child: Row(children: [
        Icon(active ? Icons.mic : Icons.mic_off, size: 16, color: active ? tokens.modeIdleIcon : tokens.textMedium),
        const SizedBox(width: 8),
        Expanded(
          child: StreamBuilder<double>(
            stream: level,
            initialData: 0,
            builder: (_, snap) {
              final v = active ? (snap.data ?? 0).clamp(0.0, 1.0) : 0.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 6,
                  child: Stack(fit: StackFit.expand, children: [
                    ColoredBox(color: tokens.ghostFill),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: v,
                      child: const ColoredBox(color: LiveStudioAccent.blue),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.tokens,
    required this.on,
    required this.enabled,
    required this.iconOn,
    required this.iconOff,
    required this.labelOn,
    required this.labelOff,
    required this.onTap,
  });
  final LiveStudioTokens tokens;
  final bool on;
  final bool enabled;
  final IconData iconOn;
  final IconData iconOff;
  final String labelOn;
  final String labelOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final label = on ? labelOn : labelOff;
    return Semantics(
      button: true,
      toggled: on,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? t.modeIdleFill : t.ghostFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: on ? t.modeIdleBorder : t.ghostBorder, width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 44,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(on ? iconOn : iconOff, size: 18, color: on ? t.modeIdleIcon : LiveStudioAccent.muteIcon),
              const SizedBox(width: 6),
              Text(label, style: LiveStudioType.s(12.5, FontWeight.w600, on ? t.modeIdleText : t.textMedium)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.tokens, required this.label, required this.primary, this.busy = false, this.onTap});
  final LiveStudioTokens tokens;
  final String label;
  final bool primary;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final enabled = onTap != null;
    final fg = primary ? LiveStudioAccent.white : t.textHigh;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || busy ? 1 : 0.5,
        child: Material(
          color: primary ? LiveStudioAccent.blue : t.ghostFill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: primary ? BorderSide.none : BorderSide(color: t.ghostBorder, width: 1),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                    : Text(label, style: LiveStudioType.s(13.5, FontWeight.w700, fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
