import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart' as system_picker;
import 'package:video_player/video_player.dart';

import '../../create/widgets/oneova_clip_trimmer_sheet.dart';
import '../theme/app_theme.dart';

/// Oneova Custom File Picker Modes
enum OneovaFilePickerMode {
  all,
  photos,
  videos,
  audio,
  documents,
}

/// Metadata item for picked file
class OneovaMediaItem {
  final File file;
  final String name;
  final String extension;
  final int sizeBytes;
  final DateTime modified;
  final OneovaFilePickerMode category;
  final Duration? duration;

  const OneovaMediaItem({
    required this.file,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.modified,
    required this.category,
    this.duration,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// High-Density Executive Custom File Picker for Oneova
/// Strictly styled with stark White/Dark surfaces, AppColors.brandBlue (#0C4FA8)
/// and AppColors.brandPink (#FF2D87) secondary accents.
class OneovaFilePicker extends StatefulWidget {
  final OneovaFilePickerMode mode;
  final bool allowMultiple;
  final List<String>? allowedExtensions;
  final String title;
  final bool enableClipTrimmer;
  final String actionLabel;

  const OneovaFilePicker({
    super.key,
    this.mode = OneovaFilePickerMode.all,
    this.allowMultiple = false,
    this.allowedExtensions,
    this.title = 'Select Media & Files',
    this.enableClipTrimmer = false,
    this.actionLabel = 'Import to Timeline',
  });

  /// Launch modal sheet and return selected files
  static Future<List<File>> pickFiles(
    BuildContext context, {
    OneovaFilePickerMode mode = OneovaFilePickerMode.all,
    bool allowMultiple = true,
    List<String>? allowedExtensions,
    String title = 'Select Files',
  }) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<List<File>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OneovaFilePicker(
        mode: mode,
        allowMultiple: allowMultiple,
        allowedExtensions: allowedExtensions,
        title: title,
      ),
    );
    return result ?? [];
  }

  /// Launch modal sheet and return a single file
  static Future<File?> pickSingleFile(
    BuildContext context, {
    OneovaFilePickerMode mode = OneovaFilePickerMode.all,
    List<String>? allowedExtensions,
    String title = 'Select Media',
    bool enableClipTrimmer = false,
    String actionLabel = 'Import to Timeline',
  }) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OneovaFilePicker(
        mode: mode,
        allowMultiple: false,
        allowedExtensions: allowedExtensions,
        title: title,
        enableClipTrimmer: enableClipTrimmer,
        actionLabel: actionLabel,
      ),
    );
    if (result is List<File> && result.isNotEmpty) return result.first;
    if (result is OneovaTrimmedMediaResult) return result.file;
    if (result is File) return result;
    return null;
  }

  /// Launch modal sheet and return a trimmed video clip result, allowing the creator to
  /// decide in/out points, trim length, aspect ratio, and speed before importing.
  static Future<OneovaTrimmedMediaResult?> pickSingleClip(
    BuildContext context, {
    OneovaFilePickerMode mode = OneovaFilePickerMode.videos,
    List<String>? allowedExtensions,
    String title = 'Select & Trim Clip',
    String actionLabel = 'Import to Timeline',
  }) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OneovaFilePicker(
        mode: mode,
        allowMultiple: false,
        allowedExtensions: allowedExtensions,
        title: title,
        enableClipTrimmer: true,
        actionLabel: actionLabel,
      ),
    );
    if (result is OneovaTrimmedMediaResult) {
      return result;
    }
    if (result is List<File> && result.isNotEmpty) {
      return OneovaTrimmedMediaResult(
        file: result.first,
        isVideo: true,
        isFullClip: true,
      );
    }
    if (result is File) {
      return OneovaTrimmedMediaResult(
        file: result,
        isVideo: true,
        isFullClip: true,
      );
    }
    return null;
  }

  @override
  State<OneovaFilePicker> createState() => _OneovaFilePickerState();
}

