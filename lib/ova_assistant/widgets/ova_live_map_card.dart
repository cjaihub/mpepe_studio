import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/location/geo_services.dart';
import '../../shared/location/oneova_map_view.dart';
import '../../shared/theme/app_theme.dart';
import '../core/ova_tool_result.dart';

/// The interactive live map inside an Ova / Gemini answer.
///
/// Autonomously locks onto the user's live GPS in the background, scans
/// "What's Near Me" categories on demand without leaving the card, self-navigates
/// (flies the camera + computes live animated routes in the background), and
/// provides rich 1-tap actions around every discovered place.
class OvaLiveMapCard extends StatefulWidget {
  final OvaMapSpec spec;
  final ValueChanged<String>? onPrompt;

  const OvaLiveMapCard({super.key, required this.spec, this.onPrompt});

  @override
  State<OvaLiveMapCard> createState() => _OvaLiveMapCardState();
}

class _OvaLiveMapCardState extends State<OvaLiveMapCard> {
  static const List<({String id, String label, IconData icon})> _nearbyCategories = [
    (id: 'food', label: 'Food & Cafe', icon: Icons.restaurant_rounded),
    (id: 'atm', label: 'ATM & Cash', icon: Icons.atm_rounded),
    (id: 'pharmacy', label: 'Pharmacy', icon: Icons.local_pharmacy_rounded),
    (id: 'fuel', label: 'Fuel', icon: Icons.local_gas_station_rounded),
    (id: 'hotel', label: 'Hotels', icon: Icons.hotel_rounded),
    (id: 'shop', label: 'Shops', icon: Icons.shopping_bag_rounded),
  ];

  GeoSignal? _signal;
  LatLng? _me;
  late List<GeoPlace> _places;
  GeoPlace? _destination;
  GeoRoute? _route;
  late String _travelMode;
  int? _selected;
  late bool _rotoscope;
  late bool _navigating;
  int _activeStepIndex = 0;
  bool _showSteps = false;
  double _speedMps = 0;
  int? _activeLiveShareMins;
  LatLng? _flyTarget;
  String? _flyTargetLabel;
  String? _activeCategory;
  bool _scanningNearby = false;
  bool _routingInBackground = false;

  @override
  void initState() {
    super.initState();
    _signal = widget.spec.signal;
    _me = widget.spec.me;
    _places = List<GeoPlace>.of(widget.spec.places);
    _destination = widget.spec.destination;
    _route = widget.spec.route;
    _travelMode = widget.spec.mode;
    _rotoscope = widget.spec.rotoscopeHighlight;
    _navigating = widget.spec.autoStartNavigation;
    _activeLiveShareMins = widget.spec.liveShareMinutes;
    if (_places.isNotEmpty) {
      _selected = 0;
      if (_route == null) {
        unawaited(_computeRouteInBackground(_places.first, mode: _travelMode));
      }
    }
  }

  double? get _remainingM {
    final d = _destination ??
        ((_selected != null && _selected! < _places.length)
            ? _places[_selected!]
            : null);
    final me = _me;
    if (d == null || me == null) return null;
    return GeoServices.instance.distanceM(me, d.point);
  }

  /// Autonomously computes the live route & ETA in the background and smoothly
  /// flies the map camera to [place].
  Future<void> _computeRouteInBackground(
    GeoPlace place, {
    String? mode,
    bool flyCamera = false,
    bool startNav = false,
  }) async {
    final me = _me ?? widget.spec.me;
    final useMode = mode ?? _travelMode;
    if (mounted) {
      setState(() {
        _destination = place;
        _travelMode = useMode;
        _routingInBackground = true;
        if (flyCamera) {
          _flyTarget = place.point;
          _flyTargetLabel = place.name;
        }
        if (startNav) {
          _navigating = true;
        }
      });
    }
    try {
      final r = await GeoServices.instance.route(me, place.point, mode: useMode);
      if (!mounted) return;
      setState(() {
        if (r != null) _route = r;
        _activeStepIndex = 0;
        _routingInBackground = false;
      });
    } catch (_) {
      if (mounted) setState(() => _routingInBackground = false);
    }
  }

