# Live Studio v2 — Design Spec

Status: **Approved 2026-10-17.** Decision: studio blue `#2F7BFF` is scoped to Live Studio tokens. On approval, the obsolete and duplicate files marked ⛔/Duplicate below, the three zips and the `*-html/` copies were moved to `~/.Trash/oneova-live-studio-obsolete-2026-10-17/`. The rows below are kept for history.
Source of truth: the HTML prototypes in `docs/live-studio/reference/html/` (unzipped from
`docs/live-studio/reference exaclt/*.zip`). Where the PNG/PDF and the HTML disagree, the HTML wins.
All geometry lives in [`assets/live_studio/studio-geometry.json`](../../assets/live_studio/studio-geometry.json). This doc explains it; it does not repeat every number.

---

## 0. File inventory

The reference folder on disk is **`docs/live-studio/reference exaclt/`** (spelled "exaclt", not "exactly").

| File | Screen | Status |
|---|---|---|
| `Live studio — landscape@2x.png` (2880×1620) | Landscape · dark | ✅ Reference. State: preset **L**, table **Goods**, tab **Participants** |
| `Live studio — landscape, light@2x.png` (2880×1620) | Landscape · light | ✅ Reference. State: preset **M**, table **Match**, tab **Interactive Map / Room** |
| `Live studio — landscape, light@2x (1).png` | Landscape · light | Duplicate. Only the comment-feed frame differs. Not needed |
| `Live studio — phone@2x.png` (780×1688) | Phone · dark | ✅ Reference. State: table **Goods** |
| `Live studio — phone, light@2x.png` (780×1688) | Phone · light | ✅ Reference. State: table **Goods** |
| `Live studio — landscape@1x.png` (1440×810, Oct 15) | Landscape · dark (**old design**) | ⛔ Superseded. Old header, 4 small tiles, no S/M/L. Do not use |
| `Live Studio Screen (1).pdf` (4 pages, Oct 17) | p1 landscape dark · p2 phone dark · p3 landscape light · p4 phone light | ✅ Current review PDF |
| `Live Studio Screen.pdf` (2 pages, Oct 15) | Same date as the old @1x PNG | ⛔ Assumed superseded. Please confirm |
| `Live studio — landscape-html.zip` → `reference/html/landscape/Main.dc.html` | Landscape · dark | ✅ Prototype (1440×810) |
| `Live studio — phone-html.zip` → `reference/html/phone/Phone.dc.html` | Phone · dark | ✅ Prototype (390×844) |
| `Live studio — phone, light-html.zip` → `reference/html/phone-light/PhoneLight.dc.html` | Phone · light | ✅ Prototype (390×844) |
| `*-html/` folders next to each zip | — | Already-extracted copies of the zips. Same files |
| `reference/html/*/assets/a5e5834b….jpg` (1376×768) | Studio background photo | ✅ This is the real photo. All wall geometry is in its pixel space |
| `reference/html/*/support.js`, `vendor/react*.js` | Prototype runtime | Not part of the design. Never ship |

Gaps to resolve:
1. **No HTML export for landscape · light.** Light landscape tokens are taken from the phone-light HTML diff (§1.2) and checked against the PNG.
2. **`/screen.png` at the repo root is 0 bytes.** The photo is the prototype's `assets/a5e5834b….jpg`. The repo already has `assets/images/live_studio_1376.jpg` (also 1376×768, but different bytes, probably re-encoded). Plan: ship the prototype's file as `assets/live_studio/broadcast_curved_1376.jpg`.
3. **`DESIGN.md` does not exist.** The "Obsidian Telemetry" tokens are in `lib/shared/theme/obsidian_telemetry_tokens.dart` (it says it was built from DESIGN.md). Conflicts with the prototype are listed in §1.4.
4. **The PNG/PDF exports have clipping artifacts.** These come from `backdrop-filter` during export: glass groups are cut into rectangles, "Request to join" is clipped on its left, the phone's "36" and its Share buttons are cut off, and "SHOW LOVE" is clipped. Visual-diff tests must mask those areas, or diff against a clean render of the HTML (§7).
5. The zips are 455–465 KB each. Unzipped copies now exist in `reference/html/`. **Commit the unzipped folder only.** Add the zips and the `*-html/` duplicates to `.gitignore`, or remove them.

