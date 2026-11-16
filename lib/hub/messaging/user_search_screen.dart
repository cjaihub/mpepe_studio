import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/messaging_repository.dart';
import '../../backend/social/models/creator_engagement_level.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/follow_button.dart';
import 'widgets/chat_user_directory.dart';

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
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadInitialUsers();
  }

  Future<void> _loadInitialUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await ChatUserDirectory.loadSuggested(limit: 35);
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

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _searchUsers(query));
  }

  Future<void> _searchUsers(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _searchResults = _allSuggestedUsers);
      return;
    }

    try {
      final users = await ChatUserDirectory.search(query, seed: _allSuggestedUsers);
      if (mounted) {
        setState(() => _searchResults = users);
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  Future<void> _startChat(AppUser user) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || _startingChatUserId != null) return;

    HapticFeedback.lightImpact();
    setState(() => _startingChatUserId = user.id);

    try {
      final repo = ref.read(messagingRepositoryProvider);
      final chatId = await repo.getOrCreateDirectChat(currentUserId, user.id);

      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      context.push('/hub/messages/$chatId');
    } catch (e) {
      if (mounted) {
        setState(() => _startingChatUserId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message
                  : 'Could not open this conversation right now.',
            ),
            backgroundColor: AppColors.brandPink,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    onChanged: _onQueryChanged,
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Search people by name or @username…',
                      hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
                      prefixIcon: Icon(Icons.search_rounded, color: context.textMuted, size: 19),
                      isDense: true,
                      filled: true,
                      fillColor: context.surfaceMid,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(color: context.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(color: context.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: const BorderSide(color: AppColors.brandBlue),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      color: AppColors.brandBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
                : _searchResults.isEmpty && _searchController.text.isNotEmpty
                    ? Center(
                        child: Text(
                          "No people found for '${_searchController.text}'",
                          style: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
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

                          return ListTile(
                            dense: true,
                            onTap: () => _startChat(user),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                            leading: CircleAvatar(
                              radius: 21,
                              backgroundColor: AppColors.brandBlue,
                              backgroundImage:
                                  (user.profilePhotoUrl != null && user.profilePhotoUrl!.isNotEmpty)
                                      ? NetworkImage(user.profilePhotoUrl!)
                                      : null,
                              child: (user.profilePhotoUrl == null || user.profilePhotoUrl!.isEmpty)
                                  ? Text(
                                      avatarLetter,
                                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    style: GoogleFonts.inter(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 14),
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
                            subtitle: user.username != null && user.username!.isNotEmpty
                                ? Text(
                                    '@${user.username}',
                                    style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                                  )
                                : null,
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
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
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
                                      : Text(
                                          'Chat',
                                          style: GoogleFonts.inter(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: Duration(milliseconds: (index.clamp(0, 8)) * 30));
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