  /// Background "What's Near Me" radar scan: acquires fresh GPS if available,
  /// queries nearby places, self-navigates the map to the closest result, and
  /// computes the live route automatically.
  Future<void> _scanNearbyCategory(String categoryId) async {
    if (_scanningNearby) return;
    HapticFeedback.selectionClick();
    setState(() {
      _activeCategory = categoryId;
      _scanningNearby = true;
    });
    try {
      LatLng origin = _me ?? widget.spec.me;
      try {
        final pos = await GeoServices.instance.current();
        origin = LatLng(pos.latitude, pos.longitude);
        _me = origin;
      } catch (_) {}

      final found = await GeoServices.instance.nearby(
        origin,
        categoryId,
        radiusM: 2500,
        limit: 8,
      );
      if (!mounted) return;
      if (found.isNotEmpty) {
        final top = found.first;
        OneovaMapHistoryService.instance.record(
          title: top.name,
          subtitle: top.address ?? categoryId,
          point: top.point,
          actionType: 'nearby',
        );
        setState(() {
          _places = found;
          _selected = 0;
          _destination = top;
          _flyTarget = top.point;
          _flyTargetLabel = top.name;
          _scanningNearby = false;
        });
        unawaited(_computeRouteInBackground(top, mode: _travelMode));
      } else {
        setState(() => _scanningNearby = false);
      }
    } catch (_) {
      if (mounted) setState(() => _scanningNearby = false);
    }
  }