---

## 1. Tokens

### 1.1 Dark theme (prototype values)
| Token | Value | Used for |
|---|---|---|
| `bg.base` | `#08080A` | Artboard, fades, studio-dim tint `rgba(8,8,10,dim)` |
| `glass.fill` | `rgba(17,17,21,0.72)` + `blur(20px)` (rail 16px) | Every glass capsule and group |
| `glass.border` | `1px rgba(255,255,255,0.10)` (landscape) / `0.12` (phone) | |
| `glass.shadow` | `0 8px 24px rgba(0,0,0,.35)` (land) / `0 6px 18px` · `0 4px 12px` (phone) | |
| `ghost.fill` | `rgba(255,255,255,0.06)` · border `0.10` | Mic/cam/S-M-L group, Share/Close |
| `text.high` | `#FFFFFF` | |
| `text.medium` | `#A3A3B2` | Secondary labels, inactive tabs |
| `text.dim` | `#525263` | Drawer grabber, inactive window dots |
| `text.popTitle` | `#E5E1E6` | Pop-out header icons |
| `placeholder` | `#6b6b7e` | |
| `pink` (accent) | `#FF2D75` · hover `#FF4D8D` | Follow, Send, ON STAGE, active tab/mode, host rim |
| `pink.activeFill` | `rgba(255,45,117,0.15)` + border `#FF2D75` | Active tab / table mode |
| `pink.sysText` | `#FFB0CA` | System comment lines |
| `pink.mute` | `#FF5A7A` | Mic-off icon on nameplate |
| `live.red` | `#FF1744` | LIVE pills; mic/cam off `rgba(255,23,68,.14)` + border `.6` |
| `blue` | `#2F7BFF` · hover `#4D8FFF` | Request to join, S/M/L active, tile rims, counts |
| `blue.rim` | `0 0 0 1.5px rgba(47,123,255,.85)` (phone tiles 2px) | Guest tiles, table, pop-out |
| `blue.soft` | `rgba(47,123,255,.16)` + border `.5`, text `#8FB6FF` | Share-to-table button |
| `blue.modeIdle` | bg `rgba(18,36,82,.85)`, border `rgba(47,123,255,.4)`, text `#C9D8FF`, icon `#8FB6FF` | Inactive table-mode chips |
| `comment.bubble` | `rgba(14,28,64,0.55)`; avatar `#16213F` + `1.5px #2F7BFF` | Comment rows |
| `cyan` | `#00F0FF` | Focus ring (dark), Goods icon, stand glow |
| `teal` | `#0FA3B1` | Sparkles button |
| `drawer.bg` | `linear-gradient(180deg,#13214A 0%,#111115 55%)`, top border `rgba(47,123,255,.45)` | Phone drawer |
| `world.surface` | `#0b0b0f`, `#191920`, `#23232C` | Table screen, pop-out body |
| `frame.default` | `#15151B` · options `#15151B #2A3550 #2F7BFF #FF2D75` | Frame color |
| `studioDim.default` | `0.15` (range 0–0.6, step 0.05) | |

### 1.2 Light theme (phone-light HTML diff; landscape light uses the same mapping)
Grey-blue surfaces, never pure white. **In-world elements stay dark in light mode**: host screen, guest tiles, nameplates, table screen, pop-out body.

