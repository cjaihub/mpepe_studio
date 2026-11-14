import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../security/oneova_ai_gateway.dart';
import 'algorithm/oneova_algorithm_models.dart';
import 'algorithm/online_feature_store.dart';

/// Learns what a person likes from their own Ova conversations, quietly in the
/// background, so their feed (Reels, Live, Shops) fits them. On by default;
/// Settings → Privacy → Personalisation turns it off, shows what was learned and
/// resets it. Disclosed in docs/policies/PRIVACY_POLICY.md.
///
/// Private to the person: only short topic words ("cooking", "arsenal") are kept,
/// in users/{uid}/algorithmic_state/current (owner-only by Firestore rules). The
/// conversations themselves are never stored for this and never shared with
/// anyone or used to train a shared model. Sensitive subjects are never learned.
class OvaTasteLearner {
  OvaTasteLearner._();
  static final OvaTasteLearner instance = OvaTasteLearner._();

  static const int _batch = 6;
  static const int _maxTopics = 8;

  /// Learned only after the person's explicit opt-in (special categories under
  /// GDPR / Kenya DPA / NDPA: health, religion, politics; plus money).
  static final RegExp _optInOnly = RegExp(
    r'(health|ill|disease|medic|diagnos|pregnan|hiv|cancer|mental|depress|therap|fitness|religio|church|mosque|islam|christian|muslim|gospel|pray|politic|party|vote|election|union|debt|loan|salary|bank|money|finance|invest|budget)',
    caseSensitive: false,
  );

  /// Never learned, even with consent (too identifying or too risky).
  static final RegExp _neverLearn = RegExp(
    r'(sex|gay|lesbian|lgbt|bisexual|queer|trans|porn|nude|naked|nsfw|xxx|onlyfans|erotic|adult|hookup|ethnic|tribe|race|crim|arrest|password|address)',
    caseSensitive: false,
  );

  final List<String> _buffer = [];
  OnlineFeatureStore? _store;
  AppLifecycleListener? _life;
  bool _busy = false;
  bool? _enabledCache;
  String? _enabledFor;
  bool? _sensitiveCache;

  /// Called once with the app's feature store so learned topics reach ranking.
  void attach(OnlineFeatureStore store) {
    _store = store;
    _life ??= AppLifecycleListener(onHide: () => unawaited(_flush()));
  }

  DocumentReference<Map<String, dynamic>>? _doc() {
    if (Firebase.apps.isEmpty) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('algorithmic_state').doc('current');
  }

  Future<bool> enabled() async {
    final d = _doc();
    if (d == null) return false;
    if (_enabledFor == d.path && _enabledCache != null) return _enabledCache!;
    try {
      final s = await d.get();
      _enabledCache = s.data()?['personalizationEnabled'] != false; // on until turned off
    } catch (_) {
      _enabledCache = true;
    }
    _enabledFor = d.path;
    return _enabledCache!;
  }

  Future<void> setEnabled(bool on) async {
    final d = _doc();
    if (d == null) return;
    _enabledCache = on;
    _enabledFor = d.path;
    if (!on) _buffer.clear();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _store?.setOptedOut(uid, !on);
    await d.set({'personalizationEnabled': on}, SetOptions(merge: true));
  }

  /// "Include sensitive topics" (health, religion, politics, money): off until
  /// the person explicitly turns it on; the consent time is kept.
  Future<bool> sensitiveAllowed() async {
    final d = _doc();
    if (d == null) return false;
    if (_enabledFor == d.path && _sensitiveCache != null) return _sensitiveCache!;
    try {
      _sensitiveCache = (await d.get()).data()?['sensitiveTopicsConsent'] == true;
    } catch (_) {
      _sensitiveCache = false;
    }
    return _sensitiveCache!;
  }

