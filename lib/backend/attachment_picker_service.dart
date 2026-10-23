import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

final attachmentPickerServiceProvider = Provider<AttachmentPickerService>((ref) {
  return AttachmentPickerService();
});

class AttachmentPickerService {
  final ImagePicker _imagePicker = ImagePicker();

  Future<File?> pickImage({required bool fromCamera}) async {
    final pickedFile = await _imagePicker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (pickedFile != null) {
      return File(pickedFile.path);
    }
    return null;
  }

  Future<File?> pickVideo({required bool fromCamera}) async {
    final pickedFile = await _imagePicker.pickVideo(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
    );
    if (pickedFile != null) {
      final mediaInfo = await VideoCompress.compressVideo(
        pickedFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      if (mediaInfo != null && mediaInfo.file != null) {
        return mediaInfo.file;
      }
      return File(pickedFile.path);
    }
    return null;
  }

  Future<File?> pickDocument() async {
    final result = await FilePicker.pickFile(
      type: FileType.any,
    );
    if (result != null && result.path != null) {
      return File(result.path!);
    }
    return null;
  }
}
