import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ova_assistant/services/ova_device_hub.dart';

/// One place or route stored in the user's Map & Location History.
class MapHistoryItem {
  final String id;
  final String title;
  final String? subtitle;
  final LatLng point;
  final String actionType; // 'fly' | 'route' | 'nearby' | 'search' | 'pin'
  final DateTime timestamp;

  const MapHistoryItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.point,
    this.actionType = 'search',
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subtitle': ?subtitle,
        'lat': point.latitude,
        'lng': point.longitude,
        'actionType': actionType,
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };

  factory MapHistoryItem.fromMap(Map<String, dynamic> m) {
    return MapHistoryItem(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] ?? 'Saved Place').toString(),
      subtitle: m['subtitle'] as String?,
      point: LatLng(
        ((m['lat'] as num?) ?? 0).toDouble(),
        ((m['lng'] as num?) ?? 0).toDouble(),
      ),
      actionType: (m['actionType'] ?? 'search').toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        ((m['timestampMs'] as num?) ?? DateTime.now().millisecondsSinceEpoch).toInt(),
      ),
    );
  }
}

/// Manages persistent Map & Location History (searches, "Fly Me There" targets,
/// routes, and nearby scans) synced to `users/{uid}/ova_context/map_history`.
class OneovaMapHistoryService {
  OneovaMapHistoryService._();
  static final OneovaMapHistoryService instance = OneovaMapHistoryService._();

  final List<MapHistoryItem> _items = [];
  bool _loaded = false;
  String? _loadedUid;
  Timer? _syncTimer;

  List<MapHistoryItem> get items => List.unmodifiable(_items);

  Future<void> warm() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_loaded && _loadedUid == uid) return;
    _loaded = true;
    _loadedUid = uid;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ova_context')
          .doc('map_history')
          .get();
      if (!doc.exists) return;
      final list = doc.data()?['items'] as List?;
      if (list == null) return;
      final existing = _items.map((x) => x.id).toSet();
      for (final raw in list) {
        if (raw is Map) {
          final item = MapHistoryItem.fromMap(Map<String, dynamic>.from(raw));
          if (item.title.isNotEmpty && existing.add(item.id)) {
            _items.add(item);
          }
        }
      }
      _items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (_items.length > 35) _items.removeRange(35, _items.length);
    } catch (_) {}
  }

  void record({
    required String title,
    String? subtitle,
    required LatLng point,
    String actionType = 'search',
  }) {
    final clean = title.trim();
    if (clean.isEmpty) return;
    final key = '${clean.toLowerCase()}_${point.latitude.toStringAsFixed(3)}_${point.longitude.toStringAsFixed(3)}';
    _items.removeWhere((e) => e.id == key || e.title.toLowerCase() == clean.toLowerCase());
    _items.insert(
      0,
      MapHistoryItem(
        id: key,
        title: clean,
        subtitle: subtitle,
        point: point,
        actionType: actionType,
        timestamp: DateTime.now(),
      ),
    );
    if (_items.length > 35) _items.removeRange(35, _items.length);
    _scheduleSync();
  }

  Future<void> clear() async {
    _items.clear();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ova_context')
          .doc('map_history')
          .set({'items': const [], 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 3), () async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('ova_context')
            .doc('map_history')
            .set({
          'updatedAt': FieldValue.serverTimestamp(),
          'items': _items.take(30).map((e) => e.toMap()).toList(),
        }, SetOptions(merge: true));
      } catch (_) {}
    });
  }
}

/// A real place from OpenStreetMap (Nominatim search or Overpass nearby).
class GeoPlace {
  final String name;
  final LatLng point;
  final String? category;
  final String? address;

  /// Straight-line distance from the user in metres, when known.
  final double? distanceM;

  /// Open now, from the OSM `opening_hours` tag when it is simple enough to read.
  final bool? openNow;

