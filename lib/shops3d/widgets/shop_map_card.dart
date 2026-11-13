import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart';
import '../models/shop_models.dart';

/// "Find the shop": how far the shop is from you on a tilted map that always
/// faces the shop. **Take me there** follows you live as you move, with the
/// distance counting down; turn-by-turn voice directions open in Maps.
Future<void> showShopMapSheet(BuildContext context, Shop3D shop) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _ShopMap(shop: shop),
  );
}

String formatDistance(double metres) {
  if (metres < 950) return '${(metres / 10).round() * 10} m';
  if (metres < 10000) return '${(metres / 1000).toStringAsFixed(1)} km';
  return '${(metres / 1000).round()} km';
}

class _ShopMap extends StatefulWidget {
  const _ShopMap({required this.shop});
  final Shop3D shop;

  @override
  State<_ShopMap> createState() => _ShopMapState();
}

class _ShopMapState extends State<_ShopMap> {
  final _map = MapController();
  StreamSubscription<Position>? _sub;
  LatLng? _me;
  String? _problem;
  bool _guiding = false;
  bool _ready = false;

  late final LatLng _shop = LatLng(widget.shop.lat!, widget.shop.lng!);

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return setState(() => _problem = 'Turn on location to see how far the shop is.');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return setState(() => _problem = 'Allow location to see how far the shop is.');
      }
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _me = LatLng(p.latitude, p.longitude));
      _frame();
    } catch (_) {
      if (mounted) setState(() => _problem = "Couldn't find where you are right now.");
    }
  }

  double get _metres => _me == null ? 0 : Geolocator.distanceBetween(_me!.latitude, _me!.longitude, _shop.latitude, _shop.longitude);

  /// Degrees clockwise from north, from me to the shop.
  double get _bearing => _me == null ? 0 : Geolocator.bearingBetween(_me!.latitude, _me!.longitude, _shop.latitude, _shop.longitude);

  /// Overview: both ends in view. Guiding: close on me, shop straight ahead.
  void _frame() {
    final me = _me;
    if (me == null || !_ready) return;
    if (_guiding) {
      _map.moveAndRotate(me, 17, -_bearing);
    } else {
      final mid = LatLng((me.latitude + _shop.latitude) / 2, (me.longitude + _shop.longitude) / 2);
      // Zoom so the straight line between the two fills most of the card.
      final zoom = (15.6 - math.log(math.max(_metres, 60) / 500) / math.ln2).clamp(3.0, 17.0);
      _map.moveAndRotate(mid, zoom, -_bearing);
    }
  }

  void _guide() {
    HapticFeedback.mediumImpact();
    setState(() => _guiding = true);
    _frame();
    _sub?.cancel();
    _sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5)).listen((p) {
      if (!mounted) return;
      setState(() => _me = LatLng(p.latitude, p.longitude));
      _frame();
    });
  }

  Future<void> _directions() async {
    final nav = Uri.parse('google.navigation:q=${_shop.latitude},${_shop.longitude}');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
    } else {
      await launchUrl(
        Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '${_shop.latitude},${_shop.longitude}'}),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final arrived = _me != null && _metres < 40;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.title3(context.textPrimary)),
                Text(
                  _problem ?? (_me == null ? 'Finding where you are…' : (arrived ? 'You’re here' : '${formatDistance(_metres)} away in a straight line')),
                  style: AppTypography.caption(arrived ? AppColors.brandBlue : context.textSecondary),
                ),
              ]),
            ),
            if (_guiding) const _LivePill(),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: SizedBox(
              height: 280,
              child: Stack(fit: StackFit.expand, children: [
                // Tilted like a 3D map: the far edge recedes toward the shop.
                Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(-0.72)
                    ..scaleByDouble(1.9, 1.9, 1.0, 1.0),
                  child: FlutterMap(
                    mapController: _map,
                    options: MapOptions(
                      initialCenter: _shop,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      onMapReady: () {
                        _ready = true;
                        _frame();
                      },
                    ),
                    children: [
                      ColorFiltered(
                        colorFilter: dark
                            ? const ColorFilter.matrix([0.7, 0, 0, 0, 0, 0, 0.7, 0, 0, 0, 0, 0, 0.78, 0, 0, 0, 0, 0, 1, 0])
                            : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                        child: TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.oneova.app',
                          maxZoom: 19,
                        ),
                      ),
                      if (_me != null)
                        PolylineLayer(polylines: [
                          Polyline(points: [_me!, _shop], strokeWidth: 4, color: AppColors.brandBlue, pattern: const StrokePattern.dotted()),
                        ]),
                      MarkerLayer(rotate: true, markers: [
                        Marker(
                          point: _shop,
                          width: 34,
                          height: 34,
                          alignment: Alignment.topCenter,
                          child: const Icon(Icons.storefront_rounded, color: AppColors.brandPink, size: 30),
                        ),
                        if (_me != null)
                          Marker(
                            point: _me!,
                            width: 22,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.brandBlue,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: AppShadows.glow(AppColors.brandBlue, radius: 10, spread: 1),
                              ),
                            ),
                          ),
                      ]),
                    ],
                  ),
                ),
                // Horizon fade so the tilted far edge blends away.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [context.surface, context.surface.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: Text('© OpenStreetMap', style: AppTypography.micro(context.textMuted).copyWith(fontSize: 8.5)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                onPressed: _me == null || _guiding ? null : _guide,
                icon: const Icon(Icons.navigation_rounded, size: 17),
                label: Text(_guiding ? 'Following you' : 'Take me there'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: context.textPrimary,
                side: BorderSide(color: context.border),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: _directions,
              icon: const Icon(Icons.turn_right_rounded, size: 17),
              label: const Text('Turn-by-turn'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text('LIVE', style: AppTypography.micro(Colors.white)),
      );
}
