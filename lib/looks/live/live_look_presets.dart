import '../models/oneova_look.dart';

/// Color looks a host can put on the live camera (GPU track processor).
/// Shared by the live control hub and the advanced live settings sheet.
const liveLookPresets = <OneovaLook>[
  OneovaLook(id: 'neutral', name: 'Neutral'),
  OneovaLook(
    id: 'cinematic',
    name: 'Cinematic',
    primary: LookPrimary(contrast: 1.15, highlights: -0.1, shadows: 0.05),
    color: LookColor(vibrance: 0.2),
  ),
  OneovaLook(
    id: 'golden_hour',
    name: 'Golden Hour',
    color: LookColor(temperature: 15.0, tint: 2.0, vibrance: 0.25),
    primary: LookPrimary(exposure: 0.1),
  ),
  OneovaLook(
    id: 'portrait_glow',
    name: 'Portrait Glow',
    primary: LookPrimary(contrast: 1.05, highlights: 0.1),
    color: LookColor(temperature: 5.0, saturation: 1.1),
  ),
  OneovaLook(
    id: 'moody_film',
    name: 'Moody Film',
    primary: LookPrimary(contrast: 1.25, shadows: -0.15, blacks: 0.05),
    film: LookFilm(grain: 0.15),
  ),
];
