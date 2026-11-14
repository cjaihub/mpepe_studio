---
name: Luminescent Cinema
colors:
  surface: '#10131a'
  surface-dim: '#10131a'
  surface-bright: '#363941'
  surface-container-lowest: '#0b0e15'
  surface-container-low: '#191b23'
  surface-container: '#1d1f27'
  surface-container-high: '#272a32'
  surface-container-highest: '#32353d'
  on-surface: '#e1e2ec'
  on-surface-variant: '#c2c6d8'
  inverse-surface: '#e1e2ec'
  inverse-on-surface: '#2d3038'
  outline: '#8c90a1'
  outline-variant: '#424656'
  surface-tint: '#b3c5ff'
  primary: '#b3c5ff'
  on-primary: '#002b75'
  primary-container: '#0066ff'
  on-primary-container: '#f8f7ff'
  inverse-primary: '#0054d6'
  secondary: '#ffb1c5'
  on-secondary: '#65002f'
  secondary-container: '#e30071'
  on-secondary-container: '#fffbff'
  tertiary: '#00dce5'
  on-tertiary: '#003739'
  tertiary-container: '#007f84'
  on-tertiary-container: '#e3feff'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#dae1ff'
  primary-fixed-dim: '#b3c5ff'
  on-primary-fixed: '#001849'
  on-primary-fixed-variant: '#003fa4'
  secondary-fixed: '#ffd9e1'
  secondary-fixed-dim: '#ffb1c5'
  on-secondary-fixed: '#3f001b'
  on-secondary-fixed-variant: '#8f0045'
  tertiary-fixed: '#63f7ff'
  tertiary-fixed-dim: '#00dce5'
  on-tertiary-fixed: '#002021'
  on-tertiary-fixed-variant: '#004f53'
  background: '#10131a'
  on-background: '#e1e2ec'
  surface-variant: '#32353d'
typography:
  display-hero:
    fontFamily: Outfit
    fontSize: 56px
    fontWeight: '800'
    lineHeight: 64px
    letterSpacing: -0.03em
  display-hero-mobile:
    fontFamily: Outfit
    fontSize: 36px
    fontWeight: '800'
    lineHeight: 44px
    letterSpacing: -0.025em
  headline-lg:
    fontFamily: Outfit
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Outfit
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Outfit
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Outfit
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  body-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.005em
  label-lg:
    fontFamily: Space Grotesk
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
    letterSpacing: 0.02em
  label-md:
    fontFamily: Space Grotesk
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.04em
  label-sm:
    fontFamily: Space Grotesk
    fontSize: 10px
    fontWeight: '600'
    lineHeight: 12px
    letterSpacing: 0.08em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-tablet: 2rem
  margin-desktop: 3rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
---

## Brand & Style

This design system defines a luxury, high-velocity social video platform engineered for cinematic short-form creators and discerning audiences. The interface pairs the kinetic urgency of short-form entertainment with the refined, architectural restraint of high-end editorial software. 

The aesthetic is anchored in **Cinematic Glassmorphism**: ultra-fine hairline boundaries, deep variable-blur backdrops, multi-layered ambient light spills, and liquid-smooth micro-interactions. The interface acts as an invisible, optical-grade lens that recedes entirely during active media playback, yet emerges with crisp, luminous presence during curation, social discovery, and authoring workflows. 

Interactions leverage physical dampening (spring physics with subtle inertia) paired with hyper-responsive neon light bleeds along interaction boundaries, creating an atmosphere that feels tactile, prestigious, and technologically flawless.

## Colors

The color system operates on high-chroma optical contrasts set against extreme chromatic absorption:

- **Primary (`#0066FF`)**: Pure electric laser blue. Serves as the primary operational hue, driving core call-to-actions, playback states, verification badges, and real-time network states.
- **Secondary (`#FF2A85`)**: High-intensity neon magenta. Used for viral resonance markers: likes, live broadcasting pings, creator appreciation, and creative highlights.
- **Tertiary (`#00F5FF`)**: Electric cyan. Applied sparingly to audio waveform peaks, scrubber needles, and multi-track remix indicators.
- **Neutral (`#0A0D14`)**: Obsidian onyx base. In dark mode, it grounds full-bleed canvas viewports without deadening deep video blacks. In light mode, it shifts to high-contrast deep ink typography against crystalline, multi-stage opalescent backgrounds (`#F8FAFC` to `#FFFFFF`).

### Surface Strategy
Surfaces are constructed through semi-transparent alpha tiers layered over deep backdrop blurs:
- **Floating Controls**: `rgba(10, 13, 20, 0.65)` in dark mode; `rgba(255, 255, 255, 0.75)` in light mode, backed by `backdrop-filter: blur(24px) saturate(180%)`.
- **Specular Hairlines**: `1px` inner/border strokes using linear gradients from `rgba(255, 255, 255, 0.18)` at the top edge to `rgba(255, 255, 255, 0.02)` at the bottom edge.

## Typography

