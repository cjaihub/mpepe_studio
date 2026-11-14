# Location and discovery: maps, places and "near you" for Reels, Live and Shops

Rules: `.agents/rules/oneova_build_vision.md` (security first). Build steps: Stage E in
`docs/plans/BUILD_LOG.md`. Status keys: ✅ exists · ⚠️ exists but must change · 🔨 to build.

## 1. What the app has today (checked 2026-11-14)

| Feature | Where | Provider | Status |
|---|---|---|---|
| Map view (pins, route line, "me" dot, signal) | `lib/shared/location/oneova_map_view.dart` | OpenStreetMap tiles (`tile.openstreetmap.org`) | ⚠️ public tile server, not for app traffic |
| Place search, reverse address | `lib/shared/location/geo_services.dart` | Nominatim (OSM) | ⚠️ 1 request/second policy |
| Nearby places by category | `geo_services.dart` (`nearby`) | Overpass API (OSM) | ⚠️ shared public server |
| Routes, open navigation | `geo_services.dart` (`route`) | OSRM demo server | ⚠️ demo server |
| Places (New) search, nearby, details; Routes | `lib/backend/maps/services/google_maps_service.dart` | Google, key from `--dart-define` | ⚠️ key never set in release builds, so it's off |
| Auto location for profile and posts | `lib/shared/location/oneova_location_detector.dart` | GPS + Nominatim | ⚠️ |
| Live location sharing in chat, collab maps | `lib/backend/location_sharing/`, `lib/backend/maps/services/collab_map_service.dart` | Firestore | ✅ |
| Ova geo tools ("what's near me", share location) | `lib/ova_assistant/services/ova_geo_tools.dart` | `geo_services.dart` | ✅ |
| Shop map card | `lib/shops3d/widgets/shop_map_card.dart` | `oneova_map_view.dart` | ✅ |
| Delivery distance for order escrow | `functions/src/commerce/orderEscrow.ts` | Google Directions (server key) | ✅ |
| Payout country from coordinates | `functions/src/creator/payouts.ts` | Google Geocoding (server key) | ⚠️ Geocoding API is **not enabled**, so this call fails quietly |
| KYC country | `lib/shared/location/country_detector.dart` | Phone GPS + on-device geocoder, network, SIM, phone number, region | ✅ new; replaced an unencrypted `http://ip-api.com` lookup |
| Location index for feeds, lives, shops | — | — | 🔨 none (no geohash or geo query anywhere) |

Google project `mpepe-2b4bd` has these Maps services on: Places API (New), Places (legacy), Directions
(legacy), Maps SDK for Android. Keys:
- "Oneova Server Maps" is limited to Directions and Places, with no app restriction. That's fine because it
  stays server-side in Secret Manager.
- "Oneova Android Maps" is limited to the Android app and the Maps SDK.
- The three Firebase auto-created keys have no app restriction. Restrict the Android one to the package
  and signing SHA-256 (🔨, in the console).

## 2. Target design

### 2.1 One server door for Maps (security and cost)
All Google Maps calls go through Cloud Functions with `GOOGLE_MAPS_SERVER_KEY` (Secret Manager). There
are no Maps keys in the app except the Android SDK key, which is restricted to our app.
- 🔨 `geoSearch(query, near?)`, `geoNearby(at, category, radius)`, `geoReverse(at)`, `geoRoute(from, to, mode)`.
- Each one checks sign-in, applies rate limits (`guard/protect`), and asks Google only for the fields it
  needs (field masks keep the price tier low). Results are cached in Firestore with a TTL by rounded
  coordinate: reverse geocode for 30 days, nearby for 1 day.
- 🔨 Turn on the Geocoding, Routes and Time Zone APIs and add them to the server key's allowed APIs.
  Retire Directions (legacy) once `geoRoute` uses Routes.
- `geo_services.dart` keeps its API, so Ova, chat and shops don't change. Only its insides move from
  OSM to these callables. OSM stays as a fallback only if Google fails.
- Map tiles: move `OneovaMapView` to the Google Maps SDK for Android (the key already exists), or to
  the Map Tiles API with a proxy. No more `tile.openstreetmap.org`.

