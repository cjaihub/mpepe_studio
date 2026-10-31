# Oneova release notes

## 1.0.0 (5) — 2026-10-31 · Internal testing

**Wallet and money**
- New wallet with coins (Play credit, can't be cashed out) and Diamonds earned from gifts. Diamonds become withdrawable 7 days after you earn them. The wallet also shows milestones, encouraging messages and your history.
- Coin checkout with Play packs and a celebration screen.
- Free / Plus / Pro / Biz plans as Google Play subscriptions (monthly or yearly).
- Withdrawals for verified creators:
  - an identity check (Stripe Identity) comes first;
  - the country is detected from your location;
  - Africa: mobile money (M-Pesa, MTN, Airtel, Orange, Wave) and banks; other countries: Stripe Connect;
  - you confirm with fingerprint or PIN, then follow the payout on a live tracker;
  - fraud checks run first, and Ova Guard can pause withdrawals after a suspicious sign-in.
- Creator Insights: views, followers, watch time, likes, comments, shares and gift earnings over time, a page for each clip, and tips in plain language.

**Security (Ova Guard)**
- Links in chats, comments and bios are checked (Google Web Risk and look-alike domains). Dangerous links are blocked, and suspicious messages get a warning.
- Scam detection: fake giveaways, payment and code requests, fake "Oneova support", impersonation.
- Automatic protection: when Ova Guard detects a threat it can, by itself:
  - pause sending;
  - hide content until it's reviewed;
  - sign out every device;
  - pause withdrawals;
  - alert an admin.

  Every action is shown in Security Center with its reason, and none of them ban anyone.
- Every server endpoint checks sign-in, rate limits and signed webhooks; App Check is ready to switch on. Collections and storage paths that were open to any signed-in user are now closed.

### Needs setup before these work
- Run the deploy steps in `tools/play/guard_deploy.sh`, and the wallet deploy list in the money hand-over note.
- Provide the secrets for Flutterwave or Paystack, Stripe and Maps.
- In Play Console, create the `oneova_plus` / `oneova_pro` / `oneova_biz` subscriptions.

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
