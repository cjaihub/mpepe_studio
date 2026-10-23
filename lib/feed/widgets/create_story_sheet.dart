import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../backend/social/services/story_service.dart';
import '../../../backend/social/models/story.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CreateStorySheet extends ConsumerStatefulWidget {
  const CreateStorySheet({super.key});

  @override
  ConsumerState<CreateStorySheet> createState() => _CreateStorySheetState();
}

class _CreateStorySheetState extends ConsumerState<CreateStorySheet> {
  final _textController = TextEditingController();
  bool _isPublishing = false;
  File? _selectedMedia;
  bool _isVideo = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickMedia() async {
    try {
      final XFile? media = await _picker.pickMedia();
      if (media != null) {
        setState(() {
          _selectedMedia = File(media.path);
          _isVideo = media.path.toLowerCase().endsWith('.mp4') || media.path.toLowerCase().endsWith('.mov');
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick media: $e')),
        );
      }
    }
  }

  void _publishStory() async {
    if (_textController.text.trim().isEmpty && _selectedMedia == null) return;
    setState(() => _isPublishing = true);

    final user = FirebaseAuth.instance.currentUser;
    
    String mediaUrl = _textController.text.trim();
    StoryMediaType type = StoryMediaType.text;

    try {
      if (_selectedMedia != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_selectedMedia!.path.split(Platform.pathSeparator).last}';
        final ref = FirebaseStorage.instance.ref().child('stories/$fileName');
        
        final uploadTask = ref.putFile(_selectedMedia!);
        final snapshot = await uploadTask.whenComplete(() {});
        mediaUrl = await snapshot.ref.getDownloadURL();
        type = _isVideo ? StoryMediaType.video : StoryMediaType.photo;
      }

      final story = Story(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        authorId: user?.uid ?? 'unknown',
        authorName: user?.displayName ?? 'You',
        authorAvatarUrl: user?.photoURL ?? 'assets/images/oneova_logo.jpg',
        mediaType: type,
        mediaUrl: mediaUrl,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        privacy: StoryPrivacy.public,
        lifecycle: StoryLifecycle.active,
        isHighlight: false,
        viewers: [],
        reactions: {},
        replyCount: 0,
      );

      await ref.read(storyServiceProvider).createStory(story);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story published successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Create Story',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _pickMedia,
                icon: const Icon(Icons.add_photo_alternate, color: AppColors.brandBlue),
                tooltip: 'Add Media',
              )
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedMedia != null) ...[
            Container(
              height: 120,
              width: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.darkSurface,
                image: _isVideo ? null : DecorationImage(
                  image: FileImage(_selectedMedia!),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  if (_isVideo)
                    const Center(child: Icon(Icons.videocam, color: Colors.white, size: 32)),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedMedia = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _textController,
            style: const TextStyle(color: Colors.white),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "What's on your mind?",
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: AppColors.darkBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isPublishing ? null : _publishStory,
              child: _isPublishing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: AnimatedLoadingIndicator(
                        size: 20,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Publish',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

