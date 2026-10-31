# Oneova: plan for the next feature set (2026-10-31)

This builds on what exists today. `AuthInteractionGate` already handles guest browsing, `geolocator` is installed, the Biz feed is at `/biz_feed`, and Ova's server AI runs on Vertex. Each phase ships as its own build and can go to Play Internal testing.

## Phase 1: Guest-first feed and smart sign-in (about 1–2 days)
- The public home feed plays for guests straight away. Like, comment, follow, share and remix open a sign-in sheet with an Oneova benefit card, close and "Not now" controls, and one-tap Google or phone sign-in. After signing in, the action the person tapped runs automatically.
- A short starter guide (3 cards) appears after the first sign-in.
- A search entry point on the home reels top bar. It already exists and opens `/hub/discover` with the new smart search.

## Phase 2: Language and location, set automatically (about 2 days)
- The app language follows the phone's language, and the person can change it later. App strings are moved to ARB files, in English, French, Swahili, Arabic, Portuguese and Spanish first.
- Ova replies in the person's language. Posts, comments and chats get a "See translation" option (server translate, as in `chatAssist`).
- Location: the app asks permission once with a clear explanation. Google Play and Android require that consent; it cannot be skipped. When it's granted, `users/{uid}.geo` (geohash and country) is kept current. This feeds the "near you" and "friends of friends" signals in the recommendation service. When it's denied, the app falls back to the country from the phone's region or SIM. There is no manual entry.

## Phase 3: Reel screen polish (about 2 days)
- Tap anywhere to like, with a burst of hearts that fades within a few hundred milliseconds. Likes stay one per person.
- Comments float up over the playing reel like a live stream, with an option to have them read aloud.
- Creators can attach a link (a Biz shop, a product or an external URL) shown as a chip on the reel, with a check that the link is safe.
- The right-hand rail and bottom area get the same tidy layout everywhere, staying within the locked home layout rules.

## Phase 4: Live Shop (about 1–2 weeks; needs your decisions below)
- A seller opens a live shop from the Biz feed. Drawers hold products; the camera shows the shop, and goods can be pinned on screen; buyers join, chat and order live.
- "Design my shop with Ova": the AI suggests a layout and theme for the stall. A full 3D walkable shop is a separate, much larger project; I'd start with a styled 2D/2.5D stall.
- Orders:
  - The buyer pays, and the money is held in escrow (server ledger plus the payment provider).
  - The seller hands the order to a driver.
  - A live map follows the driver's GPS to the buyer.
  - The buyer scans the delivery QR code, and only then is the money released to the seller.
  - Disputes and refunds are handled by the server.
- Ova inside the order chat explains where the order is and what happens next.

## Decisions and keys I need from you
1. ~~Payment provider for escrow~~ **Decided: Stripe (2026-10-31).** Design:
   - Stripe Connect: Oneova is the platform account; sellers onboard as Express connected accounts.
   - The buyer pays the platform (PaymentIntent via Payment Sheet, `flutter_stripe`). The money stays on the platform balance (escrow) and an `orders/{id}` ledger tracks each step: paid → handed to driver → delivered → released.
   - Scanning the delivery QR code triggers a server Transfer to the seller (minus the Oneova fee). Disputes and timeouts get a Refund.
   - Keys needed: the Stripe secret key and webhook signing secret in Secret Manager, and the publishable key in the app. Test-mode keys first.
   - Check first: Stripe Connect only pays out to sellers in supported countries. In Nigeria, Ghana, Kenya and South Africa, Stripe's own Paystack is the usual route, so we may need Paystack as a second payout rail later.
   - Physical goods may use Stripe under Play policy; digital coins still have to use Play Billing.
2. A Google Maps Platform API key (Maps SDK for Android, Directions and Places), restricted to `com.oneova.app` with the SHA-1 fingerprints. **The user will provide it (2026-10-31).** Use two keys:
   - The Android key (Maps SDK only, restricted to the app and its SHA-1s) goes in the manifest through a gitignored Gradle property.
   - A server key (Directions and Places, restricted by API) goes in Secret Manager and is used only by Cloud Functions.
3. ~~Your first languages and countries~~ **Decided: Africa, Europe and the US (2026-10-31).**
   - The app is fully translated in 8 languages in wave 1: English, French, Spanish, Portuguese, German, Italian, Arabic (right-to-left layout) and Swahili.
   - Wave 2 adds 8 more: Hausa, Yoruba, Amharic, Zulu, Igbo, Dutch, Polish and Turkish.
   - Any other language is still covered: Ova replies, and the "See translation" option works on posts and chats, through server translation.
   - Payouts: Stripe Connect covers the US and Europe fully, but in Africa only South Africa directly. Most African sellers (Nigeria, Ghana, Kenya and others) need Paystack, which Stripe owns, as a second payout option. Escrow is built behind one payout interface so both fit.
4. ~~Drivers~~ **Decided: partner riders on motorbikes (2026-10-31).** Riders are Oneova users like everyone else: same login, same account. They turn on a "Delivery partner" mode in their profile, which adds identity and vehicle details and a Stripe Connect payout account.
   - **Delivery price:** shown live before the order is placed. A Cloud Function calls the Directions API (with the server key) for the seller → buyer route and calculates: base fee + per-km rate + per-minute rate, with surge pricing by time of day and demand. The buyer pays item + delivery into escrow in one go.
   - **Dispatch:** the nearest online riders (by geohash) get a "New job" push with the pickup, distance and payout. The first to accept gets the job.
   - **Journey:** the rider taps "Start journey". Their GPS streams to `deliveries/{id}/track` (every ~5 s while moving). The buyer and seller see the bike move live on the map with the remaining distance and estimated arrival. Ova in the order chat explains each step.
   - **Handover:** the buyer scans the rider's QR code (or enters a 4-digit code). Escrow is then released: item amount to the seller, delivery fee to the rider, commission to Oneova.

## Biz profile: live market (decided 2026-10-31)
- Every Biz profile opens on a live storefront: an auto-playing hero (the shop's live video or latest reels), product drawers and an "Open now / Live" badge, with a "Join shop" call to action.
- "Built-in 4square" (to confirm): a Foursquare-style places layer.
  - Shops near you on the map, with check-ins, tips and ratings, and "Trending nearby".
  - Built on our own Firestore places, plus Google Places for addresses and hours, so no extra Foursquare API key is needed.

## Play listing requirements this adds
- A location permission declaration, background location only if driver tracking needs it, a Data safety update (precise location, payment info), and the financial-features declaration (escrow).
