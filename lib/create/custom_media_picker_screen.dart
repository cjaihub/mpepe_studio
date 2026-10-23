import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../backend/projects/models/oneova_draft_model.dart';
import '../backend/projects/services/oneova_draft_engine.dart';
import '../shared/theme/app_theme.dart';

/// Import screen for the creation flow: bring a clip in from the device or
/// reopen one of the user's drafts, then continue in the editor.
class CustomMediaPickerScreen extends ConsumerStatefulWidget {
  const CustomMediaPickerScreen({super.key});

  @override
  ConsumerState<CustomMediaPickerScreen> createState() => _CustomMediaPickerScreenState();
}

class _CustomMediaPickerScreenState extends ConsumerState<CustomMediaPickerScreen> with SingleTickerProviderStateMixin {
  late final TabController _typeTabController;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _typeTabController = TabController(length: 2, vsync: this); // Videos, Photos
  }

  @override
  void dispose() {
    _typeTabController.dispose();
    super.dispose();
  }

  Future<void> _importFromDevice() async {
    HapticFeedback.lightImpact();
    final wantsVideo = _typeTabController.index == 0;
    final picker = ImagePicker();
    final XFile? file = wantsVideo
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    setState(() => _isImporting = true);
    try {
      final draft = await ref.read(oneovaDraftEngineProvider.notifier).createDraftFromMedia(
            sourcePath: file.path,
            isVideo: wantsVideo,
          );
      if (mounted) _openDraft(draft);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import: $e'), backgroundColor: AppColors.brandPink),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _openDraft(OneovaDraft draft) {
    HapticFeedback.selectionClick();
    context.push('/create/editor', extra: draft);
  }

  Future<void> _confirmDeleteDraft(OneovaDraft draft) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text('Delete draft?', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          '"${draft.title}" will be removed from this device and your backup.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textMuted, fontSize: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(color: AppColors.brandPink, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(oneovaDraftEngineProvider.notifier).deleteDraft(draft.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.textPrimary, size: 22),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Import media',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: -0.3),
        ),
        bottom: TabBar(
          controller: _typeTabController,
          indicatorColor: AppColors.brandBlue,
          indicatorWeight: 2,
          labelColor: AppColors.brandBlue,
          unselectedLabelColor: context.textSecondary,
          dividerColor: context.border,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
          tabs: const [Tab(text: 'Videos', height: 40), Tab(text: 'Photos', height: 40)],
        ),
      ),
      body: TabBarView(
        controller: _typeTabController,
        children: [
          _buildDraftGrid(isVideo: true),
          _buildDraftGrid(isVideo: false),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: context.surface,
            border: Border(top: BorderSide(color: context.border, width: 1.0)),
          ),
          child: SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _isImporting ? null : _importFromDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              icon: _isImporting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(
                _isImporting ? 'Importing…' : 'Import from device',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftGrid({required bool isVideo}) {
    final drafts = ref.watch(oneovaDraftEngineProvider).where((d) => d.isVideo == isVideo && d.mediaPath.isNotEmpty).toList();

    if (drafts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isVideo ? Icons.video_library_outlined : Icons.photo_library_outlined, color: context.textMuted, size: 34),
              const SizedBox(height: 10),
              Text(
                isVideo ? 'No video drafts yet' : 'No photo drafts yet',
                style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14.5),
              ),
              const SizedBox(height: 4),
              Text(
                'Import from your device to start editing. Drafts you save appear here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, height: 1.35),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: drafts.length,
      itemBuilder: (context, index) => _DraftTile(
        draft: drafts[index],
        onTap: () => _openDraft(drafts[index]),
        onLongPress: () => _confirmDeleteDraft(drafts[index]),
      ).animate().fadeIn(duration: 250.ms, delay: (index * 25).ms),
    );
  }
}

class _DraftTile extends StatelessWidget {
  final OneovaDraft draft;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _DraftTile({required this.draft, required this.onTap, required this.onLongPress});

  String get _duration {
    final total = draft.durationSeconds.round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final thumb = draft.thumbnailPath;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: context.surfaceMid,
            child: thumb != null && File(thumb).existsSync()
                ? Image.file(File(thumb), fit: BoxFit.cover)
                : Icon(draft.isVideo ? Icons.videocam_outlined : Icons.image_outlined, color: context.textMuted, size: 28),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 4,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    draft.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
                ),
                if (draft.isVideo && draft.durationSeconds > 0)
                  Text(
                    _duration,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
