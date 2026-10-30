import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import 'dart:io';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import '../services/omnichannel_upload_engine.dart';
import '../models/omnichannel_upload_task.dart';
import '../models/connected_destination.dart';
import '../../backend/connections/linked_accounts.dart' show LinkedPlatform;
import '../../shared/widgets/linked_destinations_picker.dart';

class PremiumPostScreen extends ConsumerStatefulWidget {
  const PremiumPostScreen({super.key});

  @override
  ConsumerState<PremiumPostScreen> createState() => _PremiumPostScreenState();
}

class _PremiumPostScreenState extends ConsumerState<PremiumPostScreen> {
  Future<void> _pickAndUploadFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    final files = result.map((f) => f.path).where((p) => p != null).map((p) => File(p!)).toList();
    if (files.isNotEmpty) {
      _showPlatformSelector(files);
    }
  }

  void _showPlatformSelector(List<File> files) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _PlatformSelectorSheet(files: files);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Your Files',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => context.push('/profile/me'),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.15),
                child: const Icon(Icons.person, color: AppColors.brandBlue, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: Consumer(
        builder: (context, ref, child) {
          final tasks = ref.watch(omnichannelUploadEngineProvider);
          final activeTasks = tasks.where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.uploading).toList();
          final recentTasks = tasks.where((t) => t.status == UploadStatus.completed || t.status == UploadStatus.failed).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUploadZone(),
                if (activeTasks.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildUploadingSection(activeTasks),
                ],
                const SizedBox(height: 24),
                _buildRecentUploadsSection(recentTasks),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildUploadZone() {
    return Material(
      color: context.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () {
          HapticFeedback.lightImpact();
          _pickAndUploadFiles();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.45), width: 1.0),
          ),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.cloud_upload_outlined, size: 24, color: AppColors.brandBlue),
              ).animate().slideY(begin: 0.2, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
              const SizedBox(height: 12),
              Text(
                'Upload videos or photos',
                style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2),
              ),
              const SizedBox(height: 4),
              Text(
                'Published to your Oneova feed, plus any connected platforms you pick.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _pickAndUploadFiles();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text('Browse files', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _confirmCancelUploads(OmnichannelUploadEngine engine) async {
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: Text('Cancel uploads?', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
          'Files still uploading will be discarded. Finished uploads stay published.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep uploading', style: GoogleFonts.inter(color: context.textMuted, fontSize: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancel uploads', style: GoogleFonts.inter(color: AppColors.brandPink, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
    if (confirmed == true) await engine.cancelActiveUploads();
  }

  Widget _buildUploadingSection(List<OmnichannelUploadTask> activeTasks) {
    if (activeTasks.isEmpty) return const SizedBox.shrink();

    final aggregateProgress = activeTasks.fold(0.0, (sum, task) => sum + task.progress) / activeTasks.length;
    final engine = ref.read(omnichannelUploadEngineProvider.notifier);
    final isPaused = engine.isPaused;

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Uploading ${activeTasks.length} files',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              Icon(Icons.open_in_full_rounded, color: context.textMuted, size: 16),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: activeTasks.map((task) {
              return Container(
                margin: const EdgeInsets.only(right: 8),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                ),
                child: const Icon(Icons.image, color: AppColors.brandBlue, size: 20),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: context.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              FractionallySizedBox(
                widthFactor: aggregateProgress > 0 ? aggregateProgress : 0.05, 
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPaused ? 'Paused · ${(aggregateProgress * 100).round()}%' : '${(aggregateProgress * 100).round()}% uploaded',
                style: GoogleFonts.inter(
                  color: AppColors.brandBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: context.textMuted, size: 20),
                    tooltip: isPaused ? 'Resume uploads' : 'Pause uploads',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      engine.togglePauseAll();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.brandBlue, size: 20),
                    tooltip: 'Cancel uploads',
                    onPressed: () => _confirmCancelUploads(engine),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildRecentUploadsSection(List<OmnichannelUploadTask> recentTasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent uploaded',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              '${recentTasks.length} items',
              style: GoogleFonts.inter(
                color: context.textMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: recentTasks.length,
          itemBuilder: (context, index) {
            final task = recentTasks[index];
            final fileName = task.file.path.split('/').last;
            
            final fileSize = _formatBytes(task.file.existsSync() ? task.file.lengthSync() : 0);
            final isFailed = task.status == UploadStatus.failed;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isFailed 
                        ? AppColors.brandPink.withValues(alpha: 0.1)
                        : AppColors.brandBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isFailed ? Icons.error_outline_rounded : Icons.insert_drive_file_rounded, 
                      color: isFailed ? AppColors.brandPink : AppColors.brandBlue
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: GoogleFonts.inter(
                            color: context.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              fileSize,
                              style: GoogleFonts.inter(
                                color: isFailed ? AppColors.brandPink : context.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                              isFailed ? 'Failed · ${task.errorMessage ?? 'Unknown error'}' : 'Published',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: context.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isFailed)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: AppColors.brandBlue),
                      tooltip: 'Retry upload',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(omnichannelUploadEngineProvider.notifier).startUploads();
                      },
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, color: context.textMuted),
                    tooltip: 'Remove from list',
                    onPressed: () {
                      ref.read(omnichannelUploadEngineProvider.notifier).removeTask(task.id);
                    },
                  ),
                ],
              ).animate().fadeIn(delay: (300 + (index * 50)).ms).slideX(begin: 0.1),
            );
          },
        ),
      ],
    );
  }
}

class _PlatformSelectorSheet extends ConsumerStatefulWidget {
  final List<File> files;

  const _PlatformSelectorSheet({required this.files});

  @override
  ConsumerState<_PlatformSelectorSheet> createState() => _PlatformSelectorSheetState();
}

class _PlatformSelectorSheetState extends ConsumerState<_PlatformSelectorSheet> {
  bool _starting = false;

  static PlatformType? _typeFor(String id) => switch (LinkedPlatform.fromId(id)) {
        LinkedPlatform.youtube => PlatformType.youtube,
        LinkedPlatform.tiktok => PlatformType.tiktok,
        LinkedPlatform.instagram => PlatformType.instagram,
        LinkedPlatform.facebook => PlatformType.facebook,
        _ => null,
      };

  /// Oneova always gets the post; the linked platforms the account picked
  /// get it too, using each account's real id.
  Future<void> _startUpload() async {
    setState(() => _starting = true);
    final engine = ref.read(omnichannelUploadEngineProvider.notifier);
    final picked = ref.read(activeDestinationsProvider(DestinationPurpose.post)).map(_typeFor).whereType<PlatformType>().toSet();
    final all = await engine.fetchAllDestinations();
    final selected = all.where((d) => picked.contains(d.platform)).toList();
    if (!mounted) return;
    Navigator.pop(context);
    engine.addTasks(widget.files, selected);
    engine.startUploads();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(activeDestinationsProvider(DestinationPurpose.post)).length;
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Post to',
                style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: context.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            '${widget.files.length} file(s) go to your Oneova feed and to the linked accounts you pick. Your pick is saved for next time.',
            style: GoogleFonts.inter(color: context.textMuted, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 16),
          const Expanded(
            child: SingleChildScrollView(
              child: LinkedDestinationsPicker(purpose: DestinationPurpose.post),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: AppColors.brandWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: _starting ? null : _startUpload,
              child: _starting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandWhite))
                  : Text(
                      count == 0 ? 'Post to Oneova' : 'Post to Oneova + $count',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
