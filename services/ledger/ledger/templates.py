"""The wallet's money movements as balanced journals.

These mirror today's Firestore functions one to one, so the ledger can run in
shadow mode next to them (functions/src/ledger/outbox.ts) and then take over.
Every template is pure: same inputs, same journal.
"""
from __future__ import annotations

from .core import InvalidJournal, JournalRequest, Posting
from .fees import FeeBook, FeeError, Quote
from .policy import fiat, user

XCN, XDM = "XCN", "XDM"


def _pos(n: int, what: str) -> int:
    if not isinstance(n, int) or isinstance(n, bool) or n <= 0:
        raise InvalidJournal(f"{what} must be a positive integer")
    return n


def coin_purchase(key: str, uid: str, coins: int, debt_paid: int = 0, order_id: str | None = None) -> JournalRequest:
    """Play pack credited. A refunded earlier pack is paid back first (debt_paid)."""
    _pos(coins, "coins")
    if not 0 <= debt_paid <= coins:
        raise InvalidJournal("debt_paid must be between 0 and coins")
    postings = [Posting("sys:coins_issued", XCN, -coins)]
    if coins - debt_paid:
        postings.append(Posting(user(uid, "coins"), XCN, coins - debt_paid))
    if debt_paid:
        postings.append(Posting(user(uid, "coin_debt"), XCN, debt_paid))
    return JournalRequest(key, "coin_purchase", postings, metadata={"uid": uid, "orderId": order_id})


def coin_void(key: str, uid: str, take_from_balance: int, add_debt: int, order_id: str | None = None) -> JournalRequest:
    """A refunded pack: coins come back from the balance; what was spent becomes debt."""
    if take_from_balance < 0 or add_debt < 0 or take_from_balance + add_debt <= 0:
        raise InvalidJournal("nothing to void")
    postings = [Posting("sys:coins_issued", XCN, take_from_balance + add_debt)]
    if take_from_balance:
        postings.append(Posting(user(uid, "coins"), XCN, -take_from_balance))
    if add_debt:
        postings.append(Posting(user(uid, "coin_debt"), XCN, -add_debt))
    return JournalRequest(key, "coin_void", postings, metadata={"uid": uid, "orderId": order_id})


def gift(key: str, sender: str, coins: int, receiver: str, receiver_diamonds: int,
         remix_author: str | None = None, remix_diamonds: int = 0) -> JournalRequest:
    """A gift spends the sender's coins and creates the receivers' pending Diamonds."""
    _pos(coins, "coins")
    _pos(receiver_diamonds, "receiver_diamonds")
    if sender == receiver:
        raise InvalidJournal("you can't gift yourself")
    created = receiver_diamonds + (remix_diamonds if remix_author else 0)
    postings = [
        Posting(user(sender, "coins"), XCN, -coins),
        Posting("sys:coins_spent", XCN, coins),
        Posting("sys:dm_issued", XDM, -created),
        Posting(user(receiver, "dm_pending"), XDM, receiver_diamonds),
    ]
    if remix_author and remix_diamonds:
        _pos(remix_diamonds, "remix_diamonds")
        postings.append(Posting(user(remix_author, "dm_pending"), XDM, remix_diamonds))
    return JournalRequest(key, "gift", postings, metadata={"from": sender, "to": receiver})


def release(key: str, uid: str, diamonds: int) -> JournalRequest:
    """Hold period over: pending Diamonds become withdrawable."""
    _pos(diamonds, "diamonds")
    return JournalRequest(key, "release", [
        Posting(user(uid, "dm_pending"), XDM, -diamonds),
        Posting(user(uid, "dm_available"), XDM, diamonds),
    ], metadata={"uid": uid})


def withdrawal_lock(key: str, uid: str, diamonds: int, withdrawal_id: str) -> JournalRequest:
    _pos(diamonds, "diamonds")
    return JournalRequest(key, "withdrawal_lock", [
        Posting(user(uid, "dm_available"), XDM, -diamonds),
        Posting(user(uid, "dm_locked"), XDM, diamonds),
    ], metadata={"uid": uid, "withdrawalId": withdrawal_id})


def withdrawal_paid(key: str, uid: str, diamonds: int, withdrawal_id: str) -> JournalRequest:
    _pos(diamonds, "diamonds")
    return JournalRequest(key, "withdrawal_paid", [
        Posting(user(uid, "dm_locked"), XDM, -diamonds),
        Posting("sys:dm_paid_out", XDM, diamonds),
    ], metadata={"uid": uid, "withdrawalId": withdrawal_id})


def withdrawal_returned(key: str, uid: str, diamonds: int, withdrawal_id: str) -> JournalRequest:
    """Failed or cancelled: the Diamonds go back to available."""
    _pos(diamonds, "diamonds")
    return JournalRequest(key, "withdrawal_returned", [
        Posting(user(uid, "dm_locked"), XDM, -diamonds),
        Posting(user(uid, "dm_available"), XDM, diamonds),
    ], metadata={"uid": uid, "withdrawalId": withdrawal_id})


