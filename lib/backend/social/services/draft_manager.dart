import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class VideoDraft {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<String> clipPaths;
  final List<String> audioPaths;
  final Map<String, dynamic> metadata;

  VideoDraft({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.clipPaths = const [],
    this.audioPaths = const [],
    this.metadata = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'updatedAt': updatedAt.toIso8601String(),
      'clipPaths': clipPaths,
      'audioPaths': audioPaths,
      'metadata': metadata,
    };
  }

  factory VideoDraft.fromMap(Map<String, dynamic> map) {
    return VideoDraft(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Untitled Draft',
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : DateTime.now(),
      clipPaths: List<String>.from(map['clipPaths'] ?? []),
      audioPaths: List<String>.from(map['audioPaths'] ?? []),
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
    );
  }
  VideoDraft copyWith({
    String? id,
    String? title,
    DateTime? updatedAt,
    List<String>? clipPaths,
    List<String>? audioPaths,
    Map<String, dynamic>? metadata,
  }) {
    return VideoDraft(
      id: id ?? this.id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      clipPaths: clipPaths ?? List.from(this.clipPaths),
      audioPaths: audioPaths ?? List.from(this.audioPaths),
      metadata: metadata ?? Map.from(this.metadata),
    );
  }
}

final draftManagerProvider = NotifierProvider<DraftManager, List<VideoDraft>>(() {
  return DraftManager();
});

class DraftManager extends Notifier<List<VideoDraft>> {
  @override
  List<VideoDraft> build() {
    _loadDrafts();
    return [];
  }

  File? _draftFile;

  Future<void> _loadDrafts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _draftFile = File('${dir.path}/video_drafts.json');
      if (await _draftFile!.exists()) {
        final content = await _draftFile!.readAsString();
        final List<dynamic> data = jsonDecode(content);
        state = data.map((e) => VideoDraft.fromMap(e)).toList();
      }
    } catch (e) {
      // Failed to load
    }
  }

  Future<void> saveDraft(VideoDraft draft) async {
    final index = state.indexWhere((d) => d.id == draft.id);
    if (index >= 0) {
      state = [...state]
        ..removeAt(index)
        ..insert(index, draft);
    } else {
      state = [...state, draft];
    }
    await _persistDrafts();
  }

  Future<void> deleteDraft(String id) async {
    state = state.where((d) => d.id != id).toList();
    await _persistDrafts();
  }

  Future<void> duplicateDraft(String id) async {
    final draft = state.firstWhere((d) => d.id == id);
    final duplicated = draft.copyWith(
      id: const Uuid().v4(),
      title: '${draft.title} (Copy)',
      updatedAt: DateTime.now(),
    );
    state = [...state, duplicated];
    await _persistDrafts();
  }

  Future<void> _persistDrafts() async {
    if (_draftFile == null) return;
    try {
      final data = state.map((d) => d.toMap()).toList();
      await _draftFile!.writeAsString(jsonEncode(data));
    } catch (e) {
      // Failed to save
    }
  }

  VideoDraft createNewDraft() {
    return VideoDraft(
      id: const Uuid().v4(),
      title: 'New Project',
      updatedAt: DateTime.now(),
      metadata: {
        'ai_processing_enabled': true,
        'ai_generated': false,
        'ai_assisted': false,
        'ai_edited': false,
      },
    );
  }
}
