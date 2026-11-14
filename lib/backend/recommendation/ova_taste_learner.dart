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

  /// Never learned (special categories of personal data).
  static final RegExp _sensitive = RegExp(
    r'(health|ill|disease|medic|diagnos|pregnan|hiv|cancer|mental|depress|therap|sex|gay|lesbian|lgbt|trans|religio|church|mosque|islam|christian|muslim|pray|politic|party|vote|election|ethnic|tribe|race|union|crim|arrest|debt|loan|salary|bank|password|address)',
    caseSensitive: false,
  );

  final List<String> _buffer = [];
  OnlineFeatureStore? _store;
  AppLifecycleListener? _life;
  bool _busy = false;
  bool? _enabledCache;
  String? _enabledFor;

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
      final topics = await _extract(batch.join('\n---\n'));
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

  Future<List<String>> _extract(String transcript) async {
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
                    '(for example "cooking", "afrobeats", "arsenal", "sneakers"). Only clear interests. Never include health, '
                    'religion, politics, sexuality, ethnicity, money, crime or anything that identifies them. '
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
    return cleanTopics(jsonDecode(content)['topics']);
  }

  /// Lowercase, short, no sensitive subjects, at most [_maxTopics]. Public for tests.
  @visibleForTesting
  static List<String> cleanTopics(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>{};
    for (final t in raw) {
      if (t is! String) continue;
      final c = t.trim().toLowerCase().replaceAll('#', '').replaceAll(RegExp(r'[^a-z0-9_]'), ''); // hashtag form, so it matches reels' tags
      if (c.length < 2 || c.length > 30 || _sensitive.hasMatch(c)) continue;
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
