import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

class PhotoIoService {
  final ImagePicker _picker = ImagePicker();

  /// Pick an image from gallery
  Future<File?> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      return File(image.path);
    }
    return null;
  }

  /// Save to gallery or Share. We use share_plus as a universal approach here.
  Future<void> sharePhoto(File file, {String? text}) async {
    final xFile = XFile(file.path);
    await Share.shareXFiles([xFile], text: text);
  }
}
