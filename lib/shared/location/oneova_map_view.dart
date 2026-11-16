import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../backend/security/oneova_ai_gateway.dart';
import '../theme/app_theme.dart';
import 'geo_services.dart';

/// A signal reading taken at a point while the map was tracking the user.
class SignalSample {
  final LatLng point;
  final GeoSignal signal;
  const SignalSample(this.point, this.signal);
}

/// Colour for a signal reading: blue when strong, pink when weak or offline.
Color signalColor(BuildContext context, GeoSignal s) {
  if (s.network == 'offline' || !s.internet) return AppColors.brandPink;
  final l = s.level;
  if (l == null || l >= 3) return AppColors.brandBlue;
  if (l == 2) return context.textMuted;
  return AppColors.brandPink;
}

/// Icon for a turn-by-turn maneuver step.
IconData maneuverIcon(String type, String? modifier) {
  final m = (modifier ?? '').toLowerCase();
  if (type == 'arrive') return Icons.flag_rounded;
  if (type == 'depart') return Icons.navigation_rounded;
  if (type == 'roundabout' || type == 'rotary') return Icons.roundabout_right_rounded;
  if (m.contains('uturn')) return Icons.u_turn_left_rounded;
  if (m.contains('sharp right') || m == 'right') return Icons.turn_right_rounded;
  if (m.contains('slight right')) return Icons.turn_slight_right_rounded;
  if (m.contains('sharp left') || m == 'left') return Icons.turn_left_rounded;
  if (m.contains('slight left')) return Icons.turn_slight_left_rounded;
  return Icons.straight_rounded;
}

/// An enhanced OpenStreetMap & Satellite view used by chat location bubbles, shops, and Ova AI.
///
/// Features:
/// - **Auto-Focus on Our Location**: automatically acquires and locks onto the user's real-time GPS position.
/// - **"Fly Me There" in Real Time**: smooth 3-phase cinematic camera flight (ascend -> cruise -> descend & lock)
///   with live telemetry HUD and optional Satellite aerial imagery.
/// - **Rotoscope Contour Highlighter**: high-contrast cyber-contour map shader &
///   animated target lock reticle around highlighted places and destinations.
/// - **Live Animated Route**: flowing directional pulse and travelling beacon along
///   the active route polyline.
class OneovaMapView extends StatefulWidget {
  /// Fixed position of the user (or of the shared pin) when not tracking.
  final LatLng? me;
  final List<GeoPlace> places;
  final GeoRoute? route;
  final LatLng? destination;
  final String? destinationName;

  /// Other people's live pins (chat live location), label -> point.
  final Map<String, LatLng> others;
  final bool trackUser;
  final bool sampleSignal;
  final bool interactive;
  final double height;
  final int? highlightIndex;
  final bool rotoscopeHighlight;
  final bool navigating;
  final bool flyToTargetOnLoad;
  final LatLng? flyTarget;
  final String? flyTargetLabel;
  final int? activeStepIndex;
  final ValueChanged<int>? onPlaceTap;
  final ValueChanged<GeoSignal>? onSignal;
  final ValueChanged<LatLng>? onMove;
  final ValueChanged<double>? onSpeedMps;
  final ValueChanged<bool>? onRotoscopeChanged;
  final VoidCallback? onExpandFullScreen;

  const OneovaMapView({
    super.key,
    this.me,
    this.places = const [],
    this.route,
    this.destination,
    this.destinationName,
    this.others = const {},
    this.trackUser = false,
    this.sampleSignal = false,
    this.interactive = true,
    this.height = 200,
    this.highlightIndex,
    this.rotoscopeHighlight = false,
    this.navigating = false,
    this.flyToTargetOnLoad = false,
    this.flyTarget,
    this.flyTargetLabel,
    this.activeStepIndex,
    this.onPlaceTap,
    this.onSignal,
    this.onMove,
    this.onSpeedMps,
    this.onRotoscopeChanged,
    this.onExpandFullScreen,
  });

  @override
  State<OneovaMapView> createState() => _OneovaMapViewState();
}

