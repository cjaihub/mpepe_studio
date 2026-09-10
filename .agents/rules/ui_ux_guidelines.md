---
trigger: always_on
---

# MPEPE STUDIO UI/UX Guidelines

*These rules must be strictly followed when implementing or modifying any UI/UX components in the application.*

## 1. Brand Identity & Colors
Our color palette defines the premium, striking aesthetic of MPEPE STUDIO. Always use `AppColors` definitions over hard-coded colors.

**Brand Colors (The Core Red):**
- **Primary / Brand Core:** `AppColors.mpepeMaroon` (`#990000`). This is a vibrant, premium Red. We no longer use or refer to any colors as "Maroon"; it has been fully replaced by this bright, bold Red. (Note: The variable is currently named `mpepeMaroon` for legacy code compatibility, but the color is strictly Red).
- **Legacy Mappings:** `AppColors.mpepeGold` and `AppColors.mpepeBrown` are mapped to `#990000` (Red) to maintain brand consistency.
- **Usage of Red:** Use solid Red (`#990000`) for active states, important backgrounds, and primary actions. Avoid using faint, translucent red (e.g., `alpha: 0.05` or `0.15`) for focal elements. Instead, use the solid color paired with high-contrast `Colors.white` text and icons.

**Premium Dark Mode (Studio Aesthetic):**
- **Background:** `AppColors.darkBackground` (`#0A0A0A`) — True deep black for the app's root backgrounds.
- **Surface:** `AppColors.darkSurface` (`#141414`) — Elevated dark surface for cards and containers.
- **Highlight:** `AppColors.darkSurfaceHighlight` (`#1F1F1F`) — For hovered or slightly elevated elements.

**Text Colors:**
- **Primary:** `AppColors.textPrimary` (`#F3F4F6`) — Soft white for high readability.
- **Secondary:** `AppColors.textSecondary` (`#9CA3AF`) — Subdued gray for descriptions and secondary info.
- **Muted:** `AppColors.textMuted` (`#4B5563`) — For disabled text or low-priority details.

## 2. Typography
- **Font Family:** Strictly use `GoogleFonts.inter` for a modern, clean look.
- **Boldness:** Typography must be bold and confident to give the app a "human-like" and premium feel. 
- **Weights:** Use `FontWeight.w700` (bold) or `FontWeight.w900` (black) for titles, active navigation labels, and cards. Avoid thin or default unweighted text for important UI elements.

## 3. Components & Layouts
- **Borders & Elevation:** Avoid generic thin grid lines. Use thicker (2px) borders, solid colored containers, or soft drop shadows (`BoxShadow` with high blur radius) to separate elements.
- **Corner Radii:** Avoid sharp corners. Use generous border radii (e.g., `BorderRadius.circular(12)` to `30` depending on the element size).
- **Organization:** Complex workflows (e.g., Uploads, Dashboards) must avoid generic basic lists. Use advanced, "YouTube-style" organization with `TabBar`s (e.g., "In Progress", "Scheduled", "History"), sidebars, and hierarchical layouts.

## 4. Iconography & Navigation
- **Scale:** Icons should be prominent. Active navigation buttons and Quick Action icons should be scaled up (e.g., size `24` or `26`) compared to inactive states (`20`).
- **Active States:** Active navigation tabs should use a solid `mpepeMaroon` background with stark white icons/text and subtle scale animations (`AnimatedScale`).

## 5. User Interaction & Safeguards
- **Confirmations are Mandatory:** *CRITICAL RULE:* Before executing any significant or destructive action (e.g., Logout, Deleting, Canceling Uploads), you **MUST** present a confirmation dialog (Cancel / Confirm) to the user. Never execute immediately.
- **Smart UI:** Floating Action Buttons (FABs) and primary actions should be context-aware (e.g., only show the "Start Upload" FAB when on the "In Progress" tab).

## 6. The "WOW" Factor
- The design must always feel premium, responsive, and state-of-the-art. 
- Implement micro-animations (`AnimatedContainer`, `AnimatedScale`, `flutter_animate` extensions) for hover/tap states.
- Never use generic red/blue/green placeholders. If an image or UI element is needed, design it fully or use high-fidelity placeholders.

## 7. Core Development Standards & Quality
- **No Mock Implementations:** Do NOT use mock data, dummy implementations, or `// TODO` stubs unless explicitly instructed by the user. Always wire up real logic, state management (Riverpod), and production-ready code.
- **Corporate, Premium UI (Equit-Style):** Layouts must look highly corporate and professional, similar to the Equit mobile app. Avoid generic, repetitive, or basic layouts that look like standard AI-generated boilerplate. Every component must be meticulously crafted.
- **Human-Developed Feel:** Write code and design UI with intense attention to detail. The app should feel like it was built by an expert human developer. 
- **No Broken Code:** Do not commit or present broken, uncompilable code. Always verify syntax, imports, and types to ensure a flawless experience.

## 8. Navigation & Routing (Strict)
- **Always Navigable:** Every screen you create or modify MUST be fully navigable forwards and backwards. Never trap the user on a screen.
- **Use `context.push()` instead of `context.go()`:** For hierarchical navigation (e.g., from a dashboard to a details screen), ALWAYS use `context.push('/path')` instead of `context.go('/path')`. `context.go()` replaces the route stack and prevents the user from going back, which breaks the UX.
- **Explicit Back Buttons:** If a screen does not use a standard `AppBar`, you must explicitly implement a back button (e.g. `IconButton(icon: Icon(Icons.arrow_back))` that calls `context.pop()`).
- **Verify Stack Safety:** Always verify that navigating back (`context.pop()`) lands the user on the logically expected previous screen.
