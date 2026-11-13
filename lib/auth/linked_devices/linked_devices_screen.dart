import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/remote_connect_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/oneova_smart_status_banner.dart';

class LinkedDevicesScreen extends ConsumerStatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  ConsumerState<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends ConsumerState<LinkedDevicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(remoteConnectProvider.notifier).refreshComputers();
    });
  }

  Future<void> _refresh() async {
    HapticFeedback.lightImpact();
    await ref.read(remoteConnectProvider.notifier).refreshComputers();
    if (!mounted) return;
    final count = ref.read(remoteConnectProvider).linkedComputers.length;
    OneovaSmartStatus.show(
      context,
      title: count > 0
          ? 'Synced $count Linked Computer${count == 1 ? "" : "s"}'
          : 'No Linked Computers Yet',
      subtitle: count > 0
          ? 'Tap any online computer to open live control.'
          : 'Sign in on Oneova Desktop or pair via QR / code.',
      kind: count > 0 ? OneovaStatusKind.success : OneovaStatusKind.info,
      source: 'Linked Devices',
    );
  }

  Future<void> _confirmUnlink(LinkedComputer computer) async {
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
          'This removes ${computer.name} from your linked devices. You can re-link anytime via Oneova account sign-in, QR, or 6-digit code.',
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
          source: 'Linked Devices',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final remoteState = ref.watch(remoteConnectProvider);
    final computers = remoteState.linkedComputers;

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
          'Computers & Linked Devices',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: remoteState.isRefreshing ? null : _refresh,
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
          IconButton(
            tooltip: 'Connection History',
            onPressed: () => OneovaSmartStatus.showHistorySheet(context),
            icon: Icon(Icons.history_rounded, color: context.textPrimary, size: 20),
          ),
        ],
      ),
      body: user == null
          ? Center(
              child: Text(
                'Sign in to manage your linked computers.',
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13),
              ),
            )
          : RefreshIndicator(
              color: AppColors.brandBlue,
              backgroundColor: context.surface,
              onRefresh: _refresh,
              child: computers.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
                      children: [
                        _buildEmptyState(context),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        for (final comp in computers) _buildDeviceCard(context, comp),
                        const SizedBox(height: 12),
                        _buildPairActionRow(context),
                      ],
                    ),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3), width: 1.0),
          ),
          child: const Icon(Icons.devices_rounded, size: 30, color: AppColors.brandBlue),
        ),
        const SizedBox(height: 16),
        Text(
          'No Computers Linked Yet',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Open Oneova Desktop on your Mac or PC and sign in with the same account—or pair instantly via QR or 6-digit code.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              height: 1.4,
              color: context.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _buildPairActionRow(context),
      ],
    );
  }

  Widget _buildPairActionRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.border, width: 1.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              onPressed: () => context.push('/qr_scanner'),
              icon: Icon(Icons.qr_code_scanner_rounded, size: 17, color: context.textPrimary),
              label: Text(
                'Scan QR',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              onPressed: () => context.push('/connect'),
              icon: const Icon(Icons.dialpad_rounded, size: 17),
              label: Text(
                'Enter Code',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(BuildContext context, LinkedComputer comp) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: comp.isOnline
              ? AppColors.brandBlue.withValues(alpha: 0.4)
              : context.border,
          width: 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            Icons.desktop_mac_rounded,
            size: 20,
            color: comp.isOnline ? AppColors.brandBlue : context.textMuted,
          ),
        ),
        title: Text(
          comp.name,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: comp.isOnline ? AppColors.brandBlue : context.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  comp.isOnline
                      ? 'Online • ${comp.activeWindow ?? "Desktop"}'
                      : 'Offline • Auto-reconnect active',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: comp.isOnline ? AppColors.brandBlue : context.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Use phone as controller',
              icon: const Icon(Icons.touch_app_rounded, size: 19, color: AppColors.brandBlue),
              onPressed: () {
                HapticFeedback.selectionClick();
                ref.read(remoteConnectProvider.notifier).setActiveComputer(comp.id);
                context.push('/phone_controller/${Uri.encodeComponent(comp.id)}');
              },
            ),
            IconButton(
              tooltip: 'Unlink computer',
              icon: Icon(Icons.link_off_rounded, size: 18, color: context.textMuted),
              onPressed: () => _confirmUnlink(comp),
            ),
            Icon(Icons.chevron_right_rounded, color: context.textSecondary, size: 20),
          ],
        ),
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(remoteConnectProvider.notifier).setActiveComputer(comp.id);
          context.push('/remote_control');
        },
      ),
    );
  }
}
