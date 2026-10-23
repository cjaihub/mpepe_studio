import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/youtube/v3.dart' as youtube;
import 'youtube_auth_service.dart';
import 'package:file_picker/file_picker.dart';

class UploadTask {
  final String id;
  final File file;
  final String title;
  final String description;
  final List<String> tags;
  final String privacyStatus;
  
  double progress;
  String status; // 'pending', 'uploading', 'completed', 'failed'
  String? error;

  UploadTask({
    required this.id,
    required this.file,
    required this.title,
    this.description = '',
    this.tags = const [],
    this.privacyStatus = 'private',
    this.progress = 0.0,
    this.status = 'pending',
  });
}

class BulkUploadEngine extends Notifier<List<UploadTask>> {
  @override
  List<UploadTask> build() {
    return [];
  }

  void addFiles(List<PlatformFile> files) {
    final newTasks = files.map((file) {
      return UploadTask(
        id: '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
        file: File(file.path!),
        title: file.name.replaceAll('.mp4', '').replaceAll('.mov', ''),
      );
    }).toList();
    
    state = [...state, ...newTasks];
  }

  void removeTask(String id) {
    state = state.where((task) => task.id != id).toList();
  }

  void updateTaskMetadata(String id, {String? title, String? description, List<String>? tags}) {
    state = state.map((task) {
      if (task.id == id) {
        return UploadTask(
          id: task.id,
          file: task.file,
          title: title ?? task.title,
          description: description ?? task.description,
          tags: tags ?? task.tags,
          privacyStatus: task.privacyStatus,
          progress: task.progress,
          status: task.status,
        )..error = task.error;
      }
      return task;
    }).toList();
  }

  Future<void> startUpload(String taskId) async {
    final taskIndex = state.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    
    var task = state[taskIndex];
    if (task.status == 'uploading' || task.status == 'completed') return;

    _updateTaskStatus(taskId, 'uploading', 0.0);

    final client = await ref.read(youtubeAuthProvider.notifier).getAuthClient();
    if (client == null) {
      _updateTaskStatus(taskId, 'failed', 0.0, error: 'Not authenticated');
      return;
    }

    final youtubeApi = youtube.YouTubeApi(client);
    final video = youtube.Video();
    video.snippet = youtube.VideoSnippet()
      ..title = task.title
      ..description = task.description
      ..tags = task.tags;
      
    video.status = youtube.VideoStatus()
      ..privacyStatus = task.privacyStatus;

    try {
      final fileLength = await task.file.length();
      final media = youtube.Media(task.file.openRead(), fileLength);
      
      final request = youtubeApi.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );

      await request;
      
      _updateTaskStatus(taskId, 'completed', 1.0);
    } catch (e) {
      _updateTaskStatus(taskId, 'failed', 0.0, error: e.toString());
    }
  }

  void startAllPending() {
    for (var task in state) {
      if (task.status == 'pending') {
        startUpload(task.id);
      }
    }
  }

  void _updateTaskStatus(String id, String status, double progress, {String? error}) {
    state = state.map((task) {
      if (task.id == id) {
        task.status = status;
        task.progress = progress;
        task.error = error;
      }
      return task;
    }).toList();
  }
}

final bulkUploadEngineProvider = NotifierProvider<BulkUploadEngine, List<UploadTask>>(() {
  return BulkUploadEngine();
});
