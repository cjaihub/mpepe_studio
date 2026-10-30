import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../../backend/social/models/relationship.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../../backend/user_service.dart';

/// Screen listing blocked users on Oneova with unblock safeguards and real-time Firestore sync.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final RelationshipRepository _relRepo = RelationshipRepository();
  final Set<String> _processingIds = {};

  Future<void> _confirmAndUnblock(String targetUserId, String displayName) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || _processingIds.contains(targetUserId)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: context.border, width: 1.0),
        ),
        title: Text(
          'Unblock $displayName?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'They will be able to see your posts and send you follow requests or messages according to your privacy settings.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: context.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _processingIds.add(targetUserId));
    HapticFeedback.mediumImpact();

    try {
      await _relRepo.unblockUser(currentUid, targetUserId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unblocked $displayName',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            backgroundColor: AppColors.brandBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unblock: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(targetUserId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Blocked Accounts',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: context.topBarFg,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: currentUid.isEmpty
          ? Center(
              child: Text(
                'Please sign in to view blocked accounts',
                style: GoogleFonts.inter(color: context.textMuted),
              ),
            )
          : StreamBuilder<List<Relationship>>(
              stream: _relRepo.watchBlockedUsers(currentUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.brandBlue),
                  );
                }

                final blockedList = snapshot.data ?? [];

                if (blockedList.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              shape: BoxShape.circle,
                              border: Border.all(color: context.border, width: 1.0),
                            ),
                            child: Icon(
                              Icons.person_off_outlined,
                              size: 32,
                              color: context.textMuted,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'No Blocked Accounts',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When you block someone, they won\'t be able to see your profile, posts, or message you on Oneova.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: context.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: blockedList.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: context.border,
                    indent: 64,
                  ),
                  itemBuilder: (context, index) {
                    final rel = blockedList[index];
                    final targetId = rel.followingId;
                    final isBusy = _processingIds.contains(targetId);

                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(targetId).snapshots(),
                      builder: (context, userSnap) {
                        final userData = userSnap.data?.data() as Map<String, dynamic>?;
                        final user = userData != null ? AppUser.fromMap(userData, targetId) : null;
                        final displayName = (user != null && user.fullName.isNotEmpty)
                            ? user.fullName
                            : (userData?['displayName'] as String? ?? 'Blocked Account');
                        final username = (user != null && (user.username?.isNotEmpty ?? false))
                            ? user.username!
                            : (userData?['username'] as String? ?? 'user');
                        final avatarUrl = user?.profilePhotoUrl ?? userData?['photoURL'] as String?;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: context.surfaceMid,
                                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? Text(
                                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'B',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: context.textSecondary,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '@$username',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        color: context.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (isBusy)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                                )
                              else
                                SizedBox(
                                  height: 32,
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: context.surfaceMid,
                                      foregroundColor: context.textPrimary,
                                      side: BorderSide(color: context.border, width: 1.0),
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppRadius.sm),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _confirmAndUnblock(targetId, displayName),
                                    child: Text(
                                      'Unblock',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}
