import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';

class ProfileHighlightItem {
  final String id;
  final String title;
  final String? coverUrl;

  const ProfileHighlightItem({
    required this.id,
    required this.title,
    this.coverUrl,
  });

  factory ProfileHighlightItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ProfileHighlightItem(
      id: doc.id,
      title: data['title'] as String? ?? 'Highlight',
      coverUrl: data['coverUrl'] as String?,
    );
  }
}

/// Horizontal story highlights carousel displayed on Oneova user profiles
class ProfileHighlightsRow extends StatelessWidget {
  final String userId;
  final bool isCurrentUser;
  final Function(ProfileHighlightItem highlight)? onHighlightTap;

  const ProfileHighlightsRow({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
    this.onHighlightTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('highlights')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final highlights = docs.map((d) => ProfileHighlightItem.fromFirestore(d)).toList();

        // If not current user and no highlights, hide section completely
        if (!isCurrentUser && highlights.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 92,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: isCurrentUser ? highlights.length + 1 : highlights.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              if (isCurrentUser && index == 0) {
                // "+ New" button for account owner
                return _buildAddHighlightButton(context);
              }

              final itemIndex = isCurrentUser ? index - 1 : index;
              final highlight = highlights[itemIndex];
              return _buildHighlightBubble(context, highlight);
            },
          ),
        );
      },
    );
  }

  Widget _buildAddHighlightButton(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Select active stories to package into a permanent profile highlight.'),
                backgroundColor: AppColors.brandBlue,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            );
          },
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: context.surfaceMid,
              shape: BoxShape.circle,
              border: Border.all(color: context.border, width: 1.5),
            ),
            child: const Icon(Icons.add_rounded, size: 28, color: AppColors.brandBlue),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'New',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightBubble(BuildContext context, ProfileHighlightItem highlight) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onHighlightTap?.call(highlight);
      },
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.8), width: 1.5),
            ),
            child: CircleAvatar(
              radius: 27,
              backgroundColor: context.surfaceMid,
              backgroundImage: highlight.coverUrl != null && highlight.coverUrl!.isNotEmpty
                  ? NetworkImage(highlight.coverUrl!)
                  : null,
              child: highlight.coverUrl == null || highlight.coverUrl!.isEmpty
                  ? const Icon(Icons.star_rounded, color: AppColors.brandPink, size: 22)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 64,
            child: Text(
              highlight.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
