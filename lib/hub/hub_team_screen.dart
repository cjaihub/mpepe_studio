import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../backend/connections/linked_accounts.dart';
import '../backend/user_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

final _teamMembersStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('studio_team')
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList());
});

class HubTeamScreen extends ConsumerWidget {
  const HubTeamScreen({super.key});

  Future<void> _showInviteMemberDialog(BuildContext context) async {
    HapticFeedback.lightImpact();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final nameController = TextEditingController();
    final roleController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(
          'Invite Team Member',
          style: TextStyle(
            color: ctx.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: ctx.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Name or @username',
                labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                filled: true,
                fillColor: ctx.surfaceMid,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: ctx.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: const BorderSide(color: AppColors.brandBlue),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: roleController,
              style: TextStyle(color: ctx.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Role (e.g., Video Editor, Community)',
                labelStyle: TextStyle(color: ctx.textMuted, fontSize: 12),
                filled: true,
                fillColor: ctx.surfaceMid,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: ctx.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: const BorderSide(color: AppColors.brandBlue),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              final role = roleController.text.trim();
              if (name.isEmpty) return;
              final clean = name.replaceFirst('@', '');
              final parts = clean.split(RegExp(r'\s+'));
              final initials = parts.length >= 2
                  ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                  : clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('studio_team')
                  .add({
                'name': name,
                'role': role.isEmpty ? 'Collaborator' : role,
                'initials': initials,
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProfileProvider).asData?.value;
    final authName = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    final userName = (currentUser?.fullName.trim().isNotEmpty == true)
        ? currentUser!.fullName.trim()
        : authName;
    final linkedAccounts = ref.watch(linkedAccountsProvider).asData?.value ?? const <LinkedAccount>[];
    final teamAsync = ref.watch(_teamMembersStreamProvider);
    final teamMembers = teamAsync.asData?.value ?? const <Map<String, dynamic>>[];

    final studioName = userName.isNotEmpty ? '$userName Studio' : 'Oneova Studio';
    final studioInitial = studioName[0].toUpperCase();
    final totalMembers = 1 + teamMembers.length;
    final connectedCount = linkedAccounts.where((a) => a.status == LinkStatus.connected).length;

    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.people_outline, Icons.dashboard_outlined],
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to Home',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.go('/hub/home');
                    }
                  },
                  icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.textPrimary),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Team & studio',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: context.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OneovaCard(
              child: Row(
                children: [
                  OneovaAvatar(
                    text: studioInitial,
                    size: 48,
                    backgroundColor: AppColors.brandBlue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studioName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimary)),
                        const SizedBox(height: 4),
                        Text(
                          '$connectedCount connected account${connectedCount == 1 ? '' : 's'} · $totalMembers member${totalMembers == 1 ? '' : 's'}',
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: context.textSecondary, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('MEMBERS', style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            OneovaCard(
              child: Column(
                children: [
                  _buildMemberRow(
                    context: context,
                    initials: studioInitial,
                    name: userName.isNotEmpty ? '$userName (You)' : 'You',
                    role: 'Owner',
                    bgColor: AppColors.brandBlue,
                  ),
                  for (var i = 0; i < teamMembers.length; i++) ...[
                    Divider(color: context.border, height: 26),
                    _buildMemberRow(
                      context: context,
                      initials: (teamMembers[i]['initials'] as String?) ?? 'TM',
                      name: (teamMembers[i]['name'] as String?) ?? 'Team Member',
                      role: (teamMembers[i]['role'] as String?) ?? 'Collaborator',
                      bgColor: i.isEven ? AppColors.brandPink : AppColors.brandBlue,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => _showInviteMemberDialog(context),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  border: Border.all(color: context.border),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.add, color: AppColors.brandBlue, size: 20),
                    const SizedBox(height: 6),
                    Text('Invite a team member', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow({required BuildContext context, required String initials, required String name, required String role, Color? bgColor, Gradient? gradient}) {
    return Row(
      children: [
        OneovaAvatar(text: initials, size: 32, backgroundColor: bgColor, gradient: gradient),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary))),
        OneovaPill(text: role, isOutline: true),
      ],
    );
  }
}
