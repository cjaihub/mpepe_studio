import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../../backend/inbox/audio_recorder_service.dart';
import '../../shared/theme/app_theme.dart';

class VoiceRecorderButton extends ConsumerStatefulWidget {
  final Function(File audioFile, Duration duration) onRecordingComplete;
  
  const VoiceRecorderButton({
    super.key,
    required this.onRecordingComplete,
  });

  @override
  ConsumerState<VoiceRecorderButton> createState() => _VoiceRecorderButtonState();
}

class _VoiceRecorderButtonState extends ConsumerState<VoiceRecorderButton> {
  bool _isRecording = false;
  DateTime? _startTime;

  Future<void> _startRecording() async {
    final service = ref.read(audioRecorderServiceProvider);
    try {
      await service.startRecording();
      setState(() {
        _isRecording = true;
        _startTime = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    
    final service = ref.read(audioRecorderServiceProvider);
    final file = await service.stopRecording();
    
    final duration = DateTime.now().difference(_startTime ?? DateTime.now());
    
    setState(() {
      _isRecording = false;
      _startTime = null;
    });

    if (file != null && duration.inSeconds > 0) {
      widget.onRecordingComplete(file, duration);
    } else if (file != null) {
      // Too short, delete
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    
    final service = ref.read(audioRecorderServiceProvider);
    await service.cancelRecording();
    
    setState(() {
      _isRecording = false;
      _startTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _startRecording,
      onLongPressEnd: (details) {
        // If dragged out, maybe cancel, but for now just stop and send
        _stopRecording();
      },
      onLongPressCancel: () {
        _cancelRecording();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isRecording ? AppColors.brandBlue : Colors.transparent,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(_isRecording ? 12 : 8),
        child: Icon(
          Icons.mic,
          color: _isRecording ? Colors.white : context.textSecondary,
          size: _isRecording ? 28 : 24,
        ),
      ),
    );
  }
}