def opening_balance(key: str, uid: str, coins: int = 0, pending: int = 0, available: int = 0, locked: int = 0) -> JournalRequest:
    """One-time backfill from the Firestore counters (dry-run first, with approval)."""
    postings: list[Posting] = []
    if coins:
        postings += [Posting("sys:coins_issued", XCN, -coins), Posting(user(uid, "coins"), XCN, coins)]
    diamonds = pending + available + locked
    if diamonds:
        postings.append(Posting("sys:dm_issued", XDM, -diamonds))
        for kind, n in (("dm_pending", pending), ("dm_available", available), ("dm_locked", locked)):
            if n:
                postings.append(Posting(user(uid, kind), XDM, n))
    if any(n < 0 for n in (coins, pending, available, locked)):
        raise InvalidJournal("opening balances can't be negative")
    if not postings:
        raise InvalidJournal("nothing to open")
    return JournalRequest(key, "opening_balance", postings, metadata={"uid": uid})


_book: FeeBook | None = None


def fee_book() -> FeeBook:
    global _book
    if _book is None:
        _book = FeeBook.load()
    return _book


def _fee_postings(q: Quote, currency: str) -> list[Posting]:
    """One posting per fee part: the platform's and each partner's share."""
    out = [Posting(fiat("p", "share", currency, party), currency, n) for party, n in sorted(q.shares.items())]
    if q.platform_minor:
        out.append(Posting(fiat("sys", "fees", currency), currency, q.platform_minor))
    return out


def _fee_meta(q: Quote) -> dict:
    return {"fee": {"ruleId": q.rule_id, "ruleVersion": q.rule_version, "ruleSet": q.rule_set, "feeMinor": q.fee_minor}}


def _quote(amount: int, **tx) -> Quote:
    try:
        return fee_book().quote(amount, **tx)
    except FeeError as e:
        raise InvalidJournal(str(e)) from e


def payout_cash(key: str, uid: str, withdrawal_id: str, currency: str, gross_minor: int,
                rail: str, country: str | None = None, partner: str | None = None) -> JournalRequest:
    """Cash side of a creator payout: the Diamonds' value splits into what the
    creator receives (net, owed until the partner settles) and the fee parts."""
    _pos(gross_minor, "gross_minor")
    q = _quote(gross_minor, product="creator_payout", currency=currency, rail=rail, to_country=country, partner=partner)
    postings = [
        Posting(fiat("sys", "payout_source", currency), currency, -gross_minor),
        *_fee_postings(q, currency),
    ]
    if q.payee_credit:
        postings.append(Posting(fiat("sys", "payout_clearing", currency), currency, q.payee_credit))
    return JournalRequest(key, "payout_cash", postings, metadata={"uid": uid, "withdrawalId": withdrawal_id, **_fee_meta(q)})


def biz_order_paid(key: str, order_id: str, currency: str, total_minor: int) -> JournalRequest:
    """The buyer's card payment lands; held in escrow until delivery."""
    _pos(total_minor, "total_minor")
    return JournalRequest(key, "biz_order_paid", [
        Posting(fiat("sys", "biz_inflow", currency), currency, -total_minor),
        Posting(fiat("sys", "biz_escrow", currency), currency, total_minor),
    ], metadata={"orderId": order_id})


def biz_order_release(key: str, order_id: str, currency: str, items_minor: int, seller: str,
                      delivery_minor: int = 0, rider: str | None = None) -> JournalRequest:
    """Delivery confirmed: escrow pays the seller (items - commission) and the rider."""
    _pos(items_minor, "items_minor")
    if delivery_minor < 0 or (delivery_minor and not rider):
        raise InvalidJournal("a delivery fee needs a rider")
    q = _quote(items_minor, product="biz_order", currency=currency)
    postings = [
        Posting(fiat("sys", "biz_escrow", currency), currency, -(items_minor + delivery_minor)),
        *_fee_postings(q, currency),
    ]
    if q.payee_credit:
        postings.append(Posting(fiat("u", "biz_payable", currency, seller), currency, q.payee_credit))
    if delivery_minor and rider:
        postings.append(Posting(fiat("u", "biz_payable", currency, rider), currency, delivery_minor))
    return JournalRequest(key, "biz_order_release", postings, metadata={"orderId": order_id, "seller": seller, **_fee_meta(q)})


TEMPLATES = {
    "coin_purchase": coin_purchase,
    "coin_void": coin_void,
    "gift": gift,
    "release": release,
    "withdrawal_lock": withdrawal_lock,
    "withdrawal_paid": withdrawal_paid,
    "withdrawal_returned": withdrawal_returned,
    "opening_balance": opening_balance,
    "payout_cash": payout_cash,
    "biz_order_paid": biz_order_paid,
    "biz_order_release": biz_order_release,
}
