import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/social/services/story_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class StoryTray extends ConsumerWidget {
  const StoryTray({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Usually we would watch a provider, but we'll simulate an async fetch here
    return FutureBuilder(
      future: ref.read(storyServiceProvider).getFeedStories(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 100,
            child: Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
          );
        }
        
        final groups = snapshot.data ?? [];
        
        return SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: groups.length + 1, // +1 for the "Add Story" button
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildAddStoryButton(context);
              }
              
              final group = groups[index - 1];
              return _buildStoryRing(context, group);
            },
          ),
        );
      },
    );
  }

  Widget _buildAddStoryButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        context.push('/upload/global'); // Eventually maybe pass an arg to default to story mode
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Builder(builder: (context) {
                  final photo = FirebaseAuth.instance.currentUser?.photoURL;
                  return CircleAvatar(
                    radius: 30,
                    backgroundColor: context.surfaceMid,
                    backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                    child: photo != null && photo.isNotEmpty
                        ? null
                        : Icon(Icons.person_rounded, color: context.textMuted),
                  );
                }),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your Story',
              style: TextStyle(color: context.textPrimary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryRing(BuildContext context, UserStoryGroup group) {
    return GestureDetector(
      onTap: () {
        context.push('/social_hub/story/${group.authorId}');
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: group.hasUnviewed ? AppColors.brandBlue : context.border,
                  width: 2,
                ),
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundImage: NetworkImage(group.authorAvatarUrl),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.authorName,
              style: TextStyle(
                color: group.hasUnviewed ? context.textPrimary : context.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
