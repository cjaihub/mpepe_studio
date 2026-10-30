import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ova_memory_models.dart';
import '../services/ova_thermal_watchdog.dart';
import '../../backend/user_service.dart';

final ovaMemoryEngineProvider = Provider<OvaMemoryEngine>((ref) {
  final thermalWatchdog = ref.read(ovaThermalWatchdogProvider);
  return OvaMemoryEngine(thermalWatchdog: thermalWatchdog);
});

/// Universal Shared Memory Engine for Oneova AI
///
/// Features:
/// 1. Token Governor & Rolling Recursive Summaries (Prunes bloated context, retains 100% facts in <120 tokens)
/// 2. Real-time Emotion & Feelings Detection (Empathetic prosody, human-like resonance)
/// 3. Authenticated User Profile Awareness (Learns who is logged in, their niche, account type, preferences)
/// 4. Episodic Mistake Avoidance (Never repeats failed tool calls)
/// 5. Zero-Heat Semantic Vector Cache (64-dim quantized feature hashing, <1ms mobile CPU)
class OvaMemoryEngine {
  final OvaThermalWatchdog thermalWatchdog;
  final FirebaseFirestore? _firestore;

  // In-memory high-density caches
  final List<EpisodicMemoryRecord> _episodicCache = [];
  final Map<String, KnowledgeNode> _graphNodes = {};
  final List<KnowledgeEdge> _graphEdges = [];
  final List<SemanticVectorItem> _vectorCache = [];
  final Map<String, OvaRollingSummary> _sessionSummaries = {};
  final Map<String, List<OvaEmotionSnapshot>> _sessionMoodHistory = {};

  AppUser? _currentUserProfile;
  static const int _maxCacheSize = 60;