  const GeoPlace({
    required this.name,
    required this.point,
    this.category,
    this.address,
    this.distanceM,
    this.openNow,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'lat': point.latitude,
        'lng': point.longitude,
        'category': ?category,
        'address': ?address,
        'distanceM': ?distanceM,
        'openNow': ?openNow,
      };
}

/// One turn-by-turn maneuver step along a [GeoRoute].
class GeoRouteStep {
  final String instruction;
  final String maneuverType;
  final String? modifier;
  final double distanceM;
  final double durationS;
  final LatLng location;
  final String? streetName;

  const GeoRouteStep({
    required this.instruction,
    required this.maneuverType,
    this.modifier,
    required this.distanceM,
    required this.durationS,
    required this.location,
    this.streetName,
  });
}

/// A route from OSRM (OpenStreetMap routing).
class GeoRoute {
  final List<LatLng> points;
  final double distanceM;
  final double durationS;
  final String mode;
  final List<GeoRouteStep> steps;

  const GeoRoute({
    required this.points,
    required this.distanceM,
    required this.durationS,
    required this.mode,
    this.steps = const [],
  });
}

/// Network signal at a moment, read from the phone (Android) or connectivity.
class GeoSignal {
  /// wifi, cellular, ethernet, offline, other
  final String network;

  /// 0 (none) to 4 (great), or null when the phone does not say.
  final int? level;

  /// True when Android has validated the connection reaches the internet.
  final bool internet;

  const GeoSignal({required this.network, this.level, this.internet = true});

  String get label {
    if (network == 'offline') return 'No signal';
    final n = switch (network) { 'wifi' => 'Wi-Fi', 'cellular' => 'Mobile', 'ethernet' => 'Ethernet', _ => 'Network' };
    if (!internet) return '$n · no internet';
    final l = level;
    if (l == null) return n;
    return '$n · ${const ['none', 'weak', 'fair', 'good', 'strong'][l.clamp(0, 4)]}';
  }

  /// True when the connection is good enough for calls and maps.
  bool get strong => network != 'offline' && internet && (level == null || level! >= 3);
}

String formatDistance(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)} km';

String formatDuration(double s) {
  final mins = (s / 60).round();
  if (mins < 60) return '$mins min';
  return '${mins ~/ 60} h ${mins % 60} min';
}

/// Location, place search, nearby places, routing and signal for the whole app.
/// Uses free OpenStreetMap services, so no API key is needed.
class GeoServices {
  GeoServices._();
  static final GeoServices instance = GeoServices._();

  static const _ua = 'Oneova/1.0 (com.oneova.app)';
  static const _distance = Distance();

  // ── Location ───────────────────────────────────────────────────────────

