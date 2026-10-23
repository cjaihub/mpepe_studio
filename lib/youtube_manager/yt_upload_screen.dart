import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/utils/friendly_error_parser.dart';
import 'services/bulk_upload_engine.dart';
import '../backend/ai_brain_service.dart';

class YtUploadScreen extends ConsumerStatefulWidget {
  const YtUploadScreen({super.key});

  @override
  ConsumerState<YtUploadScreen> createState() => _YtUploadScreenState();
}

class _YtUploadScreenState extends ConsumerState<YtUploadScreen> {
  Future<void> _pickFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.video,
    );

    if (result.isNotEmpty) {
      ref.read(bulkUploadEngineProvider.notifier).addFiles(result);
    }
  }

  Future<void> _generateAiMetadata(UploadTask task) async {
    final topicController = TextEditingController(text: task.title);
    
    final topic = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purple),
            SizedBox(width: 8),
            Text('AI Metadata Generator'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What is this video about?'),
            const SizedBox(height: 12),
            TextField(
              controller: topicController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. A cinematic vlog in Tokyo...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, topicController.text),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (topic != null && topic.isNotEmpty) {
      if (!mounted) return;
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      
      try {
        final aiBrain = ref.read(aiBrainProvider);
        final metadata = await aiBrain.generateYouTubeMetadata(topic);
        
        if (mounted) Navigator.pop(context); // Close loading dialog
        
        if (metadata != null) {
          ref.read(bulkUploadEngineProvider.notifier).updateTaskMetadata(
            task.id,
            title: metadata['title'],
            description: metadata['description'],
            tags: List<String>.from(metadata['tags'] ?? []),
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Metadata generated successfully!')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to generate metadata. Please try again.')),
            );
          }
        }
      } catch (e) {
        if (mounted) Navigator.pop(context); // Close loading dialog
        debugPrint('Error generating metadata: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploadTasks = ref.watch(bulkUploadEngineProvider);

    return StudioBackground(
      backgroundIcons: const [Icons.cloud_upload_outlined, Icons.movie_creation_outlined, Icons.auto_awesome_outlined],
      appBar: AppBar(
        title: Text('Bulk Upload', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (uploadTasks.isEmpty) ...[
              _buildUploadZone().animate().fadeIn(duration: 400.ms).slideY(begin: 0.1),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Upload Queue (${uploadTasks.length})', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Files'),
                  ),
                ],
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: 16),
              
              ...uploadTasks.map((task) => _buildTaskCard(task)),
              
              const SizedBox(height: 40),
              
              ElevatedButton(
                onPressed: () {
                  ref.read(bulkUploadEngineProvider.notifier).startAllPending();
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 5,
                  shadowColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Start All Pending Uploads', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              ).animate().fadeIn(delay: 500.ms).scaleXY(begin: 0.9),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadZone() {
    return GestureDetector(
      onTap: _pickFiles,
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), width: 2, style: BorderStyle.solid),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              blurRadius: 40,
              spreadRadius: 10,
            )
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_upload_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).moveY(begin: -5, end: 5, duration: 2.seconds),
            const SizedBox(height: 24),
            Text('Tap to select videos', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('MP4, MOV, or AVI up to 256GB', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(UploadTask task) {
    IconData statusIcon = Icons.pending_actions;
    Color statusColor = Colors.grey;

    if (task.status == 'uploading') {
      statusIcon = Icons.cloud_upload;
      statusColor = Theme.of(context).colorScheme.primary;
    } else if (task.status == 'completed') {
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
    } else if (task.status == 'failed') {
      statusIcon = Icons.error;
      statusColor = Theme.of(context).colorScheme.error;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon, size: 24, color: statusColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(task.file.lengthSync() / (1024 * 1024)).toStringAsFixed(2)} MB • ${task.status.toUpperCase()}',
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (task.status != 'uploading' && task.status != 'completed') ...[
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.purple),
                  tooltip: 'Generate AI Metadata',
                  onPressed: () => _generateAiMetadata(task),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  onPressed: () {
                    ref.read(bulkUploadEngineProvider.notifier).removeTask(task.id);
                  },
                ),
              ],
            ],
          ),
          if (task.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: task.tags.map((tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('#$tag', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
              )).toList(),
            ),
          ],
          if (task.status == 'uploading') ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: null, // Indeterminate since we are waiting on HTTP response
                minHeight: 8,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (task.error != null) ...[
            const SizedBox(height: 8),
            Text(FriendlyErrorParser.parse(task.error!), style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ]
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }
}

