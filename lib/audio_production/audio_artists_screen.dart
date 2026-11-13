import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

final _audioArtistsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('audio_artists')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
          .toList());
});

class AudioArtistsScreen extends ConsumerWidget {
  const AudioArtistsScreen({super.key});

  Future<void> _showAddArtistDialog(BuildContext context) async {
    HapticFeedback.lightImpact();
    final nameController = TextEditingController();
    final genreController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(
          'Register Artist',
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
                labelText: 'Artist / Stage Name',
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
              controller: genreController,
              style: TextStyle(color: ctx.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Genre / Notes',
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
              final meta = genreController.text.trim();
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
                  .collection('audio_artists')
                  .add({
                'name': name,
                'meta': meta.isEmpty ? 'Registered Studio Artist' : meta,
                'initials': initials,
                'ownerUid': uid,
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = ref.watch(_audioArtistsStreamProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.mic_none, Icons.music_note, Icons.headphones],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Artists', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Registered artists & their requests', style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.brandBlue),
                    tooltip: 'Register Artist',
                    onPressed: () => _showAddArtistDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: artistsAsync.when(
                  data: (artists) {
                    if (artists.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_outline_rounded, size: 42, color: context.textMuted),
                            const SizedBox(height: 10),
                            Text('No registered artists yet', style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _showAddArtistDialog(context),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Register Artist'),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: artists.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final a = artists[index];
                        return _ArtistCard(
                          initials: (a['initials'] as String?) ?? 'AR',
                          name: (a['name'] as String?) ?? 'Artist',
                          meta: (a['meta'] as String?) ?? 'Registered Studio Artist',
                          color: index.isEven ? AppColors.brandBlue : AppColors.brandPink,
                          isNew: index == 0,
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                  error: (e, _) => Center(child: Text('Error loading artists: $e', style: TextStyle(color: context.textSecondary))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final String initials;
  final String name;
  final String meta;
  final Color color;
  final bool isNew;

  const _ArtistCard({
    required this.initials,
    required this.name,
    required this.meta,
    required this.color,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text(meta, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
              ],
            ),
          ),
          if (isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'New',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
