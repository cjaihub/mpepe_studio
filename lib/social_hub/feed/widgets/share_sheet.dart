import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../backend/social/models/share_models.dart';
import '../../../../backend/social/services/share_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ShareSheet extends ConsumerStatefulWidget {
  final String postId;
  final String authorId;

  const ShareSheet({
    super.key,
    required this.postId,
    required this.authorId,
  });

  static void show(BuildContext context, {required String postId, required String authorId}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ShareSheet(postId: postId, authorId: authorId),
    );
  }

  @override
  ConsumerState<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<ShareSheet> {
  ShareSettings? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await ref.read(shareServiceProvider).getShareSettings(widget.postId);
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  Future<void> _executeShare(ShareDestination destination) async {
    try {
      await ref.read(shareServiceProvider).executeShare(
        postId: widget.postId,
        authorId: widget.authorId,
        currentUserId: 'me', // Normally from Auth
        destination: destination,
      );
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shared successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: AppColors.brandBlue),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    final s = _settings!;

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Share to',
            style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          // Fast Share Row (DMs)
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5, // Mock friends
              itemBuilder: (context, index) {
                return _buildFriendAvatar(index);
              },
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(color: context.border),
          ),
          
          // Action Grid
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              if (s.allowRepost && !s.isPrivateContent)
                _buildActionIcon(Icons.repeat, 'Repost', () => _executeShare(ShareDestination.repost), isBrand: true),
              
              if (s.allowQuote && !s.isPrivateContent)
                _buildActionIcon(Icons.format_quote, 'Quote', () => _executeShare(ShareDestination.quoteRepost)),
                
              _buildActionIcon(Icons.group, 'Followers', () => _executeShare(ShareDestination.followers)),
              _buildActionIcon(Icons.link, 'Copy Link', () => _executeShare(ShareDestination.copyLink)),
              
              if (s.allowEmbed && !s.isPrivateContent)
                _buildActionIcon(Icons.code, 'Embed', () => _executeShare(ShareDestination.embed)),
                
              _buildActionIcon(Icons.chat_bubble_outline, 'Message', () => _executeShare(ShareDestination.privateChat)),
              _buildActionIcon(Icons.more_horiz, 'More', () => _executeShare(ShareDestination.externalNetwork)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendAvatar(int index) {
    return GestureDetector(
      onTap: () => _executeShare(ShareDestination.privateChat),
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=${index + 10}'),
            ),
            const SizedBox(height: 8),
            Text('Friend $index', style: TextStyle(color: context.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String label, VoidCallback onTap, {bool isBrand = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isBrand ? AppColors.brandBlue : context.surfaceMid,
              shape: BoxShape.circle,
              border: Border.all(color: isBrand ? AppColors.brandBlue : context.border),
            ),
            child: Icon(icon, color: isBrand ? Colors.white : context.textPrimary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(color: context.textPrimary, fontSize: 12), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
