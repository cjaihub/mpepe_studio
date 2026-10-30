import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../models/oneova_look.dart';

/// Snap-style Looks dock on the capture camera viewfinder:
/// circular look dials, category tabs, and real-time intensity slider.
class CameraLooksDock extends StatefulWidget {
  final OneovaLook activeLook;
  final ValueChanged<OneovaLook> onLookSelected;
  final ValueChanged<double> onIntensityChanged;
  final VoidCallback onOpenCatalog;
  final VoidCallback onClose;

  const CameraLooksDock({
    super.key,
    required this.activeLook,
    required this.onLookSelected,
    required this.onIntensityChanged,
    required this.onOpenCatalog,
    required this.onClose,
  });

  @override
  State<CameraLooksDock> createState() => _CameraLooksDockState();
}

class _CameraLooksDockState extends State<CameraLooksDock> {
  String _selectedCategory = 'All';

  static const List<OneovaLook> _starterLooks = [
    OneovaLook(id: 'neutral', name: 'Original', categories: ['all']),
    OneovaLook(
      id: 'cinematic_teal',
      name: 'Cinematic',
      categories: ['all', 'cinematic'],
      primary: LookPrimary(contrast: 1.15, shadows: 0.05),
      color: LookColor(vibrance: 0.25),
    ),
    OneovaLook(
      id: 'portrait_glow',
      name: 'Portrait',
      categories: ['all', 'portrait'],
      primary: LookPrimary(contrast: 1.05, highlights: 0.1),
      color: LookColor(temperature: 6.0, saturation: 1.1),
    ),
    OneovaLook(
      id: 'golden_hour',
      name: 'Golden Hour',
      categories: ['all', 'cinematic'],
      color: LookColor(temperature: 16.0, tint: 2.0, vibrance: 0.3),
      primary: LookPrimary(exposure: 0.1),
    ),
    OneovaLook(
      id: 'moody_film',
      name: 'Moody Film',
      categories: ['all', 'film'],
      primary: LookPrimary(contrast: 1.25, shadows: -0.15, blacks: 0.05),
      film: LookFilm(grain: 0.2),
    ),
    OneovaLook(
      id: 'vintage_70s',
      name: 'Vintage 70s',
      categories: ['all', 'vintage'],
      color: LookColor(temperature: 8.0, tint: -4.0, vibrance: 0.15),
      film: LookFilm(grain: 0.35, fade: 0.1),
    ),
    OneovaLook(
      id: 'tokyo_neon',
      name: 'Tokyo Neon',
      categories: ['all', 'cinematic'],
      color: LookColor(tint: 10.0, vibrance: 0.4),
      primary: LookPrimary(contrast: 1.2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedCategory == 'All'
        ? _starterLooks
        : _starterLooks
            .where((l) => l.categories.contains(_selectedCategory.toLowerCase()))
            .toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        border: Border.all(color: Colors.white24, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Category Tabs + Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Cinematic', 'Portrait', 'Film', 'Vintage'].map((cat) {
                        final isSel = _selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCategory = cat);
                            },
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSel ? AppColors.brandBlue : Colors.white12,
                                borderRadius: BorderRadius.circular(AppRadius.full),
                              ),
                              child: Text(
                                cat,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Intensity Slider (only when non-neutral look selected)
          if (widget.activeLook.id != 'neutral') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Intensity',
                    style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white70),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.brandBlue,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: widget.activeLook.intensity,
                        min: 0.0,
                        max: 1.0,
                        onChanged: widget.onIntensityChanged,
                      ),
                    ),
                  ),
                  Text(
                    '${(widget.activeLook.intensity * 100).toInt()}%',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Looks Dial Row
          SizedBox(
            height: 80,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: filtered.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (ctx, idx) {
                if (idx == filtered.length) {
                  // Catalog + More button
                  return InkWell(
                    onTap: widget.onOpenCatalog,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white30, width: 1.0),
                          ),
                          child: const Icon(Icons.apps_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'More',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final look = filtered[idx];
                final isSelected = widget.activeLook.id == look.id;

                return InkWell(
                  onTap: () => widget.onLookSelected(look),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppColors.brandBlue : Colors.white24,
                            width: isSelected ? 2.5 : 1.0,
                          ),
                          gradient: LinearGradient(
                            colors: isSelected
                                ? [AppColors.brandBlue, AppColors.brandPink]
                                : [Colors.white24, Colors.white10],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          look.name.substring(0, look.name.length >= 2 ? 2 : 1).toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 54,
                        child: Text(
                          look.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: isSelected ? AppColors.brandBlue : Colors.white,
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
    ).animate().slideY(begin: 0.15, duration: 200.ms).fadeIn(duration: 200.ms);
  }
}
