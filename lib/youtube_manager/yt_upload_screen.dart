import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../auth/auth_repository.dart';
import 'services/youtube_upload_service.dart';

class YtUploadScreen extends ConsumerStatefulWidget {
  const YtUploadScreen({super.key});

  @override
  ConsumerState<YtUploadScreen> createState() => _YtUploadScreenState();
}

class _YtUploadScreenState extends ConsumerState<YtUploadScreen> {
  File? _selectedFile;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _titleController.text = result.files.single.name;
      });
    }
  }

  Future<void> _uploadVideo() async {
    if (_selectedFile == null) return;
    
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
    });

    try {
      final authRepo = ref.read(authRepositoryProvider);
      final client = await authRepo.getAuthenticatedClient();
      
      if (client == null) {
        throw Exception("You must be signed in with Google to upload.");
      }
      
      final uploadService = YouTubeUploadService(client);
      
      final tags = _tagsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      setState(() { _uploadProgress = 0.3; });

      final result = await uploadService.uploadVideo(
        videoFile: _selectedFile!,
        title: _titleController.text.isNotEmpty ? _titleController.text : 'My Upload',
        description: _descriptionController.text.isNotEmpty ? _descriptionController.text : 'Uploaded via MPEPE Studio',
        tags: tags,
      );

      setState(() { _uploadProgress = 1.0; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload successful: ${result.snippet?.title}')),
        );
      }
      
      // Reset form
      setState(() {
        _selectedFile = null;
        _titleController.clear();
        _descriptionController.clear();
        _tagsController.clear();
        _isUploading = false;
        _uploadProgress = 0.0;
      });
      
    } catch (e) {
      setState(() {
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload to YouTube', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedFile == null) ...[
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_upload, size: 60, color: AppColors.ytAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'Select a video to upload',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'MP4, MOV, or AVI',
                      style: TextStyle(color: AppColors.dustText),
                    ),
                    const SizedBox(height: 24),
                    MpepeButton(
                      text: 'Select from device',
                      icon: Icons.folder,
                      onPressed: _pickFile,
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.ytAccent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.movie, size: 40, color: AppColors.ytAccent),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFile!.path.split(Platform.pathSeparator).last,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${(_selectedFile!.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB',
                            style: const TextStyle(color: AppColors.dustText, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.red),
                      onPressed: _isUploading ? null : () {
                        setState(() { _selectedFile = null; });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isUploading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                enabled: !_isUploading,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_isUploading,
              ),
              const SizedBox(height: 32),
              if (_isUploading) ...[
                LinearProgressIndicator(value: _uploadProgress, color: AppColors.ytAccent),
                const SizedBox(height: 8),
                const Center(child: Text('Uploading...', style: TextStyle(color: AppColors.dustText))),
              ] else ...[
                MpepeButton(
                  text: 'Upload to YouTube',
                  icon: Icons.upload,
                  onPressed: _uploadVideo,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
