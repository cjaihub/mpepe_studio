import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../user_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Creator Engagement Tiers matching Instagram-style creator progression.
enum CreatorTier {
  rising(1, 'Rising Creator', 'L1', AppColors.brandBlue, 'Starter'),
  active(2, 'Active Creator', 'L2', Color(0xFF00B4D8), 'Growth'),
  pro(3, 'Verified Pro', 'L3', Color(0xFF2563EB), 'Pro'),
  master(4, 'Master Creator', 'L4', AppColors.brandPink, 'Master'),
  elite(5, 'Elite Ambassador', 'L5', Color(0xFFFF007F), 'Elite');

  final int level;
  final String title;
  final String shortCode;
  final Color primaryColor;
  final String tierName;

  const CreatorTier(this.level, this.title, this.shortCode, this.primaryColor, this.tierName);

  static CreatorTier fromLevel(int level) {
    return CreatorTier.values.firstWhere(
      (t) => t.level == level,
      orElse: () => CreatorTier.rising,
    );
  }
}

/// Helper model for calculating and displaying a creator's engagement level.
class CreatorEngagementLevel {
  final CreatorTier tier;
  final int totalScore;
  final int likes;
  final int comments;
  final int followers;
  final int creations;
  final double progressToNext;
  final int pointsForNext;

  const CreatorEngagementLevel({
    required this.tier,
    required this.totalScore,
    required this.likes,
    required this.comments,
    required this.followers,
    required this.creations,
    required this.progressToNext,
    required this.pointsForNext,
  });

  /// Mathematical calculation of creator engagement:
  /// score = likes(1x) + comments(2x) + followers(3x) + creations(5x)
  factory CreatorEngagementLevel.fromStats({
    int likes = 0,
    int comments = 0,
    int followers = 0,
    int creations = 0,
  }) {
    final int score = likes + (comments * 2) + (followers * 3) + (creations * 5);

    CreatorTier tier;
    int prevThreshold = 0;
    int nextThreshold = 100;

    if (score < 100) {
      tier = CreatorTier.rising;
      prevThreshold = 0;
      nextThreshold = 100;
    } else if (score < 500) {
      tier = CreatorTier.active;
      prevThreshold = 100;
      nextThreshold = 500;
    } else if (score < 2500) {
      tier = CreatorTier.pro;
      prevThreshold = 500;
      nextThreshold = 2500;
    } else if (score < 10000) {
      tier = CreatorTier.master;
      prevThreshold = 2500;
      nextThreshold = 10000;
    } else {
      tier = CreatorTier.elite;
      prevThreshold = 10000;
      nextThreshold = 10000;
    }

    double progress = 1.0;
    int pointsLeft = 0;

    if (tier != CreatorTier.elite) {
      final range = nextThreshold - prevThreshold;
      final currentInRange = score - prevThreshold;
      progress = (currentInRange / range).clamp(0.0, 1.0);
      pointsLeft = (nextThreshold - score).clamp(0, nextThreshold);
    }

    return CreatorEngagementLevel(
      tier: tier,
      totalScore: score,
      likes: likes,
      comments: comments,
      followers: followers,
      creations: creations,
      progressToNext: progress,
      pointsForNext: pointsLeft,
    );
  }

  factory CreatorEngagementLevel.fromTier(CreatorTier tier) {
    int score = 0;
    switch (tier) {
      case CreatorTier.rising:
        score = 50;
        break;
      case CreatorTier.active:
        score = 250;
        break;
      case CreatorTier.pro:
        score = 1200;
        break;
      case CreatorTier.master:
        score = 5000;
        break;
      case CreatorTier.elite:
        score = 15000;
        break;
    }
    return CreatorEngagementLevel.fromStats(likes: score);
  }

  factory CreatorEngagementLevel.fromUser(AppUser? user, [Map<String, dynamic>? rawData]) {
    final int followers = rawData?['followers'] as int? ?? (rawData?['followersCount'] as int?) ?? 0;
    final int likes = rawData?['totalLikes'] as int? ?? (rawData?['likesCount'] as int?) ?? 0;
    final int comments = rawData?['commentsCount'] as int? ?? 0;
    final int creations = rawData?['postsCount'] as int? ?? rawData?['videoCount'] as int? ?? 0;

    return CreatorEngagementLevel.fromStats(
      likes: likes,
      comments: comments,
      followers: followers,
      creations: creations,
    );
  }

  List<String> get unlockedPerks {
    switch (tier) {
      case CreatorTier.rising:
        return [
          'High-Definition 1080p Video Uploads',
          'Direct 1-on-1 Encrypted Messaging',
          'Standard Discover Feed Indexing',
        ];
      case CreatorTier.active:
        return [
          'All Level 1 Perks',
          'Studio Multi-Track Audio Memos',
          'Story Status Duration: 24h Extended',
          'Rising Creator Discover Badge',
        ];
      case CreatorTier.pro:
        return [
          'All Level 2 Perks',
          'Verified Pro Badge with Blue Border',
          'Priority Recommendation Algorithm Boost',
          'Exclusive Group Rooms up to 50 Members',
          'Full High-Density Analytics Insights',
        ];
      case CreatorTier.master:
        return [
          'All Level 3 Perks',
          'Oneova Pink Neon Master Shield',
          'AI Dubbing & Voice Translation Suite',
          'Direct Collab Monetization Splits',
          'Unlimited VIP Private Calling Rooms',
        ];
      case CreatorTier.elite:
        return [
          'All Master Perks Unlocked',
          'Oneova Elite Crown & Golden Aura',
          'Top 1% Global Search Spotlight',
          'Instant 4K 60fps Zero-Compression Pipeline',
          'Direct Access to Partner Ad Revenue',
        ];
    }
  }
}

