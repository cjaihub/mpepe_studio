import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/remote_connect_service.dart';
import '../../../backend/webrtc_desktop_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'tactile.dart';

enum _TestState { idle, testing, ok, failed }

/// Sidebar card in the Ova chat: the linked computer's status, a one-tap
/// connection test (opens the encrypted link and measures the round trip),
/// and entries to live control and the activity log. Mouse and keyboard
/// controls live here, not in the chat itself.
class ComputerSidebarCard extends ConsumerStatefulWidget {
  const ComputerSidebarCard({super.key, this.onNavigate});

  /// Called before navigating away (e.g. to close a sheet).
  final VoidCallback? onNavigate;

  @override
  ConsumerState<ComputerSidebarCard> createState() => _ComputerSidebarCardState();
}

class _ComputerSidebarCardState extends ConsumerState<ComputerSidebarCard> {
  _TestState _test = _TestState.idle;
  int? _rtt;
  String? _detail;
  StreamSubscription<({String deviceToken, Map<String, dynamic> packet})>? _sub;
  Timer? _timeout;
  bool _openedForTest = false;
  String? _testedId;

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    final id = _testedId;
    if (_openedForTest && id != null) {
      final service = ref.read(webrtcDesktopProvider.notifier);
      if (service.modeOf(id) == 'controller') service.disconnect(id);
    }
    super.dispose();
  }

  Future<void> _runTest(LinkedComputer computer) async {
    HapticFeedback.selectionClick();
    final service = ref.read(webrtcDesktopProvider.notifier);
    setState(() {
      _test = _TestState.testing;
      _rtt = null;
      _detail = 'Opening encrypted link…';
    });
    _testedId = computer.id;
    _sub?.cancel();
    _timeout?.cancel();

    final sentAt = DateTime.now().millisecondsSinceEpoch;
    _sub = service.incoming.where((m) => m.deviceToken == computer.id).listen((m) {
      if (m.packet['action'] == 'pong') {
        final t = (m.packet['t'] as num?)?.toInt() ?? sentAt;
        _timeout?.cancel();
        if (!mounted) return;
        HapticFeedback.lightImpact();
        setState(() {
          _test = _TestState.ok;
          _rtt = DateTime.now().millisecondsSinceEpoch - t;
          _detail = service.isFastChannelOpen(computer.id) ? 'Fast lane open' : 'Connected';
        });
      }
    });

    final conn = ref.read(webrtcDesktopProvider).connections[computer.id];
    if (conn?.isDataChannelOpen != true) {
      _openedForTest = true;
      unawaited(service.connect(computer.id, mode: 'controller', force: true));
    }

    // Ping as soon as the channel opens; give up after 15 s.
    final started = DateTime.now();
    Timer.periodic(const Duration(milliseconds: 300), (t) {
      if (!mounted || _test != _TestState.testing) {
        t.cancel();
        return;
      }
      final c = ref.read(webrtcDesktopProvider).connections[computer.id];
      if (c?.isDataChannelOpen == true) {
        service.sendControlPacket(computer.id, {
          'action': 'ping',
          't': DateTime.now().millisecondsSinceEpoch,
        });
        t.cancel();
      } else if (DateTime.now().difference(started) > const Duration(seconds: 15)) {
        t.cancel();
      }
    });
    _timeout = Timer(const Duration(seconds: 16), () {
      if (!mounted || _test != _TestState.testing) return;
      setState(() {
        _test = _TestState.failed;
        _detail = computer.isOnline
            ? 'No answer. Is Oneova Desktop open on ${computer.name}?'
            : '${computer.name} is offline.';
      });
    });
  }

  void _go(String path) {
    widget.onNavigate?.call();
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteConnectProvider);
    final computer = remote.activeComputer;
    final micro = GoogleFonts.inter(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: context.textMuted,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      padding: const EdgeInsets.all(10),
      decoration: Tactile.tile(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('COMPUTER', style: micro),
              const Spacer(),
              StatusLed(on: computer?.isOnline == true, size: 5),
              const SizedBox(width: 5),
              Text(computer?.isOnline == true ? 'ONLINE' : 'OFFLINE', style: micro),
            ],
          ),
          const SizedBox(height: 8),
          if (computer == null)
            Text(
              'No computer linked yet.',
              style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
            )
          else
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: Tactile.raised(context, circle: true),
                  child: Icon(
                    Icons.laptop_mac_rounded,
                    size: 16,
                    color: computer.isOnline ? AppColors.brandBlue : context.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        computer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        _detail ?? (computer.activeWindow ?? 'Tap Test to check the link'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: _test == _TestState.failed ? AppColors.brandPink : context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_test == _TestState.ok && _rtt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: Tactile.recessed(context, radius: AppRadius.xs),
                    child: Text(
                      '$_rtt ms',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CardButton(
                  icon: _test == _TestState.testing
                      ? null
                      : (_test == _TestState.ok ? Icons.check_rounded : Icons.network_check_rounded),
                  label: _test == _TestState.testing ? 'Testing' : 'Test',
                  onTap: computer == null || _test == _TestState.testing
                      ? null
                      : () => _runTest(computer),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CardButton(
                  icon: Icons.desktop_windows_outlined,
                  label: 'Control',
                  primary: true,
                  onTap: computer == null
                      ? null
                      : () {
                          ref.read(remoteConnectProvider.notifier).setActiveComputer(computer.id);
                          _go('/phone_controller/${Uri.encodeComponent(computer.id)}');
                        },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _CardButton(
                  icon: Icons.receipt_long_outlined,
                  label: 'Logs',
                  onTap: () => _go('/computer_logs'),
                ),
              ),
            ],
          ),
          if (computer == null) ...[
            const SizedBox(height: 6),
            _CardButton(
              icon: Icons.add_link_rounded,
              label: 'Link a computer',
              onTap: () => _go('/auth/linked_devices'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.onTap, this.icon, this.primary = false});
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.brandWhite : (onTap == null ? context.textMuted : context.textPrimary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: primary
            ? BoxDecoration(
                color: onTap == null ? context.surfaceMid : AppColors.brandBlue,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              )
            : Tactile.raised(context, radius: AppRadius.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, size: 14, color: fg)
            else
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandBlue),
              ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
