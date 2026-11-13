"""Fees engine: rules, rounding, splits, worked examples from docs/FEES.md, and
parity with today's payout fees in functions/src/creator/payoutLogic.ts."""
import json
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

import pytest

from ledger import templates as t
from ledger.core import _check
from ledger.fees import FeeBook, FeeError, Share, divide, split

ROOT = Path(__file__).resolve().parents[3]


def book(*rules):
    base = {"version": 1, "effective_from": "2026-01-01T00:00:00Z", "charge": "deducted"}
    return FeeBook.from_dicts([{**base, **r} for r in rules])


# ── Worked examples (the same table is in docs/FEES.md) ────────────────────
WORKED = [
    # (rail, amount ¢, fee ¢, creator gets ¢)
    ("mobile_money", 1_000, 20, 980),      # $10: 1.5% = 15¢ → minimum 20¢
    ("mobile_money", 10_000, 150, 9_850),  # $100: 1.5% = $1.50
    ("mobile_money", 1_500, 23, 1_477),    # $15: 22.5¢ → half up → 23¢
    ("bank", 10_000, 100, 9_900),          # $100: 1% = $1, above the 50¢ minimum
    ("bank", 2_000, 50, 1_950),            # $20: 1% = 20¢ → minimum 50¢
    ("stripe", 10_000, 50, 9_950),         # $100: 25¢ + 0.25% (25¢)
    ("stripe", 200_000, 525, 199_475),     # $2,000: 25¢ + $5
]


@pytest.mark.parametrize("rail,amount,fee,net", WORKED)
def test_worked_payout_examples(rail, amount, fee, net):
    q = FeeBook.load().quote(amount, product="creator_payout", currency="USD", rail=rail)
    assert (q.fee_minor, q.payee_credit) == (fee, net)


def test_worked_biz_commission():
    q = FeeBook.load().quote(150_000, product="biz_order", currency="KES")  # KES 1,500.00
    assert (q.fee_minor, q.payee_credit) == (15_000, 135_000)


def test_worked_corridor_cap_and_partner_share():
    b = book(
        {"id": "p2p_default", "match": {"product": "p2p_transfer"}, "percent_bps": 100, "min_minor": 1_000, "charge": "on_top"},
        {"id": "p2p_ke_tz", "match": {"product": "p2p_transfer", "from_country": "KE", "to_country": "TZ"},
         "percent_bps": 200, "min_minor": 2_000, "max_minor": 50_000, "charge": "on_top",
         "shares": [{"party": "mpesa", "bps": 3_000}, {"party": "bank_tz", "bps": 1_000}]},
    )
    # KES 10,000 to Tanzania: 2% = KES 200; M-Pesa 30%, the bank 10%, Oneova keeps 60%.
    q = b.quote(1_000_000, product="p2p_transfer", currency="KES", from_country="KE", to_country="TZ")
    assert q.rule_id == "p2p_ke_tz" and q.fee_minor == 20_000
    assert q.shares == {"mpesa": 6_000, "bank_tz": 2_000} and q.platform_minor == 12_000
    assert (q.payer_debit, q.payee_credit) == (1_020_000, 1_000_000)
    # KES 5,000,000 hits the cap of KES 500.
    assert b.quote(500_000_000, product="p2p_transfer", currency="KES", from_country="KE", to_country="TZ").fee_minor == 50_000
    # Inside Kenya the general rule applies.
    assert b.quote(1_000_000, product="p2p_transfer", currency="KES", from_country="KE", to_country="KE").rule_id == "p2p_default"


# ── Rule selection ─────────────────────────────────────────────────────────
def test_new_version_takes_over_on_its_date_only():
    b = book(
        {"id": "m", "match": {"product": "merchant_payment"}, "percent_bps": 100},
        {"id": "m", "version": 2, "effective_from": "2027-01-01T00:00:00Z", "match": {"product": "merchant_payment"}, "percent_bps": 80},
    )
    before = datetime(2026, 12, 31, tzinfo=timezone.utc)
    after = datetime(2027, 1, 1, tzinfo=timezone.utc)
    assert b.quote(10_000, product="merchant_payment", currency="USD", at=before).fee_minor == 100
    q = b.quote(10_000, product="merchant_payment", currency="USD", at=after)
    assert (q.rule_version, q.fee_minor) == (2, 80)


