# Oneova 3D Shops

Full-screen 3D showrooms on top of the existing Biz commerce (Oneova Pay escrow) and Live (LiveKit) systems. Nothing here duplicates those; it adds a storefront, 3D product presentation, and the seller setup flow.

## Screens (`lib/shops3d/`)

| Route | Screen | What it does |
|---|---|---|
| `/shops` | `ShopsFeedScreen` | Vertical swipe feed of open shops. Sellers who are live come first, then open shops paged by last update. |
| `/shops/:id` | `ShopStoreScreen` | Storefront page: profile, live status, category filter, full catalog. Works while the seller is offline. |
| `/shops/:id/stage` | `ShopStageScreen` | One shop's stage (from the store page, links, or the seller's preview). |
| `/shops/p/:productId?variant=` | `ShopProductScreen` | Interactive 3D view (rotate, pinch, double-tap focus, AR), options, buy. |
| `/shops/saved` | `SavedProductsScreen` | Your saved products. |
| `/shops/setup` | `ShopSetupWizardScreen` | Seller setup: Identity → Stage → Products → Preview & open. |
| `/shops/product/edit?id=` | `ProductEditorScreen` | Photos, GLB/GLTF upload with live 3D preview, price, stock, options linked to the model's material variants. |

You get in from the Biz screen (`/biz_feed`) through `ShopsEntryCard`.

### Why the feed's 3D view is not interactive

`model_viewer_plus` runs in a web view that takes every gesture, so an interactive model would stop the vertical swipe. On the feed the model turns by itself and only the visible page loads a web view; the others show the poster, which also keeps slow phones smooth. Tapping the product opens the fully interactive view.

## Data

- `biz_shops/{uid}`: one storefront per seller. The owner writes `name, tagline, bio, avatarUrl, bannerUrl, categories, stage{backdrop,accent,card,autoRotate}, location{lat,lng}, status(draft|open|closed), featuredProductId`. Only the server writes `verified, followersCount, rating, reviewCount`, and the rules enforce that. Escrow already reads `location` here to price delivery.
- `products/{id}`: the shared Biz catalog, also used by checkout and Live. 3D Shops adds `model3dUrl, imageUrls, compareAtPrice, variants[{id,name,colorHex,stock,modelVariant}], sortOrder, active`.
- `users/{uid}/saved_products/{productId}`: private wishlist.
- Storage: `shops/{uid}/brand/*` (images up to 10 MB) and `shops/{uid}/products/{productId}/*` (images up to 10 MB, `.glb/.gltf/.usdz` up to 50 MB). Anyone can read; only the seller writes.

## Trust boundaries

- The app only displays prices and stock. `createOrderCheckout` re-reads the product, validates the chosen `variantId` and its stock (`functions/src/commerce/variant_logic.ts`), and Oneova Pay charges the server-side amount.
- When a payment succeeds, Oneova Pay (`applyOrderPaid`) lowers product and variant stock in the same transaction that marks the order paid. If two buyers paid for the last unit, the order gets `stockShortfall: true` and the seller is told to fill it or cancel.
- Live status comes from `live_streams` (`status == 'live'`, `hostId`); 3D Shops never writes to it.

## Not built yet (each needs its own decision)

- Live video and chat inside the stage: the stage links to the existing live room (`/live/viewer/:streamId`) instead of embedding a second copy while the live room is being refactored.
- Gifts, shop follow and ratings, reviews, shop reports and moderation queue, seller analytics, AI listing help.
- A web page for `https://oneova.web.app/shops/:id` (the share link opens the app route only).
- Cleanup of photos and models uploaded during an editor session that was cancelled.

## Live commerce stage (2026-11-13)

Opening **Biz & Shop** from the feed lands on `/shops`: a full-screen vertical feed of shop stages, sellers who are live first. No grids or bottom bar; swipe up / down moves between shops.

### Components

