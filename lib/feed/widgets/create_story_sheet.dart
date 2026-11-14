import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

import '../../../backend/social/models/audio_track.dart';
import '../../../backend/social/models/story.dart';
import '../../../backend/social/services/story_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/oneova_voice_typing_button.dart';

class CreateStorySheet extends ConsumerStatefulWidget {
  const CreateStorySheet({super.key});

  @override
  ConsumerState<CreateStorySheet> createState() => _CreateStorySheetState();
}

class _CreateStorySheetState extends ConsumerState<CreateStorySheet> {
  final _textController = TextEditingController();
  bool _isPublishing = false;
  final List<File> _selectedPhotos = [];
  File? _selectedVideo;
  AudioTrack? _selectedCatalogMusic;
  File? _selectedLocalMusicFile;
  String? _selectedLocalMusicTitle;
  StoryPrivacy _privacy = StoryPrivacy.public;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickMultiPhotos() async {
    HapticFeedback.selectionClick();
    try {
      final List<XFile> photos = await _picker.pickMultiImage(
        maxWidth: 1920,
        imageQuality: 88,
      );
      if (photos.isNotEmpty && mounted) {
        setState(() {
          _selectedVideo = null;
          for (final p in photos) {
            if (_selectedPhotos.length < 10) {
              _selectedPhotos.add(File(p.path));
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick photos: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    HapticFeedback.selectionClick();
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 60),
      );
      if (video != null && mounted) {
        setState(() {
          _selectedPhotos.clear();
          _selectedVideo = File(video.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick video: $e')),
        );
      }
    }
  }

  Future<void> _openMusicPicker() async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.62,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: ctx.border,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.library_music_rounded,
                        color: AppColors.brandPink,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Attach Music to Status',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ctx.textPrimary,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandBlue,
                          side: BorderSide(color: ctx.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                        ),
                        onPressed: () async {
                          final res = await FilePicker.pickFiles(
                            type: FileType.audio,
                          );
                          final file = res.firstOrNull;
                          if (file?.path != null && mounted) {
                            setState(() {
                              _selectedCatalogMusic = null;
                              _selectedLocalMusicFile = File(file!.path!);
                              _selectedLocalMusicTitle = file.name.replaceAll(
                                RegExp(r'\.[a-zA-Z0-9]+$'),
                                '',
                              );
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
                        icon: const Icon(Icons.folder_open_rounded, size: 15),
                        label: Text(
                          'From Device',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('audio_tracks')
                          .limit(30)
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        if (docs.isEmpty) {
                          return Center(
                            child: Text(
                              'Tap "From Device" above to attach any song from your phone.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: ctx.textSecondary,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: ctx.border),
                          itemBuilder: (_, i) {
                            final d = docs[i].data();
                            final track = AudioTrack.fromMap({
                              ...d,
                              'id': docs[i].id,
                            });
                            final selected =
                                _selectedCatalogMusic?.id == track.id;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.brandBlue
                                      .withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  color: AppColors.brandBlue,
                                  size: 18,
                                ),
                              ),
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: ctx.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                track.ownerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: ctx.textSecondary,
                                ),
                              ),
                              trailing: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                color: selected
                                    ? AppColors.brandPink
                                    : AppColors.brandBlue,
                                size: 20,
                              ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedCatalogMusic = track;
                                  _selectedLocalMusicFile = null;
                                  _selectedLocalMusicTitle = null;
                                });
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _publishStory() async {
    final caption = _textController.text.trim();
    if (caption.isEmpty && _selectedPhotos.isEmpty && _selectedVideo == null) {
      return;
    }
    setState(() => _isPublishing = true);

    final user = FirebaseAuth.instance.currentUser;
    String primaryMediaUrl = caption;
    final uploadedUrls = <String>[];
    StoryMediaType type = StoryMediaType.text;

    try {
      if (_selectedVideo != null) {
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${_selectedVideo!.path.split(Platform.pathSeparator).last}';
        final storageRef =
            FirebaseStorage.instance.ref().child('stories/$fileName');
        final snapshot = await storageRef.putFile(_selectedVideo!).whenComplete(() {});
        primaryMediaUrl = await snapshot.ref.getDownloadURL();
        uploadedUrls.add(primaryMediaUrl);
        type = StoryMediaType.video;
      } else if (_selectedPhotos.isNotEmpty) {
        for (var i = 0; i < _selectedPhotos.length; i++) {
          final file = _selectedPhotos[i];
          final fileName =
              '${DateTime.now().millisecondsSinceEpoch}_${i}_${file.path.split(Platform.pathSeparator).last}';
          final storageRef =
              FirebaseStorage.instance.ref().child('stories/$fileName');
          final snapshot = await storageRef.putFile(file).whenComplete(() {});
          final url = await snapshot.ref.getDownloadURL();
          uploadedUrls.add(url);
        }
        primaryMediaUrl = uploadedUrls.first;
        type = StoryMediaType.photo;
      }

      String? musicUrl = _selectedCatalogMusic?.contentUrl;
      String? musicTitle = _selectedCatalogMusic?.title;
      String? musicArtist = _selectedCatalogMusic?.ownerName;
      String? musicId = _selectedCatalogMusic?.id;

      if (_selectedLocalMusicFile != null) {
        final audioName =
            '${DateTime.now().millisecondsSinceEpoch}_${_selectedLocalMusicFile!.path.split(Platform.pathSeparator).last}';
        final audioRef =
            FirebaseStorage.instance.ref().child('stories/audio/$audioName');
        final audioSnap =
            await audioRef.putFile(_selectedLocalMusicFile!).whenComplete(() {});
        musicUrl = await audioSnap.ref.getDownloadURL();
        musicTitle = _selectedLocalMusicTitle ?? 'Original Audio';
        musicArtist = user?.displayName ?? 'You';
      }

      final story = Story(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        authorId: user?.uid ?? 'unknown',
        authorName: user?.displayName ?? 'You',
        authorAvatarUrl: user?.photoURL ?? 'assets/images/oneova_logo.jpg',
        mediaType: type,
        mediaUrl: primaryMediaUrl,
        mediaUrls: uploadedUrls,
        caption: caption.isNotEmpty ? caption : null,
        musicId: musicId,
        musicTitle: musicTitle,
        musicArtist: musicArtist,
        musicUrl: musicUrl,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        privacy: _privacy,
        lifecycle: StoryLifecycle.active,
        isHighlight: false,
        viewers: const [],
        reactions: const {},
        replyCount: 0,
      );

      await ref.read(storyServiceProvider).createStory(story);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status published!'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.brandPink,
          ),
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
    final hasMusic =
        _selectedCatalogMusic != null || _selectedLocalMusicFile != null;
    final musicLabel = _selectedCatalogMusic != null
        ? '${_selectedCatalogMusic!.title} • ${_selectedCatalogMusic!.ownerName}'
        : (_selectedLocalMusicTitle ?? '');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Create Advanced Status',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              // Privacy selector chip
              PopupMenuButton<StoryPrivacy>(
                initialValue: _privacy,
                color: context.surface,
                onSelected: (p) => setState(() => _privacy = p),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: StoryPrivacy.public,
                    child: Text('Public'),
                  ),
                  const PopupMenuItem(
                    value: StoryPrivacy.followers,
                    child: Text('Followers Only'),
                  ),
                  const PopupMenuItem(
                    value: StoryPrivacy.closeFriends,
                    child: Text('Close Friends'),
                  ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: context.border, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.public_rounded,
                        size: 13,
                        color: AppColors.brandBlue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _privacy.name.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action Chips: Multi-Photos | Video | Attach Music
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _actionChip(
                  context,
                  icon: Icons.collections_rounded,
                  label: _selectedPhotos.isEmpty
                      ? 'Multi-Photos'
                      : 'Photos (${_selectedPhotos.length})',
                  accent: AppColors.brandBlue,
                  active: _selectedPhotos.isNotEmpty,
                  onTap: _pickMultiPhotos,
                ),
                const SizedBox(width: 8),
                _actionChip(
                  context,
                  icon: Icons.videocam_rounded,
                  label: _selectedVideo != null ? 'Video Ready' : 'Video',
                  accent: AppColors.brandBlue,
                  active: _selectedVideo != null,
                  onTap: _pickVideo,
                ),
                const SizedBox(width: 8),
                _actionChip(
                  context,
                  icon: Icons.music_note_rounded,
                  label: hasMusic ? 'Change Music' : 'Attach Music',
                  accent: AppColors.brandPink,
                  active: hasMusic,
                  onTap: _openMusicPicker,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Attached Music Pill
          if (hasMusic) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              decoration: BoxDecoration(
                color: AppColors.brandPink
                    .withValues(alpha: context.isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: AppColors.brandPink.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    size: 15,
                    color: AppColors.brandPink,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      musicLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setState(() {
                      _selectedCatalogMusic = null;
                      _selectedLocalMusicFile = null;
                      _selectedLocalMusicTitle = null;
                    }),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Multi-Photo / Video Preview Strip
          if (_selectedPhotos.isNotEmpty || _selectedVideo != null) ...[
            SizedBox(
              height: 104,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_selectedVideo != null)
                    _mediaPreviewCard(
                      context,
                      file: _selectedVideo!,
                      isVideo: true,
                      badge: 'VIDEO',
                      onRemove: () => setState(() => _selectedVideo = null),
                    ),
                  for (var i = 0; i < _selectedPhotos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _mediaPreviewCard(
                        context,
                        file: _selectedPhotos[i],
                        isVideo: false,
                        badge: '${i + 1}/${_selectedPhotos.length}',
                        onRemove: () =>
                            setState(() => _selectedPhotos.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _textController,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: context.textPrimary,
            ),
            maxLines: 3,
            decoration: InputDecoration(
              isDense: true,
              hintText:
                  "Add a caption, status update, or #hashtags...",
              hintStyle: GoogleFonts.inter(
                fontSize: 12.5,
                color: context.textMuted,
              ),
              suffixIcon: OneovaVoiceTypingButton(
                controller: _textController,
                tooltip: 'Dictate status',
                idleColor: context.textSecondary,
                activeColor: AppColors.brandPink,
              ),
              filled: true,
              fillColor: context.surfaceMid,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: context.border, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: context.border, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: AppColors.brandWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              onPressed: _isPublishing ? null : _publishStory,
              child: _isPublishing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: AnimatedLoadingIndicator(
                        size: 18,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _selectedPhotos.length > 1
                          ? 'Publish ${_selectedPhotos.length} Status Photos'
                          : 'Publish Status',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color accent,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: context.isDark ? 0.22 : 0.12)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: active ? accent : context.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? accent : context.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? accent : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaPreviewCard(
    BuildContext context, {
    required File file,
    required bool isVideo,
    required String badge,
    required VoidCallback onRemove,
  }) {
    return Container(
      height: 104,
      width: 82,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        color: context.surfaceMid,
        border: Border.all(color: context.border, width: 1),
        image: isVideo
            ? null
            : DecorationImage(
                image: FileImage(file),
                fit: BoxFit.cover,
              ),
      ),
      child: Stack(
        children: [
          if (isVideo)
            const Center(
              child: Icon(
                Icons.videocam_rounded,
                color: AppColors.brandBlue,
                size: 28,
              ),
            ),
          Positioned(
            left: 5,
            bottom: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Text(
                badge,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