| Dark | → Light |
|---|---|
| `#08080A` (artboard / fades) | `#D3DAE6`; top fade `rgba(211,218,230, .92→.6→0)` |
| `rgba(17,17,21,.72)` glass | `rgba(232,237,246,.82)` |
| `rgba(17,17,21,.92)` stand disc | `rgba(228,233,242,.8)` |
| `rgba(255,255,255,a)` borders | `rgba(20,30,60,a)` |
| glass shadow `.35` | `.12` |
| `#FFFFFF` text | `#14141A` |
| `#A3A3B2` text | `#5A6072` |
| `#525263` | `#C3C9D6` |
| `#111115` (avatar ring, badge ring) | `#E8EDF6` |
| comment bubble `rgba(14,28,64,.55)` | `rgba(232,237,246,.8)`; avatar `#CBD5E6` |
| sys text `#FFB0CA` | `#D61F5C` |
| share-to-table text `#8FB6FF` | `#1F4FB8` |
| mode idle `rgba(18,36,82,.85)` / `#C9D8FF` / icon `#8FB6FF` | `rgba(47,123,255,.08)` / `#1F4FB8` / `#2F7BFF` |
| active fill `rgba(255,45,117,.15)` | `.12` |
| follow (Following) `rgba(255,255,255,.08)` | `rgba(20,30,60,.06)` |
| drawer `#13214A → #111115` | `#C9D6EE → #DDE3EC` |
| focus ring `#00F0FF` | `#2F7BFF` |
| placeholder `#6b6b7e` | `#7A8194` |
| frame default `#15151B` (opts `#2A3550`) | `#3B4763` (opts `#3B4763 #8C97AE #2F7BFF #FF2D75`) |
| studioDim default `0.15` | `0` |

### 1.3 Shape, type, motion
- **Radii**: artboard 20 · glass capsules 9999 · landscape tile 10, phone tile 14 · host clip corner ≈20 (in path) · table 14 (land) / 12 (phone) · pop-out 14 (20 when full) · drawer top 20 · drawer cards 12 · small pills 4–5 · expand buttons 8 (host), 6 (tiles/table).
- **Font stack**: `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`. Tabular numbers for counts. Sizes: host name 15/18 w700 (phone 13/16), body 13/18, label 10/14 w600 +0.06em, tile name 9px (portrait 8px; phone 13px), ON STAGE name 22/28 w700 (phone 24/28 in world units).
- **Shadows**: wall layer `drop-shadow(0 14px 22px rgba(0,0,0,.75)) drop-shadow(0 0 16px rgba(255,45,117,.3))`. Tile `0 10px 26px rgba(0,0,0,.75), 0 0 16px rgba(47,123,255,.35)` (phone `0 14px 30px`, `0 0 20px`). Table `0 18px 36px rgba(0,0,0,.8), 0 0 32px rgba(47,123,255,.4)`. Pop-out `0 24px 60px rgba(0,0,0,.6)`.
- **Glass sheen** on tiles: `linear-gradient(118deg, rgba(255,255,255,.16) 0%, rgba(255,255,255,.04) 28%, transparent 42%)`.
- **Accent glow**: inside the tile `radial-gradient(80% 70% at 50% 100%, accent+55, transparent 70%)`. On the wall behind it: same slot transform `· translate(-0.12w, -0.1h) · scale(1.24,1.2)`, radius 18, accent at opacity .32, blur 16 (phone 22).
- **Animations** (transform/opacity only):
  - `ss-pulse`: LIVE dot, 1.4s, opacity 1→.35, scale 1→.7.
  - `ss-rise`: new comment, .45s `cubic-bezier(.2,.8,.2,1)`, from translateY 18 scale .96.
  - `ss-float`: hearts, 3.2s, rise 120px, scale .6→1.1, fade.
  - `ss-eq`: audio bars, .9s, height 30%↔100%, staggered .25s.
  - `ss-up`: drawer, .32s, translateY 100%→0.
  - Tile hover: `0 0 0 2px #FF2D75, 0 0 22px rgba(255,45,117,.6)`.
  - Press: scale .98, 100ms.

