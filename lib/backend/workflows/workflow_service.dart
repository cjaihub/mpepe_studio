import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/workflow_config.dart';
import 'models/workflow_execution.dart';

final workflowServiceProvider = Provider<WorkflowService>((ref) {
  return WorkflowService(FirebaseFirestore.instance);
});

final workflowsStreamProvider = StreamProvider<List<WorkflowConfig>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const Stream.empty();

  final service = ref.watch(workflowServiceProvider);
  return service.getWorkflowsStream(user.uid);
});

final workflowExecutionsStreamProvider = StreamProvider.family<List<WorkflowExecution>, String>((ref, workflowId) {
  final service = ref.watch(workflowServiceProvider);
  return service.getWorkflowExecutionsStream(workflowId);
});

class WorkflowService {
  final FirebaseFirestore _firestore;

  WorkflowService(this._firestore);

  Stream<List<WorkflowConfig>> getWorkflowsStream(String userId) {
    return _firestore
        .collection('workflows')
        .where('ownerId', isEqualTo: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WorkflowConfig.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<WorkflowExecution>> getWorkflowExecutionsStream(String workflowId) {
    return _firestore
        .collection('workflow_executions')
        .where('workflowId', isEqualTo: workflowId)
        .orderBy('startedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => WorkflowExecution.fromMap(doc.id, doc.data()))
            .toList());
  }

  Future<void> createWorkflow(WorkflowConfig workflow) async {
    await _firestore.collection('workflows').add(workflow.toMap());
  }

  Future<void> updateWorkflow(WorkflowConfig workflow) async {
    await _firestore
        .collection('workflows')
        .doc(workflow.id)
        .update(workflow.toMap());
  }

  Future<void> deleteWorkflow(String workflowId) async {
    await _firestore.collection('workflows').doc(workflowId).delete();
  }
  
  Future<void> toggleWorkflowEnabled(String workflowId, bool isEnabled) async {
    await _firestore.collection('workflows').doc(workflowId).update({
      'enabled': isEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
