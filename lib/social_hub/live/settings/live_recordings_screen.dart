// LIVE RECORDINGS — /settings/live_recordings
// The 1080p lives the host chose to keep (users/{uid}/live_recordings),
// newest first, with share / download and delete.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../backend/live_studio/fun/studio_fun.dart';
import '../../../shared/theme/app_theme.dart';

final _recordingsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users/$uid/live_recordings')
      .orderBy('savedAt', descending: true)
      .snapshots()
      .map((q) => [for (final d in q.docs) {'id': d.id, ...d.data()}]);
});

class LiveRecordingsScreen extends ConsumerWidget {
  const LiveRecordingsScreen({super.key});

  Future<void> _share(BuildContext context, String path, String title) async {
    try {
      final url = await FirebaseStorage.instance.ref(path).getDownloadURL();
      await SharePlus.instance.share(ShareParams(uri: Uri.parse(url), subject: title));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Could not open this recording.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recordingsProvider);
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.topBarBg,
        foregroundColor: context.topBarFg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Text('Live recordings', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        error: (_, _) => Center(child: Text('Could not load recordings.', style: GoogleFonts.inter(color: context.textSecondary))),
        data: (items) => items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.video_library_outlined, size: 48, color: context.textMuted),
                    const SizedBox(height: 12),
                    Text('No saved lives yet', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: context.textPrimary)),
                    const SizedBox(height: 6),
                    Text('Turn on "Record in 1080p" when you go live, then tap Keep when it ends.',
                        textAlign: TextAlign.center, style: GoogleFonts.inter(color: context.textSecondary)),
                  ]),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = items[i];
                  final title = (r['title'] as String?) ?? 'Live';
                  final path = r['storagePath'] as String? ?? '';
                  final ms = (r['durationMs'] as num?)?.toInt();
                  final saved = r['savedAt'] is Timestamp ? (r['savedAt'] as Timestamp).toDate() : null;
                  return Container(
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: context.border),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: AppColors.brandBlue, borderRadius: BorderRadius.circular(AppRadius.md)),
                        child: const Icon(Icons.movie_rounded, color: AppColors.brandWhite),
                      ),
                      title: Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary)),
                      subtitle: Text(
                        [
                          if (saved != null) '${saved.day}/${saved.month}/${saved.year}',
                          if (ms != null) '${ms ~/ 60000}m ${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}s',
                          '1080p',
                        ].join(' · '),
                        style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Share or download',
                          icon: const Icon(Icons.ios_share_rounded, color: AppColors.brandBlue),
                          onPressed: path.isEmpty ? null : () => _share(context, path, title),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline_rounded, color: context.textMuted),
                          onPressed: () => ref.read(studioBroadcastApiProvider).decide(r['id'] as String, keep: false),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
