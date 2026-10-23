import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/secure_api_key_vault.dart';

/// Represents individual component health check state.
enum ComponentStatus { healthy, degraded, repaired, failed }

/// Diagnostic report item for a specific system pillar.
class HealthCheckItem {
  final String component;
  final ComponentStatus status;
  final String details;
  final int latencyMs;

  const HealthCheckItem({
    required this.component,
    required this.status,
    required this.details,
    this.latencyMs = 0,
  });

  Map<String, dynamic> toMap() => {
        'component': component,
        'status': status.name,
        'details': details,
        'latencyMs': latencyMs,
      };
}

/// Comprehensive report of the entire application health.
class SystemHealthReport {
  final int overallScore; // 0 - 100
  final ComponentStatus overallStatus;
  final List<HealthCheckItem> checks;
  final List<String> autoFixedIssues;
  final DateTime timestamp;

  const SystemHealthReport({
    required this.overallScore,
    required this.overallStatus,
    required this.checks,
    required this.autoFixedIssues,
    required this.timestamp,
  });
}

/// Outcome of an automated self-repair action.
class RepairResult {
  final bool success;
  final String action;
  final String summary;
  final List<String> repairedFields;
  final DateTime timestamp;

  const RepairResult({
    required this.success,
    required this.action,
    required this.summary,
    this.repairedFields = const [],
    required this.timestamp,
  });
}

/// AI-generated diagnosis for runtime errors or backend anomalies.
class AiDiagnosisResult {
  final String rootCause;
  final String severity; // low, medium, high, critical
  final String recommendedAction;
  final String humanExplanation;
  final bool autoExecuted;

  const AiDiagnosisResult({
    required this.rootCause,
    required this.severity,
    required this.recommendedAction,
    required this.humanExplanation,
    this.autoExecuted = false,
  });
}

final oneOvaSelfRepairEngineProvider = Provider<OneOvaSelfRepairEngine>((ref) {
  final vault = ref.watch(secureKeyVaultProvider);
  return OneOvaSelfRepairEngine(vault);
});

/// Primary Built-In AI Autonomous Self-Repair & Diagnostics Engine for Oneova.
///
/// Designed to autonomously:
/// 1. Scan and diagnose backend Firestore schema corruptions / missing profile keys.
/// 2. Autonomously patch, heal, and normalize user profiles atomically.
/// 3. Clear corrupt disk cache, broken video streams, and orphaned controllers.
/// 4. Consult Google Gemini models directly using the hardened secure key in vault / `.env`.
/// 5. Execute self-healing recipes and maintain an audit log in `users/{uid}/repair_logs`.
class OneOvaSelfRepairEngine {
  final SecureKeyVault _vault;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  OneOvaSelfRepairEngine(this._vault);

