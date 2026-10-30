import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/oneova_look.dart';
import '../models/ai_grade_command.dart';
import '../models/scope_sentinel_alert.dart';
import '../scopes/models/scope_frame_data.dart';
import '../services/ai_color_grader_service.dart';
import '../services/scope_sentinel_engine.dart';

@immutable
class ConversationalGraderState {
  final OneovaLook activeLook;
  final bool isListening;
  final bool isProcessing;
  final List<GradeHistoryEntry> history;
  final int historyIndex;
  final GradeDiffReport? lastDiff;
  final String? lastAssistantMessage;
  final SemanticGradeRegion targetRegion;
  final ScopeFrameData scopeData;
  final ScopeSentinelAlert? activeAlert;
  final List<String> suggestedPrompts;

  const ConversationalGraderState({
    this.activeLook = const OneovaLook(id: 'default', name: 'Original'),
    this.isListening = false,
    this.isProcessing = false,
    this.history = const [],
    this.historyIndex = -1,
    this.lastDiff,
    this.lastAssistantMessage,
    this.targetRegion = SemanticGradeRegion.entireFrame,
    required this.scopeData,
    this.activeAlert,
    this.suggestedPrompts = const [
      'Make it warmer and golden',
      'Add film grain and halation',
      'Lift shadow detail',
      'Cool down the background',
    ],
  });

  bool get canUndo => historyIndex > 0;
  bool get canRedo => historyIndex < history.length - 1;

  ConversationalGraderState copyWith({
    OneovaLook? activeLook,
    bool? isListening,
    bool? isProcessing,
    List<GradeHistoryEntry>? history,
    int? historyIndex,
    GradeDiffReport? lastDiff,
    String? lastAssistantMessage,
    SemanticGradeRegion? targetRegion,
    ScopeFrameData? scopeData,
    ScopeSentinelAlert? activeAlert,
    bool clearAlert = false,
    List<String>? suggestedPrompts,
  }) {
    return ConversationalGraderState(
      activeLook: activeLook ?? this.activeLook,
      isListening: isListening ?? this.isListening,
      isProcessing: isProcessing ?? this.isProcessing,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      lastDiff: lastDiff ?? this.lastDiff,
      lastAssistantMessage: lastAssistantMessage ?? this.lastAssistantMessage,
      targetRegion: targetRegion ?? this.targetRegion,
      scopeData: scopeData ?? this.scopeData,
      activeAlert: clearAlert ? null : (activeAlert ?? this.activeAlert),
      suggestedPrompts: suggestedPrompts ?? this.suggestedPrompts,
    );
  }
}

class ConversationalGraderController extends Notifier<ConversationalGraderState> {
  late final AiColorGraderService _graderService;
  late final ScopeSentinelEngine _sentinelEngine;

  @override
  ConversationalGraderState build() {
    _graderService = ref.watch(aiColorGraderServiceProvider);
    _sentinelEngine = ref.watch(scopeSentinelEngineProvider);

    const initialLook = OneovaLook(id: 'base', name: 'Original');
    final initialScope = ScopeFrameData.fromLook(initialLook);

    final initialEntry = GradeHistoryEntry(
      entryId: 'entry_0',
      timestamp: DateTime.now(),
      userInstruction: 'Original Base',
      lookSnapshot: initialLook,
    );

    return ConversationalGraderState(
      activeLook: initialLook,
      scopeData: initialScope,
      history: [initialEntry],
      historyIndex: 0,
    );
  }

  /// Sets the active look explicitly (e.g. from editor timeline or photo grade view).
  void setActiveLook(OneovaLook look) {
    final newScope = ScopeFrameData.fromLook(look);
    final alert = _sentinelEngine.evaluateFrame(data: newScope, currentLook: look);

    final entry = GradeHistoryEntry(
      entryId: 'entry_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      userInstruction: 'Loaded Look: ${look.name}',
      lookSnapshot: look,
    );

    state = state.copyWith(
      activeLook: look,
      scopeData: newScope,
      activeAlert: alert,
      clearAlert: alert == null,
      history: [...state.history.sublist(0, state.historyIndex + 1), entry],
      historyIndex: state.historyIndex + 1,
    );
  }