class _OneovaMapViewState extends State<OneovaMapView>
    with TickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _animCtrl;
  late final AnimationController _flyCtrl;
  StreamSubscription<Position>? _sub;
  Timer? _signalTimer;
  LatLng? _me;
  double? _heading;
  double _speedMps = 0;
  bool _follow = true;
  bool _ready = false;
  late bool _rotoscope;
  bool _satellite = false;
  String? _flyingLabel;
  LatLng? _flyFrom;
  LatLng? _flyToPoint;
  double _flyStartZoom = 14.0;
  double _flyEndZoom = 17.2;
  final List<SignalSample> _trail = [];

  @override
  void initState() {
    super.initState();
    _me = widget.me;
    _rotoscope = widget.rotoscopeHighlight;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _flyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1750),
    )..addListener(_onFlyTick);
    if (widget.trackUser || widget.navigating) _startTracking();
    if (_me == null) _autoAcquireLocation();
  }

  Future<void> _autoAcquireLocation() async {
    try {
      final p = await GeoServices.instance.current();
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      setState(() => _me = pt);
      widget.onMove?.call(pt);
      if (_ready && _follow && widget.destination == null && widget.places.isEmpty) {
        _flyTo(pt, targetZoom: 16.5, label: 'Your Location');
      }
    } catch (_) {}
  }

  void _onFlyTick() {
    if (!_ready || _flyFrom == null || _flyToPoint == null) return;
    final raw = _flyCtrl.value;
    final curved = Curves.easeInOutCubic.transform(raw);
    final lat = _flyFrom!.latitude + (_flyToPoint!.latitude - _flyFrom!.latitude) * curved;
    final lng = _flyFrom!.longitude + (_flyToPoint!.longitude - _flyFrom!.longitude) * curved;

    // 3-stage cinematic altitude arc: pull back at mid-flight, then zoom into target
    final distM = GeoServices.instance.distanceM(_flyFrom!, _flyToPoint!);
    final midDip = distM > 2500 ? 3.2 : (distM > 500 ? 1.6 : 0.6);
    final arc = math.sin(raw * math.pi);
    final interpZoom = _flyStartZoom + (_flyEndZoom - _flyStartZoom) * curved - (arc * midDip);
    _map.move(LatLng(lat, lng), interpZoom.clamp(3.0, 18.5));
  }

  Future<void> _flyTo(LatLng target, {double targetZoom = 17.2, String? label}) async {
    if (!_ready) return;
    HapticFeedback.mediumImpact();
    _flyFrom = _map.camera.center;
    _flyToPoint = target;
    _flyStartZoom = _map.camera.zoom;
    _flyEndZoom = targetZoom;
    setState(() {
      _flyingLabel = label ?? 'Target';
    });
    if (label != null && label.isNotEmpty) {
      OneovaMapHistoryService.instance.record(
        title: label,
        point: target,
        actionType: 'fly',
      );
    }
    await _flyCtrl.forward(from: 0.0);
    if (mounted) {
      setState(() => _flyingLabel = null);
    }
  }

  @override
  void didUpdateWidget(OneovaMapView old) {
    super.didUpdateWidget(old);
    if (widget.rotoscopeHighlight != old.rotoscopeHighlight) {
      _rotoscope = widget.rotoscopeHighlight;
    }
    if ((widget.trackUser || widget.navigating) && _sub == null) {
      _startTracking();
    }
    if (widget.flyTarget != null && widget.flyTarget != old.flyTarget && _ready) {
      _follow = false;
      _flyTo(widget.flyTarget!, targetZoom: 17.4, label: widget.flyTargetLabel ?? widget.destinationName);
      return;
    }
    if (!widget.trackUser && !widget.navigating && widget.me != null && widget.me != old.me) {
      _me = widget.me;
      if (_ready && _follow) _map.move(widget.me!, _map.camera.zoom);
    }
    if (widget.navigating && !old.navigating && _ready && _me != null) {
      _flyTo(_me!, targetZoom: 17.2, label: 'Navigation Start');
    } else if (widget.route != old.route ||
        widget.places.length != old.places.length ||
        widget.highlightIndex != old.highlightIndex) {
      if (widget.highlightIndex != null &&
          widget.highlightIndex! >= 0 &&
          widget.highlightIndex! < widget.places.length &&
          _ready) {
        final place = widget.places[widget.highlightIndex!];
        _flyTo(place.point, targetZoom: 17.0, label: place.name);
      } else {
        _fit();
      }
    }
  }

  void _startTracking() {
    _sub?.cancel();
    _sub = GeoServices.instance.track(distanceFilterM: 3).listen((p) {
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      final wasNull = _me == null;
      setState(() {
        _me = pt;
        _heading = p.heading >= 0 ? p.heading : _heading;
        _speedMps = p.speed >= 0 ? p.speed : 0;
      });
      widget.onMove?.call(pt);
      widget.onSpeedMps?.call(_speedMps);
      if (_ready && _follow && !_flyCtrl.isAnimating) {
        if (wasNull && widget.destination == null && widget.places.isEmpty) {
          _flyTo(pt, targetZoom: 16.6, label: 'Your Location');
        } else if (widget.navigating) {
          _map.move(pt, math.max(_map.camera.zoom, 16.8));
        } else if (widget.route == null && widget.places.isEmpty) {
          _map.move(pt, math.max(_map.camera.zoom, 16.0));
        }
      }
    }, onError: (Object e) => debugPrint('[OneovaMapView] tracking: $e'));
    if (widget.sampleSignal && _signalTimer == null) {
      _readSignal();
      _signalTimer = Timer.periodic(const Duration(seconds: 15), (_) => _readSignal());
    }
  }

  Future<void> _readSignal() async {
    final s = await GeoServices.instance.signal();
    if (!mounted) return;
    final me = _me;
    setState(() {
      if (me != null) {
        _trail.add(SignalSample(me, s));
        if (_trail.length > 200) _trail.removeAt(0);
      }
    });
    widget.onSignal?.call(s);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _flyCtrl.dispose();
    _sub?.cancel();
    _signalTimer?.cancel();
    super.dispose();
  }

  List<LatLng> get _allPoints => [
        ?_me,
        ?widget.destination,
        for (final p in widget.places) p.point,
        ...widget.others.values,
        if (widget.route != null) ...widget.route!.points,
      ];

  void _fit() {
    if (!_ready) return;
    final pts = _allPoints;
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _map.move(pts.first, 16.5);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(38),
        maxZoom: 17,
      ),
    );
  }

  /// Computes a flowing sub-polyline window and travelling beacon point for the animated route.
  (List<LatLng>, LatLng?) _animatedRouteWindow(List<LatLng> pts, double t) {
    if (pts.isEmpty) return (const [], null);
    if (pts.length == 1) return (pts, pts.first);
    final total = pts.length;
    final headIdx = (t * (total - 1)).clamp(0.0, (total - 1).toDouble());
    final idx = headIdx.floor();
    final frac = headIdx - idx;
    final LatLng beacon;
    if (idx >= total - 1) {
      beacon = pts.last;
    } else {
      final a = pts[idx];
      final b = pts[idx + 1];
      beacon = LatLng(
        a.latitude + (b.latitude - a.latitude) * frac,
        a.longitude + (b.longitude - a.longitude) * frac,
      );
    }
    final tailLen = math.max(3, (total * 0.28).round());
    final startIdx = math.max(0, idx - tailLen);
    final sub = <LatLng>[
      ...pts.sublist(startIdx, idx + 1),
      beacon,
    ];
    return (sub, beacon);
  }

  ColorFilter _tileFilter(bool dark) {
    if (_satellite) {
      return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
    }
    if (_rotoscope) {
      // High-contrast Rotoscope Neon Edge / Tactical Dark Matrix
      return const ColorFilter.matrix([
        -0.85, 0.0, 0.15, 0, 42, //
        0.0, -0.75, 0.25, 0, 52,
        0.15, 0.25, -0.55, 0, 95,
        0, 0, 0, 1, 0,
      ]);
    }
    if (dark) {
      return const ColorFilter.matrix([
        0.75, 0, 0, 0, 0, //
        0, 0.75, 0, 0, 0,
        0, 0, 0.8, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    }
    return const ColorFilter.mode(Colors.transparent, BlendMode.dst);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _allPoints;
    final center = pts.isNotEmpty ? pts.first : const LatLng(0, 0);
    final dark = AppColors.isDark(context);
    final highlightedPoint = (widget.highlightIndex != null &&
            widget.highlightIndex! >= 0 &&
            widget.highlightIndex! < widget.places.length)
        ? widget.places[widget.highlightIndex!].point
        : widget.destination;

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            final t = _animCtrl.value;
            final routePts = widget.route?.points ?? const <LatLng>[];
            final (flowSegment, beaconPoint) = _animatedRouteWindow(routePts, t);

            return Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: pts.isEmpty ? 2 : 16,
                    backgroundColor: context.surfaceMid,
                    interactionOptions: InteractionOptions(
                      flags: widget.interactive
                          ? InteractiveFlag.all & ~InteractiveFlag.rotate
                          : InteractiveFlag.none,
                    ),
                    onMapReady: () {
                      _ready = true;
                      if (widget.flyToTargetOnLoad &&
                          (widget.destination != null || widget.flyTarget != null)) {
                        final target = widget.flyTarget ?? widget.destination!;
                        _flyTo(
                          target,
                          targetZoom: 17.3,
                          label: widget.flyTargetLabel ?? widget.destinationName ?? 'Destination',
                        );
                      } else {
                        _fit();
                      }
                    },
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture && _follow) setState(() => _follow = false);
                    },
                  ),
                  children: [
                    ColorFiltered(
                      colorFilter: _tileFilter(dark),
                      child: TileLayer(
                        urlTemplate: _satellite
                            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.oneova.app',
                        maxZoom: 19,
                      ),
                    ),
                    if (routePts.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePts,
                            strokeWidth: _rotoscope ? 11 : 8,
                            color: (_rotoscope ? AppColors.brandPink : AppColors.brandBlue)
                                .withValues(alpha: _rotoscope ? 0.28 : 0.20),
                          ),
                          Polyline(
                            points: routePts,
                            strokeWidth: 6,
                            color: Colors.white.withValues(alpha: _rotoscope ? 0.55 : 0.9),
                          ),
                          Polyline(
                            points: routePts,
                            strokeWidth: 4.2,
                            color: AppColors.brandBlue,
                          ),
                          if (flowSegment.length >= 2)
                            Polyline(
                              points: flowSegment,
                              strokeWidth: 5.0,
                              color: AppColors.brandPink,
                            ),
                        ],
                      ),
                    if (_trail.isNotEmpty)
                      CircleLayer(
                        circles: [
                          for (final s in _trail)
                            CircleMarker(
                              point: s.point,
                              radius: 4,
                              color: signalColor(context, s.signal).withValues(alpha: 0.8),
                            ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (widget.route != null && widget.route!.steps.isNotEmpty)
                          for (var sIdx = 0; sIdx < widget.route!.steps.length; sIdx++)
                            if (widget.navigating || widget.activeStepIndex == sIdx)
                              Marker(
                                point: widget.route!.steps[sIdx].location,
                                width: widget.activeStepIndex == sIdx ? 26 : 14,
                                height: widget.activeStepIndex == sIdx ? 26 : 14,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: widget.activeStepIndex == sIdx
                                        ? AppColors.brandPink
                                        : Colors.white,
                                    border: Border.all(
                                      color: AppColors.brandBlue,
                                      width: 2,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black38, blurRadius: 4),
                                    ],
                                  ),
                                  child: widget.activeStepIndex == sIdx
                                      ? Icon(
                                          maneuverIcon(
                                            widget.route!.steps[sIdx].maneuverType,
                                            widget.route!.steps[sIdx].modifier,
                                          ),
                                          size: 13,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                        if (highlightedPoint != null && (_rotoscope || widget.highlightIndex != null))
                          Marker(
                            point: highlightedPoint,
                            width: 76,
                            height: 76,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _RotoscopeTargetPainter(
                                  progress: t,
                                  color: AppColors.brandPink,
                                  accent: AppColors.brandBlue,
                                ),
                              ),
                            ),
                          ),
                        if (beaconPoint != null && routePts.length >= 2)
                          Marker(
                            point: beaconPoint,
                            width: 18,
                            height: 18,
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.brandPink,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.brandPink.withValues(alpha: 0.7),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        for (var i = 0; i < widget.places.length; i++)
                          Marker(
                            point: widget.places[i].point,
                            width: widget.highlightIndex == i ? 38 : 30,
                            height: widget.highlightIndex == i ? 38 : 30,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onPlaceTap?.call(i);
                                _flyTo(
                                  widget.places[i].point,
                                  targetZoom: 17.2,
                                  label: widget.places[i].name,
                                );
                              },
                              child: _PlacePin(
                                index: i + 1,
                                highlighted: widget.highlightIndex == i,
                                open: widget.places[i].openNow,
                                rotoscope: _rotoscope,
                              ),
                            ),
                          ),
                        if (widget.destination != null)
                          Marker(
                            point: widget.destination!,
                            width: 36,
                            height: 36,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _flyTo(
                                widget.destination!,
                                targetZoom: 17.4,
                                label: widget.destinationName ?? 'Destination',
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                size: 34,
                                color: AppColors.brandPink,
                              ),
                            ),
                          ),
                        for (final e in widget.others.entries)
                          Marker(
                            point: e.value,
                            width: 36,
                            height: 36,
                            child: GestureDetector(
                              onTap: () => _flyTo(e.value, targetZoom: 17.2, label: e.key),
                              child: _PersonPin(label: e.key),
                            ),
                          ),
                        if (_me != null)
                          Marker(
                            point: _me!,
                            width: 48,
                            height: 48,
                            child: GestureDetector(
                              onTap: () => _flyTo(_me!, targetZoom: 17.0, label: 'Your Location'),
                              child: _MeDot(
                                heading: _heading,
                                live: widget.trackUser || widget.navigating,
                                pulse: t,
                                rotoscope: _rotoscope,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                if (_rotoscope)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: AppColors.brandPink.withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Real-Time "Fly Me There" Telemetry Pill while flying
                if (_flyingLabel != null)
                  Positioned(
                    top: 38,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.brandBlue, AppColors.brandPink],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 8),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.flight_takeoff_rounded, size: 13, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              'Flying to $_flyingLabel…',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Top-left HUD: Rotoscope + Satellite + Fly Me There + Speed
                if (widget.interactive)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Wrap(
                      spacing: 5,
                      children: [
                        Material(
                          color: _rotoscope
                              ? AppColors.brandPink
                              : context.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          elevation: 2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _rotoscope = !_rotoscope);
                              widget.onRotoscopeChanged?.call(_rotoscope);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_fix_high_rounded,
                                    size: 12,
                                    color: _rotoscope ? Colors.white : AppColors.brandPink,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Roto',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _rotoscope ? Colors.white : context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Material(
                          color: _satellite
                              ? AppColors.brandBlue
                              : context.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          elevation: 2,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _satellite = !_satellite);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.satellite_alt_rounded,
                                    size: 12,
                                    color: _satellite ? Colors.white : AppColors.brandBlue,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Aerial',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: _satellite ? Colors.white : context.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (highlightedPoint != null)
                          Material(
                            color: AppColors.brandBlue,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            elevation: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(AppRadius.full),
                              onTap: () {
                                setState(() => _follow = false);
                                final name = (widget.highlightIndex != null &&
                                        widget.highlightIndex! < widget.places.length)
                                    ? widget.places[widget.highlightIndex!].name
                                    : (widget.destinationName ?? 'Destination');
                                _flyTo(highlightedPoint, targetZoom: 17.5, label: name);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.flight_rounded, size: 12, color: Colors.white),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Fly There',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if ((widget.trackUser || widget.navigating) && _speedMps > 0.6)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              '${(_speedMps * 3.6).round()} km/h',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                // Top-right HUD: Auto-Focus Me & Full-Screen Explorer
                if (widget.interactive)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: context.surface.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.lightImpact();
                              if (widget.onExpandFullScreen != null) {
                                widget.onExpandFullScreen!();
                              } else {
                                showOneovaFullMapModal(
                                  context,
                                  me: _me ?? widget.me,
                                  places: widget.places,
                                  route: widget.route,
                                  destination: widget.destination,
                                  destinationName: widget.destinationName,
                                  others: widget.others,
                                  rotoscopeInitial: _rotoscope,
                                );
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                Icons.open_in_full_rounded,
                                size: 15,
                                color: AppColors.brandBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Material(
                          color: _follow
                              ? AppColors.brandBlue
                              : context.surface.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _follow = true);
                              if (_me != null) {
                                _flyTo(_me!, targetZoom: 16.8, label: 'Your Location');
                              } else {
                                _autoAcquireLocation();
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                _follow
                                    ? Icons.my_location_rounded
                                    : Icons.location_searching_rounded,
                                size: 16,
                                color: _follow ? Colors.white : AppColors.brandBlue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Positioned(
                  right: 6,
                  bottom: 3,
                  child: Text(
                    _satellite ? '© Esri World Imagery' : '© Google Maps / OSM',
                    style: GoogleFonts.inter(
                      fontSize: 8.5,
                      color: _rotoscope || _satellite || dark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RotoscopeTargetPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color accent;

  const _RotoscopeTargetPainter({
    required this.progress,
    required this.color,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    final waveR = 12.0 + (maxR - 12.0) * progress;
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: (1.0 - progress) * 0.75);
    canvas.drawCircle(center, waveR, wavePaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.28),
          accent.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR * 0.78));
    canvas.drawCircle(center, maxR * 0.78, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = color;
    final baseAngle = progress * 2 * math.pi;
    final rect = Rect.fromCircle(center: center, radius: maxR * 0.62);
    for (int i = 0; i < 4; i++) {
      final start = baseAngle + i * (math.pi / 2);
      canvas.drawArc(rect, start, math.pi / 3.2, false, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RotoscopeTargetPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MeDot extends StatelessWidget {
  final double? heading;
  final bool live;
  final double pulse;
  final bool rotoscope;

  const _MeDot({
    this.heading,
    this.live = false,
    this.pulse = 0.0,
    this.rotoscope = false,
  });

  @override
  Widget build(BuildContext context) {
    final ringRadius = 16.0 + (live ? pulse * 14.0 : 4.0);
    final ringAlpha = live ? (1.0 - pulse) * 0.45 : 0.22;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: ringRadius * 2,
          height: ringRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (rotoscope ? AppColors.brandPink : AppColors.brandBlue)
                .withValues(alpha: ringAlpha.clamp(0.05, 0.5)),
          ),
        ),
        if (heading != null)
          Transform.rotate(
            angle: heading! * math.pi / 180.0,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: 8,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.brandBlue,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
          ),
        ),
      ],
    );
  }
}

class _PlacePin extends StatelessWidget {
  final int index;
  final bool highlighted;
  final bool? open;
  final bool rotoscope;

  const _PlacePin({
    required this.index,
    this.highlighted = false,
    this.open,
    this.rotoscope = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = highlighted
        ? AppColors.brandPink
        : (rotoscope ? const Color(0xFF00E5FF) : AppColors.brandBlue);
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on_rounded, size: highlighted ? 34 : 27, color: c),
        Positioned(
          top: highlighted ? 6 : 4,
          child: Text(
            '$index',
            style: GoogleFonts.inter(
              fontSize: highlighted ? 10 : 9,
              fontWeight: FontWeight.w900,
              color: rotoscope && !highlighted ? Colors.black : Colors.white,
            ),
          ),
        ),
        if (open == true)
          Positioned(
            right: 2,
            top: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _PersonPin extends StatelessWidget {
  final String label;
  const _PersonPin({required this.label});

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brandPink,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

/// Opens a full-screen interactive Live Map & Turn-by-Turn Navigation modal
/// with "What's Near Me" radar, "Fly Me There" real-time flight, Auto-Focus Location,
/// Map History, and AI Map Concierge.
Future<void> showOneovaFullMapModal(
  BuildContext context, {
  LatLng? me,
  List<GeoPlace> places = const [],
  GeoRoute? route,
  LatLng? destination,
  String? destinationName,
  Map<String, LatLng> others = const {},
  bool rotoscopeInitial = true,
  bool startNavigatingInitial = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OneovaFullMapSheet(
      initialMe: me,
      initialPlaces: places,
      initialRoute: route,
      initialDestination: destination,
      initialDestinationName: destinationName,
      others: others,
      rotoscopeInitial: rotoscopeInitial,
      startNavigatingInitial: startNavigatingInitial,
    ),
  );
}

class _OneovaFullMapSheet extends StatefulWidget {
  final LatLng? initialMe;
  final List<GeoPlace> initialPlaces;
  final GeoRoute? initialRoute;
  final LatLng? initialDestination;
  final String? initialDestinationName;
  final Map<String, LatLng> others;
  final bool rotoscopeInitial;
  final bool startNavigatingInitial;

  const _OneovaFullMapSheet({
    this.initialMe,
    this.initialPlaces = const [],
    this.initialRoute,
    this.initialDestination,
    this.initialDestinationName,
    this.others = const {},
    this.rotoscopeInitial = true,
    this.startNavigatingInitial = false,
  });

  @override
  State<_OneovaFullMapSheet> createState() => _OneovaFullMapSheetState();
}

class _OneovaFullMapSheetState extends State<_OneovaFullMapSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  LatLng? _me;
  late List<GeoPlace> _places;
  GeoRoute? _route;
  LatLng? _destination;
  String? _destinationName;
  LatLng? _flyTarget;
  String? _flyTargetLabel;
  late bool _rotoscope;
  late bool _navigating;
  String _mode = 'driving';
  String _selectedNearCat = '';
  int? _highlightIndex;
  int _activeStepIndex = 0;
  bool _loadingRoute = false;
  bool _showStepsList = false;
  bool _showHistory = false;
  String? _aiAreaInsight;
  bool _aiLoading = false;

  static const List<(String, String, IconData)> _nearCategories = [
    ('food', "What's Near Me", Icons.near_me_rounded),
    ('cafe', 'Coffee & Cafe', Icons.local_cafe_rounded),
    ('shop', 'Shops & Malls', Icons.shopping_bag_outlined),
    ('atm', 'ATM & Bank', Icons.account_balance_rounded),
    ('fuel', 'Fuel Station', Icons.local_gas_station_rounded),
    ('pharmacy', 'Pharmacy', Icons.local_pharmacy_rounded),
    ('hotel', 'Hotels', Icons.hotel_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _me = widget.initialMe;
    _places = List.of(widget.initialPlaces);
    _route = widget.initialRoute;
    _destination = widget.initialDestination;
    _destinationName = widget.initialDestinationName;
    _rotoscope = widget.rotoscopeInitial;
    _navigating = widget.startNavigatingInitial;
    if (_route != null) _mode = _route!.mode;
    OneovaMapHistoryService.instance.warm();
    if (_me == null) _resolveMe();
  }

  Future<void> _resolveMe() async {
    try {
      final p = await GeoServices.instance.current();
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      setState(() {
        _me = pt;
        if (_destination == null && _places.isEmpty) {
          _flyTarget = pt;
          _flyTargetLabel = 'Your Location';
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanWhatsNearMe(String category) async {
    HapticFeedback.selectionClick();
    var me = _me;
    if (me == null) {
      try {
        final p = await GeoServices.instance.current();
        me = LatLng(p.latitude, p.longitude);
        _me = me;
      } catch (_) {
        return;
      }
    }
    setState(() {
      _selectedNearCat = category;
      _loadingRoute = true;
      _showHistory = false;
      _showStepsList = false;
    });
    try {
      final hits = await GeoServices.instance.nearby(me, category, radiusM: 2200, limit: 8);
      if (!mounted) return;
      setState(() {
        _places = hits;
        _highlightIndex = hits.isNotEmpty ? 0 : null;
        if (hits.isNotEmpty) {
          _flyTarget = hits.first.point;
          _flyTargetLabel = hits.first.name;
        }
        _loadingRoute = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _askAiAboutMap(String question) async {
    HapticFeedback.selectionClick();
    setState(() {
      _aiLoading = true;
      _aiAreaInsight = null;
    });
    try {
      final me = _me;
      final placeNames = _places.take(5).map((p) => '${p.name} (${formatDistance(p.distanceM ?? 0)})').join(', ');
      final prompt = [
        'User question on live map: "$question"',
        if (me != null) 'User GPS: ${me.latitude.toStringAsFixed(4)}, ${me.longitude.toStringAsFixed(4)}',
        if (_destinationName != null) 'Active destination: $_destinationName',
        if (placeNames.isNotEmpty) 'Nearby places on map: $placeNames',
        if (_route != null) 'Active route: ${formatDistance(_route!.distanceM)}, ${formatDuration(_route!.durationS)} by $_mode',
        'Reply in 2 concise, helpful sentences.',
      ].join('\n');
      final ans = await OneovaAiGateway.generate(
        prompt: prompt,
        systemInstruction: 'You are Ova AI Map Concierge inside Oneova. Give concise, practical location, route, and local discovery advice.',
        maxOutputTokens: 120,
      ).timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() {
          _aiAreaInsight = ans.trim();
          _aiLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiAreaInsight = 'Tap any place pin or "What\'s Near Me" chip to fly there in real time and start live directions.';
          _aiLoading = false;
        });
      }
    }
  }

  Future<void> _recalculateRoute({String? mode, LatLng? target, String? name, bool fly = false}) async {
    final dest = target ?? _destination;
    final me = _me;
    if (dest == null || me == null) return;
    final nextMode = mode ?? _mode;
    setState(() {
      _mode = nextMode;
      _destination = dest;
      if (name != null) _destinationName = name;
      if (fly) {
        _flyTarget = dest;
        _flyTargetLabel = name ?? _destinationName ?? 'Destination';
      }
      _loadingRoute = true;
    });
    OneovaMapHistoryService.instance.record(
      title: name ?? _destinationName ?? 'Route Destination',
      point: dest,
      actionType: fly ? 'fly' : 'route',
    );
    final r = await GeoServices.instance.route(me, dest, mode: nextMode);
    if (!mounted) return;
    setState(() {
      _route = r;
      _activeStepIndex = 0;
      _loadingRoute = false;
    });
  }

  Future<void> _searchPlaces(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _loadingRoute = true;
      _showHistory = false;
    });
    try {
      final hits = await GeoServices.instance.search(q, near: _me, limit: 6);
      if (!mounted) return;
      setState(() {
        _places = hits;
        _highlightIndex = hits.isNotEmpty ? 0 : null;
        _loadingRoute = false;
      });
      if (hits.isNotEmpty) {
        await _recalculateRoute(
          target: hits.first.point,
          name: hits.first.name,
          fly: true,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _updateActiveStep(LatLng currentPos) {
    final r = _route;
    if (r == null || r.steps.isEmpty) return;
    var bestIdx = _activeStepIndex;
    var bestDist = double.infinity;
    for (var i = 0; i < r.steps.length; i++) {
      final d = GeoServices.instance.distanceM(currentPos, r.steps[i].location);
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
    final steps = _route?.steps ?? const <GeoRouteStep>[];
    final currentStep = (steps.isNotEmpty && _activeStepIndex < steps.length)
        ? steps[_activeStepIndex]
        : null;
    final remainingM = (_me != null && _destination != null)
        ? GeoServices.instance.distanceM(_me!, _destination!)
        : _route?.distanceM;
    final historyItems = OneovaMapHistoryService.instance.items;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        children: [
          // Top Header / Search Bar + History Button + Share Live
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: context.textPrimary),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onSubmitted: _searchPlaces,
                    style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _destinationName ?? 'Search or say "Fly me to…"',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.brandBlue),
                      filled: true,
                      fillColor: context.surfaceMid,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(color: context.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        borderSide: BorderSide(color: context.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Map & Location History',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _showHistory = !_showHistory;
                      _showStepsList = false;
                    });
                  },
                  icon: Icon(
                    Icons.history_rounded,
                    color: _showHistory ? AppColors.brandPink : AppColors.brandBlue,
                  ),
                ),
                if (_me != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Share live / current location',
                    onPressed: () {
                      final pt = _me!;
                      SharePlus.instance.share(
                        ShareParams(
                          text: '📍 My live location on Oneova: https://maps.google.com/?q=${pt.latitude},${pt.longitude}',
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_location_rounded, color: AppColors.brandPink),
                  ),
              ],
            ),
          ),

          // "What's Near Me" & AI Map Quick Bar
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _askAiAboutMap("What's notable around my current location and best route tips?"),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.brandBlue, AppColors.brandPink],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'AI Area Guide',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final (catId, catLabel, catIcon) in _nearCategories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => _scanWhatsNearMe(catId),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _selectedNearCat == catId ? AppColors.brandBlue : context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: _selectedNearCat == catId ? AppColors.brandBlue : context.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              catIcon,
                              size: 12,
                              color: _selectedNearCat == catId ? Colors.white : AppColors.brandBlue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              catLabel,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _selectedNearCat == catId ? Colors.white : context.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // AI Concierge Insight Banner (when requested)
          if (_aiLoading || _aiAreaInsight != null)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.brandPink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _aiLoading ? 'Ova AI is analyzing this area…' : (_aiAreaInsight ?? ''),
                      style: GoogleFonts.inter(fontSize: 11.5, height: 1.35, color: context.textPrimary),
                    ),
                  ),
                  if (!_aiLoading)
                    GestureDetector(
                      onTap: () => setState(() => _aiAreaInsight = null),
                      child: Icon(Icons.close_rounded, size: 15, color: context.textMuted),
                    ),
                ],
              ),
            ),

          // Live Turn-by-Turn Top Banner when navigating or route active
          if (currentStep != null)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _navigating
                      ? [AppColors.brandBlue, const Color(0xFF073575)]
                      : [context.surfaceMid, context.surfaceMid],
                ),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _navigating ? AppColors.brandPink : context.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    maneuverIcon(currentStep.maneuverType, currentStep.modifier),
                    color: _navigating ? Colors.white : AppColors.brandBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentStep.instruction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _navigating ? Colors.white : context.textPrimary,
                          ),
                        ),
                        Text(
                          '${formatDistance(currentStep.distanceM)} · Step ${_activeStepIndex + 1} of ${steps.length}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _navigating ? Colors.white70 : context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _showStepsList = !_showStepsList;
                      _showHistory = false;
                    }),
                    icon: Icon(
                      _showStepsList ? Icons.map_rounded : Icons.format_list_bulleted_rounded,
                      size: 15,
                      color: _navigating ? Colors.white : AppColors.brandBlue,
                    ),
                    label: Text(
                      _showStepsList ? 'Map' : 'Steps (${steps.length})',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _navigating ? Colors.white : AppColors.brandBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main Map + History Overlay + Steps Overlay
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: OneovaMapView(
                      me: _me,
                      places: _places,
                      route: _route,
                      destination: _destination,
                      destinationName: _destinationName,
                      flyTarget: _flyTarget,
                      flyTargetLabel: _flyTargetLabel,
                      others: widget.others,
                      trackUser: true,
                      sampleSignal: true,
                      height: double.infinity,
                      highlightIndex: _highlightIndex,
                      rotoscopeHighlight: _rotoscope,
                      navigating: _navigating,
                      activeStepIndex: _activeStepIndex,
                      onRotoscopeChanged: (v) => setState(() => _rotoscope = v),
                      onPlaceTap: (i) {
                        setState(() => _highlightIndex = i);
                        _recalculateRoute(
                          target: _places[i].point,
                          name: _places[i].name,
                          fly: true,
                        );
                      },
                      onMove: (pt) {
                        _me = pt;
                        if (_navigating) _updateActiveStep(pt);
                      },
                      onExpandFullScreen: () {},
                    ),
                  ),
                  if (_loadingRoute)
                    const Positioned(
                      top: 48,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.brandPink,
                        ),
                      ),
                    ),

                  // Map & Location History Drawer
                  if (_showHistory)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.surface.withValues(alpha: 0.97),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.border),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.history_rounded, size: 17, color: AppColors.brandBlue),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Map & Location History',
                                    style: GoogleFonts.inter(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (historyItems.isNotEmpty)
                                    TextButton(
                                      onPressed: () async {
                                        await OneovaMapHistoryService.instance.clear();
                                        if (mounted) setState(() {});
                                      },
                                      child: Text(
                                        'Clear',
                                        style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.brandPink),
                                      ),
                                    ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => setState(() => _showHistory = false),
                                    icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: context.border),
                            Expanded(
                              child: historyItems.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Places you search, route to, or fly to appear here.',
                                        style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(10),
                                      itemCount: historyItems.length,
                                      separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
                                      itemBuilder: (_, idx) {
                                        final item = historyItems[idx];
                                        return ListTile(
                                          dense: true,
                                          leading: Icon(
                                            item.actionType == 'fly'
                                                ? Icons.flight_rounded
                                                : (item.actionType == 'route'
                                                    ? Icons.directions_rounded
                                                    : Icons.place_rounded),
                                            color: AppColors.brandBlue,
                                            size: 18,
                                          ),
                                          title: Text(
                                            item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w700,
                                              color: context.textPrimary,
                                            ),
                                          ),
                                          subtitle: item.subtitle != null
                                              ? Text(
                                                  item.subtitle!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                                                )
                                              : null,
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextButton.icon(
                                                onPressed: () {
                                                  setState(() {
                                                    _showHistory = false;
                                                    _destination = item.point;
                                                    _destinationName = item.title;
                                                    _flyTarget = item.point;
                                                    _flyTargetLabel = item.title;
                                                  });
                                                  _recalculateRoute(
                                                    target: item.point,
                                                    name: item.title,
                                                    fly: true,
                                                  );
                                                },
                                                icon: const Icon(Icons.flight_rounded, size: 14, color: AppColors.brandPink),
                                                label: Text(
                                                  'Fly There',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.brandPink,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (_showStepsList && steps.isNotEmpty)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.surface.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.border),
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: steps.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
                          itemBuilder: (_, idx) {
                            final st = steps[idx];
                            final active = idx == _activeStepIndex;
                            return ListTile(
                              dense: true,
                              selected: active,
                              leading: Icon(
                                maneuverIcon(st.maneuverType, st.modifier),
                                color: active ? AppColors.brandPink : AppColors.brandBlue,
                              ),
                              title: Text(
                                st.instruction,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                                  color: context.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '${formatDistance(st.distanceM)} · ${formatDuration(st.durationS)}',
                                style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                              ),
                              onTap: () {
                                setState(() {
                                  _activeStepIndex = idx;
                                  _showStepsList = false;
                                  _flyTarget = st.location;
                                  _flyTargetLabel = st.instruction;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Controls: Travel Modes + Fly Me There + Start Live Navigation
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (final (mId, mLabel, mIcon) in const [
                        ('driving', 'Drive', Icons.directions_car_rounded),
                        ('walking', 'Walk', Icons.directions_walk_rounded),
                        ('cycling', 'Bike', Icons.directions_bike_rounded),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            selected: _mode == mId,
                            selectedColor: AppColors.brandBlue,
                            backgroundColor: context.surfaceMid,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mIcon,
                                  size: 14,
                                  color: _mode == mId ? Colors.white : context.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  mLabel,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: _mode == mId ? Colors.white : context.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            onSelected: (_) => _recalculateRoute(mode: mId),
                          ),
                        ),
                      const Spacer(),
                      if (_route != null)
                        Text(
                          '${formatDuration(_route!.durationS)} · ${formatDistance(remainingM ?? _route!.distanceM)}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (_destination != null) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            side: const BorderSide(color: AppColors.brandPink),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _flyTarget = _destination;
                              _flyTargetLabel = _destinationName ?? 'Destination';
                            });
                          },
                          icon: const Icon(Icons.flight_rounded, size: 16, color: AppColors.brandPink),
                          label: Text(
                            'Fly Me There',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandPink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _navigating ? AppColors.brandPink : AppColors.brandBlue,
                            minimumSize: const Size(0, 40),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          onPressed: _destination == null && _places.isEmpty
                              ? () => _scanWhatsNearMe('food')
                              : () {
                                  HapticFeedback.mediumImpact();
                                  if (_destination == null && _places.isNotEmpty) {
                                    _recalculateRoute(
                                      target: _places.first.point,
                                      name: _places.first.name,
                                      fly: true,
                                    );
                                  }
                                  setState(() => _navigating = !_navigating);
                                },
                          icon: Icon(
                            _destination == null && _places.isEmpty
                                ? Icons.near_me_rounded
                                : (_navigating ? Icons.stop_circle_rounded : Icons.navigation_rounded),
                            size: 17,
                            color: Colors.white,
                          ),
                          label: Text(
                            _destination == null && _places.isEmpty
                                ? "Scan What's Near Me"
                                : (_navigating ? 'Stop Live Navigation' : 'Start Live Directions'),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