  Future<void> setSensitiveAllowed(bool on) async {
    final d = _doc();
    if (d == null) return;
    _sensitiveCache = on;
    await d.set({
      'sensitiveTopicsConsent': on,
      'sensitiveTopicsConsentAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (on) return;
    // Consent withdrawn: forget every sensitive topic already learned.
    try {
      final data = (await d.get()).data() ?? const {};
      final keys = <String>{
        for (final m in [data['ovaTopics'], data['topicAffinities']])
          if (m is Map) ...m.keys.map((k) => k.toString()).where((k) => _optInOnly.hasMatch(k)),
      };
      for (final k in keys) {
        await forget(k);
      }
    } catch (e) {
      debugPrint('[OvaTasteLearner] withdraw: $e');
    }
  }

  /// One finished Ova turn (chat or voice). Cheap: just buffered in memory.
  void observe(String query, String response) {
    final q = query.trim();
    if (q.length < 4) return;
    _buffer.add('User: ${q.length > 400 ? q.substring(0, 400) : q}\nOva: ${response.length > 200 ? response.substring(0, 200) : response}');
    if (_buffer.length >= _batch) unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_busy || _buffer.isEmpty) return;
    final d = _doc();
    if (d == null || !await enabled()) {
      _buffer.clear();
      return;
    }
    _busy = true;
    final batch = List<String>.from(_buffer);
    _buffer.clear();
    try {
      final topics = await _extract(batch.join('\n---\n'), allowSensitive: await sensitiveAllowed());
      if (topics.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final store = _store;
      if (store != null) {
        store.recordConversationalSignal(ChatConversationalSignal(userId: uid, extractedTopics: topics, timestamp: DateTime.now()));
        await store.flushProfile(uid);
      }
      await d.set({
        'ovaTopics': {for (final t in topics) t: FieldValue.increment(1)},
        'ovaTopicsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[OvaTasteLearner] $e');
    } finally {
      _busy = false;
    }
  }

  Future<List<String>> _extract(String transcript, {required bool allowSensitive}) async {
    if (!OneovaAiGateway.canCall('')) return const [];
    final res = await http
        .post(
          OneovaAiGateway.chatUri(''),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${await OneovaAiGateway.bearer('')}',
            'X-Title': 'Oneova',
            ...await OneovaAiGateway.appCheckHeader(''),
          },
          body: jsonEncode({
            'model': 'google/gemini-2.5-flash',
            'temperature': 0,
            'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'system',
                'content': 'From this person\'s chats with their assistant, list up to $_maxTopics things they enjoy or want to see '
                    'on a short-video, live and shopping app, as lowercase single words or short hashtags without "#" '
                    '(for example "cooking", "afrobeats", "arsenal", "sneakers"). Only clear interests. '
                    '${allowSensitive ? 'They allowed interests about health, faith, politics and money (for example "fitness", "gospel", "budgeting"); include those only when they clearly want content about them. ' : 'Never include health, religion, politics or money. '}'
                    'Never include sexuality or sexual or adult content, ethnicity, crime or anything that identifies them. '
                    'Return JSON: {"topics": ["..."]}. Return {"topics": []} if none.',
              },
              {'role': 'user', 'content': transcript},
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return const [];
    final content = jsonDecode(res.body)['choices']?[0]?['message']?['content'];
    if (content is! String) return const [];
    return cleanTopics(jsonDecode(content)['topics'], allowSensitive: allowSensitive);
  }

  /// Lowercase, short, at most [_maxTopics]. Sensitive subjects only with
  /// [allowSensitive]; never-learn subjects never. Public for tests.
  @visibleForTesting
  static List<String> cleanTopics(Object? raw, {bool allowSensitive = false}) {
    if (raw is! List) return const [];
    final out = <String>{};
    for (final t in raw) {
      if (t is! String) continue;
      final c = t.trim().toLowerCase().replaceAll('#', '').replaceAll(RegExp(r'[^a-z0-9_]'), ''); // hashtag form, so it matches reels' tags
      if (c.length < 2 || c.length > 30 || _neverLearn.hasMatch(c)) continue;
      if (!allowSensitive && _optInOnly.hasMatch(c)) continue;
      out.add(c);
      if (out.length >= _maxTopics) break;
    }
    return out.toList();
  }

  /// Removes one learned topic everywhere it is used for ranking.
  Future<void> forget(String topic) async {
    final d = _doc();
    if (d == null) return;
    await d.update({
      FieldPath(['topicAffinities', topic]): FieldValue.delete(),
      FieldPath(['ovaTopics', topic]): FieldValue.delete(),
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _store?.forgetTopic(uid, topic);
  }

  /// Clears everything learned (Ova topics and watch-based tastes).
  Future<void> resetAll() async {
    final d = _doc();
    if (d == null) return;
    _buffer.clear();
    await d.set({
      'topicAffinities': FieldValue.delete(),
      'authorAffinities': FieldValue.delete(),
      'ovaTopics': FieldValue.delete(),
      'resetAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _store?.resetProfile(uid);
  }
}
