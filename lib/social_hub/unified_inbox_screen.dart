import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class UnifiedInboxScreen extends ConsumerStatefulWidget {
  const UnifiedInboxScreen({super.key});

  @override
  ConsumerState<UnifiedInboxScreen> createState() => _UnifiedInboxScreenState();
}

class _UnifiedInboxScreenState extends ConsumerState<UnifiedInboxScreen> {
  int _selectedTabIndex = 0; // 0: All, 1: YouTube, 2: TikTok

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StudioBackground(
        backgroundIcons: const [Icons.inbox, Icons.message, Icons.forum],
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                    const Text('Unified Inbox', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.filter_list),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    _buildTab('All', 0),
                    const SizedBox(width: 12),
                    _buildTab('YouTube', 1),
                    const SizedBox(width: 12),
                    _buildTab('TikTok', 2),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  itemCount: 10,
                  itemBuilder: (context, index) {
                    bool isYoutube = index % 2 == 0;
                    if (_selectedTabIndex == 1 && !isYoutube) return const SizedBox.shrink();
                    if (_selectedTabIndex == 2 && isYoutube) return const SizedBox.shrink();

                    return _buildCommentCard(
                      context, 
                      isYoutube ? 'YouTube' : 'TikTok', 
                      isYoutube ? Icons.play_arrow : Icons.music_note,
                      isYoutube ? Colors.red : Colors.cyan,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    bool isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? Colors.transparent : Theme.of(context).colorScheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCommentCard(BuildContext context, String platform, IconData platformIcon, Color platformColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: OneovaCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OneovaAvatar(text: 'U', size: 36, backgroundColor: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('@user123', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('on "My awesome video"', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                    ],
                  ),
                ),
                Icon(platformIcon, color: platformColor, size: 16),
                const SizedBox(width: 4),
                Text(platform, style: TextStyle(color: platformColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'This is such an amazing video! Can you make part 2?',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildActionButton(context, Icons.reply, 'Reply'),
                const SizedBox(width: 16),
                _buildActionButton(context, Icons.favorite_border, 'Like'),
                const Spacer(),
                const OneovaPill(text: 'Positive', color: Colors.green, isGhost: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
