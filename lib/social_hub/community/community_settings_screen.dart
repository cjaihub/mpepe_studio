import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/social/models/community_models.dart';
import '../../../backend/social/services/community_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CommunitySettingsScreen extends ConsumerStatefulWidget {
  final String communityId;
  const CommunitySettingsScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends ConsumerState<CommunitySettingsScreen> {
  CommunityModel? _community;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final svc = ref.read(communityServiceProvider);
    final comm = await svc.getCommunity(widget.communityId);
    
    if (mounted) {
      setState(() {
        _community = comm;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    final c = _community!;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Community Settings', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('Access Control (Members)'),
          _buildAccessToggles(c),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Rules'),
          ...c.rules.map((r) => ListTile(
            title: Text(r.title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text(r.description, style: TextStyle(color: context.textSecondary)),
            trailing: IconButton(icon: Icon(Icons.delete, color: context.textMuted), onPressed: () {}),
          )),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add, color: AppColors.brandBlue),
            label: const Text('Add Rule', style: TextStyle(color: AppColors.brandBlue)),
          ),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Moderation'),
          ListTile(
            title: Text('Banned Words', style: TextStyle(color: context.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: context.textMuted),
            onTap: () {},
          ),
          ListTile(
            title: Text('Member Roles & Badges', style: TextStyle(color: context.textPrimary)),
            trailing: Icon(Icons.chevron_right, color: context.textMuted),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: context.textMuted, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildAccessToggles(CommunityModel c) {
    final access = c.accessControl[CommunityRole.member] ?? const CommunityAccessConfig();
    
    return Card(
      color: context.surface,
      child: Column(
        children: [
          SwitchListTile(
            title: Text('Can View Posts', style: TextStyle(color: context.textPrimary)),
            value: access.canViewPosts,
            activeThumbColor: AppColors.brandBlue,
            onChanged: (v) {},
          ),
          SwitchListTile(
            title: Text('Can Post Videos', style: TextStyle(color: context.textPrimary)),
            value: access.canPostVideos,
            activeThumbColor: AppColors.brandBlue,
            onChanged: (v) {},
          ),
          SwitchListTile(
            title: Text('Can Chat', style: TextStyle(color: context.textPrimary)),
            value: access.canChat,
            activeThumbColor: AppColors.brandBlue,
            onChanged: (v) {},
          ),
          SwitchListTile(
            title: Text('Can Create Events', style: TextStyle(color: context.textPrimary)),
            value: access.canCreateEvents,
            activeThumbColor: AppColors.brandBlue,
            onChanged: (v) {},
          ),
        ],
      ),
    );
  }
}
