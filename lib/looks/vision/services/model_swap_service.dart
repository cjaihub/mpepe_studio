import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/oneova_model_registry.dart';

/// Event emitted when an on-device neural model is swapped or rolled back
class ModelSwapEvent {
  final OneovaModelType type;
  final OneovaModelDescriptor activeModel;
  final OneovaModelDescriptor? previousModel;
  final bool isRollback;
  final DateTime timestamp;

  ModelSwapEvent({
    required this.type,
    required this.activeModel,
    this.previousModel,
    this.isRollback = false,
    required this.timestamp,
  });
}

/// Service managing staged swap-in, hash verification, eval gate checks,
/// and automated rollback for on-device Oneova Vision LiteRT models.
class OneovaModelSwapService {
  final Map<OneovaModelType, OneovaModelDescriptor> _activeModels = {};
  final Map<OneovaModelType, OneovaModelDescriptor> _stagedCandidates = {};
  final Map<OneovaModelType, OneovaModelDescriptor> _rollbackSnapshots = {};
  
  final StreamController<ModelSwapEvent> _swapEventController =
      StreamController<ModelSwapEvent>.broadcast();

  OneovaModelSwapService() {
    // Seed default active models from the registry
    for (final model in OneovaModelRegistry.defaultModels) {
      if (model.isActive) {
        _activeModels[model.type] = model;
      }
    }
  }

  Stream<ModelSwapEvent> get onSwapEvents => _swapEventController.stream;

  OneovaModelDescriptor? getActiveModel(OneovaModelType type) => _activeModels[type];
  OneovaModelDescriptor? getStagedCandidate(OneovaModelType type) => _stagedCandidates[type];
  OneovaModelDescriptor? getRollbackSnapshot(OneovaModelType type) => _rollbackSnapshots[type];

  /// Verifies SHA-256 integrity of downloaded model bytes against descriptor checksum
  bool verifyIntegrity(OneovaModelDescriptor descriptor, List<int> bytes) {
    if (bytes.isEmpty) return false;
    final digest = sha256.convert(bytes);
    final calculatedHash = digest.toString().toLowerCase();
    final expectedHash = descriptor.sha256Checksum.toLowerCase();
    return calculatedHash == expectedHash;
  }

  /// Stages a candidate model for evaluation and staged rollout
  void stageCandidate(OneovaModelDescriptor candidate) {
    _stagedCandidates[candidate.type] = candidate.copyWith(isStaged: true);
  }

  /// Evaluates whether candidate model passes all quantitative quality and latency gates
  bool evaluateCandidate(OneovaModelType type) {
    final candidate = _stagedCandidates[type];
    if (candidate == null) return false;
    return candidate.passesAllEvalGates;
  }

  /// Atomically activates a staged model, archiving current model for rollback safety
  bool swapInStagedModel(OneovaModelType type) {
    final candidate = _stagedCandidates[type];
    if (candidate == null) return false;

    // Strict evaluation gate check
    if (!candidate.passesAllEvalGates) {
      debugPrint('[OneovaModelSwapService] Rejecting model ${candidate.id}: failed eval gates.');
      return false;
    }

    final current = _activeModels[type];
    if (current != null) {
      _rollbackSnapshots[type] = current.copyWith(isActive: false);
    }

    final newActive = candidate.copyWith(
      isActive: true,
      isStaged: false,
    );

    _activeModels[type] = newActive;
    _stagedCandidates.remove(type);

    _swapEventController.add(ModelSwapEvent(
      type: type,
      activeModel: newActive,
      previousModel: current,
      isRollback: false,
      timestamp: DateTime.now(),
    ));

    debugPrint('[OneovaModelSwapService] Successfully swapped in model ${newActive.id} (v${newActive.version}).');
    return true;
  }

  /// Restores previous stable model if an anomaly, latency spike, or runtime error occurs
  bool rollback(OneovaModelType type) {
    final previous = _rollbackSnapshots[type];
    if (previous == null) {
      debugPrint('[OneovaModelSwapService] No rollback snapshot available for ${type.name}.');
      return false;
    }

    final current = _activeModels[type];
    final restored = previous.copyWith(isActive: true);

    _activeModels[type] = restored;
    _rollbackSnapshots.remove(type);

    _swapEventController.add(ModelSwapEvent(
      type: type,
      activeModel: restored,
      previousModel: current,
      isRollback: true,
      timestamp: DateTime.now(),
    ));

    debugPrint('[OneovaModelSwapService] Successfully rolled back ${type.name} to model ${restored.id} (v${restored.version}).');
    return true;
  }

  void dispose() {
    _swapEventController.close();
  }
}