  /// Selects semantic region to scope grading edits (Skin, Sky, Background, etc.).
  void setTargetRegion(SemanticGradeRegion region) {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    state = state.copyWith(targetRegion: region);
  }

  /// Submits spoken or typed natural language grading instruction.
  Future<void> submitPrompt(String prompt, {SemanticGradeRegion? region}) async {
    final targetReg = region ?? state.targetRegion;
    state = state.copyWith(isProcessing: true);

    try {
      final result = await _graderService.grade(
        prompt: prompt,
        currentLook: state.activeLook,
        region: targetReg,
      );

      final newScope = ScopeFrameData.fromLook(result.updatedLook);
      final alert = _sentinelEngine.evaluateFrame(data: newScope, currentLook: result.updatedLook);

      final entry = GradeHistoryEntry(
        entryId: 'entry_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        userInstruction: prompt,
        lookSnapshot: result.updatedLook,
        diffReport: result.diffReport,
      );

      final newHistory = [
        ...state.history.sublist(0, state.historyIndex + 1),
        entry,
      ];

      state = state.copyWith(
        activeLook: result.updatedLook,
        isProcessing: false,
        lastDiff: result.diffReport,
        lastAssistantMessage: result.assistantExplanation,
        suggestedPrompts: result.suggestedNextPrompts,
        scopeData: newScope,
        activeAlert: alert,
        clearAlert: alert == null,
        history: newHistory,
        historyIndex: newHistory.length - 1,
      );
    } catch (e) {
      debugPrint('[ConversationalGraderController] Grading error: $e');
      state = state.copyWith(
        isProcessing: false,
        lastAssistantMessage: 'Could not apply adjustment: $e',
      );
    }
  }

  /// Applies one-tap corrective fix proposed by Scope Sentinel.
  void applySentinelFix(ScopeSentinelAlert alert) {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    final fixedLook = alert.applyFix(state.activeLook);
    final newScope = ScopeFrameData.fromLook(fixedLook);
    _sentinelEngine.dismissAlert();

    final entry = GradeHistoryEntry(
      entryId: 'entry_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      userInstruction: 'Sentinel Fix: ${alert.suggestedFixLabel}',
      lookSnapshot: fixedLook,
    );

    final newHistory = [
      ...state.history.sublist(0, state.historyIndex + 1),
      entry,
    ];

    state = state.copyWith(
      activeLook: fixedLook,
      scopeData: newScope,
      clearAlert: true,
      lastAssistantMessage: 'Applied Sentinel corrective fix for ${alert.headline}.',
      history: newHistory,
      historyIndex: newHistory.length - 1,
    );
  }

  void dismissSentinelAlert() {
    _sentinelEngine.dismissAlert();
    state = state.copyWith(clearAlert: true);
  }

  /// Reverts one step in the grade history stack.
  void undo() {
    if (!state.canUndo) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    final targetIdx = state.historyIndex - 1;
    final entry = state.history[targetIdx];
    final scope = ScopeFrameData.fromLook(entry.lookSnapshot);

    state = state.copyWith(
      historyIndex: targetIdx,
      activeLook: entry.lookSnapshot,
      scopeData: scope,
      lastDiff: entry.diffReport,
      lastAssistantMessage: 'Reverted to: ${entry.userInstruction}',
    );
  }

  /// Advances one step in the grade history stack.
  void redo() {
    if (!state.canRedo) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    final targetIdx = state.historyIndex + 1;
    final entry = state.history[targetIdx];
    final scope = ScopeFrameData.fromLook(entry.lookSnapshot);

    state = state.copyWith(
      historyIndex: targetIdx,
      activeLook: entry.lookSnapshot,
      scopeData: scope,
      lastDiff: entry.diffReport,
      lastAssistantMessage: 'Restored to: ${entry.userInstruction}',
    );
  }
}

final conversationalGraderControllerProvider =
    NotifierProvider<ConversationalGraderController, ConversationalGraderState>(
  ConversationalGraderController.new,
);
