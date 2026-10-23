import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../backend/attachment_picker_service.dart';
import '../../../backend/calling/services/call_share_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Bottom sheet for sending photos, videos and files during a call, and for
/// browsing what both sides have shared so far.
Future<void> showCallShareSheet(
  BuildContext context,
  WidgetRef ref, {
  required String callId,
  String? chatId,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _CallShareSheet(callId: callId, chatId: chatId),
  );
}

/// Opens a shared item: photos in-app, videos and files in the system viewer.
Future<void> openCallSharedItem(BuildContext context, CallSharedItem item) async {
  if (item.kind == CallShareKind.image) {
    await showDialog<void>(
      context: context,
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.9),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: InteractiveViewer(
          child: Center(child: Image.network(item.url, fit: BoxFit.contain)),
        ),
      ),
    );
    return;
  }
  await launchUrl(Uri.parse(item.url), mode: LaunchMode.externalApplication);
}

class _CallShareSheet extends ConsumerStatefulWidget {
  final String callId;
  final String? chatId;
  const _CallShareSheet({required this.callId, this.chatId});

  @override
  ConsumerState<_CallShareSheet> createState() => _CallShareSheetState();
}

class _CallShareSheetState extends ConsumerState<_CallShareSheet> {
  double? _progress;

  Future<void> _pickAndSend(Future<File?> Function() pick) async {
    if (_progress != null) return;
    HapticFeedback.selectionClick();
    File? file;
    try {
      file = await pick();
    } catch (e) {
      _toast('Could not open the picker.');
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _progress = 0);
    try {
      await ref.read(callShareServiceProvider).share(
            callId: widget.callId,
            chatId: widget.chatId,
            file: file,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      _toast('Shared');
    } catch (e) {
      _toast(e is StateError ? e.message : 'Upload failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.inter(fontSize: 12.5)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandBlue,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final picker = ref.read(attachmentPickerServiceProvider);
    final items = ref.watch(callSharedItemsProvider(widget.callId));
    final me = FirebaseAuth.instance.currentUser?.uid;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Share in call',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Everyone in the call can open what you send.',
                  style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _Action(
                    icon: Icons.photo_rounded,
                    label: 'Photo',
                    onTap: () => _pickAndSend(() => picker.pickImage(fromCamera: false)),
                  ),
                  _Action(
                    icon: Icons.movie_rounded,
                    label: 'Video',
                    onTap: () => _pickAndSend(() => picker.pickVideo(fromCamera: false)),
                  ),
                  _Action(
                    icon: Icons.insert_drive_file_rounded,
                    label: 'File',
                    onTap: () => _pickAndSend(picker.pickDocument),
                  ),
                ],
              ),
            ),
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Uploading ${((_progress ?? 0) * 100).round()}%',
                        style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _progress,
                      minHeight: 3,
                      color: AppColors.brandBlue,
                      backgroundColor: context.surfaceMid,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Divider(height: 1, color: context.border),
            Flexible(
              child: items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                ),
                error: (_, _) => _empty('Could not load shared items.'),
                data: (list) => list.isEmpty
                    ? _empty('Nothing shared yet')
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: context.border),
                        itemBuilder: (_, i) {
                          final it = list[i];
                          final mine = it.senderId == me;
                          return ListTile(
                            dense: true,
                            leading: _thumb(it),
                            title: Text(it.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
                            subtitle: Text(
                              '${mine ? 'You' : (it.senderName.isEmpty ? 'Shared with you' : it.senderName)} · ${_size(it.size)}',
                              style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                            ),
                            trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.brandBlue),
                            onTap: () => openCallSharedItem(context, it),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted)),
        ),
      );

  Widget _thumb(CallSharedItem it) {
    final box = BorderRadius.circular(AppRadius.sm);
    if (it.kind == CallShareKind.image) {
      return ClipRRect(
        borderRadius: box,
        child: Image.network(it.url, width: 40, height: 40, fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _iconBox(Icons.image_rounded)),
      );
    }
    return _iconBox(it.kind == CallShareKind.video ? Icons.play_circle_fill_rounded : Icons.description_rounded);
  }

  Widget _iconBox(IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: AppColors.brandBlue, size: 22),
      );

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1),
            ),
            child: Column(
              children: [
                Icon(icon, color: AppColors.brandBlue, size: 22),
                const SizedBox(height: 6),
                Text(label,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
