import 'package:flutter/material.dart';
import '../../shared/widgets/follow_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:flutter/services.dart';
import '../../backend/user_service.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/social/models/creator_engagement_level.dart';
import '../../shared/theme/app_theme.dart';

class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<AppUser> _allSuggestedUsers = [];
  List<AppUser> _searchResults = [];
  bool _isLoading = false;
  String? _startingChatUserId;

  @override
  void initState() {
    super.initState();
    _loadInitialUsers();
  }

  Future<void> _loadInitialUsers() async {
    setState(() => _isLoading = true);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').limit(30).get();
      final users = snapshot.docs
          .map((doc) => AppUser.fromMap(doc.data(), doc.id))
          .where((u) => u.id != currentUserId)
          .toList();

      if (mounted) {
        setState(() {
          _allSuggestedUsers = users;
          _searchResults = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading initial users: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _searchResults = _allSuggestedUsers);
      return;
    }

    final localMatches = _allSuggestedUsers.where((u) {
      final name = u.fullName.toLowerCase();
      final username = (u.username ?? '').toLowerCase();
      final email = u.email.toLowerCase();
      return name.contains(q) || username.contains(q) || email.contains(q);
    }).toList();

    setState(() {
      _searchResults = localMatches;
    });

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(30)
          .get();

      final users = snapshot.docs
          .map((doc) => AppUser.fromMap(doc.data(), doc.id))
          .where((u) => u.id != currentUserId)
          .where((u) {
            final name = u.fullName.toLowerCase();
            final username = (u.username ?? '').toLowerCase();
            final email = u.email.toLowerCase();
            return name.contains(q) || username.contains(q) || email.contains(q);
          })
          .toList();

      if (mounted) {
        setState(() {
          _searchResults = users;
        });
      }
    } catch (e) {
      debugPrint("Search error: $e");
    }
  }

  void _startChat(AppUser user) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || _startingChatUserId != null) return;

    HapticFeedback.lightImpact();
    setState(() => _startingChatUserId = user.id);

    try {
      final repo = ref.read(messagingRepositoryProvider);
      final chatId = await repo.getOrCreateDirectChat(currentUserId, user.id);
      
      if (!mounted) return;
      // Close the search bottom sheet cleanly before navigating to conversation
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      context.push('/hub/messages/$chatId');
    } catch (e) {
      if (mounted) {
        setState(() => _startingChatUserId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting chat: $e'),
            backgroundColor: AppColors.brandPink,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _searchUsers,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search creators or people...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.search, color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
                : _searchResults.isEmpty && _searchController.text.isNotEmpty
                    ? Center(
                        child: Text(
                          "No users found for '${_searchController.text}'",
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final displayName = user.fullName.isNotEmpty
                              ? user.fullName
                              : (user.username ?? 'Oneova Creator');
                          final avatarLetter = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

                          final tier = CreatorEngagementLevel.fromUser(user).tier;
                          final currentUserId = FirebaseAuth.instance.currentUser?.uid;

                          return ListTile(
                            onTap: () => _startChat(user),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.brandBlue,
                              backgroundImage: (user.profilePhotoUrl != null && user.profilePhotoUrl!.isNotEmpty)
                                  ? NetworkImage(user.profilePhotoUrl!)
                                  : null,
                              child: (user.profilePhotoUrl == null || user.profilePhotoUrl!.isEmpty)
                                  ? Text(
                                      avatarLetter,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, color: AppColors.brandBlue, size: 14),
                                ],
                                const SizedBox(width: 6),
                                CreatorLevelBadge(
                                  tier: tier,
                                  isCompact: true,
                                  onTap: () {
                                    CreatorLevelDetailModal.show(context, tier: tier, username: displayName);
                                  },
                                ),
                              ],
                            ),
                            subtitle: Text(
                              user.username != null && user.username!.isNotEmpty
                                  ? '@${user.username}'
                                  : user.email,
                              style: const TextStyle(color: Colors.white54),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (currentUserId != null && currentUserId != user.id)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: FollowButton(
                                      targetUserId: user.id,
                                      targetName: displayName,
                                      size: FollowButtonSize.compact,
                                    ),
                                  ),
                                ElevatedButton(
                                  onPressed: _startingChatUserId == user.id ? null : () => _startChat(user),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.brandBlue,
                                    disabledBackgroundColor: AppColors.brandBlue.withValues(alpha: 0.6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: _startingChatUserId == user.id
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideY(begin: 0.1, end: 0);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
