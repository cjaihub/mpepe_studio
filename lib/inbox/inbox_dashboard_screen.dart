import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/theme/app_theme.dart';
import 'components/inbox_sidebar.dart';
import 'components/inbox_list_panel.dart';
import 'components/chat_view_panel.dart';
import 'components/context_details_panel.dart';
import 'mobile/inbox_mobile_screen.dart';
import '../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../backend/ai_agents/omni_command/omni_command_service.dart';
import 'providers/selected_inbox_item_provider.dart';
import '../backend/unified_inbox_provider.dart';

class InboxDashboardScreen extends ConsumerStatefulWidget {
  const InboxDashboardScreen({super.key});

  @override
  ConsumerState<InboxDashboardScreen> createState() => _InboxDashboardScreenState();
}

class _InboxDashboardScreenState extends ConsumerState<InboxDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncContext(ref.read(selectedInboxItemProvider));
    });
  }

  void _syncContext(UnifiedItem? item) {
    final settings = ref.read(aiSettingsProvider);
    final notifier = ref.read(aiSettingsProvider.notifier);
    final resolver = ref.read(omniContextResolverProvider);
    
    final omniContext = resolver.resolve(
      sessionId: buildOmniSessionId(),
      userId: FirebaseAuth.instance.currentUser?.uid ?? 'local_user',
      surface: 'inbox',
      activeRoute: '/inbox',
      conversationId: item?.id,
      platformId: item?.platform.name,
      aiMode: notifier.effectiveMode,
      memoryEnabled: settings.memoryEnabled,
    );
    ref.read(omniContextProvider.notifier).updateContext(omniContext);
  }
  // Add state for selected items if needed

  @override
  Widget build(BuildContext context) {
    ref.listen<UnifiedItem?>(selectedInboxItemProvider, (prev, next) {
      if (prev?.id != next?.id) {
        _syncContext(next);
      }
    });

    return Scaffold(
      backgroundColor: context.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 800) {
            return const InboxMobileScreen();
          }

          return Row(
            children: [
              // 1. Sidebar Navigation
              const InboxSidebar(),
              
              // 2. Inbox List Panel
              const InboxListPanel(),
              
              // 3. Chat / Conversation View (Takes up most remaining space)
              const Expanded(
                flex: 3,
                child: ChatViewPanel(),
              ),
              
              // 4. Right Context Details Panel
              const ContextDetailsPanel(),
            ],
          );
        },
      ),
    );
  }
}