### 2.2 Location privacy (before any "near you" feature)
- Location is opt-in, while the app is in use only. No background location for discovery.
- The server stores only a **coarse cell**: geohash precision 5 (about 5 × 5 km) for people and posts,
  precision 6 (about 1.2 km) for shops and places, which are public addresses anyway.
- A person's exact position is never stored on a post, live stream or profile, and never shown to
  others. "2 km away" is rounded, and it's hidden below 1 km for people (to stop triangulation).
- Home and work areas are learned **on the phone only**, never uploaded. The user can turn local
  discovery off and clear it in Settings → Privacy.

### 2.3 The geo index
- 🔨 Each post, live stream and shop gets `geo: { cell5, cell6, country, city }`, set by a Function
  from the creator's coarse location at publish time (never from the client directly).
- Query "near you": the user's cell plus its 8 neighbours at precision 5 (about 15 × 15 km). Widen to
  precision 4 (about 40 km) when there are too few results. Firestore `in` queries on `geo.cell5`
  (9 values) with `createdAt` ordering; composite indexes per surface.

## 3. Ranking algorithms

All scores are 0–1 and multiplied. Each surface tunes its own distance scale τ.

**Proximity:** `p(d) = exp(-d / τ)`, where d is the rounded distance in km.
τ: Reels 25 km, Live 50 km, Shops 8 km (or the shop's delivery radius, whichever is larger).

### 3.1 Reels: a local slot in For You
- Candidates come from the existing interest model, plus a local pool (posts in the 9 cells from the
  last 72 h).
- Local score = `interest(u, post) × freshness(age, half-life 18 h) × p(d) × quality(post)`.
- Blend: about 1 in 5 feed slots is local. No more than 2 local posts in a row. The same creator at most
  once per 10. Local slots switch off when the user has location off.
- "Following" and "Biz" tabs are not changed.

### 3.2 Live: "Live near you"
- Active streams in the user's cells.
- Score = `p(d) × momentum × trust`:
  - momentum = viewer growth in the last 5 min, log-scaled;
  - trust = creator reputation from Ova Guard (0.5–1).
- Shown as one small row of avatars at the top of the Live list, not a big banner. Hidden when empty.

### 3.3 Shops: "Shops that deliver to you"
- Candidate shops: the delivery zone covers the user's cell (radius or polygon on the shop), or
  pickup within 10 km.
- Score = `p(d) × open_now × rating_conf × relevance(query or interests) × delivery_eta_factor`:
  - rating_conf = a Bayesian average rating, so a 5.0 from 2 reviews doesn't beat a 4.7 from 400;
  - delivery_eta_factor = `1 / (1 + eta_min / 45)`, with ETA from one Routes matrix call for the
    top 20 candidates only.
- Verified business badge: shops verified through KYB get a small boost, never a ranking floor.

### 3.4 Self-discovery: learning what's worth showing locally
- **Exploration:** Thompson sampling over (category × distance band) arms per user. Each arm keeps
  Beta(α, β) counts of engaged (watch past 50%, like, follow, add to cart) vs skipped. This decides how
  much local content of each kind to show, with about 10% exploration so new local creators and shops
  get seen.
- **Cold start for new local creators:** a guaranteed small audience (about 200 views within their
  cells), then normal ranking.
- **Travel mode:** when the coarse cell moves more than 50 km and stays for over 6 hours, local weight
  goes up for that city for 3 days ("New in Mombasa" row), then fades.
- **Ova:** "what's happening near me" uses the same index and ranking. Its reply is a short list
  with small cards (rules §3 and §4).

### 3.5 Measuring it
- Log per impression: surface, local or not, distance band, score parts. Logs go to BigQuery.
- Watch: local watch-through vs non-local, follow rate of local creators, shop orders from local
  discovery, and complaints. A/B test τ and the local share before raising them.

## 4. KYC country (done in this change)
- `CountryDetector` order: GPS (only if allowed) through the phone's own geocoder, then mobile
  network, SIM, phone number, phone region. Nothing goes to a third party.
- The KYC form fills the ID country from it ("Detected Kenya from your location"). The user can change
  it with the searchable list of all countries, and there's a "Use my location" button.
- `kycSubmit` stores the cleaned-up signals and a `countryMismatch` flag for reviewers. A mismatch is a
  hint, never an automatic rejection.
