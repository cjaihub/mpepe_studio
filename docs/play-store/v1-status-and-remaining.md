# Oneova v1 — what's finished and what's left (2026-10-30)

All 19 linked work sessions are idle and finished their last turn. All their code is committed on
`feat/settings-autosave-reels-theme-nav-icons` (latest `d8960aa6`). Nothing is pushed to GitHub yet.

## Finished (in the code, not yet tested on a phone)
- Studio: create → edit → post to the feed, Media3 export engine.
- Calling: 1:1 and group voice/video calls with lock-screen ringing, ringback, PiP, Bluetooth, weak-network handling and a call history tab.
- Ova assistant with device actions, location sharing and Ova Guard (per-profile security events, login risk, device revoke).
- Feed, likes, comments and follows from Firestore (one per user), viral ranking, live like counter.
- Secrets out of the app: AI goes through `aiProxy` (400 requests a day per user), the TikTok exchange runs on the server, and server-side Gemini uses Vertex AI (no key).
- Play in-app auto-updates and a Play API publish script (`tools/play/release.sh`).

## Left — needs you
1. **Run `bash tools/play/backend_setup.sh`.** It turns on Vertex AI and deploys the 17 functions that aren't live yet. Until then, AI chat, email codes, Meta login and the Ova Guard actions don't work in the app.
2. **TURN server for calls** (Remote Config `webrtc_ice_servers`). Without one, many calls over mobile data never connect. This is the biggest launch risk.
3. **GitHub push.** Sign in first (`brew install gh && gh auth login`), then `git push -u origin HEAD`. The repo is public, so rotate the TikTok client secret in the TikTok portal.
4. **Play Console.** Sign in, upload `build/play/oneova-1.0.0-1.aab` to Internal testing, and fill in the declarations from `oneova-play-console-draft.md`.
5. `firebase deploy --only firestore:indexes` (the Following tab needs it).
6. Back up `android/app/upload-keystore.jks` and `android/key.properties`.

## Left — code work not started (each is its own session)
| Area | What's there now | What's missing |
|---|---|---|
| Live | Four separate entry points: `/live/broadcast`, `/live/gaming`, `/live/studio`, `/live/studio2` | One Live Studio for everyone, a step-by-step setup wizard with previews, clean session endings, reconnection when the connection drops |
| Upload | Studio picker → editor → post | A roomier upload wizard; content ID, verification and permission checks before publishing |
| AI credits | Only the flat 400/day cap in `aiProxy` | Free credit allowance per account. When it runs out, generation and agent actions stop and only the chat assistant keeps working. Paid tiers to unlock more |
| Payments | Wallet, Coins and Stripe/Flutterwave config and models; no Stripe SDK; **no Google Play Billing** | See the policy notes below |
| Security AI | Ova Guard rules plus a Vertex explanation of each event; the live-health monitor is off | Vertex scanning of chat links and messages, payment fraud checks, profile-change monitoring |

## Policy limits to design around (Google Play / law)
- **Coins and subscriptions for digital features must use Google Play Billing** on Android: AI credits, gifts, Looks and premium tiers. Stripe and Flutterwave can't be used to sell these in the Play build.
- **Creator earnings out** (gift payouts, withdrawals) can use Stripe Connect. That needs identity checks (KYC) for each creator.
- **A wallet card that pays anywhere online** means issuing payment cards. That needs a licensed issuing partner (for example Stripe Issuing, available in a few countries, with its own approval and KYC), and Play's financial-services declaration. It can't just be built in the app; it's a business and partner application first.
- **Holding user money and person-to-person transfers** is regulated as e-money or money transmission in most countries. Keep Coins as non-withdrawable platform credit, with withdrawals only for verified creators' earnings, until there's a licensed partner.
- **A tool that scans the phone outside the app and removes problems** isn't something Play allows a social app to do: no broad app inventory (QUERY_ALL_PACKAGES) and no system changes. Inside the app it's fine: link scanning, suspicious-login detection, rooted/tampered-device checks with Play Integrity.

## Suggested v1 monetization model (to confirm before building)
- **Free:** daily AI credits, for example 30 a day. Chat with Ova is always free and has a light cap. Generation, agent and Studio-AI actions cost credits.
- **Oneova Plus / Pro / Biz:** monthly Play subscriptions with more credits, HD export, no watermark, Biz tools.
- **Coins:** bought through Play Billing and spent on gifts in lives and posts.
- **Creators:** earn Diamonds from the gifts they receive. Above a minimum, they cash out through Stripe Connect after KYC. The platform takes a cut, for example 50% (TikTok-like), which keeps the margin after Play's 15–30% fee.
- **Cost guard:** credits are priced from real Vertex/OpenRouter token cost × 3. Free users get Flash-Lite models. Results are cached.
