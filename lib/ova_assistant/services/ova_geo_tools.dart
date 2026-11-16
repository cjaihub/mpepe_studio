import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/location/geo_services.dart';
import '../../shared/location/oneova_map_view.dart';
import '../core/ova_tool_result.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d, [List<String>? e]) => {'type': 'string', 'description': d, 'enum': ?e};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};
Map<String, dynamic> _b(String d) => {'type': 'boolean', 'description': d};

/// Location tools: where am I, what is near me, navigate to a place with
/// live animated route + turn-by-turn directions, rotoscope contour highlighter,
/// WhatsApp-style live location sharing, and signal checks.
class OvaGeoTools {
  OvaGeoTools._();
  static final OvaGeoTools instance = OvaGeoTools._();

  GeoServices get _geo => GeoServices.instance;

  static const names = {
    'get_location',
    'find_nearby',
    'navigate_to',
    'fly_to_place',
    'map_history',
    'share_live_location',
    'check_signal',
  };

  /// The newest position Ova saw, so follow-up questions have context.
  LatLng? lastKnown;
  String? lastAddress;

  List<OvaToolSpec> get specs => [
        OvaToolSpec(
          'get_location',
          'Find where the user is now and auto-focus on their location. Shows a live map with their position, address, signal, and rotoscope highlighter.',
          properties: {
            'rotoscope': _b('Enable rotoscope contour highlighter on the map (default true)'),
          },
        ),
        OvaToolSpec(
          'find_nearby',
          'What\'s near me: find real places near the user (restaurants, cafes, ATMs, pharmacies, hospitals, fuel, hotels, Wi-Fi spots, or a name). '
              'Shows them highlighted on a live map with rotoscope target lock, distance, and whether they are open.',
          properties: {
            'what': _s('What to look for, e.g. "coffee", "pharmacy", "ATM", "Java House". Empty for anything useful nearby.'),
            'radius_m': _i('Search radius in metres (default 1500, max 5000)'),
            'rotoscope': _b('Highlight places with rotoscope contour glow (default true)'),
          },
        ),
        OvaToolSpec(
          'fly_to_place',
          'Fly the live map camera in real time to any place, city, landmark, or address with a smooth 3D-style aerial flight animation and rotoscope target lock.',
          properties: {
            'destination': _s('Place, landmark, city, or address to fly to'),
          },
          required: ['destination'],
        ),
        OvaToolSpec(
          'map_history',
          'Show the user\'s saved Map & Location History (places they searched, routed to, or flew to) with 1-tap Fly There and Route actions.',
        ),
        OvaToolSpec(
          'navigate_to',
          'Plan a live animated route with turn-by-turn street directions from the user to a place or address, '
              'with an in-app Start Live Directions button, Fly Me There, and Google Maps handoff.',
          properties: {
            'destination': _s('Place name or address'),
            'mode': _s('How they travel', ['driving', 'walking', 'cycling']),
            'start_navigation': _b('Start live turn-by-turn navigation immediately (default true when user says start/go)'),
            'rotoscope': _b('Enable rotoscope route & target highlighter (default true)'),
          },
          required: ['destination'],
        ),
        OvaToolSpec(
          'share_live_location',
          'Share the user\'s live moving location (WhatsApp-style live location for 15 min, 1 hour, or 8 hours) on a live map.',
          properties: {
            'duration_minutes': _i('Duration in minutes: 15, 60, or 480 (default 60)'),
          },
        ),
        OvaToolSpec('check_signal', "Read the phone's current network and signal strength."),
      ];