class _OneovaFilePickerState extends State<OneovaFilePicker> {
  late OneovaFilePickerMode _currentTab;
  final List<OneovaMediaItem> _allItems = [];
  final Set<String> _selectedPaths = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.mode;
    _loadDeviceMedia();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDeviceMedia() async {
    setState(() => _isLoading = true);
    final items = <OneovaMediaItem>[];
    final Set<String> seenPaths = {};

    // Standard Android/Mobile Media Directories
    final List<String> candidatePaths = [
      '/storage/emulated/0/DCIM/Camera',
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Documents',
    ];

    try {
      final appDocs = await getApplicationDocumentsDirectory();
      candidatePaths.add(appDocs.path);
      candidatePaths.add('${appDocs.path}/oneova_media');
      candidatePaths.add('${appDocs.path}/oneova_drafts');
      candidatePaths.add('${appDocs.path}/oneova_exports');
      final appCache = await getTemporaryDirectory();
      candidatePaths.add(appCache.path);
      try {
        final extStorage = await getExternalStorageDirectory();
        if (extStorage != null) {
          candidatePaths.add(extStorage.path);
          candidatePaths.add('${extStorage.path}/Movies');
          candidatePaths.add('${extStorage.path}/DCIM');
        }
      } catch (_) {}
    } catch (_) {}

    for (final path in candidatePaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          final entities = dir.listSync(recursive: false, followLinks: false);
          for (final entity in entities) {
            if (entity is File && !seenPaths.contains(entity.path)) {
              final ext = entity.path.split('.').last.toLowerCase();
              final category = _categorizeExtension(ext);
              if (category != null) {
                try {
                  final stat = entity.statSync();
                  seenPaths.add(entity.path);
                  items.add(
                    OneovaMediaItem(
                      file: entity,
                      name: entity.uri.pathSegments.isNotEmpty
                          ? entity.uri.pathSegments.last
                          : entity.path.split('/').last,
                      extension: ext,
                      sizeBytes: stat.size,
                      modified: stat.modified,
                      category: category,
                    ),
                  );
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    }

    // Sort newest first
    items.sort((a, b) => b.modified.compareTo(a.modified));

    if (mounted) {
      setState(() {
        _allItems.clear();
        _allItems.addAll(items);
        _isLoading = false;
      });
    }
  }

  OneovaFilePickerMode? _categorizeExtension(String ext) {
    const photoExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'bmp'};
    const videoExts = {'mp4', 'mov', 'm4v', '3gp', 'mkv', 'webm', 'avi'};
    const audioExts = {'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'};
    const docExts = {'pdf', 'txt', 'doc', 'docx', 'csv', 'json', 'zip'};

    if (photoExts.contains(ext)) return OneovaFilePickerMode.photos;
    if (videoExts.contains(ext)) return OneovaFilePickerMode.videos;
    if (audioExts.contains(ext)) return OneovaFilePickerMode.audio;
    if (docExts.contains(ext)) return OneovaFilePickerMode.documents;
    return null;
  }

  Future<void> _importFromSystem() async {
    HapticFeedback.lightImpact();
    try {
      system_picker.FileType sysType;
      switch (_currentTab) {
        case OneovaFilePickerMode.photos:
          sysType = system_picker.FileType.image;
          break;
        case OneovaFilePickerMode.videos:
          sysType = system_picker.FileType.video;
          break;
        case OneovaFilePickerMode.audio:
          sysType = system_picker.FileType.audio;
          break;
        case OneovaFilePickerMode.documents:
        case OneovaFilePickerMode.all:
          sysType = system_picker.FileType.any;
          break;
      }

      final List<system_picker.PlatformFile> result;
      if (widget.allowMultiple) {
        result = await system_picker.FilePicker.pickFiles(type: sysType);
      } else {
        final single = await system_picker.FilePicker.pickFile(type: sysType);
        result = single != null ? [single] : [];
      }

      if (result.isNotEmpty) {
        final List<File> imported = [];
        for (final platformFile in result) {
          if (platformFile.path != null) {
            final file = File(platformFile.path!);
            imported.add(file);
            final ext = file.path.split('.').last.toLowerCase();
            final cat = _categorizeExtension(ext) ?? OneovaFilePickerMode.documents;
            int fileBytes = 0;
            try {
              fileBytes = file.lengthSync();
            } catch (_) {}
            final item = OneovaMediaItem(
              file: file,
              name: platformFile.name,
              extension: ext,
              sizeBytes: fileBytes,
              modified: DateTime.now(),
              category: cat,
            );
            if (!_allItems.any((x) => x.file.path == file.path)) {
              _allItems.insert(0, item);
            }
            _selectedPaths.add(file.path);
          }
        }

        if (!widget.allowMultiple && imported.isNotEmpty && mounted) {
          final file = imported.first;
          final ext = file.path.split('.').last.toLowerCase();
          final isVideo = _categorizeExtension(ext) == OneovaFilePickerMode.videos;
          if (isVideo && widget.enableClipTrimmer) {
            final trimmed = await OneovaClipTrimmerSheet.show(
              context,
              videoFile: file,
              clipTitle: file.path.split('/').last,
              actionLabel: widget.actionLabel,
            );
            if (trimmed != null && mounted) {
              Navigator.of(context).pop(trimmed);
              return;
            }
          }
          if (mounted) {
            Navigator.of(context).pop([file]);
          }
          return;
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('[OneovaFilePicker] System import notice: $e');
    }
  }

  Future<void> _openTrimmerForVideo(OneovaMediaItem item) async {
    HapticFeedback.lightImpact();
    if (!mounted) return;
    final trimmed = await OneovaClipTrimmerSheet.show(
      context,
      videoFile: item.file,
      clipTitle: item.name,
      actionLabel: widget.actionLabel,
    );
    if (trimmed != null && mounted) {
      if (widget.enableClipTrimmer) {
        Navigator.of(context).pop(trimmed);
      } else {
        Navigator.of(context).pop([trimmed.file]);
      }
    }
  }

  void _toggleSelect(OneovaMediaItem item) async {
    HapticFeedback.selectionClick();
    setState(() {
      if (widget.allowMultiple) {
        if (_selectedPaths.contains(item.file.path)) {
          _selectedPaths.remove(item.file.path);
        } else {
          _selectedPaths.add(item.file.path);
        }
      } else {
        _selectedPaths.clear();
        _selectedPaths.add(item.file.path);
      }
    });

    if (!widget.allowMultiple) {
      if (widget.enableClipTrimmer && item.category == OneovaFilePickerMode.videos) {
        await _openTrimmerForVideo(item);
        return;
      }
      Navigator.of(context).pop([item.file]);
    }
  }

  void _confirmSelection() {
    HapticFeedback.mediumImpact();
    final selectedFiles = _allItems
        .where((item) => _selectedPaths.contains(item.file.path))
        .map((item) => item.file)
        .toList();
    Navigator.of(context).pop(selectedFiles);
  }

  List<OneovaMediaItem> get _filteredItems {
    return _allItems.where((item) {
      if (_currentTab != OneovaFilePickerMode.all && item.category != _currentTab) {
        return false;
      }
      if (widget.allowedExtensions != null &&
          !widget.allowedExtensions!.contains(item.extension.toLowerCase())) {
        return false;
      }
      if (_searchQuery.isNotEmpty && !item.name.toLowerCase().contains(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF141414) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF262626) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF3F4F6) : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF475569);

    final filtered = _filteredItems;
    final selectedCount = _selectedPaths.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 22),
                  color: textPrimary,
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.inter(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandPink.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'STUDIO',
                              style: GoogleFonts.inter(
                                color: AppColors.brandPink,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Browse local media or import device files',
                        style: GoogleFonts.inter(
                          color: textSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // System Import Button
                OutlinedButton.icon(
                  onPressed: _importFromSystem,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.file_open_outlined, size: 16, color: AppColors.brandBlue),
                  label: Text(
                    'Browse',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.inter(fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search files by name...',
                  hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          color: textSecondary,
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Filter Category Tabs
          _buildCategoryTabs(isDark, borderColor, textPrimary, textSecondary),

          const SizedBox(height: 8),

          // Media Content Grid / List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                      strokeWidth: 2.5,
                    ),
                  )
                : (filtered.isEmpty
                    ? _buildEmptyState(textPrimary, textSecondary)
                    : (_currentTab == OneovaFilePickerMode.audio ||
                            _currentTab == OneovaFilePickerMode.documents
                        ? _buildListView(filtered, isDark, borderColor, textPrimary, textSecondary)
                        : _buildGridView(filtered, isDark, borderColor, textPrimary))),
          ),

          // Bottom Action Bar (if allowMultiple or items selected)
          if (widget.allowMultiple && selectedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(top: BorderSide(color: borderColor, width: 1.0)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _selectedPaths.clear()),
                      child: Text(
                        'Clear ($selectedCount)',
                        style: GoogleFonts.inter(
                          color: textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: _confirmSelection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Attach ($selectedCount)',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs(
    bool isDark,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    final tabs = [
      {'mode': OneovaFilePickerMode.all, 'label': 'All'},
      {'mode': OneovaFilePickerMode.photos, 'label': 'Photos'},
      {'mode': OneovaFilePickerMode.videos, 'label': 'Videos'},
      {'mode': OneovaFilePickerMode.audio, 'label': 'Audio'},
      {'mode': OneovaFilePickerMode.documents, 'label': 'Files'},
    ];

    return SizedBox(
      height: 32,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tabMode = tabs[index]['mode'] as OneovaFilePickerMode;
          final label = tabs[index]['label'] as String;
          final isSelected = _currentTab == tabMode;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _currentTab = tabMode);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.brandBlue
                    : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : borderColor,
                  width: 1.0,
                ),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridView(
    List<OneovaMediaItem> items,
    bool isDark,
    Color borderColor,
    Color textPrimary,
  ) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedPaths.contains(item.file.path);
        final isVideo = item.category == OneovaFilePickerMode.videos;

        return GestureDetector(
          onTap: () => _toggleSelect(item),
          onLongPress: () => _showMediaPreview(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppColors.brandPink : borderColor,
                width: isSelected ? 2.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.brandPink.withValues(alpha: 0.35),
                        blurRadius: 8,
                      )
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isSelected ? 7.5 : 9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image Thumbnail or Video Backdrop
                  if (!isVideo)
                    Image.file(
                      item.file,
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      errorBuilder: (ctx, err, stack) => Container(
                        color: context.surfaceMid,
                        child: Icon(Icons.broken_image_rounded, size: 28, color: context.textMuted),
                      ),
                    )
                  else
                    Container(
                      color: context.surfaceMid,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.brandBlue.withValues(alpha: 0.25),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: AppColors.brandBlue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.extension.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Top Left Quick Trim Action Badge (for video clips)
                  if (isVideo)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: GestureDetector(
                        onTap: () => _openTrimmerForVideo(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.content_cut_rounded, size: 11, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                'Trim',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Top Right Selection Check Badge
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? AppColors.brandPink
                            : Colors.black.withValues(alpha: 0.45),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white70,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Center(
                              child: Icon(Icons.check, size: 14, color: Colors.white),
                            )
                          : null,
                    ),
                  ),

                  // Bottom Info Strip
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isVideo)
                            const Icon(Icons.videocam_rounded, size: 12, color: Colors.white)
                          else
                            const Icon(Icons.photo_rounded, size: 12, color: Colors.white70),
                          Text(
                            item.formattedSize,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildListView(
    List<OneovaMediaItem> items,
    bool isDark,
    Color borderColor,
    Color textPrimary,
    Color textSecondary,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedPaths.contains(item.file.path);
        final isAudio = item.category == OneovaFilePickerMode.audio;

        return GestureDetector(
          onTap: () => _toggleSelect(item),
          onLongPress: () => _showMediaPreview(item),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.brandBlue.withValues(alpha: isDark ? 0.18 : 0.08)
                  : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.brandBlue : borderColor,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Icon Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isAudio ? AppColors.brandPink : AppColors.brandBlue)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isAudio ? Icons.audiotrack_rounded : Icons.description_rounded,
                    color: isAudio ? AppColors.brandPink : AppColors.brandBlue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // File Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: borderColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.extension.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                                color: textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.formattedSize,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Selection indicator
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.brandBlue : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppColors.brandBlue : borderColor,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(Icons.check, size: 14, color: Colors.white),
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(Color textPrimary, Color textSecondary) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandBlue.withValues(alpha: 0.1),
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              color: AppColors.brandBlue,
              size: 36,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No files found',
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Browse" at top to pick any file from system storage',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showMediaPreview(OneovaMediaItem item) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: ctx.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ctx.border, width: 1.0),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: ctx.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: ctx.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (item.category == OneovaFilePickerMode.photos)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: Image.file(item.file, fit: BoxFit.contain),
                  )
                else if (item.category == OneovaFilePickerMode.videos)
                  _VideoPreviewWidget(file: item.file)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        Icon(
                          item.category == OneovaFilePickerMode.audio
                              ? Icons.audiotrack_rounded
                              : Icons.description_rounded,
                          size: 56,
                          color: AppColors.brandPink,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Size: ${item.formattedSize}',
                          style: GoogleFonts.inter(color: ctx.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (item.category == OneovaFilePickerMode.videos) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _openTrimmerForVideo(item);
                      },
                      icon: const Icon(Icons.content_cut_rounded, size: 16, color: Colors.white),
                      label: Text(
                        'Trim & Ingest Video Clip',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _toggleSelect(item);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    child: Text(
                      _selectedPaths.contains(item.file.path) ? 'Deselect File' : 'Select File',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPreviewWidget extends StatefulWidget {
  final File file;
  const _VideoPreviewWidget({required this.file});

  @override
  State<_VideoPreviewWidget> createState() => _VideoPreviewWidgetState();
}

class _VideoPreviewWidgetState extends State<_VideoPreviewWidget> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller?.play();
        _controller?.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(_controller!),
          GestureDetector(
            onTap: () {
              setState(() {
                _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
              });
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
