import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../backend/messaging_repository.dart';
import '../../../backend/storage_service.dart';
import '../../../backend/user_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'widgets/chat_user_directory.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<AppUser> _suggestedUsers = [];
  List<AppUser> _searchResults = [];
  final Map<String, AppUser> _selectedById = {};
  File? _groupAvatarFile;
  bool _isLoading = true;
  bool _creating = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  Future<void> _loadSuggested() async {
    try {
      final users = await ChatUserDirectory.loadSuggested(limit: 35);
      if (mounted) {
        setState(() {
          _suggestedUsers = users;
          _searchResults = users;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _searchUsers(query));
  }

  Future<void> _searchUsers(String query) async {
    setState(() => _isLoading = true);
    try {
      final users = await ChatUserDirectory.search(query, seed: _suggestedUsers);
      if (mounted) {
        setState(() {
          _searchResults = users;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickGroupAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 84);
      if (picked != null && mounted) {
        setState(() => _groupAvatarFile = File(picked.path));
      }
    } catch (_) {}
  }

  void _toggleUserSelection(AppUser user) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedById.containsKey(user.id)) {
        _selectedById.remove(user.id);
      } else {
        _selectedById[user.id] = user;
      }
    });
  }

  Future<void> _createGroup() async {
    if (_creating) return;
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name.'), backgroundColor: AppColors.brandPink),
      );
      return;
    }
    if (_selectedById.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one person to add.'), backgroundColor: AppColors.brandPink),
      );
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    setState(() => _creating = true);
    try {
      String? avatarUrl;
      if (_groupAvatarFile != null) {
        try {
          final storage = ref.read(storageServiceProvider);
          final path = 'users/$currentUserId/avatar/group_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final snap = await storage.uploadFileWithProgress(_groupAvatarFile!, path);
          avatarUrl = await snap.ref.getDownloadURL();
        } catch (_) {
          // Proceed even if avatar upload fails so group creation isn't blocked.
        }
      }

      final participantIds = [currentUserId, ..._selectedById.keys];
      final repo = ref.read(messagingRepositoryProvider);
      final chatId = await repo.createChat(
        participantIds,
        title: groupName,
        avatarUrl: avatarUrl,
        category: 'group',
        ownerId: currentUserId,
      );

      if (mounted) {
        Navigator.pop(context);
        context.push('/hub/messages/$chatId');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create group: $e'), backgroundColor: AppColors.brandPink),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedById.values.toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 22),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    'New Group',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _creating ? null : _createGroup,
                  child: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                        )
                      : Text(
                          'Create',
                          style: GoogleFonts.inter(
                            color: AppColors.brandBlue,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _pickGroupAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: context.surfaceMid,
                        backgroundImage: _groupAvatarFile != null ? FileImage(_groupAvatarFile!) : null,
                        child: _groupAvatarFile == null
                            ? const Icon(Icons.camera_alt_outlined, color: AppColors.brandBlue, size: 22)
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: AppColors.brandBlue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    textCapitalization: TextCapitalization.words,
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Group name',
                      hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 14),
                      isDense: true,
                      filled: true,
                      fillColor: context.surfaceMid,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: context.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(color: context.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(color: AppColors.brandBlue),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selected.isNotEmpty) ...[
            SizedBox(
              height: 76,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: selected.length,
                itemBuilder: (context, index) {
                  final user = selected[index];
                  final name = user.fullName.isNotEmpty ? user.fullName : (user.username ?? '?');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.brandBlue,
                              backgroundImage:
                                  user.profilePhotoUrl?.isNotEmpty == true ? NetworkImage(user.profilePhotoUrl!) : null,
                              child: user.profilePhotoUrl?.isNotEmpty != true
                                  ? Text(
                                      name[0].toUpperCase(),
                                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: -4,
                              top: -4,
                              child: GestureDetector(
                                onTap: () => _toggleUserSelection(user),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: context.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: context.border),
                                  ),
                                  child: Icon(Icons.close, size: 12, color: context.textPrimary),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 54,
                          child: Text(
                            name.split(' ').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ).animate().scale(duration: 160.ms),
                  );
                },
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
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
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
                : _searchResults.isEmpty
                    ? Center(
                        child: Text(
                          'No matching people found',
                          style: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          final isSelected = _selectedById.containsKey(user.id);
                          final displayName = user.fullName.isNotEmpty
                              ? user.fullName
                              : (user.username ?? 'Oneova User');

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: isSelected ? AppColors.brandBlue : context.surfaceMid,
                              backgroundImage:
                                  user.profilePhotoUrl?.isNotEmpty == true ? NetworkImage(user.profilePhotoUrl!) : null,
                              child: user.profilePhotoUrl?.isNotEmpty != true
                                  ? Text(
                                      displayName[0].toUpperCase(),
                                      style: GoogleFonts.inter(
                                        color: isSelected ? Colors.white : context.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                if (user.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 13),
                                ],
                              ],
                            ),
                            subtitle: user.username?.isNotEmpty == true
                                ? Text(
                                    '@${user.username}',
                                    style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                                  )
                                : null,
                            trailing: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.brandBlue : Colors.transparent,
                                border: Border.all(
                                  color: isSelected ? AppColors.brandBlue : context.textMuted,
                                  width: 1.5,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: isSelected ? Colors.white : Colors.transparent,
                              ),
                            ),
                            onTap: () => _toggleUserSelection(user),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: _creating ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  child: Text(
                    selected.isEmpty
                        ? 'Create Group'
                        : 'Create Group (${selected.length} ${selected.length == 1 ? 'member' : 'members'})',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