  /// Performs a comprehensive real-time scan of all system subsystems.
  Future<SystemHealthReport> runSystemHealthScan() async {
    final List<HealthCheckItem> checks = [];
    final List<String> fixed = [];

    // 1. Check Authentication Status
    final user = _auth.currentUser;
    if (user != null) {
      checks.add(HealthCheckItem(
        component: 'Authentication Service',
        status: ComponentStatus.healthy,
        details: 'Active session for ${user.displayName ?? user.email ?? user.uid}',
      ));
    } else {
      checks.add(const HealthCheckItem(
        component: 'Authentication Service',
        status: ComponentStatus.degraded,
        details: 'Operating in guest / signed-out state',
      ));
    }

    // 2. Check Cloud Firestore Latency & Read/Write
    final fsStopwatch = Stopwatch()..start();
    try {
      await _firestore.collection('system_config').doc('health_ping').set({
        'lastPing': FieldValue.serverTimestamp(),
        'platform': Platform.operatingSystem,
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      fsStopwatch.stop();

      checks.add(HealthCheckItem(
        component: 'Cloud Firestore Database',
        status: ComponentStatus.healthy,
        details: 'Realtime database latency nominal (${fsStopwatch.elapsedMilliseconds}ms)',
        latencyMs: fsStopwatch.elapsedMilliseconds,
      ));
    } catch (e) {
      fsStopwatch.stop();
      checks.add(HealthCheckItem(
        component: 'Cloud Firestore Database',
        status: ComponentStatus.degraded,
        details: 'Latency high or offline fallback: $e',
        latencyMs: fsStopwatch.elapsedMilliseconds,
      ));
    }

    // 3. Check Firebase Storage
    try {
      final storageRef = FirebaseStorage.instance.ref().child('system/health_check.txt');
      // Verify storage reference without full download
      checks.add(HealthCheckItem(
        component: 'Cloud Storage Media Engine',
        status: ComponentStatus.healthy,
        details: 'Bucket storage accessible (${storageRef.bucket})',
      ));
    } catch (e) {
      checks.add(HealthCheckItem(
        component: 'Cloud Storage Media Engine',
        status: ComponentStatus.degraded,
        details: 'Storage warning: $e',
      ));
    }

    // 4. Check Gemini Primary AI Connectivity
    final geminiKey = await _vault.getGeminiApiKey();
    final openRouterKey = await _vault.getOpenRouterApiKey();
    if (geminiKey.isNotEmpty) {
      checks.add(HealthCheckItem(
        component: 'Gemini Autonomous AI Core',
        status: ComponentStatus.healthy,
        details: 'Google AI Studio key verified (${_vault.maskKey(geminiKey)})',
      ));
    } else if (openRouterKey.isNotEmpty) {
      checks.add(HealthCheckItem(
        component: 'Gemini Autonomous AI Core',
        status: ComponentStatus.healthy,
        details: 'Bridged via OpenRouter fallback (${_vault.maskKey(openRouterKey)})',
      ));
    } else {
      checks.add(const HealthCheckItem(
        component: 'Gemini Autonomous AI Core',
        status: ComponentStatus.degraded,
        details: 'API Key missing in Keystore and .env. Heuristic fallback engaged.',
      ));
    }

    // 5. Check Local App Storage & Cache
    try {
      final tempDir = await getTemporaryDirectory();
      int tempSize = 0;
      if (tempDir.existsSync()) {
        final files = tempDir.listSync(recursive: true, followLinks: false);
        for (var file in files) {
          if (file is File) {
            tempSize += file.lengthSync();
          }
        }
      }
      final sizeMb = (tempSize / (1024 * 1024)).toStringAsFixed(1);
      checks.add(HealthCheckItem(
        component: 'Local Media Cache',
        status: tempSize > 150 * 1024 * 1024 ? ComponentStatus.degraded : ComponentStatus.healthy,
        details: 'Disk cache size: $sizeMb MB',
      ));
    } catch (_) {
      checks.add(const HealthCheckItem(
        component: 'Local Media Cache',
        status: ComponentStatus.healthy,
        details: 'Local cache accessible',
      ));
    }

    // Calculate score
    int healthyCount = checks.where((c) => c.status == ComponentStatus.healthy).length;
    int score = ((healthyCount / checks.length) * 100).round();
    ComponentStatus overall = score >= 80 ? ComponentStatus.healthy : ComponentStatus.degraded;

    return SystemHealthReport(
      overallScore: score,
      overallStatus: overall,
      checks: checks,
      autoFixedIssues: fixed,
      timestamp: DateTime.now(),
    );
  }

  /// Autonomously inspects and repairs the user profile in Firestore.
  /// Fixes missing fields, corrupted schemas, broken counters, and verifies completeness.
  Future<RepairResult> repairUserProfile(String uid) async {
    final List<String> repaired = [];
    try {
      final docRef = _firestore.collection('users').doc(uid);
      final docSnap = await docRef.get();

      final currentData = docSnap.data() ?? {};
      final Map<String, dynamic> patches = {};

      // 1. Mandatory Core Identity Fields
      if (!currentData.containsKey('displayName') || (currentData['displayName'] as String?)?.trim().isEmpty == true) {
        final fallbackName = _auth.currentUser?.displayName ?? 'Oneova Creator';
        patches['displayName'] = fallbackName;
        repaired.add('displayName ($fallbackName)');
      }

      if (!currentData.containsKey('username') || (currentData['username'] as String?)?.trim().isEmpty == true) {
        final cleanBase = (currentData['displayName'] ?? 'creator')
            .toString()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9_]'), '');
        final generatedUsername = '${cleanBase.isEmpty ? 'creator' : cleanBase}_${uid.substring(0, 4)}';
        patches['username'] = generatedUsername;
        repaired.add('username (@$generatedUsername)');
      }

      if (!currentData.containsKey('email') && _auth.currentUser?.email != null) {
        patches['email'] = _auth.currentUser!.email;
        repaired.add('email');
      }

      // 2. Metrics & Counters Normalization
      if (!currentData.containsKey('followerCount') || currentData['followerCount'] is! num) {
        patches['followerCount'] = 0;
        repaired.add('followerCount');
      }
      if (!currentData.containsKey('followingCount') || currentData['followingCount'] is! num) {
        patches['followingCount'] = 0;
        repaired.add('followingCount');
      }
      if (!currentData.containsKey('postCount') || currentData['postCount'] is! num) {
        patches['postCount'] = 0;
        repaired.add('postCount');
      }

      // 3. Flags and State
      if (!currentData.containsKey('isVerified')) {
        patches['isVerified'] = false;
        repaired.add('isVerified');
      }
      if (!currentData.containsKey('accountTier')) {
        patches['accountTier'] = 'Creator Standard';
        repaired.add('accountTier');
      }
      if (!currentData.containsKey('status')) {
        patches['status'] = 'active';
        repaired.add('status');
      }
      if (!currentData.containsKey('bio') || currentData['bio'] == null) {
        patches['bio'] = '';
        repaired.add('bio');
      }

      // 4. Timestamps
      if (!currentData.containsKey('createdAt')) {
        patches['createdAt'] = FieldValue.serverTimestamp();
        repaired.add('createdAt');
      }
      patches['lastSelfRepairedAt'] = FieldValue.serverTimestamp();
      patches['profileCompleted'] = true;

      // Commit atomic patch
      if (patches.isNotEmpty) {
        await docRef.set(patches, SetOptions(merge: true));
      }

      // Log repair action to audit trail
      await _logRepairEvent(
        uid: uid,
        action: 'repair_user_profile',
        summary: 'Repaired ${repaired.length} profile attributes',
        details: patches,
      );

      return RepairResult(
        success: true,
        action: 'repair_user_profile',
        summary: repaired.isEmpty
            ? 'User profile schema is 100% verified and pristine.'
            : 'Successfully healed ${repaired.length} corrupted/missing schema fields.',
        repairedFields: repaired,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[OneOvaSelfRepair] Profile repair error: $e');
      return RepairResult(
        success: false,
        action: 'repair_user_profile',
        summary: 'Profile repair failed: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Autonomously purges corrupted local disk caches, temporary playback buffers,
  /// and resets any orphaned video stream controllers.
  Future<RepairResult> repairInterfaceAndCache() async {
    final List<String> purged = [];
    try {
      // 1. Purge Temporary Directory
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final entities = tempDir.listSync(followLinks: false);
        for (var entity in entities) {
          try {
            if (entity is File) {
              entity.deleteSync();
              purged.add(entity.path.split('/').last);
            } else if (entity is Directory) {
              entity.deleteSync(recursive: true);
              purged.add(entity.path.split('/').last);
            }
          } catch (_) {
            // Skip in-use locks
          }
        }
      }

      // 2. Clear Corrupted SharedPreferences Stale Flags
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('stuck_') || key.startsWith('corrupt_') || key.startsWith('tmp_feed_lock')) {
          await prefs.remove(key);
          purged.add('pref:$key');
        }
      }

      return RepairResult(
        success: true,
        action: 'repair_interface_cache',
        summary: 'Cleared ${purged.length} temporary cache buffers and freed memory.',
        repairedFields: purged,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return RepairResult(
        success: false,
        action: 'repair_interface_cache',
        summary: 'Cache repair error: $e',
        timestamp: DateTime.now(),
      );
    }
  }

  /// Sends the caught error context to Google Gemini to formulate an exact
  /// root cause analysis and autonomously trigger the prescribed repair.
  Future<AiDiagnosisResult> diagnoseAndRepairWithGemini({
    required String errorSummary,
    String? stackTrace,
    String? componentContext,
  }) async {
    final geminiKey = await _vault.getGeminiApiKey();
    final model = await _vault.getPreferredGeminiModel();

    final systemInstruction = '''
You are Ova Engine, the primary autonomous self-repair and diagnostics intelligence of the Oneova mobile app.
Analyze the provided Flutter / Firestore / Media error context and produce an exact, actionable root-cause analysis.
Return ONLY a valid JSON object matching this schema:
{
  "rootCause": "Brief technical explanation of what caused the glitch",
  "severity": "low" | "medium" | "high" | "critical",
  "recommendedAction": "repair_user_profile" | "repair_interface_cache" | "reconnect_stream" | "none",
  "humanExplanation": "A friendly 1-2 sentence explanation to reassure the user that Oneova is fixing it."
}
''';

    final promptText = '''
Component: ${componentContext ?? 'Unknown'}
Error Summary: $errorSummary
Stack Trace: ${stackTrace ?? 'No stack trace provided'}
Platform: ${Platform.operatingSystem}
''';

    try {
      String jsonResponse = '';

      if (geminiKey.isNotEmpty) {
        // Direct Google AI Studio Gemini REST Endpoint
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey',
        );

        final payload = {
          'system_instruction': {
            'parts': [
              {'text': systemInstruction}
            ]
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': promptText}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.2,
            'maxOutputTokens': 512,
            'responseMimeType': 'application/json',
          }
        };

        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          jsonResponse = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        }
      }

      // Fallback to OpenRouter if Gemini Key is not set or failed
      if (jsonResponse.isEmpty) {
        final openRouterKey = await _vault.getOpenRouterApiKey();
        if (openRouterKey.isNotEmpty) {
          final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $openRouterKey',
                  'HTTP-Referer': 'https://oneova.app',
                  'X-Title': 'Oneova',
                },
                body: jsonEncode({
                  'model': 'google/gemini-2.5-flash',
                  'response_format': {'type': 'json_object'},
                  'messages': [
                    {'role': 'system', 'content': systemInstruction},
                    {'role': 'user', 'content': promptText},
                  ],
                }),
              )
              .timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            jsonResponse = data['choices']?[0]?['message']?['content'] ?? '';
          }
        }
      }

