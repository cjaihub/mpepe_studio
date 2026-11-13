# Oneova fees (Phase 2)

All fees come from one place: [`services/ledger/config/fee_rules.json`](../services/ledger/config/fee_rules.json).
Change them only through a reviewed pull request. Every quote and every posted journal records the
rule id, the rule version and a hash of the whole rule file, so we can always tell which rules
charged a payment.

Code: `services/ledger/ledger/fees.py`. API: `POST /v1/fees/quote` (internal).
Tests: `services/ledger/tests/test_fees.py`, which runs every example on this page.

## A rule

| Field | Meaning |
|---|---|
| `id`, `version` | A new version with a later `effective_from` replaces the old one on that date. Old versions stay in the file, as history. |
| `effective_from` | ISO time (UTC) from which the rule applies. |
| `match.product` | `creator_payout`, `balance_payout`, `biz_order`, `p2p_transfer`, `merchant_payment`, `cash_in` or `cash_out`. |
| `match.rail`, `from_country`, `to_country`, `currency`, `partner` | Optional. A rule with more of these filled in is more specific, and the most specific matching rule wins. If two are equally specific, the newer one wins. |
| `percent_bps` | Percentage in basis points: 100 bps = 1%. |
| `flat_minor` | A fixed amount in minor units (cents, or whole shillings for UGX and XOF). |
| `min_minor`, `max_minor` | Floor and cap on the total fee. |
| `charge` | `deducted`: the fee comes out of the amount, so the payee gets less. `on_top`: the payer pays amount + fee. |
| `rounding` | `half_up` (default), `half_even`, `down` or `up`. Applies to the percentage part. |
| `shares` | Partners' cut of the fee, in bps of the fee. Oneova keeps the rest. |

Rules for how the numbers work:
- Integers only. There is no floating-point anywhere in fee maths.
- fee = clamp(round(amount × bps / 10,000) + flat, min, max).
- A deducted fee can never be more than the amount.
- Shares are split by largest remainder, so the parts always add up exactly to the fee.

## How a fee lands in the ledger
Each part of a fee is **its own posting** inside the same journal as the payment, so it's atomic:
- `sys:fees_{cur}` is Oneova's part.
- `p:{partner}:share_{cur}` is each partner's part.

The journal's metadata names the rule.

## Today's rules (unchanged from the app's current fees)

| Rule | Product | Fee |
|---|---|---|
| `payout_mobile_money` | Creator payout, mobile money | 1.5%, at least 20¢ (USD), deducted |
| `payout_bank` | Creator payout, bank | 1%, at least 50¢, deducted |
| `balance_payout_mobile_money` | Seller and rider balance withdrawal, mobile money | 1.5%, rounded up, deducted (local currency) |
| `balance_payout_bank` | Seller and rider balance withdrawal, bank | 1%, rounded up, deducted |
| `biz_commission` | Biz order items (any currency) | 10% of items, rounded down so the platform never takes more than 10%; the delivery fee goes to the rider in full |

Stripe payouts were retired when Oneova Pay replaced Stripe (2026-11-13), so the `payout_stripe` rule was removed.

**Parity:** balance-payout fees and the order commission (`functions/src/pay/payLogic.ts`) already use integer maths, and the engine matches them exactly on about 7,000 amounts. For creator payouts, the test runs the app's current TypeScript fee function on 45,715 amounts per rail. The
results are identical except at exact half-cent values (for example 1.5% of $15.00 = 22.5¢). There,
the old floating-point code rounds unpredictably, while the engine always rounds half up. The
difference is at most 1¢. Until the cut-over, a fee change must be made in both `fee_rules.json` and
`functions/src/creator/payoutLogic.ts`; the parity test fails if they drift apart.

## Worked examples (all are tests)

| Case | Amount | Fee | Received |
|---|---|---|---|
| Mobile-money payout | $10.00 | 1.5% = 15¢ → minimum **20¢** | $9.80 |
| Mobile-money payout | $100.00 | **$1.50** | $98.50 |
| Mobile-money payout | $15.00 | 22.5¢ → half up → **23¢** | $14.77 |
| Bank payout | $100.00 | 1% = **$1.00** | $99.00 |
| Bank payout | $20.00 | 20¢ → minimum **50¢** | $19.50 |
| Balance payout, mobile money | KES 1,000 | 1.5% = **KES 15** | KES 985 |
| Balance payout, bank | KES 1.01 | 1.01¢ → up → **2¢** | KES 0.99 |
| Biz order | KES 1,500.00 items | 10% = **KES 150** | seller KES 1,350 |
| Biz order | KES 9.99 items | 99.9¢ → down → **99¢** | seller KES 9.00 |

Example of a corridor rule, shown to explain the format. It is **not** a live rule; p2p prices are a
business decision still to be made:

| Case | Amount | Fee | Split |
|---|---|---|---|
| KE → TZ transfer (2%, min KES 20, cap KES 500, on top) | KES 10,000 | **KES 200** (sender pays KES 10,200) | M-Pesa 30% = KES 60, bank 10% = KES 20, Oneova KES 120 |
| Same corridor | KES 5,000,000 | capped at **KES 500** | |
| Inside Kenya (general 1% rule) | KES 10,000 | the general rule applies | |

## Needs a business or legal decision
- Prices for p2p transfers, scan-to-pay (merchant payments), cash-in and cash-out per country. In
  several markets regulators publish fee caps for mobile money, and fees must be disclosed before
  confirming (the confirm screen will show the quote).
- Partner revenue-share percentages, from each partner contract.
- Whether a half cent should round in the customer's favour (`down`) instead of `half_up`.
- Tax (VAT or excise on fees, e.g. Kenya's excise duty on transfer fees) isn't modelled yet. It
  would be another posting line per fee.
