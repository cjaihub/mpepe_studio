import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../agent_workspace/ova_agent_sync_controller.dart';
import '../agent_workspace/widgets/ova_claude_agent_workspace.dart';
import '../shared/theme/app_theme.dart';

class RemoteChatScreen extends ConsumerWidget {
  const RemoteChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentState = ref.watch(ovaAgentSyncProvider);
    final online = agentState.workstationOnline;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: AppBar(
          backgroundColor: context.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: context.border, width: 1.0)),
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: context.textPrimary,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/hub/home');
              }
            },
          ),
          title: Text(
            'Workstation Agent Studio',
            style: GoogleFonts.inter(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: context.textPrimary,
            ),
          ),
          actions: [
            if (online)
              IconButton(
                tooltip: 'Live Screen Monitor',
                icon: const Icon(
                  Icons.desktop_mac_rounded,
                  size: 19,
                  color: AppColors.brandBlue,
                ),
                onPressed: () => context.push('/remote_monitor'),
              )
            else
              IconButton(
                tooltip: 'Connect Workstation',
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 19,
                  color: AppColors.brandBlue,
                ),
                onPressed: () => context.push('/connect'),
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
      body: SafeArea(
        child: OvaAgentWorkspace(
          onOpenConnectWorkstation: () => context.push('/connect'),
        ),
      ),
    );
  }
}
