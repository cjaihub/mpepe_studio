---
trigger: always_on
---

# Oneova UI/UX Guidelines

*These rules must be strictly followed when implementing or modifying any UI/UX components in the application.*

---

## 1. Brand Identity & Universal Dual-Mode System (Light & Dark)
Our color palette defines the premium, striking aesthetic of Oneova. The application strictly supports **both Light and Dark modes globally**. Every component—both existing and new—must be fully wired to the global theme system.

### Brand Colors (The Core Blue & Pink Accent)
- **Primary / Brand Core:** `AppColors.brandBlue` (`#0C4FA8`). A deep, executive-grade Blue. **NEVER use Maroon or Red for the core branding.**
- **Secondary Accent:** `AppColors.brandPink` (`#FF2D87`). High-energy accent for live indicators, badges, remix buttons, unread notification dots, and secondary CTAs.
- **Usage of Blue:** Use solid Blue (`AppColors.brandBlue`) for primary action buttons, active navigation states, and key focal points. Pair with high-contrast stark white text and icons.

### Color Tokens by Theme
| Token | Dark Mode (`#0A0A0A` Studio Aesthetic) | Light Mode (Clean Corporate Luxury) | Dynamic Helper / Context Extension |
|---|---|---|---|
| **Background** | `AppColors.darkBackground` (`#0A0A0A`) | `AppColors.lightBackground` (`#FFFFFF`) | `context.bg` / `AppColors.background(context)` |
| **Card / Surface** | `AppColors.darkSurface` (`#141414`) | `AppColors.lightSurface` (`#F8FAFC`) | `context.surface` / `AppColors.surface(context)` |
| **Surface Mid / High** | `AppColors.darkSurfaceHighlight` (`#1F1F1F`)| `AppColors.lightSurfaceHighlight` (`#F1F5F9`)| `context.surfaceMid` / `AppColors.surfaceMid(context)` |
| **Border / Hairline** | `AppColors.outline` (`#262626`) | `AppColors.lightBorder` (`#E2E8F0`) | `context.border` / `AppColors.border(context)` |
| **Primary Text** | `AppColors.textPrimary` (`#F3F4F6`) | `AppColors.lightTextPrimary` (`#0F172A`) | `context.textPrimary` / `AppColors.textPrimaryOf(context)` |
| **Secondary Text** | `AppColors.textSecondary` (`#9CA3AF`) | `AppColors.lightTextSecondary` (`#475569`) | `context.textSecondary` / `AppColors.textSecondaryOf(context)` |
| **Muted Text** | `AppColors.textMuted` (`#6B7280`) | `AppColors.lightTextMuted` (`#94A3B8`) | `context.textMuted` / `AppColors.textMutedOf(context)` |

### CRITICAL RULE: Mandatory Global Light / Dark Mode Wiring
1. **Never Hardcode Fixed Colors:** 
   - NEVER use static `Colors.black`, `Colors.white`, or fixed dark hex codes (`0xFF0A0A0A`, `0xFF141414`, `0xFF1F1F1F`) on scaffolds, cards, modals, sheets, dialogs, borders, or text.
   - ALWAYS resolve dynamically via `context.bg`, `context.surface`, `context.surfaceMid`, `context.border`, `context.textPrimary`, `context.textSecondary`, `context.textMuted` (via `OneovaThemeExtension`) or `AppColors.background(context)`, `AppColors.surface(context)`, etc.
2. **High-Contrast Legibility in Both Modes:**
   - In Light Mode, text must be dark slate (`#0F172A` / `#475569`) with clear 1px borders against pure white/slate backgrounds. Never allow light-gray text on white backgrounds.
   - In Dark Mode, text must be soft white (`#F3F4F6`) with dark surface elevation against `#0A0A0A`. Never allow dark text on dark surfaces.
3. **Mandatory Dual-Mode Verification:**
   - Every single component or screen created or modified must be verified to look stunning and legible in **BOTH** Light and Dark modes.

---

## 2. High-Density Executive Scale ("Look Smaller, Tighter, More Legit & Premium")
The app must have a refined, compact, high-density iOS/Linear luxury aesthetic. Avoid bloated, oversized UI elements that waste screen real estate.

### Typography Scale (`GoogleFonts.inter`)
Use `AppTypography` or `GoogleFonts.inter` with calibrated compact sizes:
- **Display / H1:** 22 - 24px (`FontWeight.w800`, letterSpacing: -0.4, line-height: 1.25)
- **Page Titles / H2:** 17 - 19px (`FontWeight.w700`, letterSpacing: -0.3)
- **Card / Section Titles:** 14 - 15.5px (`FontWeight.w700`, letterSpacing: -0.2)
- **Subtitles & Callouts:** 12.5 - 13.5px (`FontWeight.w600`)
- **Body Text:** 12.5 - 13.0px (`FontWeight.w400` or `w500`, height: 1.35)
- **Captions & Secondary Meta:** 10.5 - 11.5px (`FontWeight.w400` or `w500`)
- **Micro Badges / Pill Tags:** 9.0 - 10.0px (`FontWeight.w800` or `w900`, letterSpacing: 0.6 - 1.0)