Typography balances clean geometric authority with precision data density:
- **Headlines (`Outfit`)**: Clean, hyper-modern geometric geometry with razor-sharp terminal cuts. Delivers monumental impact for viral reel metrics, audio title banners, and profile headers.
- **Body (`Plus Jakarta Sans`)**: Highly legible, humanized neo-grotesque optimized for rapid scanning of fast-scrolling comment streams, captions, and descriptions against high-motion video.
- **Labels & Telemetry (`Space Grotesk`)**: Technical, rhythmic monoline character used for timestamps, video aspect ratios, frame rates, audio stems, and interaction counter tags.

## Layout & Spacing

Layout centers around an uncompromising **Content-First Fluid Viewport Architecture**:

- **Mobile (Full Canvas)**: 0px outer margin on video feeds; interaction overlays float with `margin` (`1rem`) offset from bottom safe areas and right-hand thumbsweep rails.
- **Desktop & Web Discovery**: A 12-column adaptive layout scaling up to `1440px`. Feeds lock into a centered vertical 9:16 aspect ratio theater stage flanked by contextual metadata panes (creator portfolio, comments, audio track remixes) separated by `gutter-desktop` (`1.5rem`).
- **Rhythm**: Spacing follows a 4px/8px quantum. Gaps between related micro-actions (e.g., like button and count) utilize `space-xs` (4px), while sequential action clusters use `space-md` (16px) to eliminate accidental input strikes during high-speed vertical scrolling.

## Elevation & Depth

Visual hierarchy abandons flat gray drop shadows entirely, relying instead on **Luminescent Layering and Ambient Diffusion**:

- **Level 1 (Submerged Canvas)**: Video viewport at base z-index (`z-0`), edge-vignetted using a soft radial gradient: `radial-gradient(circle, transparent 60%, rgba(10, 13, 20, 0.45) 100%)`.
- **Level 2 (In-Feed Overlays & Scrims)**: Frosted glass badges and overlays. Backdrop blur `16px`, background `rgba(15, 23, 42, 0.45)`, enclosed by a `1px` translucent boundary `rgba(255, 255, 255, 0.12)`.
- **Level 3 (Interactive Controls & Sticky Dock)**: Ambient chromatic drop shadows. Rather than black shadows, floating action buttons project an illuminated halo sampled from their primary hue: `0 12px 32px -4px rgba(0, 102, 255, 0.35), 0 4px 12px -2px rgba(255, 42, 133, 0.2)`.
- **Level 4 (Modals & Sheet Panels)**: Deep multi-stage occlusion. Backdrop blur `32px` with `box-shadow: 0 32px 64px -16px rgba(0, 0, 0, 0.65), 0 0 0 1px rgba(255, 255, 255, 0.1) inset`.

## Shapes

The design system employs **Rounded Geometry (Level 2)** to echo the physical contours of modern curved-glass mobile flagships:
- Base components (cards, bottom sheets, preview frames) utilize `0.5rem` (`rounded`) up to `1rem` (`rounded-lg`).
- High-velocity touch targets (action pills, avatar frames, comment chips) transition intentionally into smooth circular pills (`9999px`) to maintain fluid thumb ergonomics.
- Video preview tiles feature an explicit inner corner radius of `1rem`, paired with a precision `1px` sub-pixel border stroke to prevent pixel feathering against dark canvases.

## Components

### Buttons
- **Primary Action (Follow / Publish / Remix)**: Pill-shaped, featuring an active electric gradient (`linear-gradient(135deg, #0066FF 0%, #3B82F6 100%)`). On hover/press, it emits an exterior ambient glow (`box-shadow: 0 0 24px rgba(0, 102, 255, 0.5)`). Text styled with `label-lg`, pure white.
- **Glass / Floating Action Buttons (Like, Share, Bookmark)**: Circular 48px controls. Background `rgba(10, 13, 20, 0.55)`, blur `20px`, enclosed in `1px` solid `rgba(255, 255, 255, 0.15)`. Active like state transitions icon to `#FF2A85` accompanied by an expansive neon particle shockwave.

### Chips & Tags
- Compact pills using `label-md`. Background: `rgba(255, 255, 255, 0.08)`. Border: `1px solid rgba(255, 255, 255, 0.06)`. Audio attribution chips feature a dynamic live equalizing graphic (3 neon-blue vertical bars reacting with CSS keyframe animation).

### Input Fields & Search Bars
- Translucent capsule inputs. Background `rgba(15, 23, 42, 0.6)`, `backdrop-filter: blur(16px)`. Border is `1px solid rgba(255, 255, 255, 0.12)`. When focused, border transitions smoothly to `#0066FF` with an inner glow `0 0 12px rgba(0, 102, 255, 0.3)`.

### Cards & Reel Previews
- Previews feature a 9:16 aspect ratio with an edge-to-edge video thumbnail, masked with `rounded-lg`. Overlay metadata displays at the base over a bottom-to-top gradient scrim (`rgba(10, 13, 20, 0.8)` to transparent).

### Scrubbers & Progress Indicators
- Ultra-thin 2px idle progress bar positioned at the base of the viewport (`rgba(255, 255, 255, 0.3)`). On interaction, it expands to 6px height with a tactile `#0066FF` fill and an illuminated circular scrubber thumb displaying current frame timestamps via `label-sm`.