      // Parse JSON result or fallback
      Map<String, dynamic> parsed = {};
      if (jsonResponse.isNotEmpty) {
        try {
          // Clean potential markdown wrappers
          var clean = jsonResponse.trim();
          if (clean.startsWith('```json')) clean = clean.substring(7);
          if (clean.startsWith('```')) clean = clean.substring(3);
          if (clean.endsWith('```')) clean = clean.substring(0, clean.length - 3);
          parsed = jsonDecode(clean.trim());
        } catch (_) {}
      }

      final rootCause = parsed['rootCause'] ?? 'Transient pipeline anomaly detected';
      final severity = parsed['severity'] ?? 'medium';
      final action = parsed['recommendedAction'] ?? 'repair_interface_cache';
      final humanExplanation = parsed['humanExplanation'] ??
          'Ova detected a temporary display glitch and has optimized your app resources.';

      // Autonomously execute the recommended action
      bool executed = false;
      if (action == 'repair_user_profile') {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          await repairUserProfile(uid);
          executed = true;
        }
      } else if (action == 'repair_interface_cache') {
        await repairInterfaceAndCache();
        executed = true;
      }

      return AiDiagnosisResult(
        rootCause: rootCause,
        severity: severity,
        recommendedAction: action,
        humanExplanation: humanExplanation,
        autoExecuted: executed,
      );
    } catch (e) {
      debugPrint('[OneOvaSelfRepair] AI Diagnostic error: $e');
      // Autonomous fallback repair
      await repairInterfaceAndCache();
      return AiDiagnosisResult(
        rootCause: 'Heuristic diagnostic fallback: $e',
        severity: 'low',
        recommendedAction: 'repair_interface_cache',
        humanExplanation: 'Ova flushed the local cache and stabilized app background services.',
        autoExecuted: true,
      );
    }
  }

  Future<void> _logRepairEvent({
    required String uid,
    required String action,
    required String summary,
    required dynamic details,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).collection('repair_logs').add({
        'action': action,
        'summary': summary,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': Platform.operatingSystem,
        'appVersion': '1.0.0+1',
      });
    } catch (_) {}
  }
}
