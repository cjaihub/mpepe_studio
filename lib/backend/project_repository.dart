import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'projects/models/pro_project_models.dart';

class StudioProject {
  final String id;
  final String category; // 'Video' or 'Audio'
  final String title;
  final String status; // Scripting, Filming, Editing, Review, Delivered (Video) or Recording, Mixing, Mastering (Audio)
  final int completedSteps;
  final int totalSteps;
  final List<String> characters;
  final List<String> props;
  final List<String> storyboardUrls;
  final String? script;
  final List<String> toolsUsed;
  final String? ownerId;
  final List<String>? memberIds;
  final String? canonicalGroupId;
  final List<Sequence> sequences;
  final String? activeSequenceId;
  final ProjectSettings settings;
  final DateTime createdAt;

  StudioProject({
    required this.id,
    required this.category,
    required this.title,
    required this.status,
    required this.completedSteps,
    this.totalSteps = 5,
    this.characters = const [],
    this.props = const [],
    this.storyboardUrls = const [],
    this.script,
    this.toolsUsed = const [],
    this.ownerId,
    this.memberIds,
    this.canonicalGroupId,
    this.sequences = const [],
    this.activeSequenceId,
    this.settings = const ProjectSettings(width: 1080, height: 1920, frameRate: 30.0),
    required this.createdAt,
  });

  StudioProject copyWith({
    String? id,
    String? category,
    String? title,
    String? status,
    int? completedSteps,
    int? totalSteps,
    List<String>? characters,
    List<String>? props,
    List<String>? storyboardUrls,
    String? script,
    List<String>? toolsUsed,
    List<Sequence>? sequences,
    String? activeSequenceId,
    ProjectSettings? settings,
    DateTime? createdAt,
  }) {
    return StudioProject(
      id: id ?? this.id,
      category: category ?? this.category,
      title: title ?? this.title,
      status: status ?? this.status,
      completedSteps: completedSteps ?? this.completedSteps,
      totalSteps: totalSteps ?? this.totalSteps,
      characters: characters ?? this.characters,
      props: props ?? this.props,
      storyboardUrls: storyboardUrls ?? this.storyboardUrls,
      script: script ?? this.script,
      toolsUsed: toolsUsed ?? this.toolsUsed,
      sequences: sequences ?? this.sequences,
      activeSequenceId: activeSequenceId ?? this.activeSequenceId,
      settings: settings ?? this.settings,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory StudioProject.fromJson(Map<String, dynamic> json, String id) {
    return StudioProject(
      id: id,
      category: json['category'] ?? 'Video',
      title: json['title'] ?? '',
      status: json['status'] ?? 'Draft',
      completedSteps: json['completedSteps'] ?? 0,
      totalSteps: json['totalSteps'] ?? 5,
      characters: List<String>.from(json['characters'] ?? []),
      props: List<String>.from(json['props'] ?? []),
      storyboardUrls: List<String>.from(json['storyboardUrls'] ?? []),
      script: json['script'],
      toolsUsed: List<String>.from(json['toolsUsed'] ?? []),
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'title': title,
      'status': status,
      'completedSteps': completedSteps,
      'totalSteps': totalSteps,
      'characters': characters,
      'props': props,
      'storyboardUrls': storyboardUrls,
      'script': script,
      'toolsUsed': toolsUsed,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

class ProjectRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<StudioProject>> watchProjects() {
    return _firestore
        .collection('studio_projects')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StudioProject.fromJson(doc.data(), doc.id))
            .toList());
  }

  Future<String> addProject(StudioProject project) async {
    try {
      if (project.id.isEmpty) {
        final docRef = await _firestore.collection('studio_projects').add(project.toJson());
        return docRef.id;
      } else {
        await _firestore.collection('studio_projects').doc(project.id).set(project.toJson());
        return project.id;
      }
    } catch (e) {
      debugPrint('Error adding project: $e');
      rethrow;
    }
  }
  
  Future<void> updateProject(dynamic project) async {
    await _firestore.collection('studio_projects').doc(project.id).update(project.toJson());
  }

  Future<dynamic> getProject(String id) async {
    final doc = await _firestore.collection('studio_projects').doc(id).get();
    if (doc.exists && doc.data() != null) {
      return StudioProject.fromJson(doc.data()!, doc.id);
    }
    return null;
  }

  Future<void> deleteProject(String id) async {
    await _firestore.collection('studio_projects').doc(id).delete();
  }
}

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

final projectsStreamProvider = StreamProvider<List<StudioProject>>((ref) {
  return ref.watch(projectRepositoryProvider).watchProjects();
});
