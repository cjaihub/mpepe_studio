import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/location/geo_services.dart';
import '../../shared/location/oneova_map_view.dart';
import '../../shared/theme/app_theme.dart';
import '../core/ova_tool_result.dart';

/// The map inside an Ova answer. It follows the user's real position live,
/// highlights the places Ova found, draws the route, and records the
/// measured signal along the way (blue = strong, pink = weak).
class OvaLiveMapCard extends StatefulWidget {
  final OvaMapSpec spec;
  final ValueChanged<String>? onPrompt;

  const OvaLiveMapCard({super.key, required this.spec, this.onPrompt});

  @override
  State<OvaLiveMapCard> createState() => _OvaLiveMapCardState();
}

class _OvaLiveMapCardState extends State<OvaLiveMapCard> {
  GeoSignal? _signal;
  LatLng? _me;
  int? _selected;
  int _weakSamples = 0;

  @override
  void initState() {
    super.initState();
    _signal = widget.spec.signal;
    _me = widget.spec.me;
  }

  double? get _remainingM {
    final d = widget.spec.destination;
    final me = _me;
    if (d == null || me == null) return null;
    return GeoServices.instance.distanceM(me, d.point);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final sel = _selected == null ? null : spec.places[_selected!];
    final remaining = _remainingM;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OneovaMapView(
          me: spec.me,
          places: spec.places,
          route: spec.route,
          destination: spec.destination?.point,
          trackUser: true,
          sampleSignal: true,
          height: spec.route != null || spec.places.isNotEmpty ? 210 : 170,
          highlightIndex: _selected,
          onPlaceTap: (i) => setState(() => _selected = i),
          onMove: (p) => setState(() => _me = p),
          onSignal: (s) => setState(() {
            _signal = s;
            if (!s.strong) _weakSamples++;
          }),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(context, Icons.fiber_manual_record_rounded, 'Live', AppColors.brandPink),
            if (_signal != null)
              _chip(
                context,
                _signal!.network == 'wifi' ? Icons.wifi_rounded : Icons.signal_cellular_alt_rounded,
                _signal!.label,
                signalColor(context, _signal!),
              ),
            if (remaining != null)
              _chip(context, Icons.flag_rounded, '${formatDistance(remaining)} to go', AppColors.brandBlue),
          ],
        ),
        if (_weakSamples > 0 && spec.route != null) ...[
          const SizedBox(height: 4),
          Text(
            'Weak signal recorded on your way (pink dots). Download the route in Google Maps before you lose coverage.',
            style: GoogleFonts.inter(fontSize: 10.5, height: 1.35, color: context.textSecondary),
          ),
        ],
        if (sel != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      Text(
                        [
                          if (sel.distanceM != null) formatDistance(sel.distanceM!),
                          if (sel.openNow == true) 'Open now',
                          if (sel.openNow == false) 'Closed',
                          ?sel.address,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Directions',
                  onPressed: () => widget.onPrompt?.call('navigate to ${sel.name}'),
                  icon: const Icon(Icons.directions_rounded, size: 18, color: AppColors.brandBlue),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Navigate now',
                  onPressed: () => GeoServices.instance.openNavigation(sel.point, mode: spec.mode),
                  icon: const Icon(Icons.navigation_rounded, size: 18, color: AppColors.brandPink),
                ),
              ],
            ),
          ),
        ],
      ],
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
          Text(text, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
        ],
      ),
    );
  }
}
