import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../create/studio/models/studio_project.dart';

/// A one-tap look: a filter at an intensity plus adjustments (StudioAdjust
/// keys: exposure, brightness, contrast, saturation, warmth, tint, fade,
/// highlights, shadows, whites, blacks, vibrance, sharpen, grain, vignette)
/// and beauty (skin smoothing). Applies the same way in the camera and the
/// editor.
@immutable
class OneovaPreset {
  final String id;
  final String name;
  final String filterId;
  final double intensity;
  final Map<String, double> adjust;
  final double beauty;
  final bool builtIn;

  const OneovaPreset({
    required this.id,
    required this.name,
    this.filterId = 'none',
    this.intensity = 1,
    this.adjust = const {},
    this.beauty = 0,
    this.builtIn = false,
  });

  StudioAdjust applyTo(StudioAdjust base) {
    var a = base;
    for (final k in StudioAdjust.keys) {
      a = a.withValue(k, (adjust[k] ?? 0).clamp(-1.0, 1.0).toDouble());
    }
    return a;
  }

  /// This preset on a Studio clip (beauty goes to the skin retouch).
  StudioClip applyToClip(StudioClip c) => c.copyWith(
        lookId: filterId,
        lookIntensity: intensity,
        adjust: applyTo(c.adjust),
        retouch: c.isImage || beauty > 0 || c.retouch.smooth > 0 ? c.retouch.withValue('smooth', beauty) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filterId': filterId,
        'intensity': intensity,
        'adjust': adjust,
        'beauty': beauty,
      };

