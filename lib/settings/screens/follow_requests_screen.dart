import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../../backend/social/models/relationship.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../../backend/user_service.dart';

/// Screen listing pending follow requests for a private Oneova account.
/// Fully dual-mode aware (Light & Dark), real-time Firestore backed, with zero mock data.
class FollowRequestsScreen extends ConsumerStatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  ConsumerState<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends ConsumerState<FollowRequestsScreen> {
  final RelationshipRepository _relRepo = RelationshipRepository();
  final Set<String> _processingIds = {};

  Future<void> _accept(String requesterId, String requesterName) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || _processingIds.contains(requesterId)) return;

    setState(() => _processingIds.add(requesterId));
    HapticFeedback.mediumImpact();

    try {
      await _relRepo.acceptFollowRequest(currentUid, requesterId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Accepted follow request from $requesterName',
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
            content: Text('Failed to accept: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(requesterId));
      }
    }
  }

  Future<void> _decline(String requesterId) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || _processingIds.contains(requesterId)) return;

    setState(() => _processingIds.add(requesterId));
    HapticFeedback.lightImpact();

    try {
      await _relRepo.declineFollowRequest(currentUid, requesterId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Removed follow request',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            backgroundColor: context.surfaceMid,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(requesterId));
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
          'Follow Requests',
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
                'Please sign in to view follow requests',
                style: GoogleFonts.inter(color: context.textMuted),
              ),
            )
          : StreamBuilder<List<Relationship>>(
              stream: _relRepo.watchPendingFollowRequests(currentUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.brandBlue),
                  );
                }

                final requests = snapshot.data ?? [];

                if (requests.isEmpty) {
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
                              color: AppColors.brandBlue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.25), width: 1.5),
                            ),
                            child: const Icon(
                              Icons.group_add_outlined,
                              size: 32,
                              color: AppColors.brandBlue,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'No Pending Requests',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'When people ask to follow your private account, you will see and manage their requests here.',
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
                  itemCount: requests.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    thickness: 1,
                    color: context.border,
                    indent: 64,
                  ),
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    final isBusy = _processingIds.contains(req.followerId);

                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(req.followerId).snapshots(),
                      builder: (context, userSnap) {
                        final userData = userSnap.data?.data() as Map<String, dynamic>?;
                        final user = userData != null ? AppUser.fromMap(userData, req.followerId) : null;
                        final displayName = (user != null && user.fullName.isNotEmpty)
                            ? user.fullName
                            : (userData?['displayName'] as String? ?? 'Oneova Creator');
                        final username = (user != null && (user.username?.isNotEmpty ?? false))
                            ? user.username!
                            : (userData?['username'] as String? ?? 'user');
                        final avatarUrl = user?.profilePhotoUrl ?? userData?['photoURL'] as String?;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => context.push('/profile/${req.followerId}'),
                                child: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: context.surfaceMid,
                                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                      ? NetworkImage(avatarUrl)
                                      : null,
                                  child: (avatarUrl == null || avatarUrl.isEmpty)
                                      ? Text(
                                          displayName.isNotEmpty ? displayName[0].toUpperCase() : 'O',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.brandBlue,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => context.push('/profile/${req.followerId}'),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              displayName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: context.textPrimary,
                                              ),
                                            ),
                                          ),
                                          if (user?.isVerified == true) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.verified, size: 14, color: AppColors.brandBlue),
                                          ],
                                        ],
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
                              ),
                              const SizedBox(width: 10),
                              if (isBusy)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                                )
                              else
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Confirm button
                                    SizedBox(
                                      height: 32,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.brandBlue,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                          ),
                                          elevation: 0,
                                        ),
                                        onPressed: () => _accept(req.followerId, displayName),
                                        child: Text(
                                          'Confirm',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // Decline button
                                    SizedBox(
                                      height: 32,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: context.surfaceMid,
                                          foregroundColor: context.textPrimary,
                                          side: BorderSide(color: context.border, width: 1.0),
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(AppRadius.sm),
                                          ),
                                          elevation: 0,
                                        ),
                                        onPressed: () => _decline(req.followerId),
                                        child: Text(
                                          'Delete',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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
