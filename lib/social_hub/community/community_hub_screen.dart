import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/social/models/community_models.dart';
import '../../../backend/social/services/community_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CommunityHubScreen extends ConsumerStatefulWidget {
  final String communityId;
  const CommunityHubScreen({super.key, required this.communityId});

  @override
  ConsumerState<CommunityHubScreen> createState() => _CommunityHubScreenState();
}

class _CommunityHubScreenState extends ConsumerState<CommunityHubScreen> with SingleTickerProviderStateMixin {
  CommunityModel? _community;
  List<CommunityEvent> _events = [];
  bool _isLoading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    final svc = ref.read(communityServiceProvider);
    final comm = await svc.getCommunity(widget.communityId);
    final evts = await svc.getUpcomingEvents(widget.communityId);
    
    if (mounted) {
      setState(() {
        _community = comm;
        _events = evts;
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
        title: Text(c.name, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: context.textPrimary),
            onPressed: () => context.push('/social_hub/community/${c.id}/settings'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.brandBlue,
          labelColor: context.textPrimary,
          unselectedLabelColor: context.textMuted,
          tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Chat'),
            Tab(text: 'Events'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFeed(c),
          _buildChat(c),
          _buildEvents(c),
        ],
      ),
    );
  }

  Widget _buildFeed(CommunityModel c) {
    final access = c.accessControl[CommunityRole.member] ?? const CommunityAccessConfig();
    
    return Column(
      children: [
        if (access.canViewPosts)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPostCard('Creator', 'Welcome to the community! Check out the rules in settings.'),
                _buildPostCard('Member1', 'So excited to be here!'),
              ],
            ),
          )
        else
          Expanded(
            child: Center(
              child: Text('You do not have access to view posts.', style: TextStyle(color: context.textMuted)),
            ),
          ),
        
        // Post Input
        if (access.canPostVideos || c.ownerId == 'me')
          Container(
            padding: const EdgeInsets.all(16),
            color: context.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Share something...',
                      hintStyle: TextStyle(color: context.textMuted),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(icon: Icon(Icons.image, color: context.textSecondary), onPressed: () {}),
                IconButton(icon: const Icon(Icons.send, color: AppColors.brandBlue), onPressed: () {}),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildChat(CommunityModel c) {
    final access = c.accessControl[CommunityRole.member] ?? const CommunityAccessConfig();
    if (!access.canChat && c.ownerId != 'me') {
      return Center(child: Text('Chat is disabled for members.', style: TextStyle(color: context.textMuted)));
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildChatBubble('Hello everyone!', isMe: false),
              _buildChatBubble('Hey!', isMe: true),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: context.surface,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: TextStyle(color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Message community...',
                    hintStyle: TextStyle(color: context.textMuted),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.send, color: AppColors.brandBlue), onPressed: () {}),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEvents(CommunityModel c) {
    if (_events.isEmpty) {
      return Center(child: Text('No upcoming events', style: TextStyle(color: context.textMuted)));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final e = _events[index];
        return Card(
          color: context.surface,
          child: ListTile(
            leading: const Icon(Icons.event, color: AppColors.brandBlue),
            title: Text(e.title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text(e.description, style: TextStyle(color: context.textSecondary)),
            trailing: const Text('Join', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            onTap: () {},
          ),
        );
      },
    );
  }

  Widget _buildPostCard(String author, String text) {
    return Card(
      color: context.surface,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 16, backgroundColor: context.surfaceMid),
                const SizedBox(width: 8),
                Text(author, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(text, style: TextStyle(color: context.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String text, {required bool isMe}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text, style: TextStyle(color: isMe ? Colors.white : context.textPrimary)),
      ),
    );
  }
}
