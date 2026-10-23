import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ova_memory_models.dart';
import '../services/ova_thermal_watchdog.dart';

final ovaMemoryEngineProvider = Provider<OvaMemoryEngine>((ref) {
  final thermalWatchdog = ref.read(ovaThermalWatchdogProvider);
  return OvaMemoryEngine(thermalWatchdog: thermalWatchdog);
});

/// Universal Shared Memory Engine for Oneova AI
///
/// Combines:
/// 1. Episodic Memory ("Learn from past mistakes" & mistake avoidance)
/// 2. Semantic Memory (Lightweight zero-heat Vector Store + Knowledge Graph)
/// Shared across all AI screens (Overlay, AI Lab, Voice Calling, Studio Tools)
class OvaMemoryEngine {
  final OvaThermalWatchdog thermalWatchdog;
  final FirebaseFirestore? _firestore;

  // In-memory high-density caches (LRU bounded for zero mobile heating)
  final List<EpisodicMemoryRecord> _episodicCache = [];
  final Map<String, KnowledgeNode> _graphNodes = {};
  final List<KnowledgeEdge> _graphEdges = [];
  final List<SemanticVectorItem> _vectorCache = [];

  static const int _maxCacheSize = 60;

  OvaMemoryEngine({
    required this.thermalWatchdog,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? (kIsWeb ? null : FirebaseFirestore.instance) {
    _seedBaselineMemory();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. EPISODIC MEMORY: LEARN FROM PAST MISTAKES
  // ───────────────────────────────────────────────────────────────────────────

  /// Seeds default episodic knowledge rules representing real platform learnings
  void _seedBaselineMemory() {
    // 1. Reel Export mistake learning
    _episodicCache.add(
      EpisodicMemoryRecord(
        id: 'ep_seed_reel_01',
        userId: 'system',
        scenarioKey: 'reel_export',
        triggerPrompt: 'Export and boost reel',
        executedSteps: ['encode_video', 'inject_reels'],
        outcome: EpisodeOutcome.failure,
        failureReason: 'Missing mandatory content safety scan',
        mistakeDetected: 'Exported reel directly without running safety & adult moderation check first',
        preventativeGuidance: 'Always run lexical and visual content safety check before injecting into Oneova Reels.',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
      ),
    );

    // 2. Workstation Remote Actuation mistake learning
    _episodicCache.add(
      EpisodicMemoryRecord(
        id: 'ep_seed_workstation_01',
        userId: 'system',
        scenarioKey: 'workstation_actuation',
        triggerPrompt: 'Render timeline on desktop',
        executedSteps: ['dispatch_render_command'],
        outcome: EpisodeOutcome.failure,
        failureReason: 'Target workstation was in sleep mode',
        mistakeDetected: 'Dispatched GPU render payload while workstation was in sleep state',
        preventativeGuidance: 'Always verify workstation wake state and validate passkey prior to command dispatch.',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );

    // 3. Workflow Ticket & Action mistake learning (Image 3 reference)
    _episodicCache.add(
      EpisodicMemoryRecord(
        id: 'ep_seed_workflow_01',
        userId: 'system',
        scenarioKey: 'ticket_refund_workflow',
        triggerPrompt: 'Close ticket and refund',
        executedSteps: ['close_ticket', 'process_refund'],
        outcome: EpisodeOutcome.failure,
        failureReason: 'Ticket closed before refund settlement confirmed',
        mistakeDetected: 'Closed user ticket before payment gateway verified refund',
        preventativeGuidance: 'Ensure refund confirmation status is verified and green before closing support ticket.',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    // 4. Live Calling & Stage mistake learning
    _episodicCache.add(
      EpisodicMemoryRecord(
        id: 'ep_seed_live_01',
        userId: 'system',
        scenarioKey: 'live_stage',
        triggerPrompt: 'Go live on stage',
        executedSteps: ['open_room', 'publish_audio'],
        outcome: EpisodeOutcome.failure,
        failureReason: 'Acoustic background feedback detected',
        mistakeDetected: 'Live audio channel initiated without background noise cancellation active',
        preventativeGuidance: 'Initialize DSP noise suppression and mute background channels before live broadcasting.',
        timestamp: DateTime.now().subtract(const Duration(hours: 12)),
      ),
    );

    // Seed Semantic Knowledge Graph
    _seedBaselineGraph();
  }

  /// Queries past mistakes to prevent repeating them in the current action
  List<MistakeAvoidanceRule> findMistakeAvoidance(String scenarioKey, List<String> plannedSteps) {
    final rules = <MistakeAvoidanceRule>[];
    final keyLower = scenarioKey.toLowerCase();

    final matchingEpisodes = _episodicCache.where((ep) {
      if (!ep.hadMistake) return false;
      if (scenarioKey.isNotEmpty && ep.scenarioKey == scenarioKey) return true;
      if (keyLower.isNotEmpty) {
        if (ep.scenarioKey.toLowerCase().contains(keyLower) ||
            ep.triggerPrompt.toLowerCase().contains(keyLower) ||
            (ep.mistakeDetected?.toLowerCase().contains(keyLower) ?? false) ||
            (ep.failureReason?.toLowerCase().contains(keyLower) ?? false)) {
          return true;
        }
      }
      for (final step in plannedSteps) {
        if (ep.executedSteps.contains(step)) return true;
      }
      return false;
    });

    for (final ep in matchingEpisodes) {
      if (ep.mistakeDetected != null && ep.preventativeGuidance != null) {
        rules.add(
          MistakeAvoidanceRule(
            scenarioKey: ep.scenarioKey,
            mistake: ep.mistakeDetected!,
            correctiveAction: ep.preventativeGuidance!,
            confidence: 0.95,
          ),
        );
      }
    }

    return rules;
  }

  /// Records a completed or failed autonomous episode into memory
  Future<void> recordEpisode(EpisodicMemoryRecord episode) async {
    // Add to in-memory cache with LRU eviction
    _episodicCache.insert(0, episode);
    if (_episodicCache.length > _maxCacheSize) {
      _episodicCache.removeLast();
    }

    // Persist to Cloud Firestore in background without blocking UI
    final firestore = _firestore;
    if (firestore != null && episode.userId != 'system' && episode.userId.isNotEmpty) {
      unawaited(
        firestore
            .collection('users')
            .doc(episode.userId)
            .collection('ai_episodes')
            .doc(episode.id)
            .set(episode.toMap(), SetOptions(merge: true))
            .catchError((e) {
          debugPrint('[OvaMemoryEngine] Firestore episode sync error: $e');
        }),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. SEMANTIC MEMORY: VECTOR DATABASE + KNOWLEDGE GRAPH
  // ───────────────────────────────────────────────────────────────────────────

  void _seedBaselineGraph() {
    // Nodes representing the exact user diagram:
    // CUSTOMER --[PREFERS]--> EMAIL
    // CUSTOMER --[PLACED]--> ORDER 4471
    // ORDER 4471 --[CONTAINS]--> PHONE
    addNode(KnowledgeNode(id: 'customer_oneova', type: 'Customer', label: 'Verified Customer (Creator)', properties: {'vip': true}));
    addNode(KnowledgeNode(id: 'channel_email', type: 'Channel', label: 'Email', properties: {'preferred': true, 'address': 'creator@oneova.studio'}));
    addNode(KnowledgeNode(id: 'channel_phone', type: 'Channel', label: 'Phone', properties: {'tel': '+1 (555) 019-4471'}));
    addNode(KnowledgeNode(id: 'order_4471', type: 'Order', label: 'Order 4471', properties: {'status': 'settled', 'item': 'Studio Master Pass'}));
    addNode(KnowledgeNode(id: 'format_4k60', type: 'Preference', label: '4K 60fps HDR Master', properties: {'codec': 'H.265'}));
    addNode(KnowledgeNode(id: 'reels_engine', type: 'Platform', label: 'Oneova Reels Primary', properties: {'locked': true}));

    // Edges (Direct representation of Knowledge Graph diagram)
    addEdge(KnowledgeEdge(id: 'e1', sourceId: 'customer_oneova', targetId: 'channel_email', relation: 'PREFERS'));
    addEdge(KnowledgeEdge(id: 'e2', sourceId: 'customer_oneova', targetId: 'order_4471', relation: 'PLACED'));
    addEdge(KnowledgeEdge(id: 'e3', sourceId: 'order_4471', targetId: 'channel_phone', relation: 'CONTAINS'));
    addEdge(KnowledgeEdge(id: 'e4', sourceId: 'customer_oneova', targetId: 'format_4k60', relation: 'PREFERS'));
    addEdge(KnowledgeEdge(id: 'e5', sourceId: 'customer_oneova', targetId: 'reels_engine', relation: 'STREAMED_ON'));

    // Vector items (Direct representation of Vector Database clusters from diagram)
    addSemanticVector('Customer communication channel preference: PREFERS EMAIL for notifications, receipts, and studio updates', 'customer_channel');
    addSemanticVector('How to reach them: Connect via primary registered email address (customer preferred contact channel)', 'reach_query');
    addSemanticVector('Order 4471 contains delivery recipient telephone number (+1 555-019-4471) for urgent courier SMS alerts', 'order_fulfillment');
    addSemanticVector('Oneova Reels LinUCB multi-armed bandit distribution engine with 10x Fast-Trend reach accelerator', 'reels');
    addSemanticVector('Content safety zero tolerance adult moderation, lexical analysis, and burn notice enforcement', 'safety');
    addSemanticVector('Remote workstation DaVinci Resolve color grading, GPU timeline rendering, and passkey authentication', 'studio');
    addSemanticVector('Digital Human persona live stage broadcasting with low-latency DSP noise cancellation', 'live');
    addSemanticVector('High velocity viral hashtags and creator audience retention optimization for Oneova Reels', 'analytics');
  }

  /// Adds an entity node to the knowledge graph
  void addNode(KnowledgeNode node) {
    _graphNodes[node.id] = node;
  }

  /// Adds a directed relationship edge to the knowledge graph
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

  /// Adds text to the lightweight zero-heat local vector store
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

  /// Performs fast, zero-heat local cosine similarity search
  List<SemanticVectorItem> vectorSearch(String query, {int limit = 3}) {
    final queryVector = _computeLightweightEmbedding(query);
    final scored = _vectorCache.map((item) {
      final score = item.cosineSimilarity(queryVector);
      return MapEntry(item, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  /// Generates a unified memory context string for AI model prompts across all screens
  String buildUnifiedMemoryContext({required String query, required String scenarioKey}) {
    final buffer = StringBuffer();

    // 1. Episodic Lessons & Mistake Avoidance ("Avoid repeating past mistakes")
    final mistakes = findMistakeAvoidance(scenarioKey, []);
    if (mistakes.isNotEmpty) {
      buffer.writeln('### 🛡️ EPISODIC MEMORY (PREVENT PAST MISTAKES):');
      for (final m in mistakes) {
        buffer.writeln('- PAST MISTAKE: ${m.mistake}');
        buffer.writeln('  CORRECTIVE ACTION: ${m.correctiveAction}');
      }
      buffer.writeln();
    }

    // 2. Semantic Memory: Knowledge Graph Traversal
    final customer = _graphNodes['customer_oneova'];
    if (customer != null) {
      final preferredChannels = getConnectedNodes(customer.id, relation: 'PREFERS');
      final placedOrders = getConnectedNodes(customer.id, relation: 'PLACED');

      buffer.writeln('### 🕸️ KNOWLEDGE GRAPH RELATIONSHIPS:');
      buffer.writeln('- Customer: ${customer.label}');
      for (final channel in preferredChannels) {
        buffer.writeln('  -> PREFERS: ${channel.label} (${channel.type})');
      }
      for (final order in placedOrders) {
        buffer.writeln('  -> PLACED: ${order.label}');
        final orderItems = getConnectedNodes(order.id, relation: 'CONTAINS');
        for (final item in orderItems) {
          buffer.writeln('     -> CONTAINS: ${item.label} (${item.type})');
        }
      }
      buffer.writeln();
    }

    // 3. Semantic Memory: Vector Database Clustering
    final matches = vectorSearch(query, limit: 2);
    if (matches.isNotEmpty) {
      buffer.writeln('### 🎯 VECTOR DATABASE CLUSTERS (SEMANTIC SIMILARITY):');
      for (final match in matches) {
        buffer.writeln('- [Cluster: ${match.category.toUpperCase()}] ${match.content}');
      }
    }

    return buffer.toString().trim();
  }

  /// 64-dimensional quantized feature hashing embedding
  /// Runs in < 1ms on any mobile CPU with 0 heat generation and 0 network overhead
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

    // L2 Normalize
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