### 1.4 Conflicts with repo rules (need your call)
| Topic | Prototype | Repo rule | Proposal |
|---|---|---|---|
| Primary blue | `#2F7BFF` | `AppColors.brandBlue #0C4FA8` | Keep `#2F7BFF` **scoped to Live Studio tokens** (like `OTColors`), since the 2% visual diff needs it. Otherwise all blues shift darker |
| Pink | `#FF2D75` | `AppColors.brandPink #FF2D87`; `OTColors.neonPink #FF2D75` | Use `OTColors.neonPink` (already `#FF2D75`) |
| Font | System stack | `OTType` uses Space Grotesk / Inter; app guide says Inter | Use the system font in the studio (Flutter: no `fontFamily` → SF on iOS, Roboto on Android), as the brief says |
| Red | `#FF1744` LIVE pill | "Never Maroon/Red as **branding**" | OK. LIVE status, not branding (`OTColors.liveCrimson` already exists) |
| Icons | Inline SVG (Lucide-style strokes) | Material `Icons` only | Map each to a Material icon (§4.6). Small differences from the PNG are expected; mask them in the diff or accept them |
| Hard-coded colors | Everywhere | "Always use AppColors" | All values go into one `LiveStudioTokens` (dark/light) class. No literals in widgets |

---

## 2. Geometry

**Coordinate spaces**
- **World**: studio photo pixels, 1376×768. Host screen, guest tiles, wall glows and the host floor glow are in world space.
- **UI**: artboard pixels (landscape 1440×810, phone 390×844). Fades, the stand, the table, chrome, comments and the pop-out are in UI space.

**Camera** (world → UI): `ui = world · scale + translate`.
- Landscape: `scale 1.0547 (= 810/768)`, `translate (-5.6, 0)`. Fit to height, centered horizontally. **At runtime**: `scale = viewportH / 768`, `tx = (viewportW - 1376·scale) / 2`.
- Phone: `scale 0.66`, `translate (-259, 30)`. A fixed crop centered on the host. **At runtime**: scale by `viewportW / 390` and keep the crop.

**Host screen** (world space; full SVG paths in the JSON):
- Landscape: rect `413,206 · 547×286`. Clip path has a curved top edge (sag 39px, center) and a curved bottom edge (≈19.8px), corner radius ≈20. A pink rim stroke `rgba(255,45,117,.75)` of width `hostRim = 2·fw/1.0547 + 4` sits under a frame stroke in `frameColor` of width `hostStroke = 2·fw/1.0547`.
- Phone: rect `590,240.14 · 196×279.9`, a vertical screen. Same structure; strokes use `/0.66`.
- Contents:
  - background `radial-gradient(120% 90% at 50% 20%, #3a1830, #15121c 55%, #0b0b0f)`;
  - avatar silhouette;
  - bottom gradient `rgba(8,8,10,.75)`, 120px high (phone .85, 130px);
  - "ON STAGE" pill, name, role;
  - LIVE pill;
  - expand button: 32px landscape (left 30, top 28); 40px phone (left 16, top 22).

**Guest wall slots** (world space). Each slot is a flat tile mapped onto its wall with `matrix3d`. Corners are listed TL, TR, BR, BL.

Landscape, tiles 160×100 for L1/L2/R2/R1 and 80×180 for the portrait slots LP/RP. Prototype order s1..s6 = L1, L2, R2, R1, LP, RP.

