import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:oneova_media_engine/oneova_media_engine.dart';

import '../../../shared/theme/app_theme.dart';
import '../screens/studio_media_picker_screen.dart';
import '../services/studio_media.dart';
import 'studio_ui.dart';

/// Runs [task] behind a blocking dialog with a progress bar. On failure the
/// dialog shows the error with Retry / Close instead of failing silently.
/// Resolves to the task's result, or null if the user gave up.
Future<T?> runStudioTask<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(void Function(double progress) onProgress) task,
  Future<void> Function()? onCancel,
  String Function(Object error)? describeError,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StudioTaskDialog<T>(title: title, task: task, onCancel: onCancel, describeError: describeError),
  );
}

class _StudioTaskDialog<T> extends StatefulWidget {
  final String title;
  final Future<T> Function(void Function(double) onProgress) task;
  final Future<void> Function()? onCancel;
  final String Function(Object error)? describeError;

  const _StudioTaskDialog({required this.title, required this.task, this.onCancel, this.describeError});

  @override
  State<_StudioTaskDialog<T>> createState() => _StudioTaskDialogState<T>();
}

class _StudioTaskDialogState<T> extends State<_StudioTaskDialog<T>> {
  double _progress = 0;
  String? _error;
  bool _running = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _progress = 0;
    });
    try {
      final result = await widget.task((p) {
        if (mounted && !_cancelled) setState(() => _progress = p.clamp(0.0, 1.0));
      });
      if (mounted && !_cancelled) Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() {
        _running = false;
        _error = widget.describeError?.call(e) ?? e.toString();
      });
    }
  }

  Future<void> _cancel() async {
    if (_running) {
      final ok = await studioConfirm(
        context,
        title: 'Cancel?',
        message: 'This will stop "${widget.title.toLowerCase()}". Your edit stays in Projects.',
        confirmLabel: 'Stop',
      );
      if (!ok || !mounted) return;
    }
    _cancelled = true;
    await widget.onCancel?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg), side: BorderSide(color: context.border)),
        title: Row(
          children: [
            Icon(failed ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
                color: failed ? AppColors.brandPink : AppColors.brandBlue, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(failed ? '${widget.title} failed' : widget.title,
                  style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: failed
            ? Text(_error!, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.4))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: LinearProgressIndicator(
                      value: _progress <= 0 ? null : _progress,
                      minHeight: 6,
                      color: AppColors.brandBlue,
                      backgroundColor: context.surfaceMid,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(_progress <= 0 ? 'Starting…' : '${(_progress * 100).round()}%',
                      style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
        actions: [
          TextButton(
            onPressed: _cancel,
            child: Text(failed ? 'Close' : 'Cancel',
                style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w600)),
          ),
          if (failed)
            TextButton(
              onPressed: _run,
              child: Text('Retry', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// Imports [picks] into clips. Files likely to need converting (HEIC, GIF,
/// AVI, MKV, WebM...) run behind the progress dialog; plain MP4/JPEG picks
/// open straight away. Null if the user gave up.
Future<StudioImportResult?> studioImportWithProgress(BuildContext context, List<StudioPick> picks, {bool allowVideo = true}) async {
  const quick = {'mp4', 'mov', 'm4v', '3gp', 'jpg', 'jpeg', 'png', 'webp'};
  final slow = picks.any((p) {
    final name = p.path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot < 0 || !quick.contains(name.substring(dot + 1).toLowerCase());
  });
  if (!slow) return StudioMedia.importPicks(picks, allowVideo: allowVideo);
  return runStudioTask<StudioImportResult>(
    context,
    title: 'Opening media',
    onCancel: OneovaMediaEngine.cancel,
    task: (onProgress) async {
      onProgress(0.05);
      final sub = OneovaMediaEngine.progress.listen((p) => onProgress(0.05 + p * 0.9));
      try {
        return await StudioMedia.importPicks(picks, allowVideo: allowVideo);
      } finally {
        await sub.cancel();
      }
    },
  );
}
