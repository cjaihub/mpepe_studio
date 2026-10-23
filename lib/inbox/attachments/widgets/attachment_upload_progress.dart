import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AttachmentUploadProgress extends StatefulWidget {
  final UploadTask uploadTask;
  final VoidCallback onCancel;

  const AttachmentUploadProgress({
    super.key,
    required this.uploadTask,
    required this.onCancel,
  });

  @override
  State<AttachmentUploadProgress> createState() => _AttachmentUploadProgressState();
}

class _AttachmentUploadProgressState extends State<AttachmentUploadProgress> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TaskSnapshot>(
      stream: widget.uploadTask.snapshotEvents,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Upload Failed', style: TextStyle(color: Colors.red));
        }

        final state = snapshot.data?.state ?? TaskState.running;
        final progress = snapshot.data != null 
            ? snapshot.data!.bytesTransferred / snapshot.data!.totalBytes 
            : 0.0;

        if (state == TaskState.success) {
          return const Icon(Icons.check_circle, color: Colors.green);
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceHighlight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: AnimatedLoadingIndicator(
                  value: progress,
                  color: AppColors.brandBlue,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(width: 16),
              
              if (state == TaskState.running)
                GestureDetector(
                  onTap: () => widget.uploadTask.pause(),
                  child: const Icon(Icons.pause, color: Colors.white, size: 20),
                )
              else if (state == TaskState.paused)
                GestureDetector(
                  onTap: () => widget.uploadTask.resume(),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                ),
                
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () {
                  widget.uploadTask.cancel();
                  widget.onCancel();
                },
                child: const Icon(Icons.close, color: Colors.red, size: 20),
              ),
            ],
          ),
        );
      }
    );
  }
}
