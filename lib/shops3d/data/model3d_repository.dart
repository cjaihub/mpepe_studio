import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The seller's private 3D model library (`users/{uid}/models3d`).
///
/// Only the owner can read it; every write goes through the model service
/// (functions/src/models3d), which converts, optimizes and hosts the files.
/// A model becomes public only as a copy on a product the owner chooses.

enum ModelStatus {
  queued,
  converting,
  generating,
  optimizing,
  ready,
  failed,

  /// Photos are saved; waiting for Oneova's 3D builder to be switched on.
  needsEngine;

  static ModelStatus parse(Object? v) => switch (v) {
        'needs_engine' => ModelStatus.needsEngine,
        _ => ModelStatus.values.firstWhere((e) => e.name == v, orElse: () => ModelStatus.queued),
      };

  bool get working => this == queued || this == converting || this == generating || this == optimizing;
}

@immutable
class ModelStep {
  const ModelStep(this.at, this.text);
  final DateTime at;
  final String text;
}

@immutable
class Model3DAsset {
  const Model3DAsset({
    required this.id,
    required this.name,
    required this.status,
    this.kind = 'upload',
    this.stage = '',
    this.progress = 0,
    this.steps = const [],
    this.thumbUrl,
    this.mobileUrl,
    this.hdUrl,
    this.arUrl,
    this.mobileBytes = 0,
    this.sourceBytes = 0,
    this.triangles = 0,
    this.mobileTriangles = 0,
    this.materials = const [],
    this.animations = const [],
    this.productId,
    this.error,
    this.engineOwner,
    this.createdAt,
  });

  final String id;
  final String name;
  final ModelStatus status;

  /// 'upload' or 'generate'.
  final String kind;

  /// What the model agent is doing right now, in plain words.
  final String stage;
  final double progress;
  final List<ModelStep> steps;
  final String? thumbUrl;
  final String? mobileUrl;
  final String? hdUrl;
  final String? arUrl;
  final int mobileBytes;
  final int sourceBytes;
  final int triangles;
  final int mobileTriangles;
  final List<String> materials;
  final List<String> animations;
  final String? productId;
  final String? error;

  /// Who built it: 'oneova' (Oneova's own 3D builder). Older models may say 'user'.
  final String? engineOwner;
  final DateTime? createdAt;

  bool get ready => status == ModelStatus.ready && (mobileUrl ?? '').startsWith('https://');

