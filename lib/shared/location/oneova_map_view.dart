import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

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

/// A compact OpenStreetMap view used by chat location bubbles and Ova.
///
/// With [trackUser] it follows the phone's real position live and, with
/// [sampleSignal], records the measured network signal along the way.
class OneovaMapView extends StatefulWidget {
  /// Fixed position of the user (or of the shared pin) when not tracking.
  final LatLng? me;
  final List<GeoPlace> places;
  final GeoRoute? route;
  final LatLng? destination;

  /// Other people's live pins (chat live location), label -> point.
  final Map<String, LatLng> others;
  final bool trackUser;
  final bool sampleSignal;
  final bool interactive;
  final double height;
  final int? highlightIndex;
  final ValueChanged<int>? onPlaceTap;
  final ValueChanged<GeoSignal>? onSignal;
  final ValueChanged<LatLng>? onMove;

  const OneovaMapView({
    super.key,
    this.me,
    this.places = const [],
    this.route,
    this.destination,
    this.others = const {},
    this.trackUser = false,
    this.sampleSignal = false,
    this.interactive = true,
    this.height = 200,
    this.highlightIndex,
    this.onPlaceTap,
    this.onSignal,
    this.onMove,
  });

  @override
  State<OneovaMapView> createState() => _OneovaMapViewState();
}

class _OneovaMapViewState extends State<OneovaMapView> {
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  Timer? _signalTimer;
  LatLng? _me;
  double? _heading;
  bool _follow = true;
  bool _ready = false;
  final List<SignalSample> _trail = [];

  @override
  void initState() {
    super.initState();
    _me = widget.me;
    if (widget.trackUser) _startTracking();
  }

  @override
  void didUpdateWidget(OneovaMapView old) {
    super.didUpdateWidget(old);
    if (!widget.trackUser && widget.me != null && widget.me != old.me) {
      _me = widget.me;
      if (_ready && _follow) _map.move(widget.me!, _map.camera.zoom);
    }
    if (widget.route != old.route || widget.places.length != old.places.length) _fit();
  }

  void _startTracking() {
    _sub = GeoServices.instance.track(distanceFilterM: 5).listen((p) {
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      setState(() {
        _me = pt;
        _heading = p.heading >= 0 ? p.heading : null;
      });
      widget.onMove?.call(pt);
      if (_ready && _follow && widget.route == null && widget.places.isEmpty) {
        _map.move(pt, _map.camera.zoom);
      }
    }, onError: (Object e) => debugPrint('[OneovaMapView] tracking: $e'));
    if (widget.sampleSignal) {
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
      _map.move(pts.first, 16);
      return;
    }
    _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(36), maxZoom: 17));
  }

  @override
  Widget build(BuildContext context) {
    final pts = _allPoints;
    final center = pts.isNotEmpty ? pts.first : const LatLng(0, 0);
    final dark = AppColors.isDark(context);
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: pts.isEmpty ? 2 : 15,
                backgroundColor: context.surfaceMid,
                interactionOptions: InteractionOptions(
                  flags: widget.interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none,
                ),
                onMapReady: () {
                  _ready = true;
                  _fit();
                },
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                ColorFiltered(
                  colorFilter: dark
                      ? const ColorFilter.matrix([
                          0.75, 0, 0, 0, 0, //
                          0, 0.75, 0, 0, 0,
                          0, 0, 0.8, 0, 0,
                          0, 0, 0, 1, 0,
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.oneova.app',
                    maxZoom: 19,
                  ),
                ),
                if (widget.route != null)
                  PolylineLayer(polylines: [
                    Polyline(points: widget.route!.points, strokeWidth: 6, color: Colors.white.withValues(alpha: 0.9)),
                    Polyline(points: widget.route!.points, strokeWidth: 4, color: AppColors.brandBlue),
                  ]),
                if (_trail.isNotEmpty)
                  CircleLayer(circles: [
                    for (final s in _trail)
                      CircleMarker(point: s.point, radius: 4, color: signalColor(context, s.signal).withValues(alpha: 0.8)),
                  ]),
                MarkerLayer(markers: [
                  for (var i = 0; i < widget.places.length; i++)
                    Marker(
                      point: widget.places[i].point,
                      width: 30,
                      height: 30,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: widget.onPlaceTap == null ? null : () => widget.onPlaceTap!(i),
                        child: _PlacePin(index: i + 1, highlighted: widget.highlightIndex == i, open: widget.places[i].openNow),
                      ),
                    ),
                  if (widget.destination != null)
                    Marker(
                      point: widget.destination!,
                      width: 30,
                      height: 30,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on_rounded, size: 30, color: AppColors.brandPink),
                    ),
                  for (final e in widget.others.entries)
                    Marker(point: e.value, width: 34, height: 34, child: _PersonPin(label: e.key)),
                  if (_me != null) Marker(point: _me!, width: 26, height: 26, child: _MeDot(heading: _heading, live: widget.trackUser)),
                ]),
              ],
            ),
            Positioned(
              right: 4,
              bottom: 2,
              child: Text('© OpenStreetMap', style: GoogleFonts.inter(fontSize: 8.5, color: Colors.black54)),
            ),
            if (widget.interactive && pts.isNotEmpty)
              Positioned(
                right: 6,
                top: 6,
                child: Material(
                  color: context.surface,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() => _follow = true);
                      _fit();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(_follow ? Icons.my_location_rounded : Icons.location_searching_rounded, size: 16, color: AppColors.brandBlue),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MeDot extends StatelessWidget {
  final double? heading;
  final bool live;
  const _MeDot({this.heading, this.live = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brandBlue.withValues(alpha: 0.18),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brandBlue,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      ),
    );
  }
}

class _PlacePin extends StatelessWidget {
  final int index;
  final bool highlighted;
  final bool? open;
  const _PlacePin({required this.index, this.highlighted = false, this.open});

  @override
  Widget build(BuildContext context) {
    final c = highlighted ? AppColors.brandPink : AppColors.brandBlue;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Icon(Icons.location_on_rounded, size: highlighted ? 30 : 26, color: c),
        Positioned(
          top: highlighted ? 5 : 4,
          child: Text('$index', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
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
      child: Text(initial, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}