def test_no_rule_means_no_quote():
    with pytest.raises(FeeError):
        FeeBook.load().quote(1_000, product="p2p_transfer", currency="USD")


def test_bad_rules_are_refused_at_load():
    for bad in (
        {"id": "x", "match": {"product": "nope"}},
        {"id": "x", "match": {"product": "cash_in", "colour": "red"}},
        {"id": "x", "match": {"product": "cash_in"}, "percent_bps": 1.5},
        {"id": "x", "match": {"product": "cash_in"}, "min_minor": 10, "max_minor": 5},
        {"id": "x", "match": {"product": "cash_in"}, "shares": [{"party": "a", "bps": 6000}, {"party": "b", "bps": 5000}]},
    ):
        with pytest.raises(FeeError):
            book(bad)


def test_deducted_fee_never_exceeds_the_amount():
    q = FeeBook.load().quote(5, product="creator_payout", currency="USD", rail="bank")
    assert q.fee_minor == 5 and q.payee_credit == 0


# ── Integer math ───────────────────────────────────────────────────────────
def test_rounding_modes():
    assert [divide(n, 2, "half_up") for n in (1, 3, 5)] == [1, 2, 3]
    assert [divide(n, 2, "half_even") for n in (1, 3, 5)] == [0, 2, 2]
    assert divide(7, 2, "down") == 3 and divide(7, 2, "up") == 4


@pytest.mark.parametrize("total", [0, 1, 2, 3, 7, 99, 100, 101, 12_345])
def test_split_always_adds_up(total):
    parts, platform = split(total, (Share("a", 3_333), Share("b", 3_333), Share("c", 1_000)))
    assert sum(parts.values()) + platform == total
    assert all(v >= 0 for v in parts.values()) and platform >= 0


# ── Journals: every fee part is its own posting ────────────────────────────
def test_payout_and_biz_journals_balance_and_name_the_rule():
    for req in (
        t.payout_cash("k-pay00001", "bob", "w1", "USD", 10_000, "mobile_money"),
        t.biz_order_release("k-biz00001", "o1", "KES", 150_000, "seller1", 20_000, "rider1"),
    ):
        _check(req)
        assert req.metadata["fee"]["ruleId"] and req.metadata["fee"]["ruleSet"]
        assert any(p.account.startswith("sys:fees_") for p in req.postings)


# ── Parity with the TypeScript payout fee in use today ─────────────────────
def test_parity_with_today_payout_fees():
    compiled = ROOT / "functions" / "lib" / "creator" / "payoutLogic.js"
    if not shutil.which("node") or not compiled.exists():
        pytest.skip("node or the compiled functions are not available")
    amounts = list(range(1, 20_001)) + list(range(20_000, 200_001, 7))
    js = ("const l=require(process.argv[1]);const a=JSON.parse(process.argv[2]);const o={};"
          "for(const r of ['mobile_money','bank','stripe'])o[r]=a.map(c=>Math.round(l.payoutFeeUsd(r,c/100)*100));"
          "console.log(JSON.stringify(o))")
    ts = json.loads(subprocess.check_output(["node", "-e", js, str(compiled), json.dumps(amounts)]))
    b = FeeBook.load()
    exact = {"mobile_money": (150, 0), "bank": (100, 0), "stripe": (25, 25)}
    for rail, fees in ts.items():
        bps, _flat = exact[rail]
        for amount, old in zip(amounts, fees):
            if old >= amount:
                continue  # today's code refuses these ("nothing would arrive"); the engine caps at the amount
            new = b.quote(amount, product="creator_payout", currency="USD", rail=rail).fee_minor
            if new != old:
                # Only at exact half cents, where the old float maths rounds unpredictably.
                assert (amount * bps) % 10_000 == 5_000 and abs(new - old) == 1, (rail, amount, old, new)
