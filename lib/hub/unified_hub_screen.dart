import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../backend/unified_inbox_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/studio_background.dart';
import 'components/unified_list_tab.dart';
import 'components/interactive_comments_tab.dart';
import 'components/interactive_messages_tab.dart';

class UnifiedHubScreen extends ConsumerStatefulWidget {
  const UnifiedHubScreen({super.key});

  @override
  ConsumerState<UnifiedHubScreen> createState() => _UnifiedHubScreenState();
}

class _UnifiedHubScreenState extends ConsumerState<UnifiedHubScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cjAiActive = ref.watch(cjAiAssistantProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StudioBackground(
        backgroundIcons: const [Icons.forum_outlined, Icons.comment_outlined, Icons.notifications_active_outlined],
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context, cjAiActive),
              if (cjAiActive)
                _buildAIBanner(),
              _buildTabBar(context),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: cjAiActive ? Border(top: BorderSide(color: AppColors.neonPurple.withValues(alpha: 0.3), width: 2)) : null,
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: const [
                      InteractiveMessagesTab(),
                      InteractiveCommentsTab(),
                      UnifiedListTab(itemType: UnifiedItemType.notification),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool cjAiActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              Text('Unified Hub', style: AppTheme.h1Style.copyWith(fontSize: 22)),
            ],
          ),
          _buildAIToggle(cjAiActive),
        ],
      ),
    );
  }

  Widget _buildAIToggle(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: isActive ? AppColors.aiGradient : null,
        color: isActive ? null : AppColors.darkSurfaceHighlight,
        border: isActive ? null : Border.all(color: AppColors.outline),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.neonPurple.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: isActive ? Colors.white : AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'CJ AI',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 24,
            child: Switch(
              value: isActive,
              onChanged: (value) {
                ref.read(cjAiAssistantProvider.notifier).setAssistantState(value);
              },
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.white.withValues(alpha: 0.3),
              inactiveThumbColor: AppColors.textSecondary,
              inactiveTrackColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.neonPurple.withValues(alpha: 0.1),
        border: Border(bottom: BorderSide(color: AppColors.neonPurple.withValues(alpha: 0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, size: 14, color: AppColors.neonPurple),
          const SizedBox(width: 8),
          Text(
            'CJ AI Assistant is monitoring and handling replies',
            style: TextStyle(
              color: AppColors.neonPurple,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: AppColors.outline.withValues(alpha: 0.3))),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: Theme.of(context).colorScheme.primary,
        indicatorWeight: 3,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: AppColors.textSecondary,
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'Messages'),
          Tab(text: 'Comments'),
          Tab(text: 'Alerts'),
        ],
      ),
    );
  }
}
