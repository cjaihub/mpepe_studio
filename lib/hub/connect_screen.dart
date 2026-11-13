import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/services/oneova_biometrics_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../backend/remote_connect_service.dart';
import '../backend/webrtc_desktop_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/oneova_smart_status_banner.dart';
import '../widgets/oneova_assistant_overlay.dart';

/// Oneova Connected Computers & Online Control Hub.
///
/// Auto-discovers account-linked workstations in real time, supports QR &
/// 6-digit E2EE session pairing, pull-to-refresh, live screen previews, command
/// & notification history, and launches the full-screen Online Device Control Panel.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _passkeyController = TextEditingController();
  bool _isProcessing = false;
  bool _isUnlocking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(remoteConnectProvider.notifier).refreshComputers();
    });
  }

  @override
  void dispose() {
    final held = _preloadedId;
    if (held != null) _webrtc.release(held);
    _pinController.dispose();
    _passkeyController.dispose();
    super.dispose();
  }

  /// Starts the live link as soon as the computer page opens, so the preview
  /// is real video and the control panel opens already streaming.
  String? _preloadedId;
  late final WebRTCDesktopService _webrtc = ref.read(webrtcDesktopProvider.notifier);

  void _preload(String? deviceId) {
    if (!mounted || deviceId == _preloadedId) return;
    final old = _preloadedId;
    if (old != null) _webrtc.release(old);
    _preloadedId = deviceId;
    if (deviceId != null) _webrtc.hold(deviceId);
  }

  Future<void> _refreshDevices({bool showToast = false}) async {
    HapticFeedback.lightImpact();
    await ref.read(remoteConnectProvider.notifier).refreshComputers();
    if (!mounted) return;
    final computers = ref.read(remoteConnectProvider).linkedComputers;
    final onlineCount = computers.where((c) => c.isOnline).length;
    if (showToast) {
      OneovaSmartStatus.show(
        context,
        title: onlineCount > 0
            ? '$onlineCount Workstation${onlineCount == 1 ? "" : "s"} Online'
            : (computers.isEmpty
                ? 'No Linked Computers Yet'
                : 'Synced ${computers.length} Linked Computer${computers.length == 1 ? "" : "s"}'),
        subtitle: onlineCount > 0
            ? 'Live heartbeat verified. Tap to launch Online Device Control.'
            : 'Sign in on Oneova Desktop or pair via QR / 6-digit code.',
        kind: onlineCount > 0 ? OneovaStatusKind.success : OneovaStatusKind.info,
        source: 'Device Sync',
      );
    }
  }

  void _openControlPanel(LinkedComputer computer) {
    HapticFeedback.mediumImpact();
    ref.read(remoteConnectProvider.notifier).setActiveComputer(computer.id);
    context.push('/remote_control');
  }

  Future<void> _linkViaAccount() async {
    setState(() => _isProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Sign in to Oneova first to sync account computers.');
      }

      await ref.read(remoteConnectProvider.notifier).refreshComputers();
      final computers = ref.read(remoteConnectProvider).linkedComputers;

      if (computers.isEmpty) {
        throw Exception(
          'No workstation signed in with your Oneova account yet. Sign in on your Mac or enter the 6-digit session code below.',
        );
      }

      final target = computers.firstWhere(
        (c) => c.isOnline,
        orElse: () => computers.first,
      );
      await ref.read(remoteConnectProvider.notifier).linkComputer(target.id);

      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Synced with ${target.name}',
          subtitle: target.isOnline
              ? 'Opening Online Device Control Panel...'
              : 'Workstation linked (currently offline).',
          kind: OneovaStatusKind.success,
          source: 'Account Sync',
        );
        if (target.isOnline) {
          _openControlPanel(target);
        }
      }
    } catch (e) {
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Account Sync Notice',
          subtitle: e.toString().replaceFirst('Exception: ', ''),
          kind: OneovaStatusKind.warning,
          source: 'Account Sync',
          actionLabel: 'Retry',
          onAction: _linkViaAccount,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _connectSession() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      OneovaSmartStatus.show(
        context,
        title: 'Enter 6-Digit Session Code',
        subtitle: 'Open Oneova Desktop -> Code Session to view your 6-digit PIN.',
        kind: OneovaStatusKind.warning,
        source: 'Pairing',
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final deviceId = await ref.read(remoteConnectProvider.notifier).pairWithSessionPin(pin);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _pinController.clear();
      OneovaSmartStatus.show(
        context,
        title: 'Workstation Paired',
        subtitle: 'Launching live Online Device Control Panel...',
        kind: OneovaStatusKind.success,
        source: 'Pairing',
      );
      ref.read(remoteConnectProvider.notifier).setActiveComputer(deviceId);
      context.push('/remote_control');
    } catch (e) {
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Pairing Failed',
          subtitle: e.toString().replaceFirst('Exception: ', ''),
          kind: OneovaStatusKind.error,
          source: 'Pairing',
          actionLabel: 'Retry',
          onAction: _connectSession,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmUnlinkComputer(LinkedComputer computer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: dialogCtx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: dialogCtx.border, width: 1.0),
        ),
        title: Text(
          'Unlink ${computer.name}?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: dialogCtx.textPrimary,
          ),
        ),
        content: Text(
          'This removes ${computer.name} from your paired device list. You can re-link anytime via account sign-in, QR, or 6-digit code.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: dialogCtx.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: dialogCtx.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              'Unlink',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(remoteConnectProvider.notifier)
          .unlinkComputer(computer.id, deleteFromAccount: true);
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Unlinked ${computer.name}',
          kind: OneovaStatusKind.info,
          source: 'Device Link',
        );
      }
    }
  }

  Future<void> _handleWakeAndUnlock(LinkedComputer computer) async {
    ref.read(remoteConnectProvider.notifier).setActiveComputer(computer.id);
    final biometrics = ref.read(oneovaBiometricsServiceProvider);
    final authenticated = await biometrics.authenticate(reason: 'Wake & unlock workstation');
    if (authenticated) {
      setState(() => _isUnlocking = true);
      await ref.read(remoteConnectProvider.notifier).unlockWorkstation(passkey: '');
      if (mounted) {
        setState(() => _isUnlocking = false);
        HapticFeedback.mediumImpact();
        OneovaSmartStatus.show(
          context,
          title: 'Wake & Unlock Signal Sent',
          subtitle: 'Resuming ${computer.name}...',
          kind: OneovaStatusKind.success,
          source: 'Remote Power',
        );
      }
    } else {
      _showPasskeyEntrySheet(computer);
    }
  }

  void _showPasskeyEntrySheet(LinkedComputer computer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: sheetCtx.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: sheetCtx.border, width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetCtx.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.vpn_key_rounded, color: AppColors.brandPink, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unlock ${computer.name}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: sheetCtx.textPrimary,
                          ),
                        ),
                        Text(
                          'Resume workstation session from sleep',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: sheetCtx.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passkeyController,
                obscureText: true,
                style: GoogleFonts.inter(color: sheetCtx.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter computer password or PIN',
                  hintStyle: GoogleFonts.inter(color: sheetCtx.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: sheetCtx.surfaceMid,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: sheetCtx.border, width: 1.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: BorderSide(color: sheetCtx.border, width: 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  onPressed: () async {
                    final pass = _passkeyController.text.trim();
                    Navigator.pop(sheetCtx);
                    setState(() => _isUnlocking = true);
                    await ref.read(remoteConnectProvider.notifier).unlockWorkstation(passkey: pass);
                    if (mounted) {
                      setState(() => _isUnlocking = false);
                      HapticFeedback.lightImpact();
                      OneovaSmartStatus.show(
                        context,
                        title: 'Unlock Dispatched',
                        subtitle: 'Sent secure unlock command to ${computer.name}.',
                        kind: OneovaStatusKind.success,
                        source: 'Remote Power',
                      );
                    }
                  },
                  child: Text(
                    'Unlock & Resume',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatHeartbeat(DateTime? lastSeen, bool isOnline) {
    if (lastSeen == null) return isOnline ? 'Live now' : 'Offline';
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inSeconds < 12) return 'Live • just now';
    if (diff.inSeconds < 60) return 'Live • ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final remoteState = ref.watch(remoteConnectProvider);
    final linkedComputers = remoteState.linkedComputers;
    final activeComputer = remoteState.activeComputer;
    final hasLinked = linkedComputers.isNotEmpty && activeComputer != null;
    final preloadId = activeComputer != null && activeComputer.isOnline ? activeComputer.id : null;
    if (preloadId != _preloadedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _preload(preloadId));
    }

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        title: Text(
          'Connected Computers',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh linked computers',
            onPressed: remoteState.isRefreshing ? null : () => _refreshDevices(showToast: true),
            icon: remoteState.isRefreshing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandBlue,
                    ),
                  )
                : Icon(Icons.refresh_rounded, color: context.textPrimary, size: 20),
          ),
          ValueListenableBuilder<List<OneovaStatusEvent>>(
            valueListenable: OneovaSmartStatus.historyNotifier,
            builder: (context, events, _) {
              return IconButton(
                tooltip: 'Connection & Status History',
                onPressed: () => OneovaSmartStatus.showHistorySheet(context),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.history_rounded, color: context.textPrimary, size: 20),
                    if (events.isNotEmpty)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.brandPink,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 20),
            tooltip: 'Ova AI Agent',
            onPressed: () => OneOvaAssistantOverlay.show(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.brandBlue,
        backgroundColor: context.surface,
        onRefresh: () => _refreshDevices(showToast: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            if (hasLinked) ...[
              _buildActiveWorkstationPortalCard(activeComputer),
              if (linkedComputers.length > 1) ...[
                const SizedBox(height: 14),
                _buildAllLinkedDevicesSection(linkedComputers, activeComputer.id),
              ],
              const SizedBox(height: 16),
              const SizedBox.shrink(),
              const SizedBox(height: 20),
            ] else ...[
              _buildEmptyHeroBanner(),
              const SizedBox(height: 18),
            ],
            Text(
              hasLinked ? 'LINK ANOTHER COMPUTER' : 'PAIR YOUR COMPUTER',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: context.textMuted,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildQuickPairButton(
                    icon: Icons.qr_code_scanner_rounded,
                    label: 'Scan QR',
                    onTap: _isProcessing ? null : () => context.push('/qr_scanner'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildQuickPairButton(
                    icon: Icons.sync_rounded,
                    label: 'Account Sync',
                    isPrimary: true,
                    onTap: _isProcessing ? null : _linkViaAccount,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildPinEntryCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyHeroBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3), width: 1.0),
            ),
            child: const Icon(Icons.devices_rounded, color: AppColors.brandBlue, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'No Online Computers Detected Yet',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sign in with the same Oneova account on Oneova Desktop (Mac/PC) for automatic background linking, or pair instantly via QR / 6-digit code below.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.4,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildQuickPairButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isPrimary = false,
  }) {
    return SizedBox(
      height: 42,
      child: Material(
        color: isPrimary ? AppColors.brandBlue : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isPrimary ? AppColors.brandBlue : context.border,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: isPrimary ? Colors.white : context.textPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isPrimary ? Colors.white : context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveWorkstationPortalCard(LinkedComputer computer) {
    final isSleeping = computer.isSleeping;
    final isLocked = computer.isLocked;
    final processors = computer.systemInfo['processors'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: computer.isOnline
              ? AppColors.brandBlue.withValues(alpha: 0.45)
              : context.border,
          width: 1.0,
        ),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.desktop_mac_rounded, color: AppColors.brandBlue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            computer.name,
                            style: GoogleFonts.inter(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (computer.os.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                              border: Border.all(color: context.border, width: 1.0),
                            ),
                            child: Text(
                              '${computer.os.toUpperCase()}${processors != null ? " • ${processors}C" : ""}',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: context.textSecondary,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: computer.isOnline
                                ? AppColors.brandBlue
                                : (isSleeping ? AppColors.brandPink : context.textMuted),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isSleeping
                                ? 'Sleep Mode • ${_formatHeartbeat(computer.lastSeenAt, false)}'
                                : isLocked
                                    ? 'Locked • ${_formatHeartbeat(computer.lastSeenAt, computer.isOnline)}'
                                    : _formatHeartbeat(computer.lastSeenAt, computer.isOnline),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: computer.isOnline
                                  ? AppColors.brandBlue
                                  : context.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  computer.activeWindow ?? 'Desktop',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
                tooltip: 'Unlink computer',
                onPressed: () => _confirmUnlinkComputer(computer),
                icon: Icon(Icons.link_off_rounded, size: 17, color: context.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Rendered Screen Preview Portal
          GestureDetector(
            onTap: () => _openControlPanel(computer),
            child: _LiveComputerScreenPreview(
              computer: computer,
              onTap: () => _openControlPanel(computer),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    icon: const Icon(Icons.fullscreen_rounded, size: 18),
                    label: Text(
                      'Open Online Control Panel',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () => _openControlPanel(computer),
                  ),
                ),
              ),
            ],
          ),

          if (isSleeping || isLocked) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.6), width: 1.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                icon: _isUnlocking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.brandPink,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded, color: AppColors.brandPink, size: 16),
                label: Text(
                  _isUnlocking ? 'Unlocking...' : 'Wake & Unlock with Biometrics',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPink,
                  ),
                ),
                onPressed: _isUnlocking ? null : () => _handleWakeAndUnlock(computer),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.03, end: 0);
  }

  Widget _buildAllLinkedDevicesSection(
    List<LinkedComputer> computers,
    String activeId,
  ) {
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
          Text(
            'SWITCH LINKED WORKSTATION (${computers.length})',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: context.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          for (final comp in computers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(remoteConnectProvider.notifier).setActiveComputer(comp.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: comp.id == activeId
                        ? AppColors.brandBlue.withValues(alpha: 0.1)
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: comp.id == activeId ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.computer_rounded,
                        size: 16,
                        color: comp.isOnline ? AppColors.brandBlue : context.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          comp.name,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        comp.isOnline ? 'Online' : 'Offline',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: comp.isOnline ? AppColors.brandBlue : context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPinEntryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: const Icon(Icons.dialpad_rounded, color: AppColors.brandBlue, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter 6-Digit Session Code',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Pair instantly with the code shown on Oneova Desktop',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onSubmitted: (_) => _connectSession(),
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: context.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '123456',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        letterSpacing: 2,
                        color: context.textMuted,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  onPressed: _isProcessing ? null : _connectSession,
                  child: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Pair',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveComputerScreenPreview extends ConsumerWidget {
  final LinkedComputer computer;
  final VoidCallback onTap;

  const _LiveComputerScreenPreview({
    required this.computer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(
      webrtcDesktopProvider.select((s) => s.connections[computer.id]),
    );
    final renderer = conn?.renderer;
    if (conn != null &&
        conn.status == WebRTCStatus.connected &&
        conn.hasVideoStream &&
        renderer != null) {
      // Real-time video of the computer (same stream the panel uses).
      return AspectRatio(
        aspectRatio: 16 / 10,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.6), width: 1.0),
          ),
          clipBehavior: Clip.antiAlias,
          child: RTCVideoView(
            renderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),
        ),
      );
    }
    // Fallback while the live link connects: last frame the computer posted.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('registered_computers')
          .doc(computer.id)
          .collection('live_stream')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        Uint8List? frameBytes;
        final data = snapshot.data?.data();
        final b64 = data?['frame_b64'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          try {
            frameBytes = base64Decode(b64);
          } catch (_) {}
        }

        return AspectRatio(
          aspectRatio: 16 / 10,
          child: Container(
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (frameBytes != null)
                  Image.memory(
                    frameBytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monitor_rounded,
                          size: 32,
                          color: computer.isOnline ? AppColors.brandBlue : context.textMuted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          computer.isOnline
                              ? 'Tap to open live interactive screen'
                              : 'Workstation offline — auto-reconnect active',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  right: 10,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.surface.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_rounded,
                              size: 12,
                              color: computer.isOnline ? AppColors.brandBlue : context.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              computer.isOnline
                                  ? 'LIVE INTERACTIVE CONTROL'
                                  : 'STANDBY',
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.brandBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
