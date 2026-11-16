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
/// Follows the user's real position live, highlights places and routes with
/// **Rotoscope Contour Highlighter**, animates the route polyline, provides
/// in-app **Start Live Turn-by-Turn Directions**, and includes WhatsApp-style
/// **Live Location Sharing** controls.
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
  late bool _rotoscope;
  late bool _navigating;
  int _activeStepIndex = 0;
  bool _showSteps = false;
  double _speedMps = 0;
  int? _activeLiveShareMins;

  @override
  void initState() {
    super.initState();
    _signal = widget.spec.signal;
    _me = widget.spec.me;
    _rotoscope = widget.spec.rotoscopeHighlight;
    _navigating = widget.spec.autoStartNavigation;
    _activeLiveShareMins = widget.spec.liveShareMinutes;
    if (widget.spec.places.isNotEmpty) _selected = 0;
  }

  double? get _remainingM {
    final d = widget.spec.destination;
    final me = _me;
    if (d == null || me == null) return null;
    return GeoServices.instance.distanceM(me, d.point);
  }

  void _updateStepForPosition(LatLng pt) {
    final steps = widget.spec.route?.steps ?? const <GeoRouteStep>[];
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
    final spec = widget.spec;
    final sel = (_selected != null && _selected! < spec.places.length)
        ? spec.places[_selected!]
        : null;
    final remaining = _remainingM;
    final steps = spec.route?.steps ?? const <GeoRouteStep>[];
    final currentStep = (steps.isNotEmpty && _activeStepIndex < steps.length)
        ? steps[_activeStepIndex]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active Turn-by-Turn Direction Header when Navigating or Route available
        if (currentStep != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                Icon(
                  maneuverIcon(currentStep.maneuverType, currentStep.modifier),
                  size: 20,
                  color: _navigating ? Colors.white : AppColors.brandBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentStep.instruction,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _navigating ? Colors.white : context.textPrimary,
                        ),
                      ),
                      Text(
                        '${formatDistance(currentStep.distanceM)} · ${spec.route != null ? formatDuration(spec.route!.durationS) : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

        // Interactive Map with Rotoscope Highlighter & Live Animated Route
        OneovaMapView(
          me: spec.me,
          places: spec.places,
          route: spec.route,
          destination: spec.destination?.point,
          destinationName: spec.destination?.name,
          trackUser: true,
          sampleSignal: true,
          height: spec.route != null || spec.places.isNotEmpty ? 225 : 185,
          highlightIndex: _selected,
          rotoscopeHighlight: _rotoscope,
          navigating: _navigating,
          activeStepIndex: _activeStepIndex,
          onRotoscopeChanged: (v) => setState(() => _rotoscope = v),
          onPlaceTap: (i) => setState(() => _selected = i),
          onMove: (p) {
            setState(() => _me = p);
            if (_navigating) _updateStepForPosition(p);
          },
          onSpeedMps: (s) => setState(() => _speedMps = s),
          onSignal: (s) => setState(() {
            _signal = s;
            if (!s.strong) _weakSamples++;
          }),
        ),

        const SizedBox(height: 6),

        // Primary Action Bar: Start Live Directions, Rotoscope, Full Map & Live Share
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (spec.destination != null || sel != null)
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (spec.route != null) {
                    setState(() => _navigating = !_navigating);
                  } else if (sel != null) {
                    widget.onPrompt?.call('start navigation to ${sel.name}');
                  } else if (spec.destination != null) {
                    GeoServices.instance.openNavigation(
                      spec.destination!.point,
                      mode: spec.mode,
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _navigating ? AppColors.brandPink : AppColors.brandBlue,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _navigating ? Icons.stop_circle_rounded : Icons.navigation_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _navigating ? 'Stop Navigation' : 'Start',
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
            _chip(
              context,
              Icons.fiber_manual_record_rounded,
              _activeLiveShareMins != null
                  ? 'Sharing Live (${_activeLiveShareMins}m)'
                  : 'Live GPS',
              AppColors.brandPink,
            ),
            if (_speedMps > 0.6)
              _chip(
                context,
                Icons.speed_rounded,
                '${(_speedMps * 3.6).round()} km/h',
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
            if (remaining != null)
              _chip(
                context,
                Icons.flag_rounded,
                '${formatDistance(remaining)} to go',
                AppColors.brandBlue,
              ),
            // WhatsApp-style Live Location Share quick pill
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                final pt = _me ?? spec.me;
                setState(() => _activeLiveShareMins = _activeLiveShareMins == 60 ? null : 60);
                SharePlus.instance.share(
                  ShareParams(
                    text: '📍 Live Location (Oneova): https://maps.google.com/?q=${pt.latitude},${pt.longitude}',
                  ),
                );
              },
              child: _chip(
                context,
                Icons.share_location_rounded,
                'Share Live',
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

        if (_weakSamples > 0 && spec.route != null) ...[
          const SizedBox(height: 4),
          Text(
            'Weak signal recorded on your way (pink dots). Download the route in Google Maps before you lose coverage.',
            style: GoogleFonts.inter(fontSize: 10.5, height: 1.35, color: context.textSecondary),
          ),
        ],

        // Highlighted Place Card with Directions + Start Navigation
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
                  tooltip: 'Animated Route & Steps',
                  onPressed: () => widget.onPrompt?.call('navigate to ${sel.name}'),
                  icon: const Icon(Icons.directions_rounded, size: 18, color: AppColors.brandBlue),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Start Navigation Now',
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