| Slot | S | **M (default)** | L |
|---|---|---|---|
| L1 | (24,162.74) (162,178.51) (162,261.07) (24,240.57) | (12,154.37) (168,172.2) (168,285.96) (12,262.78) | (4,142.46) (172,161.66) (172,310.74) (4,296.34) |
| L2 | (184,181.03) (330,197.71) (330,286.03) (184,264.34) | (180,173.57) (342,192.09) (342,311.81) (180,287.74) | (178,162.34) (350,182) (350,326) (178,311.26) |
| R2 | (1046,197.71) (1192,181.03) (1192,264.34) (1046,286.03) | (1034,192.09) (1196,173.57) (1196,287.74) (1034,311.81) | (1026,182) (1198,162.34) (1198,311.26) (1026,326) |
| R1 | (1214,178.51) (1352,162.74) (1352,240.57) (1214,261.07) | (1208,172.2) (1364,154.37) (1364,262.78) (1208,285.96) | (1204,161.66) (1372,142.46) (1372,296.34) (1204,310.74) |
| LP | (264,336) (330,339) (330,484) (264,486) | (252,328) (340,332) (340,492) (252,495) | (232,318) (352,323) (352,502) (232,506) |
| RP | (1046,339) (1112,336) (1112,486) (1046,484) | (1036,332) (1124,328) (1124,495) (1036,492) | (1024,323) (1144,318) (1144,506) (1024,502) |

Left and right are exact mirrors around x = 688. Quads are integers, which shows the prototype computed its matrices from these 4 points. `homographyFromQuad(nativeSize, corners)` must reproduce the prototype `matrix3d` to within 1e-3 (unit test; the raw matrices are kept in the JSON).

Phone: 4 slots and no S/M/L.

| Slot | Tile | Corners |
|---|---|---|
| PL1 (s1, upper-left) | 150×92 | (419,211.69) (582,243.31) (582,321.52) (419,307.74) |
| PL2 (s2, lower-left) | 150×110 | (419,350.48) (582,359.39) (582,484.08) (419,467.87) |
| PR1 (s3, upper-right) | 150×92 | (794,242.97) (954,211.69) (954,307.74) (794,321.37) |
| PR2 (s4, lower-right) | 150×110 | (794,359.3) (954,350.48) (954,467.87) (794,483.91) |

Phone guests 5–6 are not on the wall. They are listed in Participants.

**Tile frame**: `border = frameWidth` px in landscape and `round(frameWidth·1.5, 0.1)` px on phone. frameWidth range 0–12, default 4. Expand button offset inside the tile: landscape wide `(134,6)` 20px, portrait `(54,6)`; phone `(114,6)` 30px.

**Table and stand** (UI space)
| | Landscape | Phone |
|---|---|---|
| Table screen (16:9) | `576,450 · 288×162`, r14 | `74,378 · 240×135`, r12 |
| Stand beam (trapezoid, cyan .25→0) | `660,600 · 120×30` | `150,496 · 90×30` |
| Stand disc (ellipse, blue border .75, radial fill, pink+cyan glow) | `590,612 · 260×44` | `105,512 · 180×28` |
| Stand inner ring (cyan .45) | `630,620 · 180×28` | `135,517 · 120×18` |
| Compact table rail (4×30px vertical) | in header capsule | `left 32, top 377` |

**Other UI anchors**
- Comments: landscape `24,528 · 420×174`, mask fades in over the top 38%. Phone `12,556 · 272×212`, 35%.
- Love column (landscape): `right 24, top 470 · 76×226`. Phone hearts: `right 10, bottom 62 · 40×150`.
- Pop-out default: landscape `470,110 · 500×320`, min 240×150. Phone `20,120 · 350×240`, min 160×120. Clamped to the artboard.
- Fades: landscape top 140px `rgba(8,8,10,.7)→0`, bottom 300px `rgba(8,8,10,.92) 20% → 0`. Phone top 150px blurred fade (6px blur, mask 35%), plus a panel from y=430, 180px `→ #08080A` at 60%.

**"Comments never cover a screen"**: the comment box is landscape `x 24–444, y 528–702` and phone `x 12–284, y ≥ 556`. It clears the table (left edge 576 / phone bottom 513) and the host (UI x ≥ 430, bottom ≈ 519). **One overlap in the prototype**: at preset **L**, LP's bottom edge (world y 506 → UI y ≈ 534, UI x 239–365) runs about 6px into the top of the comment box. That band is fully transparent under the fade mask, so nothing shows, but a strict check fails. Proposal: at preset L, start the comment box at the projected LP bottom + 4px (y ≈ 538, height 164). A layout test checks that no *visible* comment row intersects any projected tile quad, the host clip or the table, at S/M/L in both orientations.

