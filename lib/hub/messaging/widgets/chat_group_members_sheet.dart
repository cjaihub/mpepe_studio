import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../backend/messaging_repository.dart';
import '../../../backend/storage_service.dart';
import '../../../backend/user_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'chat_user_directory.dart';

/// Group info section (rename, change photo, member roster, add/remove members, leave group).
class ChatGroupManagementSection extends ConsumerStatefulWidget {
  final ChatModel chat;
  final String currentUserId;
  final Future<AppUser?> Function(String uid) getUserCached;
  final VoidCallback onCloseSheet;

  const ChatGroupManagementSection({
    super.key,
    required this.chat,
    required this.currentUserId,
    required this.getUserCached,
    required this.onCloseSheet,
  });

  @override
  ConsumerState<ChatGroupManagementSection> createState() => _ChatGroupManagementSectionState();
}

class _ChatGroupManagementSectionState extends ConsumerState<ChatGroupManagementSection> {
  bool _updatingPhoto = false;

  bool get _isOwner => widget.chat.ownerId == null || widget.chat.ownerId == widget.currentUserId;

  Future<void> _renameGroup() async {
    final ctrl = TextEditingController(text: widget.chat.title ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(
          'Rename group',
          style: GoogleFonts.inter(color: ctx.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Group name',
            hintStyle: GoogleFonts.inter(color: ctx.textMuted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName == null || newName.isEmpty) return;
    await ref.read(messagingRepositoryProvider).renameGroup(widget.chat.id, newName);
  }

  Future<void> _changePhoto() async {
    if (_updatingPhoto) return;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, imageQuality: 85);
      if (picked == null) return;
      setState(() => _updatingPhoto = true);
      final path = 'users/${widget.currentUserId}/avatar/group_${widget.chat.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final snap = await ref.read(storageServiceProvider).uploadFileWithProgress(File(picked.path), path);
      final url = await snap.ref.getDownloadURL();
      await ref.read(messagingRepositoryProvider).updateGroupAvatar(widget.chat.id, url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update group photo'), backgroundColor: AppColors.brandPink),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingPhoto = false);
    }
  }

  Future<void> _addMembers() async {
    final added = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMembersSheet(existingIds: widget.chat.participants.toSet()),
    );
    if (added == null || added.isEmpty) return;
    await ref.read(messagingRepositoryProvider).addGroupMembers(widget.chat.id, added);
  }

  Future<void> _confirmRemoveMember(String memberId, String memberName) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(
          'Remove $memberName?',
          style: GoogleFonts.inter(color: ctx.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'They will no longer receive messages in this group.',
          style: GoogleFonts.inter(color: ctx.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(messagingRepositoryProvider).removeGroupMember(widget.chat.id, memberId);
    }
  }

  Future<void> _confirmLeaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(
          'Leave group?',
          style: GoogleFonts.inter(color: ctx.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        content: Text(
          'You will stop receiving messages from ${widget.chat.title ?? 'this group'}.',
          style: GoogleFonts.inter(color: ctx.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave Group'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(messagingRepositoryProvider).leaveGroup(widget.chat.id, widget.currentUserId);
      widget.onCloseSheet();
      if (mounted) context.go('/hub/messages');
    }
  }

  @override
  Widget build(BuildContext context) {
    final participants = widget.chat.participants;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_rounded, size: 16, color: AppColors.brandBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Group Members (${participants.length})',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (widget.chat.category != 'channel')
              TextButton.icon(
                onPressed: _addMembers,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 15, color: AppColors.brandBlue),
                label: Text(
                  'Add',
                  style: GoogleFonts.inter(
                    color: AppColors.brandBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: AppDecorations.groupedSection(context),
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.edit_rounded, size: 18, color: AppColors.brandBlue),
                title: Text('Rename group', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 18),
                onTap: _renameGroup,
              ),
              Divider(height: 1, color: context.border),
              ListTile(
                dense: true,
                leading: _updatingPhoto
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                    : const Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.brandBlue),
                title: Text('Change group photo', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 18),
                onTap: _changePhoto,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: AppDecorations.groupedSection(context),
          child: Column(
            children: [
              for (var i = 0; i < participants.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 52, color: context.border),
                _MemberRow(
                  uid: participants[i],
                  isMe: participants[i] == widget.currentUserId,
                  isOwner: participants[i] == widget.chat.ownerId,
                  canRemove: _isOwner && participants[i] != widget.currentUserId,
                  getUser: widget.getUserCached,
                  onTapProfile: () {
                    widget.onCloseSheet();
                    context.push('/profile/${participants[i]}');
                  },
                  onRemove: (name) => _confirmRemoveMember(participants[i], name),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: AppDecorations.groupedSection(context),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.exit_to_app_rounded, size: 18, color: AppColors.brandPink),
            title: Text(
              'Leave group',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            onTap: _confirmLeaveGroup,
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final String uid;
  final bool isMe;
  final bool isOwner;
  final bool canRemove;
  final Future<AppUser?> Function(String uid) getUser;
  final VoidCallback onTapProfile;
  final void Function(String name) onRemove;

  const _MemberRow({
    required this.uid,
    required this.isMe,
    required this.isOwner,
    required this.canRemove,
    required this.getUser,
    required this.onTapProfile,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: getUser(uid),
      builder: (context, snap) {
        final user = snap.data;
        final name = isMe
            ? 'You'
            : (user != null && user.fullName.isNotEmpty
                ? user.fullName
                : (user?.username ?? 'Member'));
        final avatar = user?.profilePhotoUrl;
        return ListTile(
          dense: true,
          onTap: isMe ? null : onTapProfile,
          leading: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.brandBlue,
            backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar == null || avatar.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  )
                : null,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (user?.isVerified == true) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 13),
              ],
              if (isOwner) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                  child: Text(
                    'Admin',
                    style: GoogleFonts.inter(
                      color: AppColors.brandBlue,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: user?.username?.isNotEmpty == true
              ? Text('@${user!.username}', style: GoogleFonts.inter(color: context.textMuted, fontSize: 11))
              : null,
          trailing: canRemove
              ? IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppColors.brandPink),
                  onPressed: () => onRemove(name),
                )
              : null,
        );
      },
    );
  }
}

class _AddMembersSheet extends StatefulWidget {
  final Set<String> existingIds;
  const _AddMembersSheet({required this.existingIds});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AppUser> _seed = [];
  List<AppUser> _results = [];
  final Set<String> _picked = {};
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ChatUserDirectory.loadSuggested(limit: 40);
      final filtered = list.where((u) => !widget.existingIds.contains(u.id)).toList();
      if (mounted) {
        setState(() {
          _seed = filtered;
          _results = filtered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      final res = await ChatUserDirectory.search(q, seed: _seed, excludeIds: widget.existingIds);
      if (mounted) setState(() => _results = res);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Add Members', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList()),
                  child: Text(
                    _picked.isEmpty ? 'Done' : 'Add (${_picked.length})',
                    style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search people…',
                hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: context.textMuted, size: 18),
                isDense: true,
                filled: true,
                fillColor: context.surfaceMid,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide(color: context.border)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
                : _results.isEmpty
                    ? Center(child: Text('No people available to add', style: GoogleFonts.inter(color: context.textMuted)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final u = _results[i];
                          final name = u.fullName.isNotEmpty ? u.fullName : (u.username ?? 'Oneova User');
                          final on = _picked.contains(u.id);
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.brandBlue,
                              backgroundImage: u.profilePhotoUrl?.isNotEmpty == true ? NetworkImage(u.profilePhotoUrl!) : null,
                              child: u.profilePhotoUrl?.isNotEmpty != true
                                  ? Text(name[0].toUpperCase(), style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700))
                                  : null,
                            ),
                            title: Text(name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                            subtitle: u.username?.isNotEmpty == true ? Text('@${u.username}', style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5)) : null,
                            trailing: Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: on ? AppColors.brandBlue : context.textMuted),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (!on) {
                                  _picked.add(u.id);
                                } else {
                                  _picked.remove(u.id);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
