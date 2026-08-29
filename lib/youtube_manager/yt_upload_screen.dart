import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class YtUploadScreen extends StatelessWidget {
  const YtUploadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload to YouTube', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.cloud_upload, size: 40, color: AppColors.ytAccent),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select a video to upload',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Videos will be uploaded privately first. You can use Gemini to generate titles, descriptions, and tags before publishing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.dustText, height: 1.5),
            ),
            const SizedBox(height: 32),
            MpepeButton(
              text: 'Select from device',
              icon: Icons.folder,
              onPressed: () {
                // TODO: Implement file picker
              },
            ),
            const SizedBox(height: 16),
            MpepeButton(
              text: 'Import from Video Production',
              isPrimary: false,
              icon: Icons.movie,
              onPressed: () {
                // TODO: Implement studio integration
              },
            ),
          ],
        ),
      ),
    );
  }
}
