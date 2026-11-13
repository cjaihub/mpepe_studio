import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

final _studioCrewStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('studio_crew')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList());
});

class VideoTeamScreen extends ConsumerWidget {
  const VideoTeamScreen({super.key});

  Future<void> _showAddCrewDialog(BuildContext context) async {
    HapticFeedback.lightImpact();
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
          'Add Crew Member',
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
                labelText: 'Full Name',
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
                labelText: 'Role (e.g., Director of Photography, Editor)',
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
              final parts = name.split(RegExp(r'\s+'));
              final initials = parts.length >= 2
                  ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
                  : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isEmpty) return;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('studio_crew')
                  .add({
                'name': name,
                'role': role.isEmpty ? 'Crew Member' : role,
                'initials': initials,
                'ownerUid': uid,
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crewAsync = ref.watch(_studioCrewStreamProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.videocam_outlined, Icons.movie_creation_outlined, Icons.camera_alt_outlined],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Crew',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: context.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.brandBlue),
                    tooltip: 'Add Crew Member',
                    onPressed: () => _showAddCrewDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: crewAsync.when(
                  data: (crew) {
                    if (crew.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.group_outlined, size: 42, color: context.textMuted),
                            const SizedBox(height: 10),
                            Text(
                              'No crew members added yet',
                              style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _showAddCrewDialog(context),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Crew Member'),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: crew.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final member = crew[index];
                        return _CrewCard(
                          initials: (member['initials'] as String?) ?? 'CR',
                          name: (member['name'] as String?) ?? 'Crew Member',
                          role: (member['role'] as String?) ?? 'Production Crew',
                          color: index.isEven ? AppColors.brandBlue : AppColors.brandPink,
                        ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                  error: (e, _) => Center(child: Text('Error loading crew: $e', style: TextStyle(color: context.textSecondary))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrewCard extends StatelessWidget {
  final String initials;
  final String name;
  final String role;
  final Color color;

  const _CrewCard({
    required this.initials,
    required this.name,
    required this.role,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: context.textPrimary)),
                const SizedBox(height: 4),
                Text(role, style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