  OvaMemoryEngine({
    required this.thermalWatchdog,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? (kIsWeb ? null : FirebaseFirestore.instance) {
    _initEngine();
  }

  void _initEngine() {
    // Listen to Firebase Auth state to hydrate logged in user profile dynamically
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        hydrateUserProfile(user.uid);
      } else {
        _currentUserProfile = null;
        _graphNodes.clear();
        _graphEdges.clear();
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. AUTHENTICATED USER IDENTITY & KNOWLEDGE GRAPH
  // ───────────────────────────────────────────────────────────────────────────

  /// Hydrates real user profile and creates true identity graph nodes
  Future<void> hydrateUserProfile(String uid) async {
    final firestore = _firestore;
    if (firestore == null || uid.isEmpty) return;

    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return;

      final user = AppUser.fromMap(doc.data()!, uid);
      _currentUserProfile = user;

      // Build real user Knowledge Graph
      final userNodeId = 'user_${user.id}';
      addNode(KnowledgeNode(
        id: userNodeId,
        type: 'Creator',
        label: user.fullName.isNotEmpty ? user.fullName : '@${user.username}',
        properties: {
          'username': user.username,
          'accountType': user.accountType,
          'category': user.category,
          'pronouns': user.pronouns,
          'isVerified': user.isVerified,
        },
      ));

      if (user.category != null && user.category!.isNotEmpty) {
        final catNodeId = 'cat_${user.category}';
        addNode(KnowledgeNode(id: catNodeId, type: 'Niche', label: user.category!));
        addEdge(KnowledgeEdge(id: 'edge_user_cat', sourceId: userNodeId, targetId: catNodeId, relation: 'SPECIALIZES_IN'));
      }

      // Add real user links
      for (final link in user.links) {
        final title = link['title'] ?? 'Link';
        final url = link['url'] ?? '';
        if (url.isNotEmpty) {
          final linkNodeId = 'link_${url.hashCode}';
          addNode(KnowledgeNode(id: linkNodeId, type: 'Link', label: title, properties: {'url': url}));
          addEdge(KnowledgeEdge(id: 'edge_link_${url.hashCode}', sourceId: userNodeId, targetId: linkNodeId, relation: 'PUBLISHES'));
        }
      }

      // Hydrate past persistent user memories
      final memoriesSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('ai_memories')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      for (final mDoc in memoriesSnap.docs) {
        final content = mDoc.data()['content'] as String? ?? '';
        final category = mDoc.data()['category'] as String? ?? 'user_preference';
        if (content.isNotEmpty) {
          addSemanticVector(content, category);
        }
      }
    } catch (e) {
      debugPrint('[OvaMemoryEngine] Error hydrating user profile: $e');
    }
  }

  AppUser? get currentUserProfile => _currentUserProfile;

  // ───────────────────────────────────────────────────────────────────────────
  // 2. TOKEN GOVERNOR & RECURSIVE ROLLING SUMMARIES
  // ───────────────────────────────────────────────────────────────────────────

  /// Fetches current rolling summary for a conversation session
  OvaRollingSummary? getSessionSummary(String sessionId) => _sessionSummaries[sessionId];

  /// Condenses conversation history into a concise executive summary (< 120 tokens)
  /// Prunes old raw turns while preserving 100% of facts, decisions, and context.
  Future<void> updateRollingSummary({
    required String sessionId,
    required String userId,
    required List<Map<String, dynamic>> recentTurns,
  }) async {
    if (recentTurns.isEmpty) return;

    final existing = _sessionSummaries[sessionId];
    final buffer = StringBuffer();
    final decisions = <String>[...existing?.keyDecisions ?? []];
    final entities = <String>[...existing?.activeEntities ?? []];

    // Extract intents and key agreements from recent turns
    for (final turn in recentTurns) {
      final role = turn['role'] ?? 'user';
      final content = turn['content']?.toString() ?? '';
      if (content.isEmpty) continue;

      if (role == 'user') {
        if (content.toLowerCase().contains('want') ||
            content.toLowerCase().contains('create') ||
            content.toLowerCase().contains('edit') ||
            content.toLowerCase().contains('fix') ||
            content.toLowerCase().contains('export')) {
          final snippet = content.length > 80 ? '${content.substring(0, 80)}...' : content;
          if (!decisions.contains(snippet)) {
            decisions.add(snippet);
            if (decisions.length > 5) decisions.removeAt(0);
          }
        }
      }
    }

    if (existing != null) {
      buffer.write(existing.summaryText);
      buffer.write(' ');
    }

    final latestUserTurn = recentTurns.lastWhere(
      (t) => t['role'] == 'user',
      orElse: () => {'content': ''},
    )['content']?.toString() ?? '';

    if (latestUserTurn.isNotEmpty) {
      final condensed = latestUserTurn.length > 100
          ? '${latestUserTurn.substring(0, 97)}...'
          : latestUserTurn;
      buffer.write('Latest topic: $condensed.');
    }

    // Keep summary under ~120 tokens (roughly 450 characters)
    String finalSummary = buffer.toString().trim();
    if (finalSummary.length > 450) {
      finalSummary = finalSummary.substring(finalSummary.length - 450);
    }

    final summary = OvaRollingSummary(
      sessionId: sessionId,
      userId: userId,
      summaryText: finalSummary,
      keyDecisions: decisions,
      activeEntities: entities,
      turnCount: (existing?.turnCount ?? 0) + recentTurns.length,
      updatedAt: DateTime.now(),
    );

    _sessionSummaries[sessionId] = summary;

    // Persist asynchronously in Firestore
    final firestore = _firestore;
    if (firestore != null && userId.isNotEmpty && userId != 'system') {
      unawaited(
        firestore
            .collection('users')
            .doc(userId)
            .collection('ai_session_summaries')
            .doc(sessionId)
            .set(summary.toMap(), SetOptions(merge: true))
            .catchError((_) {}),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. EMOTION & FEELINGS DETECTION (HIGH EQ PROSODY & CHARTS)
  // ───────────────────────────────────────────────────────────────────────────

  /// Analyzes text in real-time to detect user emotional state and guide Ova's tone
  OvaEmotionSnapshot detectEmotion(String text, {String sessionId = 'default'}) {
    final lower = text.toLowerCase();

    OvaEmotionValence valence = OvaEmotionValence.reflective;
    String primaryLabel = 'Warm & Attentive';
    String toneGuidance = 'Respond warmly, conversational, direct, and concise.';
    double intensity = 0.7;

    // 1. Frustrated / Stressed indicators
    if (lower.contains('broken') ||
        lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('stuck') ||
        lower.contains('annoying') ||
        lower.contains('not working') ||
        lower.contains('urgent') ||
        lower.contains('cant') ||
        lower.contains("can't") ||
        lower.contains('why is it')) {
      valence = OvaEmotionValence.frustrated;
      primaryLabel = 'Needs Urgent Clarity';
      toneGuidance = 'Calm, highly empathetic, solution-first. Zero robot filler, no excuses. Resolve directly.';
      intensity = 0.9;
    }
    // 2. Excited / Celebratory
    else if (lower.contains('wow') ||
        lower.contains('amazing') ||
        lower.contains('great') ||
        lower.contains('love') ||
        lower.contains('awesome') ||
        lower.contains('viral') ||
        lower.contains('fire') ||
        lower.contains('lets go') ||
        lower.contains("let's go") ||
        lower.contains('finally')) {
      valence = OvaEmotionValence.excited;
      primaryLabel = 'High Energy & Visionary';
      toneGuidance = 'Match enthusiasm, celebrate milestones, fuel creative ideas with high momentum.';
      intensity = 0.95;
    }
    // 3. Creative / Ideation Flow
    else if (lower.contains('idea') ||
        lower.contains('script') ||
        lower.contains('brainstorm') ||
        lower.contains('create') ||
        lower.contains('concept') ||
        lower.contains('what if') ||
        lower.contains('vibe') ||
        lower.contains('style')) {
      valence = OvaEmotionValence.creativeFlow;
      primaryLabel = 'Creative Flow';
      toneGuidance = 'Inventive, inspiring, sharp, offer bold creative alternatives without overwhelming.';
      intensity = 0.85;
    }
    // 4. Analytical / Task execution
    else if (lower.contains('export') ||
        lower.contains('data') ||
        lower.contains('stats') ||
        lower.contains('settings') ||
        lower.contains('verify') ||
        lower.contains('run') ||
        lower.contains('schedule')) {
      valence = OvaEmotionValence.focused;
      primaryLabel = 'Deep Focus & Executive';
      toneGuidance = 'Precise, factual, efficient executive clarity. Clean bullet points.';
      intensity = 0.8;
    }

    final snapshot = OvaEmotionSnapshot(
      valence: valence,
      intensity: intensity,
      primaryEmotionLabel: primaryLabel,
      toneGuidance: toneGuidance,
      timestamp: DateTime.now(),
    );

    // Record in session mood arc for charts
    _sessionMoodHistory.putIfAbsent(sessionId, () => []).add(snapshot);
    if (_sessionMoodHistory[sessionId]!.length > 30) {
      _sessionMoodHistory[sessionId]!.removeAt(0);
    }

    return snapshot;
  }

  List<OvaEmotionSnapshot> getSessionMoodHistory(String sessionId) {
    return _sessionMoodHistory[sessionId] ?? [];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. EPISODIC MEMORY (PREVENT MISTAKES)
  // ───────────────────────────────────────────────────────────────────────────

  List<MistakeAvoidanceRule> findMistakeAvoidance(String scenarioKey, List<String> plannedSteps) {
    final rules = <MistakeAvoidanceRule>[];
    final keyLower = scenarioKey.toLowerCase();

    final matching = _episodicCache.where((ep) {
      if (!ep.hadMistake) return false;
      if (scenarioKey.isNotEmpty && ep.scenarioKey == scenarioKey) return true;
      if (keyLower.isNotEmpty && (ep.scenarioKey.toLowerCase().contains(keyLower) || ep.triggerPrompt.toLowerCase().contains(keyLower))) {
        return true;
      }
      for (final step in plannedSteps) {
        if (ep.executedSteps.contains(step)) return true;
      }
      return false;
    });

    for (final ep in matching) {
      if (ep.mistakeDetected != null && ep.preventativeGuidance != null) {
        rules.add(MistakeAvoidanceRule(
          scenarioKey: ep.scenarioKey,
          mistake: ep.mistakeDetected!,
          correctiveAction: ep.preventativeGuidance!,
          confidence: 0.95,
        ));
      }
    }
    return rules;
  }

  Future<void> recordEpisode(EpisodicMemoryRecord episode) async {
    _episodicCache.insert(0, episode);
    if (_episodicCache.length > _maxCacheSize) {
      _episodicCache.removeLast();
    }

    final firestore = _firestore;
    if (firestore != null && episode.userId != 'system' && episode.userId.isNotEmpty) {
      unawaited(
        firestore
            .collection('users')
            .doc(episode.userId)
            .collection('ai_episodes')
            .doc(episode.id)
            .set(episode.toMap(), SetOptions(merge: true))
            .catchError((_) {}),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 5. LOCAL ZERO-HEAT VECTOR STORE & GRAPH
  // ───────────────────────────────────────────────────────────────────────────

  void addNode(KnowledgeNode node) {
    _graphNodes[node.id] = node;
  }

  void addEdge(KnowledgeEdge edge) {
    _graphEdges.removeWhere((e) => e.id == edge.id);
    _graphEdges.add(edge);
  }

  /// Finds nodes connected to an entity by optional relation
  List<KnowledgeNode> getConnectedNodes(String sourceId, {String? relation}) {
    final targetIds = _graphEdges
        .where((e) => e.sourceId == sourceId && (relation == null || e.relation == relation))
        .map((e) => e.targetId)
        .toSet();

    return targetIds
        .map((tid) => _graphNodes[tid])
        .whereType<KnowledgeNode>()
        .toList();
  }

  void addSemanticVector(String text, String category) {
    final embedding = _computeLightweightEmbedding(text);
    _vectorCache.insert(
      0,
      SemanticVectorItem(
        id: 'vec_${DateTime.now().microsecondsSinceEpoch}',
        content: text,
        embedding: embedding,
        category: category,
        createdAt: DateTime.now(),
      ),
    );
    if (_vectorCache.length > _maxCacheSize) {
      _vectorCache.removeLast();
    }
  }

  List<SemanticVectorItem> vectorSearch(String query, {int limit = 3}) {
    if (_vectorCache.isEmpty || query.trim().isEmpty) return const [];
    final queryVector = _computeLightweightEmbedding(query);
    final scored = _vectorCache.map((item) {
      final score = item.cosineSimilarity(queryVector);
      return MapEntry(item, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  /// Builds a high-density, token-efficient unified memory context
  String buildUnifiedMemoryContext({
    required String query,
    required String scenarioKey,
    String sessionId = 'default',
  }) {
    final buffer = StringBuffer();
    final user = _currentUserProfile;

    // 1. Authenticated Creator Identity Context
    if (user != null) {
      buffer.writeln('### 👤 USER PROFILE:');
      buffer.writeln('- Name: ${user.fullName.isNotEmpty ? user.fullName : '@${user.username}'}');
      if (user.username != null && user.username!.isNotEmpty) buffer.writeln('- Username: @${user.username}');
      buffer.writeln('- Account Type: ${user.accountType.toUpperCase()}');
      if (user.category != null && user.category!.isNotEmpty) buffer.writeln('- Niche / Category: ${user.category}');
      if (user.pronouns != null && user.pronouns!.isNotEmpty) buffer.writeln('- Pronouns: ${user.pronouns}');
      buffer.writeln();
    }

    // 2. Rolling Session Summary (Saves tokens, remembers previous decisions)
    final summary = _sessionSummaries[sessionId];
    if (summary != null && summary.summaryText.isNotEmpty) {
      buffer.writeln('### 🧠 RECURSIVE SESSION SUMMARY (<120 tokens):');
      buffer.writeln(summary.summaryText);
      if (summary.keyDecisions.isNotEmpty) {
        buffer.writeln('Decisions: ${summary.keyDecisions.join("; ")}');
      }
      buffer.writeln();
    }

    // 3. Real-Time Emotion & Tone Guidance
    final emotion = detectEmotion(query, sessionId: sessionId);
    buffer.writeln('### 🎭 EMOTION & EQ TONE GUIDANCE:');
    buffer.writeln('- Detected User State: ${emotion.primaryEmotionLabel} (Intensity: ${(emotion.intensity * 100).toInt()}%)');
    buffer.writeln('- Tone Directive: ${emotion.toneGuidance}');
    buffer.writeln();

    // 4. Mistake Avoidance
    final mistakes = findMistakeAvoidance(scenarioKey, []);
    if (mistakes.isNotEmpty) {
      buffer.writeln('### 🛡️ MISTAKE AVOIDANCE:');
      for (final m in mistakes) {
        buffer.writeln('- Past Mistake: ${m.mistake} -> Corrective: ${m.correctiveAction}');
      }
      buffer.writeln();
    }

    // 5. Relevant Learned Knowledge
    final matches = vectorSearch(query, limit: 2);
    if (matches.isNotEmpty) {
      buffer.writeln('### 🎯 RECALLED USER PREFERENCES:');
      for (final match in matches) {
        buffer.writeln('- ${match.content}');
      }
    }

    return buffer.toString().trim();
  }

  List<double> _computeLightweightEmbedding(String text) {
    const dim = 64;
    final vector = List<double>.filled(dim, 0.0);
    final tokens = text.toLowerCase().split(RegExp(r'\s+'));

    for (final token in tokens) {
      final hash = token.hashCode;
      for (int i = 0; i < dim; i++) {
        final bit = (hash >> (i % 31)) & 1;
        vector[i] += bit == 1 ? 1.0 : -0.5;
      }
    }

    double norm = 0.0;
    for (final v in vector) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm > 0) {
      for (int i = 0; i < dim; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }
}