### Component Sizing & Density
- **Buttons:**
  - Standard button height: **38 - 42px** (never bloated 52-60px blocks).
  - Padding: `EdgeInsets.symmetric(horizontal: 16, vertical: 9)`.
  - Border radius: `AppRadius.sm` (8px) or `AppRadius.md` (12px).
- **Text Fields & Inputs:**
  - Always set `isDense: true`.
  - Content padding: `EdgeInsets.symmetric(horizontal: 12, vertical: 10)`.
  - Border radius: `AppRadius.sm` (8-10px) with 1.0px hairline border.
- **Navigation & App Bars:**
  - Bottom Navigation Bar height: **~62px** (never 76-80px). Center studio button: 44×32px (icon size 22).
  - Top AppBar / Header toolbar height: **48 - 52px**.
- **Corner Radii (`AppRadius`):**
  - `AppRadius.xs`: 4.0 (tags, small badges)
  - `AppRadius.sm`: 8.0 (inputs, small buttons, feature chips)
  - `AppRadius.md`: 12.0 (cards, list items, action tiles)
  - `AppRadius.lg`: 16.0 (hero cards, containers)
  - `AppRadius.xl`: 20.0 (bottom sheet tops, dialogs)
  - `AppRadius.full`: 999.0 (capsule pills, avatars)
- **Hairline Borders (1.0px):**
  - Always use crisp 1.0px hairline borders (`Border.all(color: context.border, width: 1.0)`).
  - Never use chunky 2-3px borders that make UI look unpolished or heavy.
- **Shadows (`AppShadows`):**
  - In Dark Mode: use subtle luminous glow (`AppShadows.glow`) or deep ambient shadows (`AppShadows.sm`).
  - In Light Mode: use soft natural drop shadows (`AppShadows.sm`, `AppShadows.md`) with subtle opacity (8-12%).

---

## 3. Components & Layouts
- **Containers & Cards:** Use `AppDecorations.groupedSection(context)` or `AppDecorations.card(context)` to automatically get the correct background, 1px hairline border, and border radius.
- **Organization:** Complex workflows (Uploads, Dashboards, Studio) must use clean `TabBar`s, segmented chips, and compact hierarchical cards.
- **Micro-Animations:** Use subtle, snappy micro-interactions:
  - `AnimatedScale` (scale: 0.96) on card/button tap states with `Duration(milliseconds: 150)`.
  - `flutter_animate` extensions (`.fadeIn(duration: 250.ms)`, `.slideY(begin: 0.05, end: 0)`).

---

## 4. User Interaction & Safeguards
- **Confirmations are Mandatory:** *CRITICAL RULE:* Before executing any significant or destructive action (Logout, Deleting, Canceling Uploads), you **MUST** present a confirmation dialog (Cancel / Confirm) to the user. Never execute immediately.
- **Haptic Feedback:** Pair interactive sheet openings and primary taps with `HapticFeedback.lightImpact()`.

---

## 5. Core Development Standards & Quality
- **No Mock Implementations:** Do NOT use mock data, dummy implementations, or `// TODO` stubs unless explicitly instructed by the user. Always wire real Firestore real-time streams, Riverpod providers, and production-ready code.
- **Corporate, Premium UI:** Layouts must look highly corporate and professional, like Linear, Apple, or Stripe. Avoid generic, repetitive, or basic layouts.
- **No Broken Code:** Do not commit or present broken, uncompilable code. Always verify syntax, imports, and types with `flutter analyze`.

---

## 6. Navigation & Routing (Strict)
- **Always Navigable:** Every screen you create or modify MUST be fully navigable forwards and backwards. Never trap the user on a screen.
- **Use `context.push()` instead of `context.go()`:** For hierarchical navigation (e.g., from a feed/dashboard to details), ALWAYS use `context.push('/path')` instead of `context.go('/path')`. `context.go()` replaces the route stack and prevents going back.
- **Explicit Back Buttons:** If a screen does not use a standard `AppBar`, you must explicitly implement a back button (e.g. `IconButton(icon: Icon(Icons.arrow_back))` calling `context.pop()`).
- **Verify Stack Safety:** Always verify that navigating back (`context.pop()`) lands the user on the logically expected previous screen.

---

## 7. Guardrail Verification (Mandatory Before Completing Any Task)
1. Run `flutter test test/guards/home_lock_test.dart`. It MUST pass 100%.
2. Run `flutter analyze` on touched files. It must report 0 issues.
3. Verify the app name is strictly **Oneova** (never Mpepe, Oneover, or Onerova).
4. Verify colors are strictly `AppColors.brandBlue` (#0C4FA8) primary and `AppColors.brandPink` (#FF2D87) secondary accent. Never Maroon or Red.