/// Compact badge widget for creator engagement level
class CreatorLevelBadge extends StatelessWidget {
  final CreatorEngagementLevel? level;
  final CreatorTier? tier;
  final bool showLabel;
  final bool isCompact;
  final VoidCallback? onTap;

  const CreatorLevelBadge({
    super.key,
    this.level,
    this.tier,
    this.showLabel = true,
    this.isCompact = false,
    this.onTap,
  }) : assert(level != null || tier != null);

  @override
  Widget build(BuildContext context) {
    final effectiveTier = tier ?? level!.tier;
    final isElite = effectiveTier == CreatorTier.elite;
    final effectiveShowLabel = isCompact ? false : showLabel;

    final badgeChild = Container(
      padding: EdgeInsets.symmetric(
        horizontal: effectiveShowLabel ? 6 : 4,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: isElite ? null : effectiveTier.primaryColor.withValues(alpha: 0.18),
        gradient: isElite
            ? const LinearGradient(
                colors: [AppColors.brandPink, Color(0xFF9D4EDD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isElite ? Colors.white70 : effectiveTier.primaryColor.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isElite) ...[
            const Icon(Icons.workspace_premium_rounded, size: 10, color: Colors.amber),
            const SizedBox(width: 3),
          ] else if (effectiveTier == CreatorTier.pro) ...[
            const Icon(Icons.verified_rounded, size: 10, color: Color(0xFF2563EB)),
            const SizedBox(width: 3),
          ],
          Text(
            effectiveTier.shortCode,
            style: GoogleFonts.inter(
              color: isElite ? Colors.white : effectiveTier.primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 9.5,
              letterSpacing: 0.4,
            ),
          ),
          if (effectiveShowLabel) ...[
            const SizedBox(width: 3),
            Text(
              effectiveTier.tierName.toUpperCase(),
              style: GoogleFonts.inter(
                color: isElite ? Colors.white : Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 8.5,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: badgeChild,
        ),
      );
    }
    return badgeChild;
  }
}

/// Instagram-style interactive modal displaying full creator progression & perks
class CreatorLevelDetailModal extends StatelessWidget {
  final CreatorEngagementLevel level;
  final String userName;
  final String? avatarUrl;

  const CreatorLevelDetailModal({
    super.key,
    required this.level,
    required this.userName,
    this.avatarUrl,
  });

  static Future<void> show(
    BuildContext context, {
    CreatorEngagementLevel? level,
    CreatorTier? tier,
    String? userName,
    String? username,
    String? avatarUrl,
  }) {
    final effectiveLevel = level ??
        (tier != null
            ? CreatorEngagementLevel.fromStats(followers: tier.level * 100)
            : const CreatorEngagementLevel(
                tier: CreatorTier.rising,
                totalScore: 0,
                likes: 0,
                comments: 0,
                followers: 0,
                creations: 0,
                progressToNext: 0,
                pointsForNext: 100,
              ));
    final effectiveName = userName ?? username ?? 'Creator';

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CreatorLevelDetailModal(
        level: effectiveLevel,
        userName: effectiveName,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tier = level.tier;
    final isElite = tier == CreatorTier.elite;

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Top Header: User avatar + Tier
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isElite ? AppColors.brandPink : tier.primaryColor,
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: (avatarUrl != null && avatarUrl!.isNotEmpty)
                        ? Image.network(avatarUrl!, fit: BoxFit.cover)
                        : Container(
                            color: tier.primaryColor.withValues(alpha: 0.2),
                            child: Center(
                              child: Text(
                                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                                style: GoogleFonts.inter(
                                  color: context.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              userName,
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          CreatorLevelBadge(level: level, showLabel: true),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tier: ${tier.title}',
                        style: GoogleFonts.inter(
                          color: isElite ? AppColors.brandPink : tier.primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Score & Progress card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Creator Engagement Score',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${level.totalScore} pts',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: level.progressToNext,
                      minHeight: 7,
                      backgroundColor: context.border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isElite ? AppColors.brandPink : tier.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isElite
                        ? 'Highest tier achieved! You have unlocked all elite creator privileges.'
                        : '${level.pointsForNext} more engagement points needed to reach Tier ${tier.level + 1}.',
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Stats Breakdown Row
            Row(
              children: [
                _buildStatPill(context, 'Likes', '${level.likes}', Icons.favorite_rounded, AppColors.brandPink),
                const SizedBox(width: 8),
                _buildStatPill(context, 'Followers', '${level.followers}', Icons.people_alt_rounded, AppColors.brandBlue),
                const SizedBox(width: 8),
                _buildStatPill(context, 'Creations', '${level.creations}', Icons.video_collection_rounded, const Color(0xFF00B4D8)),
              ],
            ),

            const SizedBox(height: 20),

            // Unlocked Creator Perks Title
            Text(
              'Unlocked Creator Perks',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 10),

            // List of perks
            ...level.unlockedPerks.map((perk) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: isElite ? AppColors.brandPink : tier.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          perk,
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(BuildContext context, String label, String value, IconData icon, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                color: context.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
