# Oneova release notes

## 1.0.0 (4) — 2026-10-31 · Internal testing

Everything the work sessions finished, in one build.

**Brand**
- New Oneova logo on the app icon, launch screen, in-app logo and store listing.
- Animated splash: the logo pops in with a heartbeat, ripples and floating hearts. It opens the feed in about a second, or tap to open right away.
- Motto: "Oneova — The reason you matter".

**Live**
- One Live Studio for everyone, with a step-by-step setup wizard and clean endings (no stuck lives).
- Host entertainment tools, 1080p recording and restreaming, and a live controls hub.
- Coin gifts, voice presets, mute-all for moderators, double-tap love, live counts, and gifts and GIFs in comments.

**Coins and gifts**
- Coins are bought through Google Play Billing (7 packs). The server checks each purchase with Google before crediting it.
- 17 gifts (1 to 5,000 coins) that can be sent in lives or straight to a profile, with a gift-landing animation and gifter levels 1–13.
- Biz orders pay through Stripe Checkout, including local payment methods.

**Calls**
- Ringback tone, a "Ringing…" status, the screen turning off at your ear, picture-in-picture, Bluetooth headsets, and a weak-network banner with automatic reconnecting.
- In-call camera filters, a sound pad both sides hear, shared music, a people panel and call layouts.
- Call history in the Calls tab.

**Chat**
- Message actions (including translate), highlights, compact link and file cards, a sticky encryption banner and a per-chat AI switch.
- Custom chat backgrounds for one chat or all chats.

**Camera and AR**
- AI face effects with live tracking and an effect library.
- On Android, a native camera that keeps full resolution and saves the effects into recorded videos.

**AI**
- Ova voice mode on Vertex AI Live; the server's Gemini also runs on Vertex AI.
- The app ships with no AI keys: chat AI goes through the `aiProxy` server function, with a daily limit per user.
- Drawing an "O" opens Ova.

**Accounts and notifications**
- Premium login and sign-up screens, AI profile suggestions, rich notifications and in-app sharing.

**Platform**
- The app updates itself from the Play Store: high-priority updates install right away, and the rest download in the background and install the next time the app is closed (never during a call).
- Android 7.0 (API 24) and later.

### Needs the backend deploy before it works
Run `bash tools/play/backend_setup.sh`, then deploy:
`firebase deploy --only firestore:rules,functions:verifyCoinPurchase,functions:sendUserGift,functions:lsGift`.

In Play Console:
- create the coin products (`coins_70` … `coins_17500`);
- invite the server's service account with "View financial data" and "Manage orders".

## 1.0.0 (3) — 2026-10-31
New logo and splash on top of build 2.

## 1.0.0 (2) — 2026-10-31
Calling upgrade, live gifting, chat actions, Vertex voice mode.

## 1.0.0 (1) — 2026-10-30
First Internal testing release.
