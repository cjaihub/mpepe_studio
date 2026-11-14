---
trigger: always_on
---

# Oneova build vision: read before any change

Every AI agent and every developer follows this file. It says what Oneova is in this version, what is
out, the order of priorities, and how to leave work so the next agent can carry on.
The build order and status live in `docs/plans/BUILD_LOG.md`. Read it, take the next open step, and
update it when you stop.

## 1. Priorities (in this order, every time)
1. **Security.** It always comes first. No secrets in the app or `.env` that ships with it. Every
   server call is checked on the server (auth, App Check where on, owner checks, rate limits). Money,
   identity and computer control need the signed-in owner and, for risky actions, a device biometric.
   Computer control sessions are end-to-end encrypted, tied to one account and one paired device, and
   can be stopped from either side at any moment. Never log personal data, tokens or screen content.
2. **User-friendly.** Natural language and natural touches. One clear action per screen. Plain words,
   no jargon. Every screen has a back path.
3. **Modern design.** Compact, calm, content first (see section 4).
4. **Smooth animations.** 150–250 ms, ease-out, no jank; respect "reduce motion".
5. **Premium feel.** Hairlines, quiet surfaces, careful type, blue first and pink as an accent.

## 2. What Oneova is in this version
Keep and improve:
- **Reels, Chat, Studio (+), AI Lab, Me** (the locked bottom nav), stories, notifications.
- **Live**: going live, live shopping stage, gifts.
- **Ova AI**: one interface for chat, voice and agents. Agents use the same Ova screen, not separate apps.
- **My computer** (online control): see the computer live, move the mouse from the phone, type with
  voice as the keyboard, run computer commands and shortcuts. It works across networks, not only on
  the same Wi-Fi. Control icons and features sit inside the Ova assistant overlay.
- **Insights**: creator insights and business insights.
- **Business, shops and Oneova Pay**, Oneova ID, settings.

Removed in this version (do not bring back without the user asking):
- Studio management: the YouTube manager screens (`/yt/*`), video production dashboard, projects,
  equipment and team (`/video/*`), audio productions, library and artists (`/audio/*`), the team tab
  (`/hub/team`), the CRM and the communication manager. Old links redirect to the nearest kept screen.
  The YouTube *services* stay because restreaming, linked accounts and uploads use them.

## 3. How Ova and agents should feel
- The user only speaks or types natural language, or uses natural gestures (tap, drag, pinch).
- Ova thinks and works **in the background**. While it works, show one small animated activity icon
  with a one-line plain message ("Opening Chrome on your Mac…"). No logs, no tool names, no JSON.
- Results come back as a short message, with media (images, video, audio, voice) shown inline and
  small. Details open on tap.
- Risky actions (pay, delete, send, buy, control a computer) ask once with a clear confirm, then a
  biometric where money or identity is involved.
- Skills and shortcuts run behind the scenes. The user never has to learn a command.

## 4. Compact, low-distraction UI
- Use the shared compact parts in `lib/shared/widgets/compact/` (rows, groups, section headers, chips,
  small cards, "show more", activity pill). Don't hand-build big boxes.
- Lists and settings: grouped thin rows (44–48 px), not a full card per item.
- Real cards only for things that must stand out (a balance, an order that needs action).
- Padding 12 px inside small cards, 16 px page gutters. Avoid 20–24 px padding on everyday blocks.
- Summary first, details on tap. Checklists and tips hide once done or dismissed.
- On Reels and Live, nothing floats over the content except the essential controls, and extra
  controls fade after a few seconds without a touch.
- At most one banner at a time. Badges are pink dots, not big counters.
- Every part works in light and dark mode (see `ui_ux_guidelines.md`).

## 5. How to work so the next agent can continue
- Small steps, each one built, analysed (`flutter analyze` on touched files), guard-tested
  (`flutter test test/guards/home_lock_test.dart`) and committed with a clear message.
- After each step, update `docs/plans/BUILD_LOG.md`: what was done, what is next, anything blocked.
- Don't start a new area while one is half done. Finish, record, then move on.
- Ask the user before deploying servers, live money actions, or deleting user data.