  factory Model3DAsset.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final files = d['files'] is Map ? d['files'] as Map : const {};
    final stats = d['stats'] is Map ? d['stats'] as Map : const {};
    String? url(String k) => files[k] is Map ? (files[k] as Map)['url'] as String? : null;
    final created = d['createdAt'];
    return Model3DAsset(
      id: doc.id,
      name: (d['name'] as String?) ?? 'Model',
      status: ModelStatus.parse(d['status']),
      kind: (d['kind'] as String?) ?? 'upload',
      stage: (d['stage'] as String?) ?? '',
      progress: ((d['progress'] as num?) ?? 0).toDouble().clamp(0, 1),
      steps: [
        for (final s in (d['steps'] as List? ?? const []))
          if (s is Map && s['text'] != null)
            ModelStep(DateTime.fromMillisecondsSinceEpoch((s['at'] as num?)?.toInt() ?? 0), '${s['text']}'),
      ],
      thumbUrl: d['thumbUrl'] as String?,
      mobileUrl: url('mobile'),
      hdUrl: url('hd'),
      arUrl: url('ar'),
      mobileBytes: files['mobile'] is Map ? (((files['mobile'] as Map)['bytes'] as num?) ?? 0).toInt() : 0,
      sourceBytes: ((d['sourceBytes'] as num?) ?? 0).toInt(),
      triangles: ((stats['triangles'] as num?) ?? 0).toInt(),
      mobileTriangles: ((stats['mobileTriangles'] as num?) ?? 0).toInt(),
      materials: List<String>.from((stats['materials'] as List?)?.whereType<String>() ?? const []),
      animations: List<String>.from((stats['animations'] as List?)?.whereType<String>() ?? const []),
      productId: d['productId'] as String?,
      error: d['error'] as String?,
      engineOwner: d['engineOwner'] as String?,
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

/// URLs a product gets when a library model is put on it.
typedef PublishedModel = ({String url, String? hdUrl, String? arUrl, List<String> animations});

class Model3DRepository {
  Model3DRepository({FirebaseFirestore? db, FirebaseStorage? storage, FirebaseAuth? auth, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final FirebaseFunctions _fn;

  static const formats = ['glb', 'gltf', 'obj', 'stl'];
  static const maxSourceBytes = 100 * 1024 * 1024;

  String _uid() {
    final u = _auth.currentUser?.uid;
    if (u == null) throw StateError('Sign in to use your model library.');
    return u;
  }

  CollectionReference<Map<String, dynamic>> _lib(String uid) => _db.collection('users').doc(uid).collection('models3d');

  String newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Stream<List<Model3DAsset>> watchLibrary() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _lib(uid).orderBy('createdAt', descending: true).limit(200).snapshots().map((s) => s.docs.map(Model3DAsset.fromDoc).toList());
  }

  Stream<Model3DAsset?> watchModel(String id) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _lib(uid).doc(id).snapshots().map((d) => d.exists ? Model3DAsset.fromDoc(d) : null);
  }

  /// Uploads a 3D file into the private library and starts optimizing it.
  /// Returns the new model id; progress is then followed with [watchModel].
  Future<String> addFile(File file, {String? name, String? productId, void Function(double)? onProgress}) async {
    final uid = _uid();
    final original = file.path.split(Platform.pathSeparator).last;
    final ext = original.contains('.') ? original.split('.').last.toLowerCase() : '';
    if (!formats.contains(ext)) throw StateError('Use a .glb, .gltf, .obj or .stl file.');
    if (await file.length() > maxSourceBytes) throw StateError('3D files must be under 100 MB.');
    final id = newId();
    final fileName = 'model.$ext';
    final task = _storage.ref('users/$uid/models3d/$id/source/$fileName').putFile(
          file,
          SettableMetadata(contentType: ext == 'glb' ? 'model/gltf-binary' : 'application/octet-stream'),
        );
    if (onProgress != null) {
      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) onProgress(s.bytesTransferred / s.totalBytes);
      }, onError: (_) {});
    }
    await task;
    final base = original.contains('.') ? original.substring(0, original.lastIndexOf('.')) : original;
    await _call('model3dCreate', {'modelId': id, 'fileName': fileName, 'name': name ?? base, 'productId': ?productId});
    return id;
  }

  /// Sends one to four photos (front first) to be built into a 3D model.
  /// Returns the id and whether Oneova's 3D builder started on it now.
  Future<({String id, bool started})> generateFromPhotos(
    List<File> photos, {
    required String name,
    String? productId,
    void Function(double)? onProgress,
  }) async {
    final uid = _uid();
    if (photos.isEmpty || photos.length > 4) throw StateError('Add one to four photos.');
    final id = newId();
    for (var i = 0; i < photos.length; i++) {
      final task = _storage.ref('users/$uid/models3d/$id/photos/$i.jpg').putFile(photos[i], SettableMetadata(contentType: 'image/jpeg'));
      if (onProgress != null) {
        task.snapshotEvents.listen((s) {
          if (s.totalBytes > 0) onProgress((i + s.bytesTransferred / s.totalBytes) / photos.length);
        }, onError: (_) {});
      }
      await task;
    }
    final r = await _call('model3dGenerate', {'modelId': id, 'photoCount': photos.length, 'name': name, 'productId': ?productId});
    return (id: id, started: r['status'] == 'queued');
  }

  Future<void> resume(String id) => _call('model3dResume', {'modelId': id});

  /// Puts a ready model on a product (public copies are made by the server).
  Future<PublishedModel> attach(String modelId, String productId) async {
    final r = await _call('model3dAttach', {'modelId': modelId, 'productId': productId});
    return (
      url: '${r['model3dUrl']}',
      hdUrl: r['model3dHdUrl'] as String?,
      arUrl: r['model3dArUrl'] as String?,
      animations: List<String>.from((r['modelAnimations'] as List?)?.whereType<String>() ?? const []),
    );
  }

  Future<void> delete(String id) => _call('model3dDelete', {'modelId': id});

  /// Whether Oneova's own 3D builder is on (photo → 3D can start now).
  Future<bool> builderAvailable() async {
    final r = await _call('model3dEngineStatus', const {});
    return r['available'] == true;
  }

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _fn.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 120))).call(data);
      return Map<String, dynamic>.from(r.data as Map? ?? const {});
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Something went wrong. Try again.');
    }
  }
}

final model3dRepositoryProvider = Provider<Model3DRepository>((ref) => Model3DRepository());

final modelLibraryProvider = StreamProvider.autoDispose<List<Model3DAsset>>(
  (ref) => ref.watch(model3dRepositoryProvider).watchLibrary(),
);

final model3dProvider = StreamProvider.autoDispose.family<Model3DAsset?, String>(
  (ref, id) => ref.watch(model3dRepositoryProvider).watchModel(id),
);

/// Whether photo → 3D can start now (null while checking or offline).
final model3dBuilderProvider = FutureProvider.autoDispose<bool?>((ref) async {
  try {
    return await ref.watch(model3dRepositoryProvider).builderAvailable();
  } catch (_) {
    return null;
  }
});

String formatBytes(int b) {
  if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(b >= 10 * 1024 * 1024 ? 0 : 1)} MB';
  if (b >= 1024) return '${(b / 1024).round()} KB';
  return '$b B';
}
