"""The wallet's money movements as balanced journals.

These mirror today's Firestore functions one to one, so the ledger can run in
shadow mode next to them (functions/src/ledger/outbox.ts) and then take over.
Every template is pure: same inputs, same journal.
"""
from __future__ import annotations

from .core import InvalidJournal, JournalRequest, Posting
from .policy import user

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


TEMPLATES = {
    "coin_purchase": coin_purchase,
    "coin_void": coin_void,
    "gift": gift,
    "release": release,
    "withdrawal_lock": withdrawal_lock,
    "withdrawal_paid": withdrawal_paid,
    "withdrawal_returned": withdrawal_returned,
    "opening_balance": opening_balance,
}
