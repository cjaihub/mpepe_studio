# MPEPE STUDIO Design System

## Typography & Colors
- **Font**: `GoogleFonts.inter` (Weights: w700, w900 for active states).
- **Primary Brand (Red)**: `AppColors.mpepeMaroon` (`#990000`). Used for all active states, focal buttons, and primary highlights. No faint reds.
- **Dark Mode Surfaces**: `AppColors.darkBackground` (`#0A0A0A`) -> `AppColors.darkSurface` (`#141414`) -> `AppColors.darkSurfaceHighlight` (`#1F1F1F`).

## Component Guidelines
1. **Modals**: ONLY use `AppModals` for confirmation, destructive, or error alerts. Do NOT write ad-hoc dialogs.
2. **Navigation**: Always use `context.push()` to maintain the back stack. Never use `context.go()` for hierarchical navigation.
3. **Elevation**: Use 2px borders or soft drop shadows. No generic thin grid lines.
