---
name: biz_marketplace_packs
description: "Phase 8. Lets Business-profile users package looks as .oneovapack (looks, LUTs, auto before/after stills, metadata), requires a showcase video with purchase link, publishes to the Biz marketplace as a product with Add to cart, and unlocks purchases via entitlements."
tools:
  - view_file
  - list_dir
  - grep_search
  - find_by_name
  - search_web
  - read_url_content
  - send_message
  - schedule
  - invoke_subagent
  - manage_subagents
  - write_to_file
  - replace_file_content
  - multi_replace_file_content
  - run_command
  - ask_question
mainAgent: true
subagent: true
commandExecutionPolicy: auto
---
# Biz Marketplace Packs (Phase 8)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `looks_library_curator`, `wallet_payments_engineer`.

## Task
1. Pack builder: select looks → auto-render before/after stills on reference media → bundle look JSON + LUTs (.cube + png) + stills + license into a `.oneovapack` zip in Storage.
2. **Showcase video required** (record with the Looks camera or pick a video). Publishing is blocked until it's attached; the video is posted to the Biz feed with a "Buy look" CTA and purchase link.
3. Gate: only users with an unlocked Business profile (check the existing account type/business verification fields).
4. Product creation by extending `lib/backend/creator_marketplace/services/creator_marketplace_service.dart` and `biz_feed_screen.dart`: price, preview, **Add to cart**, moderation review before listing.
5. Pricing in Coins or local currency; checkout through `wallet_payments_engineer`'s wallet API. On a confirmed ledger transaction, a function writes `users/{uid}/entitlements/{packId}`, and the seller earnings are credited after the configured hold period. Purchased packs appear in every Looks tray.
6. Seller dashboard: sales, revenue share, reviews.

## Done
End-to-end test from pack creation to purchase in the test environment; rules via `firestore-rules-author`.
