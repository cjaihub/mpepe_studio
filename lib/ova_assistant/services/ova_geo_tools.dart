import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/location/geo_services.dart';
import '../core/ova_tool_result.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d, [List<String>? e]) => {'type': 'string', 'description': d, 'enum': ?e};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};

/// Location tools: where am I, what is near me, navigate to a place, and
/// signal checks. Results carry an [OvaMapSpec], so Ova's answer shows a
/// live map that follows the user.
class OvaGeoTools {
  OvaGeoTools._();
  static final OvaGeoTools instance = OvaGeoTools._();

  GeoServices get _geo => GeoServices.instance;

  static const names = {'get_location', 'find_nearby', 'navigate_to', 'check_signal'};

  /// The newest position Ova saw, so follow-up questions have context.
  LatLng? lastKnown;
  String? lastAddress;

  List<OvaToolSpec> get specs => [
        OvaToolSpec('get_location', 'Find where the user is now. Shows a live map with their position, the address and their signal.'),
        OvaToolSpec(
          'find_nearby',
          'Find real places near the user (restaurants, cafes, ATMs, pharmacies, hospitals, fuel, hotels, Wi-Fi spots, or a name). '
              'Shows them highlighted on a live map with distance and whether they are open.',
          properties: {
            'what': _s('What to look for, e.g. "coffee", "pharmacy", "ATM", "Java House". Empty for anything useful nearby.'),
            'radius_m': _i('Search radius in metres (default 1500, max 5000)'),
          },
        ),
        OvaToolSpec(
          'navigate_to',
          'Plan a route from the user to a place or address and show it on a live map. The user can then tap Navigate for turn-by-turn in Google Maps.',
          properties: {
            'destination': _s('Place name or address'),
            'mode': _s('How they travel', ['driving', 'walking', 'cycling']),
          },
          required: ['destination'],
        ),
        OvaToolSpec('check_signal', "Read the phone's current network and signal strength."),
      ];