  void _updateStepForPosition(LatLng pt) {
    final steps = _route?.steps ?? const <GeoRouteStep>[];
    if (steps.isEmpty) return;
    var bestIdx = _activeStepIndex;
    var bestDist = double.infinity;
    for (var i = 0; i < steps.length; i++) {
      final d = GeoServices.instance.distanceM(pt, steps[i].location);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestIdx != _activeStepIndex && mounted) {
      setState(() => _activeStepIndex = bestIdx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = (_selected != null && _selected! < _places.length)
        ? _places[_selected!]
        : _destination;
    final remaining = _remainingM;
    final steps = _route?.steps ?? const <GeoRouteStep>[];
    final currentStep = (steps.isNotEmpty && _activeStepIndex < steps.length)
        ? steps[_activeStepIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Autonomous "What's Near Me" Radar Category Bar
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _nearbyCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, idx) {
              final cat = _nearbyCategories[idx];
              final isSelected = _activeCategory == cat.id;
              return GestureDetector(
                onTap: () => _scanNearbyCategory(cat.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brandBlue : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: isSelected ? AppColors.brandBlue : context.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        cat.icon,
                        size: 12.5,
                        color: isSelected ? Colors.white : AppColors.brandBlue,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        cat.label,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),

        // 2. Active Turn-by-Turn Direction Header when Navigating or Route available
        if (currentStep != null || _scanningNearby || _routingInBackground)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              gradient: _navigating
                  ? const LinearGradient(
                      colors: [AppColors.brandBlue, Color(0xFF073472)],
                    )
                  : null,
              color: _navigating ? null : context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: _navigating ? AppColors.brandPink : context.border,
              ),
            ),
            child: Row(
              children: [
                if (_scanningNearby || _routingInBackground)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: AppColors.brandPink,
                    ),
                  )
                else if (currentStep != null)
                  Icon(
                    maneuverIcon(currentStep.maneuverType, currentStep.modifier),
                    size: 19,
                    color: _navigating ? Colors.white : AppColors.brandBlue,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _scanningNearby
                            ? 'Scanning places around your live location…'
                            : (_routingInBackground
                                ? 'Finding the fastest route to ${sel?.name ?? "destination"}…'
                                : (currentStep?.instruction ?? '')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _navigating ? Colors.white : context.textPrimary,
                        ),
                      ),
                      if (!_scanningNearby && !_routingInBackground && currentStep != null)
                        Text(
                          '${formatDistance(currentStep.distanceM)} · ${_route != null ? '${formatDuration(_route!.durationS)} total ($_travelMode)' : ''}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: _navigating ? Colors.white70 : context.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (steps.length > 1)
                  GestureDetector(
                    onTap: () => setState(() => _showSteps = !_showSteps),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: (_navigating ? Colors.white : AppColors.brandBlue)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        _showSteps ? 'Hide steps' : '${steps.length} steps',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _navigating ? Colors.white : AppColors.brandBlue,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // 3. Interactive Self-Navigating Map with Rotoscope & Live Route
        OneovaMapView(
          me: _me ?? widget.spec.me,
          places: _places,
          route: _route,
          destination: _destination?.point,
          destinationName: _destination?.name,
          flyToTargetOnLoad: widget.spec.flyToTarget,
          flyTarget: _flyTarget,
          flyTargetLabel: _flyTargetLabel,
          trackUser: true,
          sampleSignal: true,
          height: _route != null || _places.isNotEmpty ? 228 : 188,
          highlightIndex: _selected,
          rotoscopeHighlight: _rotoscope,
          navigating: _navigating,
          activeStepIndex: _activeStepIndex,
          onRotoscopeChanged: (v) => setState(() => _rotoscope = v),
          onPlaceTap: (i) {
            if (i >= 0 && i < _places.length) {
              HapticFeedback.selectionClick();
              setState(() => _selected = i);
              unawaited(
                _computeRouteInBackground(
                  _places[i],
                  mode: _travelMode,
                  flyCamera: true,
                ),
              );
            }
          },
          onMove: (p) {
            setState(() => _me = p);
            if (_navigating) _updateStepForPosition(p);
          },
          onSpeedMps: (s) => setState(() => _speedMps = s),
          onSignal: (s) => setState(() => _signal = s),
        ),

        // 4. Horizontal Nearby Places Carousel (Tap any card to self-navigate)
        if (_places.length > 1) ...[
          const SizedBox(height: 7),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _places.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                final p = _places[idx];
                final isSel = _selected == idx;
                final dist = p.distanceM ??
                    (_me != null ? GeoServices.instance.distanceM(_me!, p.point) : null);
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selected = idx);
                    unawaited(
                      _computeRouteInBackground(
                        p,
                        mode: _travelMode,
                        flyCamera: true,
                      ),
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 172,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? AppColors.brandBlue.withValues(alpha: 0.14)
                          : context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: isSel ? AppColors.brandBlue : context.border,
                        width: isSel ? 1.2 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSel ? AppColors.brandPink : AppColors.brandBlue,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (dist != null) formatDistance(dist),
                            if (p.openNow == true) 'Open',
                            ?p.address,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // 5. Selected Place Rich Action Dock (Start Go · Fly There · Walk/Drive · Ask Ova · Share)
        if (sel != null) ...[
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: AppColors.brandBlue.withValues(alpha: 0.32),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 16,
                      color: AppColors.brandPink,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          Text(
                            [
                              if (_route != null)
                                '${formatDistance(_route!.distanceM)} · ${formatDuration(_route!.durationS)}'
                              else if (sel.distanceM != null)
                                formatDistance(sel.distanceM!),
                              if (sel.openNow == true) 'Open now',
                              ?sel.address,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Travel Mode Switcher (Drive / Walk)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        final nextMode = _travelMode == 'walking' ? 'driving' : 'walking';
                        unawaited(_computeRouteInBackground(sel, mode: nextMode));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          color: context.surface,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: context.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _travelMode == 'walking'
                                  ? Icons.directions_walk_rounded
                                  : Icons.directions_car_rounded,
                              size: 13,
                              color: AppColors.brandBlue,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _travelMode == 'walking' ? 'Walk' : 'Drive',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Action 1: Start Live Turn-by-Turn Navigation
                      _actionButton(
                        icon: _navigating
                            ? Icons.stop_circle_rounded
                            : Icons.navigation_rounded,
                        label: _navigating ? 'Stop Go' : 'Start Live Go',
                        filled: true,
                        color: _navigating ? AppColors.brandPink : AppColors.brandBlue,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          if (_route != null) {
                            setState(() => _navigating = !_navigating);
                          } else {
                            unawaited(
                              _computeRouteInBackground(
                                sel,
                                flyCamera: true,
                                startNav: true,
                              ),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      // Action 2: Fly Me There (3D Aerial Camera Flight)
                      _actionButton(
                        icon: Icons.flight_takeoff_rounded,
                        label: 'Fly There',
                        color: AppColors.brandPink,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _flyTarget = sel.point;
                            _flyTargetLabel = sel.name;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      // Action 3: Ask Ova About This Place
                      _actionButton(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Ask Ova',
                        color: AppColors.brandBlue,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onPrompt?.call(
                            'Tell me about ${sel.name} and what is good to know before going there',
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      // Action 4: Open External Turn-by-Turn Handoff
                      _actionButton(
                        icon: Icons.open_in_new_rounded,
                        label: 'Google Maps',
                        color: AppColors.brandBlue,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          GeoServices.instance.openNavigation(
                            sel.point,
                            mode: _travelMode,
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      // Action 5: Share Pin / Live Location
                      _actionButton(
                        icon: Icons.share_location_rounded,
                        label: 'Share',
                        color: AppColors.brandPink,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          SharePlus.instance.share(
                            ShareParams(
                              text:
                                  '📍 ${sel.name}: https://maps.google.com/?q=${sel.point.latitude},${sel.point.longitude}',
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 6),

        // 6. Status & Quick Utility Chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _scanNearbyCategory(_activeCategory ?? 'food'),
              child: _chip(
                context,
                Icons.my_location_rounded,
                'Refresh Near Me',
                AppColors.brandBlue,
              ),
            ),
            GestureDetector(
              onTap: () => widget.onPrompt?.call('show my map history'),
              child: _chip(
                context,
                Icons.history_rounded,
                'History',
                AppColors.brandBlue,
              ),
            ),
            if (_speedMps > 0.6)
              _chip(
                context,
                Icons.speed_rounded,
                '${(_speedMps * 3.6).round()} km/h',
                AppColors.brandBlue,
              ),
            if (remaining != null)
              _chip(
                context,
                Icons.flag_rounded,
                '${formatDistance(remaining)} away',
                AppColors.brandBlue,
              ),
            if (_signal != null)
              _chip(
                context,
                _signal!.network == 'wifi'
                    ? Icons.wifi_rounded
                    : Icons.signal_cellular_alt_rounded,
                _signal!.label,
                signalColor(context, _signal!),
              ),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                final pt = _me ?? widget.spec.me;
                setState(
                  () => _activeLiveShareMins = _activeLiveShareMins == 60 ? null : 60,
                );
                SharePlus.instance.share(
                  ShareParams(
                    text:
                        '📍 Live Location (Oneova): https://maps.google.com/?q=${pt.latitude},${pt.longitude}',
                  ),
                );
              },
              child: _chip(
                context,
                Icons.share_location_rounded,
                _activeLiveShareMins != null
                    ? 'Sharing Live (${_activeLiveShareMins}m)'
                    : 'Share Live Location',
                AppColors.brandPink,
              ),
            ),
          ],
        ),

        // Expandable Turn-by-Turn Steps List
        if (_showSteps && steps.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: steps.length,
              itemBuilder: (_, idx) {
                final st = steps[idx];
                final active = idx == _activeStepIndex;
                return InkWell(
                  onTap: () => setState(() => _activeStepIndex = idx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          maneuverIcon(st.maneuverType, st.modifier),
                          size: 15,
                          color: active ? AppColors.brandPink : AppColors.brandBlue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            st.instruction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          formatDistance(st.distanceM),
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: filled ? color : color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: filled ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