| Spec name | Widget | File |
|---|---|---|
| ShopSwipeFeed | `ShopsFeedScreen` | `screens/shops_feed_screen.dart` |
| LiveStageComponent | `ShopStageView` | `widgets/shop_stage_view.dart` |
| SellerProfileComponent | stage header (logo, name, verified, LIVE, viewers, Follow, close) | `widgets/shop_stage_view.dart` (`_TopBar`, `_FollowChip`) |
| Seller live video | `SellerLiveLayer` | `widgets/live_commerce.dart` |
| ThreeDProductViewer | `Product3DViewer` + `StagePlatform` | `widgets/product_3d_viewer.dart`, `widgets/stage_style.dart` |
| ProductInfoCard + PurchaseButton | `ProductInfoCard` (Buy now, Add to cart, deal price) | `widgets/product_info_card.dart` |
| LiveChatComponent | `ShopLiveChat` (live comments) / `StoreAssistantChat` (Ova) | `widgets/live_commerce.dart` |
| Engagement controls | `EngagementRail`, `LiveHearts` | `widgets/live_commerce.dart` |
| Live promotion | `LiveDealCard`, `showLiveDealEditor` | `widgets/live_commerce.dart` |
| Cart | `showShopCartSheet` | `widgets/live_commerce.dart` |

### Store modes

- **Seller live**: the seller's camera fills the stage behind the product (`studioRoomProvider(streamId)`, joined as a viewer only for the visible page). Comments, love reactions and gifts go to the same live room as the Live Studio, so the seller answers from their live screen.
- **Store live** (seller offline): the 3D showroom stays open, Ova answers from the shop's own catalog through `aiGateway` (Vertex AI), and buying works 24/7.

### Integration points

| Need | Where |
|---|---|
| Real-time streaming | LiveKit rooms via `lsStart` / `lsToken` (`backend/live_studio/media`) |
| Live comments | Live Studio comment port (Firestore listeners + `lsComment`) |
| 3D models | GLB/GLTF/USDZ in Storage `shops/{uid}/products/…`, shown with `model_viewer_plus` |
| Payments | Oneova Pay checkout at `/biz/checkout/:productId` (the payment session replaces the old provider) |
| Live deal | `biz_shops/{uid}.liveDeal {title, percentOff, endsAt, productIds}`; checkout prices it on the server |
| Cart | `users/{uid}/cart/{productId or productId__variantId}`; each line checks out as its own order |
| Products | `products/{id}` (shared Biz catalog) |
| Seller tools | `/shops/setup`, `/shops/product/edit`, the More sheet (Live deal) on the seller's own stage |

### Not built yet
- Recorded product demos for store live (no demo-video field on products yet).
- Product ratings and reviews (the card shows the shop rating when the server sets one).
- Multi-item checkout from the cart.

## Business portal (`/business`)

| Screen | Route | What it does |
|---|---|---|
| Portal home | `/business` | Sales today, orders to prepare, low stock, visitors; quick actions (go live, add product, live deal, my stage, store page); verified-business state (links to `/id/business`) |
| Orders | `/business/orders` | Seller queue: to prepare / in delivery / completed / cancelled; `bizSetFulfilment` moves new → packed → ready → shipped and tells the buyer |
| Inventory | `/business/inventory` | Stock per product and option with quick edits, low-stock filter |
| Settings | `/business/settings` | Pickup / delivery, countries, returns / shipping / contact policies, low-stock line; discount codes (`?tab=codes`) |
| Insights | `/business/insights` | 7 / 30 / 90 days: sales and change vs the previous period, funnel (visitors → carts → orders), product performance, buyers and returning rate, buying hours, stock outlook, fulfilment speed |

Server (`functions/src/commerce/storeTools.ts`, pure rules in `storeLogic.ts`, 6 tests): `bizSetFulfilment`, `bizSubmitReview` (one per completed order; product and shop ratings are server-only), `bizTrackEvent` (views / carts / saves, one per person per item per day, into `biz_shops/{uid}/daily/{yyyymmdd}`), `bizCheckCode` (code preview). Checkout prices customizations and codes with `priceCustomization` / `codeDiscount` (Oneova Pay session).

## 3D customization and textures

- Sellers add **buyer customization** to a product: choices (color, material, size…) that can switch a model material look and/or put a texture on the model, with extra prices; or short texts (engraving). Buyers customize on `/shops/p/:id` and see it live in 3D; the selection travels to checkout (`?custom=`, base64url JSON) and onto the order.
- **Texture engine** (`functions/src/commerce/textureEngine.ts`, 4 tests): seamless procedural textures (wood, marble, carbon fibre, denim, leather, brushed metal, glitter, knit, terrazzo, camo, concrete, velvet) rendered to PNG on the server. `textureLibrary` fills the hosted library in Storage (`textures/library/`) on first use; `textureCreate` renders a seller's own colorway into `shops/{uid}/textures/`. Sellers can also upload a photo of their material.
- The 3D viewer reports the model's material names and applies textures (image, roughness, metallic, tiling) to the whole model or one material, keeping the model's own textures to restore.
- Products keep default textures (`products/{id}.textures`). While live, the seller can **show a texture on air** from the stage's More sheet (`biz_shops/{uid}.stageTexture`); every viewer's stage applies it to that product.