---

## 3. Components

| Component | States / variants |
|---|---|
| `StudioStage` (world layer) | theme, dim 0–0.6, background studio id, orientation |
| `HostScreen` | live video · avatar fallback · speaking · muted · popped-out ("In window") · pinned |
| `WallTile` | live video (low simulcast layer) · avatar fallback (cam off; muted avatar at opacity .78 and saturate .7) · speaking (eq bars in accent) · muted (mic-off icon) · popped ("In window" overlay `rgba(10,12,20,.78)` blur 4) · empty slot · hover/focus · names shown/hidden |
| `Nameplate` | frosted `rgba(10,12,20,.62)` blur 8, border `rgba(255,255,255,.14)`, radius 9999; eq bars **or** mic-off, then the name (ellipsis) |
| `CartoonAvatar` | accent color (per user), muted variant |
| `TableScreen` | modes Goods / Screen / Match / Movie · tag pill · LIVE pill (stream modes) · title/sub · CTA: "View item", or "Join" ↔ "Watching" (`#191920` + pink border) |
| `PopoutWindow` | floating · dragging · resizing · full screen; person or table content; header 44px with title, LIVE, full screen, close; resize grip 28px |
| `HostCard` | avatar ring gradient `#FF2D75→#2F7BFF` · name · LIVE · viewers ("200K watching" / phone "200K") · Follow ↔ Following |
| `TableModeCapsule` | "On the table" label + 4 chips; the active chip expands with its label |
| `ParticipantsStack` | 3 avatar circles (28px, −8 overlap, ring `#111115`) + count |
| `RequestToJoinButton` | landscape full pill · phone 36px icon; states: idle · pending · approved · on stage (→ "Leave stage") |
| `ControlsGroup` (land) | mic on/off · cam on/off · S/M/L segmented control · Share-to-table |
| `RoomTabs` | Lobby · Presenter's Goods (dot) · Interactive Map / Room · Participants (count) · Activity & Chat (dot). Landscape shows the first 4 in the bar; the drawer shows all 5 |
| `CommentBar` | input "Say something nice…" (phone "Add a comment…") · sparkles · love · send |
| `CommentFeed` | message row · system row (pink text) · enter animation · top fade mask |
| `LoveButton` | landscape 56px + "SHOW LOVE" + "+N" · phone 40px gradient + count badge · floating hearts |
| `LiveFeaturesDrawer` (phone) | table modes (44px) · room tiles (84px) · tools row (Grid view, Switch layout, Camera, Share to table) · scrim |
| `ShareSheet`, `ParticipantsPanel`, `JoinRequestQueue`, `DeviceCheck`, `HostSettingsSheet` | **Not in the prototype**. Built from these tokens; layouts to be agreed in Step 1 |

---

## 4. Interactions

1. **Swap to center.** Tapping a wall tile swaps that person with the center (`order[0] ↔ order[i]`). Tapping the center does nothing. Prototype `order` starts `[0..6]` with the host at 0.
2. **Pop-out.**
   - Every screen (host, tiles, table) has an expand button that opens one floating window. The prototype allows one at a time.
   - Opening resets the window to its default size and position.
   - Drag by the header (ignored on buttons and in full screen). Resize by the corner grip. Both are clamped to the artboard.
   - Double-click the header, or the button, toggles full screen.
   - While open, the source tile shows "In window".
3. **Table modes.**
   - Picking a mode sets the table (the prototype does it locally; production has the host broadcast it).
   - Goods CTA "View item" switches the tab to Presenter's Goods.
   - Stream modes: the CTA toggles Join ↔ Watching for each mode.
   - "Share to the table" sets the mode to Screen.
