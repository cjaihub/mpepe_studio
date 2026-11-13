"""Fees engine: config-driven rules, integer math, exact revenue splits.

A rule matches a transaction on product, and optionally rail, corridor
(from_country -> to_country), currency and partner. The most specific
matching rule that is in effect wins; among equally specific rules the later
effective_from wins. Rules live in config/fee_rules.json, which changes only
through a reviewed pull request; every quote names the rule id, version and
the hash of the rule set, so a posted journal always says which rules it used.

fee = clamp(percent_bps of amount (rounded) + flat_minor, min_minor, max_minor)
The fee is split between partners (shares, in bps of the fee, largest
remainder so the parts always add up) and the platform keeps the rest.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CONFIG = Path(__file__).resolve().parent.parent / "config" / "fee_rules.json"
MATCH_KEYS = ("product", "rail", "from_country", "to_country", "currency", "partner")
PRODUCTS = {"creator_payout", "balance_payout", "biz_order", "p2p_transfer", "merchant_payment", "cash_in", "cash_out"}


class FeeError(ValueError):
    pass


@dataclass(frozen=True)
class Share:
    party: str  # partner id, e.g. "flutterwave" or "bank_x"
    bps: int    # of the fee, 1..10000


@dataclass(frozen=True)
class FeeRule:
    id: str
    version: int
    effective_from: datetime
    match: dict[str, str]
    percent_bps: int = 0
    flat_minor: int = 0
    min_minor: int | None = None
    max_minor: int | None = None
    charge: str = "deducted"
    rounding: str = "half_up"
    shares: tuple[Share, ...] = ()

    @property
    def specificity(self) -> int:
        return sum(1 for k in MATCH_KEYS if k in self.match)


@dataclass
class Quote:
    rule_id: str
    rule_version: int
    rule_set: str
    amount_minor: int
    currency: str
    fee_minor: int
    charge: str
    percent_part: int
    flat_part: int
    shares: dict[str, int] = field(default_factory=dict)
    platform_minor: int = 0

    @property
    def payer_debit(self) -> int:
        """What leaves the payer: amount + fee when charged on top, else the amount."""
        return self.amount_minor + self.fee_minor if self.charge == "on_top" else self.amount_minor

    @property
    def payee_credit(self) -> int:
        """What reaches the payee: the amount, or amount - fee when the fee is deducted."""
        return self.amount_minor if self.charge == "on_top" else self.amount_minor - self.fee_minor

    def to_dict(self) -> dict[str, Any]:
        return {
            "ruleId": self.rule_id, "ruleVersion": self.rule_version, "ruleSet": self.rule_set,
            "amountMinor": self.amount_minor, "currency": self.currency, "feeMinor": self.fee_minor,
            "charge": self.charge, "percentPart": self.percent_part, "flatPart": self.flat_part,
            "shares": self.shares, "platformMinor": self.platform_minor,
            "payerDebit": self.payer_debit, "payeeCredit": self.payee_credit,
        }


def _int(v: Any, name: str, lo: int = 0, hi: int = 10**15) -> int:
    if not isinstance(v, int) or isinstance(v, bool) or not lo <= v <= hi:
        raise FeeError(f"{name} must be an integer between {lo} and {hi}")
    return v


def parse_rule(d: dict[str, Any]) -> FeeRule:
    if not isinstance(d.get("id"), str) or not d["id"]:
        raise FeeError("rule needs an id")
    match = d.get("match") or {}
    if set(match) - set(MATCH_KEYS):
        raise FeeError(f"{d['id']}: unknown match keys {sorted(set(match) - set(MATCH_KEYS))}")
    if match.get("product") not in PRODUCTS:
        raise FeeError(f"{d['id']}: match.product must be one of {sorted(PRODUCTS)}")
    shares = tuple(Share(str(s["party"]), _int(s["bps"], f"{d['id']} share bps", 1, 10_000)) for s in d.get("shares", []))
    if sum(s.bps for s in shares) > 10_000:
        raise FeeError(f"{d['id']}: shares exceed 100% of the fee")
    if d.get("charge", "deducted") not in ("on_top", "deducted"):
        raise FeeError(f"{d['id']}: charge must be on_top or deducted")
    if d.get("rounding", "half_up") not in ("half_up", "half_even", "down", "up"):
        raise FeeError(f"{d['id']}: unknown rounding")
    rule = FeeRule(
        id=d["id"],
        version=_int(d.get("version"), f"{d['id']} version", 1, 10**6),
        effective_from=datetime.fromisoformat(d["effective_from"].replace("Z", "+00:00")),
        match={k: str(v) for k, v in match.items()},
        percent_bps=_int(d.get("percent_bps", 0), f"{d['id']} percent_bps", 0, 10_000),
        flat_minor=_int(d.get("flat_minor", 0), f"{d['id']} flat_minor"),
        min_minor=None if d.get("min_minor") is None else _int(d["min_minor"], f"{d['id']} min_minor"),
        max_minor=None if d.get("max_minor") is None else _int(d["max_minor"], f"{d['id']} max_minor"),
        charge=d.get("charge", "deducted"),
        rounding=d.get("rounding", "half_up"),
        shares=shares,
    )
    if rule.min_minor is not None and rule.max_minor is not None and rule.min_minor > rule.max_minor:
        raise FeeError(f"{rule.id}: min_minor is above max_minor")
    return rule


def divide(n: int, d: int, mode: str) -> int:
    """n / d for non-negative integers, rounded by [mode], with no floats."""
    q, r = divmod(n, d)
    if r == 0 or mode == "down":
        return q
    if mode == "up":
        return q + 1
    twice = 2 * r
    if twice > d:
        return q + 1
    if twice < d:
        return q
    return q + 1 if mode == "half_up" or q % 2 == 1 else q  # exact half


def split(total: int, shares: tuple[Share, ...]) -> tuple[dict[str, int], int]:
    """Splits [total] by bps with the largest-remainder method; returns (parts, platform)."""
    if not shares:
        return {}, total
    exact = [(s.party, total * s.bps) for s in shares]
    parts = {p: v // 10_000 for p, v in exact}
    # Partners together get their combined share rounded half-up; the extra
    # units go to the largest remainders (ties by party name), so it adds up.
    target = divide(total * sum(s.bps for s in shares), 10_000, "half_up")
    leftover = target - sum(parts.values())
    for party, _v in sorted(exact, key=lambda x: (-(x[1] % 10_000), x[0]))[:leftover]:
        parts[party] += 1
    parts = {p: v for p, v in parts.items() if v}
    return parts, total - sum(parts.values())


class FeeBook:
    def __init__(self, rules: list[FeeRule], rule_set: str):
        ids = [(r.id, r.version) for r in rules]
        if len(ids) != len(set(ids)):
            raise FeeError("duplicate rule id + version")
        self.rules = rules
        self.rule_set = rule_set

    @classmethod
    def load(cls, path: Path = CONFIG) -> "FeeBook":
        raw = path.read_bytes()
        data = json.loads(raw)
        return cls([parse_rule(r) for r in data["rules"]], hashlib.sha256(raw).hexdigest()[:16])

    @classmethod
    def from_dicts(cls, rules: list[dict[str, Any]]) -> "FeeBook":
        raw = json.dumps(rules, sort_keys=True).encode()
        return cls([parse_rule(r) for r in rules], hashlib.sha256(raw).hexdigest()[:16])

    def find(self, at: datetime | None = None, **tx: str | None) -> FeeRule:
        at = at or datetime.now(timezone.utc)
        live = [
            r for r in self.rules
            if r.effective_from <= at and all(tx.get(k) == v for k, v in r.match.items())
        ]
        if not live:
            raise FeeError(f"no fee rule for {', '.join(f'{k}={v}' for k, v in tx.items() if v)}")
        return max(live, key=lambda r: (r.specificity, r.effective_from, r.version))

    def quote(self, amount_minor: int, *, product: str, currency: str, rail: str | None = None,
              from_country: str | None = None, to_country: str | None = None, partner: str | None = None,
              at: datetime | None = None) -> Quote:
        _int(amount_minor, "amount_minor", 1)
        rule = self.find(at, product=product, currency=currency, rail=rail,
                         from_country=from_country, to_country=to_country, partner=partner)
        percent = divide(amount_minor * rule.percent_bps, 10_000, rule.rounding)
        fee = percent + rule.flat_minor
        if rule.min_minor is not None:
            fee = max(fee, rule.min_minor)
        if rule.max_minor is not None:
            fee = min(fee, rule.max_minor)
        if rule.charge == "deducted" and fee > amount_minor:
            fee = amount_minor  # a fee can never take more than the whole amount
        shares, platform = split(fee, rule.shares)
        return Quote(rule.id, rule.version, self.rule_set, amount_minor, currency, fee, rule.charge,
                     percent, rule.flat_minor, shares, platform)