  /// Asks for permission if needed. Returns a reason string when location
  /// cannot be used, or null when it is ready.
  Future<String?> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) return 'Location is turned off on this phone.';
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied) return 'Location permission was not given.';
    if (p == LocationPermission.deniedForever) return 'Location is blocked for Oneova. Turn it on in Settings.';
    return null;
  }

  Future<Position> current() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      rethrow;
    }
  }

  // geolocator keeps ONE platform position stream per app and ignores the
  // settings of later callers, so every map and live share listens here and
  // the platform stream is restarted only when background mode changes.
  final Set<_Tracker> _trackers = {};
  StreamSubscription<Position>? _platformSub;
  bool _platformBackground = false;
  Position? _lastPosition;

  /// Live position updates. [background] keeps updates going with a
  /// notification while the app is in the background (Android).
  /// [distanceFilterM] is applied per listener.
  Stream<Position> track({int distanceFilterM = 10, bool background = false, String? notificationText}) {
    late final _Tracker t;
    final c = StreamController<Position>();
    t = _Tracker(c, background, notificationText, distanceFilterM);
    c.onListen = () {
      _trackers.add(t);
      _syncPlatformStream();
      final last = _lastPosition;
      if (last != null) t.offer(last);
    };
    c.onCancel = () {
      _trackers.remove(t);
      _syncPlatformStream();
    };
    return c.stream;
  }

  void _syncPlatformStream() {
    if (_trackers.isEmpty) {
      _platformSub?.cancel();
      _platformSub = null;
      return;
    }
    final bg = _trackers.any((t) => t.background);
    if (_platformSub != null && bg == _platformBackground) return;
    _platformSub?.cancel();
    _platformBackground = bg;
    final text = _trackers.firstWhere((t) => t.background, orElse: () => _trackers.first).notificationText;
    _platformSub = Geolocator.getPositionStream(locationSettings: _settings(bg, text)).listen(
      (p) {
        _lastPosition = p;
        for (final t in _trackers.toList()) {
          t.offer(p);
        }
      },
      onError: (Object e) {
        for (final t in _trackers.toList()) {
          t.controller.addError(e);
        }
      },
    );
  }

  LocationSettings _settings(bool background, String? notificationText) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        intervalDuration: const Duration(seconds: 4),
        foregroundNotificationConfig: background
            ? ForegroundNotificationConfig(
                notificationTitle: 'Oneova is sharing your location',
                notificationText: notificationText ?? 'Live location is on',
                enableWakeLock: false,
                setOngoing: true,
              )
            : null,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: background,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3);
  }

  double distanceM(LatLng a, LatLng b) => _distance.as(LengthUnit.Meter, a, b);

  // ── Search (Google Maps Server Gateway -> Nominatim fallback) ──────────

  Future<List<GeoPlace>> search(String query, {LatLng? near, int limit = 5}) async {
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('mapsGateway');
        final res = await callable.call({
          'action': 'search',
          'query': query,
          if (near != null) 'lat': near.latitude,
          if (near != null) 'lng': near.longitude,
          'limit': limit,
        }).timeout(const Duration(seconds: 7));
        final data = res.data as Map?;
        final list = (data?['places'] as List?) ?? const [];
        if (list.isNotEmpty) {
          final out = <GeoPlace>[];
          for (final raw in list.whereType<Map>()) {
            final lat = (raw['lat'] as num?)?.toDouble();
            final lng = (raw['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) continue;
            final p = LatLng(lat, lng);
            out.add(
              GeoPlace(
                name: (raw['name'] ?? query).toString(),
                point: p,
                category: raw['category'] as String?,
                address: raw['address'] as String?,
                distanceM: near == null ? null : distanceM(near, p),
                openNow: raw['openNow'] as bool?,
              ),
            );
          }
          if (out.isNotEmpty) {
            if (near != null) out.sort((a, b) => a.distanceM!.compareTo(b.distanceM!));
            OneovaMapHistoryService.instance.record(
              title: out.first.name,
              subtitle: out.first.address,
              point: out.first.point,
              actionType: 'search',
            );
            return out;
          }
        }
      } catch (_) {}
    }

    final params = {
      'q': query,
      'format': 'jsonv2',
      'limit': '$limit',
      'addressdetails': '0',
      if (near != null) ...{
        // Prefer results around the user (about 50 km box), not exclusively.
        'viewbox': '${near.longitude - 0.5},${near.latitude + 0.5},${near.longitude + 0.5},${near.latitude - 0.5}',
      },
    };
    final res = await http
        .get(Uri.https('nominatim.openstreetmap.org', '/search', params), headers: {'User-Agent': _ua})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('Place search failed (${res.statusCode})');
    final list = jsonDecode(res.body) as List;
    final out = <GeoPlace>[];
    for (final e in list.cast<Map<String, dynamic>>()) {
      final lat = double.tryParse('${e['lat']}');
      final lng = double.tryParse('${e['lon']}');
      if (lat == null || lng == null) continue;
      final p = LatLng(lat, lng);
      final display = (e['display_name'] as String?) ?? '';
      final name = (e['name'] as String?)?.trim();
      out.add(GeoPlace(
        name: name == null || name.isEmpty ? display.split(',').first : name,
        point: p,
        category: e['type'] as String?,
        address: display,
        distanceM: near == null ? null : distanceM(near, p),
      ));
    }
    if (near != null) out.sort((a, b) => a.distanceM!.compareTo(b.distanceM!));
    if (out.isNotEmpty) {
      OneovaMapHistoryService.instance.record(
        title: out.first.name,
        subtitle: out.first.address,
        point: out.first.point,
        actionType: 'search',
      );
    }
    return out;
  }

  Future<String?> reverse(LatLng p) async {
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('mapsGateway');
        final res = await callable.call({
          'action': 'reverse',
          'lat': p.latitude,
          'lng': p.longitude,
        }).timeout(const Duration(seconds: 6));
        final addr = (res.data as Map?)?['address'] as String?;
        if (addr != null && addr.trim().isNotEmpty) return addr.trim();
      } catch (_) {}
    }
    try {
      final res = await http.get(
        Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'lat': '${p.latitude}',
          'lon': '${p.longitude}',
          'format': 'jsonv2',
          'zoom': '17',
        }),
        headers: {'User-Agent': _ua},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final a = (m['address'] as Map?)?.cast<String, dynamic>() ?? const {};
      final parts = <String>[
        for (final k in ['road', 'suburb', 'city', 'town', 'village', 'country'])
          if (a[k] is String && (a[k] as String).isNotEmpty) a[k] as String,
      ];
      if (parts.isEmpty) return m['display_name'] as String?;
      return parts.take(3).join(', ');
    } catch (_) {
      return null;
    }
  }

  // ── Nearby (Overpass) ──────────────────────────────────────────────────

  /// Plain-word category -> OSM tag filters.
  static const Map<String, List<String>> categories = {
    'restaurant': ['amenity=restaurant', 'amenity=fast_food'],
    'food': ['amenity=restaurant', 'amenity=fast_food', 'amenity=cafe'],
    'cafe': ['amenity=cafe'],
    'coffee': ['amenity=cafe'],
    'bar': ['amenity=bar', 'amenity=pub'],
    'hospital': ['amenity=hospital', 'amenity=clinic'],
    'pharmacy': ['amenity=pharmacy'],
    'atm': ['amenity=atm', 'amenity=bank'],
    'bank': ['amenity=bank'],
    'fuel': ['amenity=fuel'],
    'gas': ['amenity=fuel'],
    'parking': ['amenity=parking'],
    'supermarket': ['shop=supermarket', 'shop=convenience'],
    'shop': ['shop=supermarket', 'shop=mall', 'shop=convenience'],
    'mall': ['shop=mall'],
    'hotel': ['tourism=hotel', 'tourism=guest_house'],
    'gym': ['leisure=fitness_centre'],
    'park': ['leisure=park'],
    'police': ['amenity=police'],
    'school': ['amenity=school', 'amenity=university'],
    'church': ['amenity=place_of_worship'],
    'mosque': ['amenity=place_of_worship'],
    'bus': ['highway=bus_stop', 'amenity=bus_station'],
    'wifi': ['internet_access=wlan', 'internet_access=yes'],
    'cinema': ['amenity=cinema'],
    'toilet': ['amenity=toilets'],
  };

  static String? categoryFor(String text) {
    final t = text.toLowerCase();
    for (final k in categories.keys) {
      if (t.contains(k)) return k;
    }
    return null;
  }

  Future<List<GeoPlace>> nearby(LatLng at, String what, {int radiusM = 1500, int limit = 8}) async {
    final r = radiusM.clamp(200, 15000);
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('mapsGateway');
        final res = await callable.call({
          'action': 'nearby',
          'lat': at.latitude,
          'lng': at.longitude,
          'what': what.trim().isEmpty ? 'restaurant cafe shop' : what.trim(),
          'radiusM': r,
          'limit': limit,
        }).timeout(const Duration(seconds: 7));
        final data = res.data as Map?;
        final list = (data?['places'] as List?) ?? const [];
        if (list.isNotEmpty) {
          final out = <GeoPlace>[];
          for (final raw in list.whereType<Map>()) {
            final lat = (raw['lat'] as num?)?.toDouble();
            final lng = (raw['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) continue;
            final p = LatLng(lat, lng);
            out.add(
              GeoPlace(
                name: (raw['name'] ?? 'Place').toString(),
                point: p,
                category: raw['category'] as String?,
                address: raw['address'] as String?,
                distanceM: distanceM(at, p),
                openNow: raw['openNow'] as bool?,
              ),
            );
          }
          if (out.isNotEmpty) {
            out.sort((a, b) => a.distanceM!.compareTo(b.distanceM!));
            OneovaMapHistoryService.instance.record(
              title: what.trim().isEmpty ? "What's near me (${out.first.name})" : 'Nearby $what · ${out.first.name}',
              subtitle: out.first.address,
              point: out.first.point,
              actionType: 'nearby',
            );
            return out.take(limit).toList();
          }
        }
      } catch (_) {}
    }

    final cat = categoryFor(what);
    final osmR = radiusM.clamp(200, 5000);
    final filters = cat != null
        ? categories[cat]!.map((f) {
            final kv = f.split('=');
            return 'nwr["${kv[0]}"="${kv[1]}"](around:$osmR,${at.latitude},${at.longitude});';
          }).join()
        : 'nwr["name"~"${what.replaceAll('"', '')}",i](around:$osmR,${at.latitude},${at.longitude});';
    final q = '[out:json][timeout:15];($filters);out center 40;';
    final res = await http
        .post(Uri.parse('https://overpass-api.de/api/interpreter'), headers: {'User-Agent': _ua}, body: {'data': q})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Nearby search failed (${res.statusCode})');
    final els = ((jsonDecode(res.body) as Map<String, dynamic>)['elements'] as List? ?? const []).cast<Map<String, dynamic>>();
    final out = <GeoPlace>[];
    for (final e in els) {
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final name = tags['name'] as String?;
      if (name == null || name.trim().isEmpty) continue;
      final lat = (e['lat'] ?? (e['center'] as Map?)?['lat']) as num?;
      final lng = (e['lon'] ?? (e['center'] as Map?)?['lon']) as num?;
      if (lat == null || lng == null) continue;
      final p = LatLng(lat.toDouble(), lng.toDouble());
      final street = [tags['addr:street'], tags['addr:housenumber']].whereType<String>().join(' ');
      out.add(GeoPlace(
        name: name,
        point: p,
        category: (tags['amenity'] ?? tags['shop'] ?? tags['tourism'] ?? tags['leisure']) as String?,
        address: street.isEmpty ? null : street,
        distanceM: distanceM(at, p),
        openNow: _openNow(tags['opening_hours'] as String?),
      ));
    }
    out.sort((a, b) => a.distanceM!.compareTo(b.distanceM!));
    final seen = <String>{};
    final result = out.where((p) => seen.add(p.name.toLowerCase())).take(limit).toList();
    if (result.isNotEmpty) {
      OneovaMapHistoryService.instance.record(
        title: what.trim().isEmpty ? "What's near me (${result.first.name})" : 'Nearby $what · ${result.first.name}',
        subtitle: result.first.address,
        point: result.first.point,
        actionType: 'nearby',
      );
    }
    return result;
  }

  /// Reads only the simple, common forms ("24/7", "Mo-Su 08:00-22:00").
  /// Returns null when the hours are missing or too complex to be sure.
  static bool? _openNow(String? oh) {
    if (oh == null) return null;
    final s = oh.trim();
    if (s == '24/7') return true;
    final m = RegExp(r'^(?:Mo-Su\s+)?(\d{2}):(\d{2})-(\d{2}):(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final now = DateTime.now();
    final mins = now.hour * 60 + now.minute;
    final from = int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
    var to = int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!);
    if (to <= from) to += 24 * 60;
    final t = mins < from ? mins + 24 * 60 : mins;
    return t >= from && t < to;
  }

  // ── Routing (Google Maps Directions Gateway -> OSRM fallback) ──────────

  Future<GeoRoute?> route(LatLng from, LatLng to, {String mode = 'driving'}) async {
    if (FirebaseAuth.instance.currentUser != null) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('mapsGateway');
        final res = await callable.call({
          'action': 'route',
          'fromLat': from.latitude,
          'fromLng': from.longitude,
          'toLat': to.latitude,
          'toLng': to.longitude,
          'mode': mode,
        }).timeout(const Duration(seconds: 7));
        final rMap = (res.data as Map?)?['route'] as Map?;
        if (rMap != null) {
          final rawPts = (rMap['points'] as List?) ?? const [];
          final pts = <LatLng>[
            for (final pt in rawPts.whereType<Map>())
              LatLng(((pt['lat'] as num?) ?? 0).toDouble(), ((pt['lng'] as num?) ?? 0).toDouble()),
          ];
          if (pts.isNotEmpty) {
            final rawSteps = (rMap['steps'] as List?) ?? const [];
            final steps = <GeoRouteStep>[
              for (final st in rawSteps.whereType<Map>())
                GeoRouteStep(
                  instruction: (st['instruction'] ?? 'Continue').toString(),
                  maneuverType: (st['maneuverType'] ?? 'continue').toString(),
                  modifier: st['modifier'] as String?,
                  distanceM: ((st['distanceM'] as num?) ?? 0).toDouble(),
                  durationS: ((st['durationS'] as num?) ?? 0).toDouble(),
                  location: LatLng(
                    ((st['lat'] as num?) ?? to.latitude).toDouble(),
                    ((st['lng'] as num?) ?? to.longitude).toDouble(),
                  ),
                ),
            ];
            return GeoRoute(
              points: pts,
              distanceM: ((rMap['distanceM'] as num?) ?? distanceM(from, to)).toDouble(),
              durationS: ((rMap['durationS'] as num?) ?? 60).toDouble(),
              mode: mode,
              steps: steps,
            );
          }
        }
      } catch (_) {}
    }

    // Fallback: OpenStreetMap OSRM
    final profile = switch (mode) { 'walking' => 'routed-foot', 'cycling' => 'routed-bike', _ => 'routed-car' };
    final url = Uri.parse(
      'https://routing.openstreetmap.de/$profile/route/v1/driving/'
      '${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson&steps=true',
    );
    try {
      var res = await http.get(url, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        final fallbackUrl = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson&steps=true',
        );
        res = await http.get(fallbackUrl, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return null;
      }
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = m['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final r = routes.first as Map<String, dynamic>;
      final coords = ((r['geometry'] as Map)['coordinates'] as List).cast<List>();
      final parsedSteps = <GeoRouteStep>[];
      final legs = r['legs'] as List?;
      if (legs != null) {
        for (final leg in legs.whereType<Map>()) {
          final rawSteps = leg['steps'] as List?;
          if (rawSteps == null) continue;
          for (final st in rawSteps.whereType<Map>()) {
            final man = (st['maneuver'] as Map?)?.cast<String, dynamic>() ?? const {};
            final mType = (man['type'] ?? 'continue').toString();
            final mMod = man['modifier']?.toString();
            final locList = man['location'] as List?;
            final loc = (locList != null && locList.length >= 2)
                ? LatLng((locList[1] as num).toDouble(), (locList[0] as num).toDouble())
                : to;
            final road = (st['name'] ?? st['ref'] ?? '').toString().trim();
            final dist = ((st['distance'] as num?) ?? 0).toDouble();
            final dur = ((st['duration'] as num?) ?? 0).toDouble();
            final instr = _buildStepInstruction(mType, mMod, road);
            if (dist > 3 || mType == 'arrive' || mType == 'depart') {
              parsedSteps.add(
                GeoRouteStep(
                  instruction: instr,
                  maneuverType: mType,
                  modifier: mMod,
                  distanceM: dist,
                  durationS: dur,
                  location: loc,
                  streetName: road.isEmpty ? null : road,
                ),
              );
            }
          }
        }
      }
      return GeoRoute(
        points: [for (final c in coords) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())],
        distanceM: (r['distance'] as num).toDouble(),
        durationS: (r['duration'] as num).toDouble(),
        mode: mode,
        steps: parsedSteps,
      );
    } catch (e) {
      debugPrint('[GeoServices] route failed: $e');
      return null;
    }
  }

  static String _buildStepInstruction(String type, String? modifier, String road) {
    final onRoad = road.isNotEmpty ? ' onto $road' : '';
    final mod = (modifier ?? '').replaceAll('_', ' ').trim();
    switch (type) {
      case 'depart':
        return road.isNotEmpty ? 'Start on $road' : 'Head out on route';
      case 'arrive':
        return 'Arrive at destination';
      case 'roundabout':
      case 'rotary':
        return 'Take the roundabout$onRoad';
      case 'merge':
        return 'Merge ${mod.isNotEmpty ? mod : ''}$onRoad'.trim();
      case 'fork':
        return 'Keep ${mod.isNotEmpty ? mod : 'ahead'} at the fork$onRoad';
      case 'end of road':
        return 'At the end of the road, turn ${mod.isNotEmpty ? mod : 'ahead'}$onRoad';
      case 'new name':
      case 'continue':
        if (mod.isNotEmpty && mod != 'straight') {
          return 'Bear $mod$onRoad';
        }
        return road.isNotEmpty ? 'Continue on $road' : 'Continue straight';
      default:
        if (mod.isNotEmpty) {
          return 'Turn $mod$onRoad';
        }
        return road.isNotEmpty ? 'Proceed on $road' : 'Continue along route';
    }
  }

  /// Opens turn-by-turn navigation in Google Maps (or the browser if it is
  /// not installed).
  Future<bool> openNavigation(LatLng to, {String mode = 'driving', String? label}) async {
    final travel = switch (mode) { 'walking' => 'walking', 'cycling' => 'bicycling', 'transit' => 'transit', _ => 'driving' };
    if (!kIsWeb && Platform.isAndroid) {
      final m = switch (mode) { 'walking' => 'w', 'cycling' => 'b', _ => 'd' };
      final nav = Uri.parse('google.navigation:q=${to.latitude},${to.longitude}&mode=$m');
      try {
        if (await launchUrl(nav, mode: LaunchMode.externalApplication)) return true;
      } catch (_) {}
    }
    final web = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${to.latitude},${to.longitude}',
      'travelmode': travel,
      'dir_action': 'navigate',
    });
    return launchUrl(web, mode: LaunchMode.externalApplication);
  }

  Future<bool> openInMaps(LatLng p, {String? label}) {
    final q = label == null ? '${p.latitude},${p.longitude}' : '${p.latitude},${p.longitude} ($label)';
    return launchUrl(
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': q}),
      mode: LaunchMode.externalApplication,
    );
  }

  // ── Signal ─────────────────────────────────────────────────────────────

  /// Reads the phone's current network and signal level. On Android this
  /// comes from the system (Wi-Fi RSSI / cell level); elsewhere only the
  /// connection type is known.
  Future<GeoSignal> signal() async {
    if (OvaDeviceHub.supported) {
      try {
        final s = await OvaDeviceHub().deviceState();
        final level = s['signalLevel'];
        return GeoSignal(
          network: (s['network'] as String?) ?? 'other',
          level: level is num && level >= 0 ? level.toInt() : null,
          internet: s['internet'] != false,
        );
      } catch (_) {}
    }
    try {
      final r = await InternetAddress.lookup('one.one.one.one').timeout(const Duration(seconds: 4));
      return GeoSignal(network: 'other', internet: r.isNotEmpty);
    } catch (_) {
      return const GeoSignal(network: 'offline', internet: false);
    }
  }

  /// Bounds helper: a zoom that fits the given span (rough, for previews).
  static double zoomForSpan(double metres) {
    if (metres <= 0) return 16;
    return (math.log(40000000 / metres) / math.ln2 - 1).clamp(3, 17).toDouble();
  }
}

class _Tracker {
  final StreamController<Position> controller;
  final bool background;
  final String? notificationText;
  final int distanceFilterM;
  Position? _last;

  _Tracker(this.controller, this.background, this.notificationText, this.distanceFilterM);

  void offer(Position p) {
    final last = _last;
    if (last != null &&
        Geolocator.distanceBetween(last.latitude, last.longitude, p.latitude, p.longitude) < distanceFilterM) {
      return;
    }
    _last = p;
    if (!controller.isClosed) controller.add(p);
  }
}