  Future<OvaToolResult> run(String name, Map<String, dynamic> a) async {
    String s(String k) => (a[k] ?? '').toString().trim();
    int i(String k, int d) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k)) ?? d;
    switch (name) {
      case 'get_location':
        return whereAmI();
      case 'find_nearby':
        return nearby(s('what'), radiusM: i('radius_m', 1500));
      case 'navigate_to':
        return navigate(s('destination'), mode: s('mode').isEmpty ? 'driving' : s('mode'));
      case 'check_signal':
        return checkSignal();
    }
    return OvaToolResult.fail('Unknown location action.');
  }

  static const _settings = OvaResultAction(label: 'Location settings', icon: Icons.settings_rounded, url: 'ova://location_settings');

  Future<(LatLng?, OvaToolResult?)> _here() async {
    final problem = await _geo.ensureReady();
    if (problem != null) {
      return (null, OvaToolResult(ok: false, summary: problem, icon: Icons.location_off_rounded, actions: const [_settings]));
    }
    try {
      final p = await _geo.current();
      final pt = LatLng(p.latitude, p.longitude);
      lastKnown = pt;
      return (pt, null);
    } catch (e) {
      return (null, OvaToolResult.fail('Could not get your location: $e', icon: Icons.location_off_rounded));
    }
  }

  String _signalLine(GeoSignal s) {
    if (s.network == 'offline' || !s.internet) return 'No internet right now.';
    if (s.strong) return 'Signal: ${s.label}.';
    return 'Signal: ${s.label}; calls and maps may be slow here.';
  }

  Future<OvaToolResult> whereAmI() async {
    final (me, err) = await _here();
    if (err != null) return err;
    final results = await Future.wait([_geo.reverse(me!), _geo.signal()]);
    final address = results[0] as String?;
    final signal = results[1] as GeoSignal;
    lastAddress = address;
    final coords = '${me.latitude.toStringAsFixed(5)}, ${me.longitude.toStringAsFixed(5)}';
    return OvaToolResult(
      ok: true,
      title: address ?? 'You are here',
      summary: 'User location: ${address ?? coords} ($coords). ${_signalLine(signal)}',
      icon: Icons.my_location_rounded,
      map: OvaMapSpec(me: me, signal: signal),
      actions: [
        OvaResultAction(label: "What's nearby", icon: Icons.near_me_rounded, prompt: "what's near me"),
        OvaResultAction(
          label: 'Share',
          icon: Icons.ios_share_rounded,
          prompt: 'share my location https://maps.google.com/?q=${me.latitude},${me.longitude}',
        ),
      ],
    );
  }

  Future<OvaToolResult> nearby(String what, {int radiusM = 1500}) async {
    final (me, err) = await _here();
    if (err != null) return err;
    List<GeoPlace> places;
    try {
      places = what.isEmpty || RegExp(r'^(places?|anything|stuff|things)$').hasMatch(what.toLowerCase())
          ? await _geo.nearby(me!, 'food', radiusM: radiusM)
          : await _geo.nearby(me!, what, radiusM: radiusM);
      if (places.isEmpty && what.isNotEmpty && GeoServices.categoryFor(what) == null) {
        places = (await _geo.search(what, near: me, limit: 6)).where((p) => (p.distanceM ?? 1e9) < 50000).toList();
      }
    } catch (e) {
      return OvaToolResult.fail('Nearby search failed: $e', icon: Icons.wifi_off_rounded);
    }
    final label = what.isEmpty ? 'places' : what;
    if (places.isEmpty) {
      return OvaToolResult(
        ok: true,
        summary: 'No $label found within ${formatDistance(radiusM.toDouble())} on OpenStreetMap.',
        icon: Icons.search_off_rounded,
        map: OvaMapSpec(me: me),
        actions: [
          if (radiusM < 5000)
            OvaResultAction(label: 'Search wider', icon: Icons.zoom_out_map_rounded, prompt: 'find $label within 5 km'),
        ],
      );
    }
    final lines = [
      for (var k = 0; k < places.length; k++)
        '${k + 1}. ${places[k].name} – ${formatDistance(places[k].distanceM ?? 0)}'
            '${places[k].openNow == true ? ' (open now)' : places[k].openNow == false ? ' (closed now)' : ''}'
            '${places[k].address != null ? ', ${places[k].address}' : ''}',
    ];
    return OvaToolResult(
      ok: true,
      title: '${places.length} ${label.toLowerCase()} near you',
      summary: 'Nearby $label:\n${lines.join('\n')}',
      icon: Icons.near_me_rounded,
      map: OvaMapSpec(me: me, places: places),
      items: [
        for (var k = 0; k < places.length; k++)
          OvaResultItem(
            title: '${k + 1}. ${places[k].name}',
            subtitle: [
              formatDistance(places[k].distanceM ?? 0),
              if (places[k].openNow == true) 'Open now',
              if (places[k].openNow == false) 'Closed',
              ?places[k].category?.replaceAll('_', ' '),
            ].join(' · '),
            icon: Icons.place_rounded,
            onTap: OvaResultAction(label: 'Go', icon: Icons.directions_rounded, prompt: 'navigate to ${places[k].name}'),
          ),
      ],
    );
  }

  Future<OvaToolResult> navigate(String destination, {String mode = 'driving'}) async {
    if (destination.isEmpty) return OvaToolResult.fail('Where do you want to go?');
    final (me, err) = await _here();
    if (err != null) return err;
    GeoPlace? dest;
    try {
      final hits = await _geo.search(destination, near: me, limit: 5);
      dest = hits.isEmpty ? null : hits.first;
      if (dest == null) {
        // Maybe it is a nearby place type ("nearest pharmacy").
        final near = await _geo.nearby(me!, destination, radiusM: 3000, limit: 1);
        if (near.isNotEmpty) dest = near.first;
      }
    } catch (e) {
      return OvaToolResult.fail('Place search failed: $e', icon: Icons.wifi_off_rounded);
    }
    if (dest == null) {
      return OvaToolResult(ok: false, summary: 'I could not find "$destination" on the map.', icon: Icons.wrong_location_rounded);
    }
    final results = await Future.wait([_geo.route(me!, dest.point, mode: mode), _geo.signal()]);
    final route = results[0] as GeoRoute?;
    final signal = results[1] as GeoSignal;
    final navUrl = 'ova://navigate?lat=${dest.point.latitude}&lng=${dest.point.longitude}&mode=$mode';
    final how = switch (mode) { 'walking' => 'walk', 'cycling' => 'ride', _ => 'drive' };
    final summary = route == null
        ? '${dest.name} is ${formatDistance(_geo.distanceM(me, dest.point))} away (straight line). No route was available, Google Maps can still navigate. ${_signalLine(signal)}'
        : 'Route to ${dest.name}: ${formatDistance(route.distanceM)}, about ${formatDuration(route.durationS)} by $how. ${_signalLine(signal)}';
    return OvaToolResult(
      ok: true,
      title: route == null ? dest.name : '${dest.name} · ${formatDuration(route.durationS)} ($how)',
      summary: summary,
      icon: Icons.directions_rounded,
      map: OvaMapSpec(me: me, destination: dest, route: route, mode: mode, signal: signal),
      actions: [
        OvaResultAction(label: 'Navigate', icon: Icons.navigation_rounded, url: navUrl),
        if (mode != 'walking')
          OvaResultAction(label: 'Walk instead', icon: Icons.directions_walk_rounded, prompt: 'walk to ${dest.name}'),
        if (mode == 'walking')
          OvaResultAction(label: 'Drive instead', icon: Icons.directions_car_rounded, prompt: 'drive to ${dest.name}'),
      ],
    );
  }

  Future<OvaToolResult> checkSignal() async {
    final s = await _geo.signal();
    return OvaToolResult(
      ok: s.network != 'offline',
      summary: _signalLine(s),
      icon: s.network == 'offline'
          ? Icons.signal_cellular_off_rounded
          : s.network == 'wifi'
              ? Icons.wifi_rounded
              : Icons.signal_cellular_alt_rounded,
      actions: s.strong ? const [] : const [OvaResultAction(label: 'Network settings', icon: Icons.settings_rounded, url: 'ova://network_settings')],
    );
  }

  /// Context line for the system prompt (no lookup; uses what Ova saw).
  String contextLine() {
    final p = lastKnown;
    if (p == null) return 'Location not checked yet (use get_location when needed).';
    return 'Last known location: ${lastAddress ?? '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}'}.';
  }
}