## Smart product creation, 3D model service, live show (2026-11-13)

### Product creator (`/shops/product/new`, `screens/product_creator_screen.dart`)
Page by page: Photos → Details → Price → 3D model → Review. `AgentActivityBar` (`widgets/agent_activity.dart`) shows what Ova is doing and can be minimized.
- Photos: background removed on the phone (`data/product_photo.dart`, Studio cut-out) and placed on white.
- Details and price: `shopListingDraft` (`functions/src/models3d/listing.ts`, Gemini on Vertex AI) reads up to four photos plus the shop profile and returns name, description, category, colours, tags and a price band in the seller's currency. Five or more similar Oneova products in that currency outrank the model's estimate (`listingLogic.priceBand`). Nothing is saved until the seller confirms.
- Leaving saves a draft; a model that is still building lands on the product when ready and the seller is notified.
- The full editor stays at `/shops/product/edit?id=`.

### Private 3D model library (`/shops/models`, `functions/src/models3d/`)
- `users/{uid}/models3d/{id}` and Storage `users/{uid}/models3d/{id}/…`: owner-read only, server-written. A model is public only as a copy on a product (`model3dAttach` → `shops/{uid}/products/{productId}/model/`).
- Sources: GLB, GLTF (single file), OBJ, STL up to 100 MB, or 1–4 photos (front first).
- `optimize.ts` writes three files per model: **mobile** (≤120k triangles, 1024px WebP, Meshopt), **hd** for tablets (≤400k, 2048px WebP, Meshopt), **ar** (≤200k, PNG/JPEG, Draco) for the system AR viewer. Material names, variants and animations are kept. The viewer picks hd on tablets (`ShopProduct.viewUrl`).
- Photo → 3D engines (`providers.ts`): the seller's own linked account (key AES-256-GCM encrypted in `model3d_keys/{uid}`, needs secret `MODEL3D_VAULT_KEY`) or Oneova's built-in engine (secret `MESHY_API_KEY`). With neither, photos are kept (`needs_engine`) and can be built later. Only Meshy is implemented.
- `model3dWorker` (4 GiB) converts and optimizes; `model3dSweep` (every minute) follows running generations and fails stuck jobs.
- Not supported yet: FBX, USDZ, multi-file glTF, iOS AR (no USDZ output).

### Currencies
`fxRefresh` rewrites `fx_rates/USD` hourly (about 160 currencies; the source publishes daily). The app streams it (`data/currencies.dart`): the picker lists every currency with a live rate, the default is the phone's region, and product cards show the price in the viewer's own currency (`≈`). Checkout stays in the seller's currency; delivery fees for currencies without their own table are the USD table converted at the stored rate.

### Tracked share links (`functions/src/commerce/shareLinks.ts`)
`https://oneova.web.app/s/{code}` (Hosting rewrite → `shareLinkOpen`): counts the click, shows a preview with OpenGraph tags, opens the app on the product or stage and sends people without the app to the store. `?ref=code` travels to checkout (`data/share_ref.dart`), so `share_links/{code}` holds clicks → opens → checkouts → purchases and revenue. Buying is app-only.

### Live show (`biz_shops/{shopId}/stage/show`, `data/stage_show.dart`, `widgets/stage_live.dart`)
- The seller and anyone on the live's stage (co-host, guest) steer the 3D for everyone: drag (camera pose), named views, spin, the model's animations, which product is on air. Viewers follow, or tap to explore on their own; exploring writes nothing.
- `ShelfCards`: the goods as small price cards with an ON AIR tag. Viewers tap a card for `ProductPreviewScreen` (own 3D, price in their currency, Ova chat); back returns to the live.
- Product questions (`shopChatSend`, `biz_shops/{shopId}/chats/{buyerId}`): Ova answers from the catalog; the seller reads every chat (`showSellerChatsSheet`), can take over, and answers privately or on air (`spotlight`, shown to everyone for 20 s). Voice: mic input and read-aloud are opt-in.
- `showShopMapSheet` (`widgets/shop_map_card.dart`): straight-line distance, tilted map facing the shop, "Take me there" follows the buyer live; turn-by-turn opens Maps.
- Not built: several 3D models on screen at once (one live 3D view at a time keeps phones smooth), a continuous voice call with Ova, in-app route lines along roads.