  Future<OvaToolResult> run(String name, Map<String, dynamic> a) async {
    String s(String k) => (a[k] ?? '').toString().trim();
    int i(String k, int d) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k)) ?? d;
    bool b(String k, bool d) => a[k] is bool ? a[k] as bool : (s(k).isEmpty ? d : s(k) == 'true');
    switch (name) {
      case 'get_location':
        return whereAmI(rotoscope: b('rotoscope', true));
      case 'find_nearby':
        return nearby(s('what'), radiusM: i('radius_m', 1500), rotoscope: b('rotoscope', true));
      case 'fly_to_place':
        return flyToPlace(s('destination'));
      case 'map_history':
        return showMapHistory();
      case 'navigate_to':
        return navigate(
          s('destination'),
          mode: s('mode').isEmpty ? 'driving' : s('mode'),
          startNavigation: b('start_navigation', false),
          rotoscope: b('rotoscope', true),
        );
      case 'share_live_location':
        return shareLiveLocation(durationMinutes: i('duration_minutes', 60));
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

  Future<OvaToolResult> whereAmI({bool rotoscope = true}) async {
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
      map: OvaMapSpec(me: me, signal: signal, rotoscopeHighlight: rotoscope),
      actions: [
        const OvaResultAction(label: "What's nearby", icon: Icons.near_me_rounded, prompt: "what's near me"),
        const OvaResultAction(label: 'Share Live 1h', icon: Icons.share_location_rounded, prompt: 'share my live location for 60 minutes'),
        OvaResultAction(
          label: 'Send Pin',
          icon: Icons.ios_share_rounded,
          prompt: 'share my location https://maps.google.com/?q=${me.latitude},${me.longitude}',
        ),
      ],
    );
  }

  Future<OvaToolResult> shareLiveLocation({int durationMinutes = 60}) async {
    final (me, err) = await _here();
    if (err != null) return err;
    final results = await Future.wait([_geo.reverse(me!), _geo.signal()]);
    final address = results[0] as String?;
    final signal = results[1] as GeoSignal;
    lastAddress = address;
    final mins = durationMinutes.clamp(15, 480);
    final label = mins >= 60 ? '${mins ~/ 60} hour${mins >= 120 ? 's' : ''}' : '$mins mins';
    return OvaToolResult(
      ok: true,
      title: 'Live Location Active · $label',
      summary: 'Sharing live GPS location at ${address ?? '${me.latitude.toStringAsFixed(5)}, ${me.longitude.toStringAsFixed(5)}'} for $label. ${_signalLine(signal)}',
      icon: Icons.share_location_rounded,
      map: OvaMapSpec(
        me: me,
        signal: signal,
        rotoscopeHighlight: true,
        liveShareMinutes: mins,
      ),
      actions: [
        OvaResultAction(
          label: 'Send Live Link',
          icon: Icons.send_rounded,
          prompt: 'share text 📍 Live Location ($label): https://maps.google.com/?q=${me.latitude},${me.longitude}',
        ),
        const OvaResultAction(label: "What's nearby", icon: Icons.near_me_rounded, prompt: "what's near me"),
      ],
    );
  }

  Future<OvaToolResult> flyToPlace(String destination) async {
    if (destination.isEmpty) {
      return OvaToolResult.fail('Tell me which place, landmark, or city to fly to.');
    }
    final (me, _) = await _here();
    GeoPlace? dest;
    try {
      final hits = await _geo.search(destination, near: me, limit: 5);
      dest = hits.isEmpty ? null : hits.first;
      if (dest == null && me != null) {
        final near = await _geo.nearby(me, destination, radiusM: 5000, limit: 1);
        if (near.isNotEmpty) dest = near.first;
      }
    } catch (e) {
      return OvaToolResult.fail('Could not look up "$destination": $e', icon: Icons.wifi_off_rounded);
    }
    if (dest == null) {
      return OvaToolResult(
        ok: false,
        summary: 'I could not find "$destination" on the map.',
        icon: Icons.wrong_location_rounded,
      );
    }
    OneovaMapHistoryService.instance.record(
      title: dest.name,
      subtitle: dest.address,
      point: dest.point,
      actionType: 'fly',
    );
    final origin = me ?? dest.point;
    final route = me != null ? await _geo.route(me, dest.point) : null;
    final signal = await _geo.signal();
    return OvaToolResult(
      ok: true,
      title: '🚁 Flying to ${dest.name}',
      summary: 'Flying live to ${dest.name}${dest.address != null ? ' (${dest.address})' : ''}.'
          '${route != null ? ' Route is ${formatDistance(route.distanceM)} (${formatDuration(route.durationS)}).' : ''}',
      icon: Icons.flight_rounded,
      map: OvaMapSpec(
        me: origin,
        destination: dest,
        route: route,
        signal: signal,
        rotoscopeHighlight: true,
        flyToTarget: true,
      ),
      actions: [
        OvaResultAction(
          label: 'Start Live Directions',
          icon: Icons.navigation_rounded,
          prompt: 'start navigation to ${dest.name}',
        ),
        const OvaResultAction(
          label: "What's Nearby",
          icon: Icons.near_me_rounded,
          prompt: "what's near me",
        ),
      ],
    );
  }

  Future<OvaToolResult> showMapHistory() async {
    await OneovaMapHistoryService.instance.warm();
    final (me, _) = await _here();
    final items = OneovaMapHistoryService.instance.items;
    if (items.isEmpty) {
      return OvaToolResult(
        ok: true,
        title: 'Map History Empty',
        summary: 'No saved places or routes in your Map History yet. Try asking "What\'s near me" or "Fly me to…".',
        icon: Icons.history_rounded,
        map: me != null ? OvaMapSpec(me: me, rotoscopeHighlight: true) : null,
      );
    }
    final places = [
      for (final h in items.take(8))
        GeoPlace(
          name: h.title,
          point: h.point,
          address: h.subtitle,
          distanceM: me != null ? _geo.distanceM(me, h.point) : null,
        ),
    ];
    return OvaToolResult(
      ok: true,
      title: '${items.length} places in Map History',
      summary: 'Recent Map History:\n${items.take(8).map((h) => '- ${h.title}${h.subtitle != null ? ' (${h.subtitle})' : ''}').join('\n')}',
      icon: Icons.history_rounded,
      map: OvaMapSpec(
        me: me ?? places.first.point,
        places: places,
        rotoscopeHighlight: true,
      ),
      items: [
        for (final h in items.take(8))
          OvaResultItem(
            title: h.title,
            subtitle: h.subtitle,
            icon: h.actionType == 'fly' ? Icons.flight_rounded : Icons.place_rounded,
            onTap: OvaResultAction(
              label: 'Fly There',
              icon: Icons.flight_rounded,
              prompt: 'fly me to ${h.title}',
            ),
          ),
      ],
    );
  }

  Future<OvaToolResult> nearby(String what, {int radiusM = 1500, bool rotoscope = true}) async {
    final (me, err) = await _here();
    if (err != null) return err;
    List<GeoPlace> places;
    try {
      places = what.isEmpty || RegExp(r'^(places?|anything|stuff|things|near me|around me)$').hasMatch(what.toLowerCase())
          ? await _geo.nearby(me!, 'food', radiusM: radiusM)
          : await _geo.nearby(me!, what, radiusM: radiusM);
      if (places.isEmpty && what.isNotEmpty && GeoServices.categoryFor(what) == null) {
        places = (await _geo.search(what, near: me, limit: 6)).where((p) => (p.distanceM ?? 1e9) < 50000).toList();
      }
    } catch (e) {
      return OvaToolResult.fail('I couldn\'t check places nearby right now. Please check your connection.', icon: Icons.wifi_off_rounded);
    }
    final label = what.isEmpty ? 'places' : what;
    if (places.isEmpty) {
      return OvaToolResult(
        ok: true,
        title: 'Nothing found nearby yet',
        summary: 'I didn\'t spot any $label within ${formatDistance(radiusM.toDouble())} of your current location. Would you like me to look a bit wider?',
        icon: Icons.search_off_rounded,
        map: OvaMapSpec(me: me, rotoscopeHighlight: rotoscope),
        actions: [
          if (radiusM < 5000)
            OvaResultAction(label: 'Search 5 km around me', icon: Icons.zoom_out_map_rounded, prompt: 'find $label within 5 km'),
          const OvaResultAction(label: 'Food & Cafes', icon: Icons.restaurant_rounded, prompt: 'find food near me'),
          const OvaResultAction(label: 'ATMs & Cash', icon: Icons.atm_rounded, prompt: 'find ATM near me'),
        ],
      );
    }

    // Automatically pre-compute the live route to the closest top place and
    // reverse-geocode the user's current area in the background!
    final topPlace = places.first;
    final bgResults = await Future.wait([
      _geo.route(me, topPlace.point),
      _geo.reverse(me),
      _geo.signal(),
    ]);
    final autoRoute = bgResults[0] as GeoRoute?;
    final myArea = bgResults[1] as String?;
    final signal = bgResults[2] as GeoSignal;
    lastAddress = myArea;

    OneovaMapHistoryService.instance.record(
      title: topPlace.name,
      subtitle: topPlace.address ?? label,
      point: topPlace.point,
      actionType: 'nearby',
    );

    final lines = [
      for (var k = 0; k < places.length; k++)
        '${k + 1}. ${places[k].name} (${formatDistance(places[k].distanceM ?? 0)})'
            '${places[k].openNow == true ? ' · Open now' : ''}'
            '${places[k].address != null ? ' · ${places[k].address}' : ''}',
    ];
    final areaIntro = myArea != null && myArea.isNotEmpty ? 'Around $myArea, ' : '';
    final routeHint = autoRoute != null
        ? ' The closest is ${topPlace.name}, just ${formatDistance(autoRoute.distanceM)} (${formatDuration(autoRoute.durationS)}) away — I\'ve already highlighted the route on your map.'
        : '';

    return OvaToolResult(
      ok: true,
      title: '${places.length} ${label.toLowerCase()} near you',
      summary: '${areaIntro}I found ${places.length} $label near you.$routeHint\n${lines.join('\n')}',
      icon: Icons.near_me_rounded,
      map: OvaMapSpec(
        me: me,
        places: places,
        destination: topPlace,
        route: autoRoute,
        signal: signal,
        rotoscopeHighlight: rotoscope,
        flyToTarget: true,
      ),
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
            onTap: OvaResultAction(label: 'Start Route', icon: Icons.directions_rounded, prompt: 'start navigation to ${places[k].name}'),
          ),
      ],
      actions: [
        OvaResultAction(
          label: 'Navigate to ${topPlace.name}',
          icon: Icons.navigation_rounded,
          prompt: 'start navigation to ${topPlace.name}',
        ),
        OvaResultAction(
          label: 'Fly to ${topPlace.name}',
          icon: Icons.flight_takeoff_rounded,
          prompt: 'fly me to ${topPlace.name}',
        ),
        const OvaResultAction(
          label: 'Cafes & Food',
          icon: Icons.restaurant_rounded,
          prompt: 'find coffee and food near me',
        ),
        const OvaResultAction(
          label: 'ATMs',
          icon: Icons.atm_rounded,
          prompt: 'find ATM near me',
        ),
        const OvaResultAction(
          label: 'Pharmacies',
          icon: Icons.local_pharmacy_rounded,
          prompt: 'find pharmacy near me',
        ),
      ],
    );
  }

  Future<OvaToolResult> navigate(
    String destination, {
    String mode = 'driving',
    bool startNavigation = false,
    bool rotoscope = true,
  }) async {
    if (destination.isEmpty) return OvaToolResult.fail('Where do you want to go?');
    final (me, err) = await _here();
    if (err != null) return err;
    GeoPlace? dest;
    try {
      final hits = await _geo.search(destination, near: me, limit: 5);
      dest = hits.isEmpty ? null : hits.first;
      if (dest == null) {
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
    final stepSummary = (route != null && route.steps.isNotEmpty)
        ? '\nNext turns: ${route.steps.take(3).map((s) => '${s.instruction} (${formatDistance(s.distanceM)})').join(' → ')}.'
        : '';
    final summary = route == null
        ? '${dest.name} is ${formatDistance(_geo.distanceM(me, dest.point))} away (straight line). No route was available, Google Maps can still navigate. ${_signalLine(signal)}'
        : 'Route to ${dest.name}: ${formatDistance(route.distanceM)}, about ${formatDuration(route.durationS)} by $how.$stepSummary ${_signalLine(signal)}';
    return OvaToolResult(
      ok: true,
      title: route == null ? dest.name : '${dest.name} · ${formatDuration(route.durationS)} ($how)',
      summary: summary,
      icon: Icons.directions_rounded,
      map: OvaMapSpec(
        me: me,
        destination: dest,
        route: route,
        mode: mode,
        signal: signal,
        rotoscopeHighlight: rotoscope,
        autoStartNavigation: startNavigation,
      ),
      items: [
        if (route != null)
          for (final st in route.steps.take(6))
            OvaResultItem(
              title: st.instruction,
              subtitle: '${formatDistance(st.distanceM)} · ${formatDuration(st.durationS)}',
              icon: maneuverIcon(st.maneuverType, st.modifier),
            ),
      ],
      actions: [
        OvaResultAction(label: 'Start in Google Maps', icon: Icons.navigation_rounded, url: navUrl),
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