4. **Follow** toggles Follow ↔ Following.
5. **Mic/cam toggles** change label, icon and style (red tint when off).
6. **Size S/M/L** swaps the wall preset (landscape only). Default M.
7. **Comments.**
   - Enter or Send appends a row. Sparkles appends the system line "sent sparkles". Share appends "shared this live".
   - The prototype keeps the last 200 rows. Production renders at most about 50.
   - Prototype placeholders (replace with live data): a mock row every 2.6s from a fixed pool; initial rows "babbe joined the live" and "Guest 06 requested to join the stage".
8. **Love** increments a counter (badge or "+N") and plays floating hearts.
9. **Drawer** (phone). Live features opens it; scrim, ✕ or picking an item closes it. Participants opens the drawer with the Participants tab selected.
10. **Room tabs** set `tab` (default `room`).
11. **New in this brief, not in the prototype**:
    - speaker modes Host pinned / Auto active speaker / Manual, with hysteresis 1.5s to take the center and 4s minimum hold; a pin overrides auto;
    - layout broadcast;
    - join request flow;
    - host moderation;
    - settings persistence;
    - a participants overflow rotation.
    Behavior follows the brief. UI uses these tokens.

### 4.6 Icon mapping (Material only)
expand → `open_in_full` · in-window → `picture_in_picture_alt` · mic/mic-off → `mic`/`mic_off` · cam → `videocam`/`videocam_off` · grid → `grid_view` · S/M/L leading → `view_column` · share-to-table → `cast` · share → `ios_share` · close → `close` · goods → `inventory_2` · screen → `desktop_windows` · match → `sports_soccer` · movie → `movie` · lobby → `home_outlined` · map → `map_outlined` · people → `group_outlined` · chat → `chat_bubble_outline` · sparkles → `auto_awesome` · love → `favorite` · send → `send` · eye → `visibility` · request join → `add` / `person_add_alt` · full screen → `fullscreen`/`fullscreen_exit` · resize → `south_east`.

---

## 5. Placeholders → real data

| Prototype | Source (wired in Step 2) |
|---|---|
| "Single Searching" (host card title) | Live session title |
| "Host" / "Presenting" | Host profile display name / role on stage |
| "Guest 01–06", accents | Stage participants (profile name, assigned accent color) |
| "200K watching" | Live viewer count (realtime, compact format) |
| "36", G1–G3 | Participant count + the first 3 avatars |
| Comment pool and loop | Realtime comment stream + recent history for late joiners |
| `[Product name]` / `[Price]` | Products API (the host's pinned product) |
| `Host's screen` | Screen-share track |
| `[Home] vs [Away]` / `[Movie title]` | Watch-party content metadata (rights-cleared sources only) |
| Love count, sparkles | Reactions aggregated on the server |

---

## 6. Theme / settings (saved per host, applied for every viewer)
`studioId`, `theme (dark|light)`, `frameWidth 0–12 (4)`, `frameColor (theme default + 4 options)`, `guestSize s|m|l (m)`, `showNames (true)`, `studioDim 0–0.6 (dark .15 / light 0)`, `speakerMode pinned|auto|manual (pinned)`.

## 7. Visual-regression plan
Golden tests render each screen in the same state as its reference PNG: landscape dark = L/Goods/Participants; landscape light = M/Match/Room; phones = Goods. Each is diffed at 2× against the PNG, with the export-artifact areas masked (§0 gap 4), the comment feed masked (its content changes), and icon glyphs masked. Pass: ≤ 2% of pixels differ.

## 8. Open questions for you
1. Brand blue `#2F7BFF` scoped to the studio, or `brandBlue #0C4FA8`? (§1.4)
2. Is `Live Studio Screen.pdf` (Oct 15) obsolete? Can I delete the duplicate `light@2x (1).png`, the zips and the `*-html/` copies from git?
3. Phone guests 5–6 have no wall slot. Is "Participants list only" correct?
4. Should the prototype-only drawer tools (Grid view, Switch layout) become real features, or be dropped?