  static OneovaPreset? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String) return null;
    final adj = <String, double>{};
    final a = raw['adjust'];
    if (a is Map) {
      for (final e in a.entries) {
        if (e.key is String && StudioAdjust.keys.contains(e.key) && e.value is num) adj[e.key as String] = (e.value as num).toDouble();
      }
    }
    return OneovaPreset(
      id: raw['id'] as String,
      name: raw['name'] as String,
      filterId: raw['filterId'] as String? ?? 'none',
      intensity: (raw['intensity'] as num?)?.toDouble() ?? 1,
      adjust: adj,
      beauty: (raw['beauty'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Built-in Oneova presets plus the user's own (Firestore
/// `users/{uid}/camera_presets`, mirrored on the phone so saving works
/// offline) and favourites (`users/{uid}/preset_favourites`).
class OneovaPresets extends ChangeNotifier {
  OneovaPresets._();
  static final OneovaPresets instance = OneovaPresets._();

  static const builtIns = <OneovaPreset>[
    OneovaPreset(id: 'p_glow_up', name: 'Glow Up', filterId: 'ov_honey_skin', intensity: 0.8, beauty: 0.45, adjust: {'brightness': 0.08, 'contrast': 0.05}, builtIn: true),
    OneovaPreset(id: 'p_melanin_luxe', name: 'Melanin Luxe', filterId: 'ov_bronze', intensity: 0.85, beauty: 0.3, adjust: {'shadows': 0.12, 'vibrance': 0.1}, builtIn: true),
    OneovaPreset(id: 'p_soft_studio', name: 'Soft Studio', filterId: 'ov_velvet', intensity: 0.9, beauty: 0.55, adjust: {'brightness': 0.06, 'contrast': -0.05}, builtIn: true),
    OneovaPreset(id: 'p_clean_daylight', name: 'Clean Daylight', filterId: 'ov_daylight', intensity: 1, adjust: {'exposure': 0.05, 'sharpen': 0.15}, builtIn: true),
    OneovaPreset(id: 'p_movie_night', name: 'Movie Night', filterId: 'ov_marquee', intensity: 0.9, adjust: {'contrast': 0.12, 'vignette': 0.2}, builtIn: true),
    OneovaPreset(id: 'p_after_hours', name: 'After Hours', filterId: 'ov_afterdark', intensity: 0.85, adjust: {'shadows': 0.15, 'grain': 0.1}, builtIn: true),
    OneovaPreset(id: 'p_film_diary', name: 'Film Diary', filterId: 'ov_emulsion', intensity: 1, adjust: {'fade': 0.1, 'grain': 0.2}, builtIn: true),
    OneovaPreset(id: 'p_old_roll', name: 'Old Roll', filterId: 'ov_expired_roll', intensity: 0.85, adjust: {'warmth': 0.1, 'vignette': 0.25}, builtIn: true),
    OneovaPreset(id: 'p_beach_day', name: 'Beach Day', filterId: 'ov_zanzibar', intensity: 1, adjust: {'brightness': 0.06, 'vibrance': 0.12}, builtIn: true),
    OneovaPreset(id: 'p_golden_walk', name: 'Golden Walk', filterId: 'ov_sunset_strip', intensity: 0.9, adjust: {'highlights': -0.15, 'warmth': 0.08}, builtIn: true),
    OneovaPreset(id: 'p_kilima_morning', name: 'Kilima Morning', filterId: 'ov_kilima_gold', intensity: 0.8, adjust: {'exposure': 0.08, 'shadows': 0.1}, builtIn: true),
    OneovaPreset(id: 'p_green_escape', name: 'Green Escape', filterId: 'ov_canopy', intensity: 1, adjust: {'vibrance': 0.1, 'sharpen': 0.1}, builtIn: true),
    OneovaPreset(id: 'p_city_pulse', name: 'City Pulse', filterId: 'ov_city_lights', intensity: 1, adjust: {'contrast': 0.1, 'shadows': 0.12}, builtIn: true),
    OneovaPreset(id: 'p_neon_party', name: 'Neon Party', filterId: 'ov_cyberglow', intensity: 0.85, beauty: 0.2, adjust: {'contrast': 0.08}, builtIn: true),
    OneovaPreset(id: 'p_food_fresh', name: 'Food Fresh', filterId: 'ov_fresh_market', intensity: 1, adjust: {'brightness': 0.05, 'saturation': 0.1, 'sharpen': 0.2}, builtIn: true),
    OneovaPreset(id: 'p_brunch_light', name: 'Brunch Light', filterId: 'ov_brunch', intensity: 0.9, adjust: {'warmth': 0.05, 'fade': 0.05}, builtIn: true),
    OneovaPreset(id: 'p_pastel_dream', name: 'Pastel Dream', filterId: 'ov_cotton_candy', intensity: 0.85, beauty: 0.3, adjust: {'brightness': 0.08}, builtIn: true),
    OneovaPreset(id: 'p_wedding_ivory', name: 'Wedding Ivory', filterId: 'ov_ivory', intensity: 1, beauty: 0.4, adjust: {'highlights': -0.1, 'shadows': 0.08}, builtIn: true),
    OneovaPreset(id: 'p_moody_storm', name: 'Moody Storm', filterId: 'ov_storm', intensity: 0.9, adjust: {'contrast': 0.1, 'fade': 0.06}, builtIn: true),
    OneovaPreset(id: 'p_street_grit', name: 'Street Grit', filterId: 'ov_grit', intensity: 0.8, adjust: {'sharpen': 0.25, 'vignette': 0.2}, builtIn: true),
    OneovaPreset(id: 'p_classic_mono', name: 'Classic Mono', filterId: 'ov_silver_screen', intensity: 1, adjust: {'contrast': 0.1, 'grain': 0.12}, builtIn: true),
    OneovaPreset(id: 'p_ink_portrait', name: 'Ink Portrait', filterId: 'ov_ink', intensity: 0.9, beauty: 0.3, adjust: {'shadows': 0.1}, builtIn: true),
    OneovaPreset(id: 'p_safari_trip', name: 'Safari Trip', filterId: 'ov_safari', intensity: 1, adjust: {'warmth': 0.06, 'sharpen': 0.15}, builtIn: true),
    OneovaPreset(id: 'p_kanga_pop', name: 'Kanga Pop', filterId: 'ov_kanga', intensity: 0.9, adjust: {'vibrance': 0.1, 'contrast': 0.06}, builtIn: true),
  ];

  static const _localKey = 'oneova_user_presets';
  static const _favKey = 'oneova_preset_favourites';

  List<OneovaPreset> _mine = const [];
  Set<String> _favs = const {};
  bool _loaded = false;

  List<OneovaPreset> get mine => _mine;
  bool isFavourite(String id) => _favs.contains(id);
  List<OneovaPreset> get favourites => [...all.where((p) => _favs.contains(p.id))];
  List<OneovaPreset> get all => [..._mine, ...builtIns];

  OneovaPreset? byId(String id) => all.where((p) => p.id == id).firstOrNull;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  CollectionReference<Map<String, dynamic>>? _col(String name) {
    final uid = _uid;
    return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).collection(name);
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_localKey);
      if (raw != null) {
        _mine = [for (final m in (jsonDecode(raw) as List)) ?OneovaPreset.fromJson(m)];
      }
      _favs = (p.getStringList(_favKey) ?? const []).toSet();
      notifyListeners();
    } catch (e) {
      debugPrint('[Presets] local load failed: $e');
    }
    // The account copy wins: presets follow the user to a new phone.
    try {
      final col = _col('camera_presets');
      final favCol = _col('preset_favourites');
      if (col == null || favCol == null) return;
      final q = await col.orderBy('updatedAt', descending: true).limit(200).get();
      final remote = [for (final d in q.docs) ?OneovaPreset.fromJson(d.data())];
      final ids = remote.map((p) => p.id).toSet();
      // Presets saved here while offline are pushed up.
      final localOnly = _mine.where((p) => !ids.contains(p.id)).toList();
      _mine = [...remote, ...localOnly];
      for (final p in localOnly) {
        unawaited(_push(p));
      }
      final f = await favCol.get();
      _favs = {..._favs, ...f.docs.map((d) => d.id)};
      await _saveLocal();
      notifyListeners();
    } catch (e) {
      debugPrint('[Presets] account sync failed (kept on this phone): $e');
    }
  }

  Future<void> _saveLocal() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_localKey, jsonEncode([for (final m in _mine) m.toJson()]));
      await p.setStringList(_favKey, _favs.toList());
    } catch (_) {}
  }

  Future<void> _push(OneovaPreset p) async {
    final col = _col('camera_presets');
    if (col == null) return;
    await col.doc(p.id).set({
      ...p.toJson(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves a new preset from the current look; returns it.
  Future<OneovaPreset> save({
    required String name,
    required String filterId,
    required double intensity,
    required StudioAdjust adjust,
    required double beauty,
  }) async {
    final values = <String, double>{
      for (final k in StudioAdjust.keys)
        if (adjust.toJson()[k] is num && (adjust.toJson()[k] as num) != 0) k: (adjust.toJson()[k] as num).toDouble(),
    };
    final preset = OneovaPreset(
      id: 'u_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name.trim().isEmpty ? 'My preset' : name.trim().substring(0, name.trim().length.clamp(0, 40)),
      filterId: filterId,
      intensity: intensity,
      adjust: values,
      beauty: beauty,
    );
    _mine = [preset, ..._mine];
    notifyListeners();
    await _saveLocal();
    try {
      await _push(preset);
    } catch (e) {
      debugPrint('[Presets] saved on this phone only for now: $e');
    }
    return preset;
  }

  Future<void> delete(OneovaPreset p) async {
    if (p.builtIn) return;
    _mine = [..._mine.where((m) => m.id != p.id)];
    _favs = {..._favs}..remove(p.id);
    notifyListeners();
    await _saveLocal();
    try {
      await _col('camera_presets')?.doc(p.id).delete();
      await _col('preset_favourites')?.doc(p.id).delete();
    } catch (_) {}
  }

  Future<void> toggleFavourite(String id) async {
    final on = !_favs.contains(id);
    _favs = on ? {..._favs, id} : ({..._favs}..remove(id));
    notifyListeners();
    await _saveLocal();
    try {
      final doc = _col('preset_favourites')?.doc(id);
      if (doc == null) return;
      on ? await doc.set({'createdAt': FieldValue.serverTimestamp()}) : await doc.delete();
    } catch (_) {}
  }
}
