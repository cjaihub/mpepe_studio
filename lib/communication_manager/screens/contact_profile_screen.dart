import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/contact_profile.dart';
import '../services/contact_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import '../../social_hub/profile/social_profile_view.dart';
import '../../backend/user_service.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ContactProfileScreen extends ConsumerStatefulWidget {
  final String targetUserId;

  const ContactProfileScreen({super.key, required this.targetUserId});

  @override
  ConsumerState<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends ConsumerState<ContactProfileScreen> {
  ContactProfile? _contactProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final service = ref.read(contactServiceProvider.notifier);
    final profile = await service.getContact(widget.targetUserId);
    if (mounted) {
      setState(() {
        _contactProfile = profile;
      });
    }
  }

  void _toggleMute() async {
    if (_contactProfile == null) return;
    final isMuted = _contactProfile!.relationalData.isMuted;
    await ref.read(contactServiceProvider.notifier).setMuteStatus(widget.targetUserId, !isMuted);
    _loadProfile();
  }

  void _toggleBlock() async {
    if (_contactProfile == null) return;
    final isBlocked = _contactProfile!.relationalData.isBlocked;
    if (!isBlocked) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.darkSurface,
          title: const Text('Block User?', style: TextStyle(color: AppColors.textPrimary)),
          content: const Text('Are you sure you want to block this contact?', style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await ref.read(contactServiceProvider.notifier).setBlockStatus(widget.targetUserId, !isBlocked);
    _loadProfile();
  }

  void _showMoreOptions() {
    if (_contactProfile == null) return;
    final rel = _contactProfile!.relationalData;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(rel.isMuted ? Icons.volume_up : Icons.volume_off, color: AppColors.textPrimary),
                title: Text(rel.isMuted ? 'Unmute' : 'Mute', style: const TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _toggleMute();
                },
              ),
              ListTile(
                leading: Icon(rel.isBlocked ? Icons.check_circle_outline : Icons.block, color: Colors.red),
                title: Text(rel.isBlocked ? 'Unblock' : 'Block', style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _toggleBlock();
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                title: const Text('Report', style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted')));
                },
              ),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(userProvider);
    final users = usersState.value ?? [];
    
    // Find realtime AppUser to get live follower/following counts
    AppUser? realUser;
    try {
      realUser = users.firstWhere((u) => u.id == widget.targetUserId);
    } catch (_) {
      realUser = null;
    }

    if (realUser == null && _contactProfile == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: AnimatedLoadingIndicator()),
      );
    }

    // Fallback to contact profile user if realUser is missing momentarily
    final displayUser = realUser ?? _contactProfile!.user;
    
    // Determine status from contact profile
    final bool isBlocked = _contactProfile?.relationalData.isBlocked ?? false;
    final bool isFollowing = _contactProfile?.relationalData.relationshipStatus == RelationshipStatus.following || 
                             _contactProfile?.relationalData.relationshipStatus == RelationshipStatus.mutual;

    return SocialProfileView(
      user: displayUser,
      isCurrentUser: false,
      isBlocked: isBlocked,
      primaryActionText: isFollowing ? 'Unfollow' : 'Follow',
      onPrimaryActionTap: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Follow toggled')));
      },
      secondaryActionText: 'Message',
      onSecondaryActionTap: () {
        context.push('/social_hub/chat/${widget.targetUserId}');
      },
      onMoreTap: _showMoreOptions,
    );
  }
}
