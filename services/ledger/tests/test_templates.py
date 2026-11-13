"""Pure tests: every wallet movement is a balanced journal (no database)."""
import pytest

from ledger import templates as t
from ledger.core import InvalidJournal, JournalRequest, Posting, _check, request_hash
from ledger.policy import AccountError


def sums(req):
    out = {}
    for p in req.postings:
        out[p.currency] = out.get(p.currency, 0) + p.amount
    return out


ALL = [
    t.coin_purchase("k-000001", "alice", 700),
    t.coin_purchase("k-000002", "alice", 700, debt_paid=500),
    t.coin_void("k-000003", "alice", 200, 500),
    t.gift("k-000004", "alice", 100, "bob", 80),
    t.gift("k-000005", "alice", 100, "bob", 60, remix_author="carol", remix_diamonds=20),
    t.release("k-000006", "bob", 80),
    t.withdrawal_lock("k-000007", "bob", 80, "w1"),
    t.withdrawal_paid("k-000008", "bob", 80, "w1"),
    t.withdrawal_returned("k-000009", "bob", 80, "w1"),
    t.opening_balance("k-000010", "bob", coins=5, pending=3, available=2, locked=1),
]


@pytest.mark.parametrize("req", ALL, ids=[r.kind for r in ALL])
def test_every_template_balances(req):
    _check(req)
    assert all(v == 0 for v in sums(req).values())


def test_coins_and_diamonds_never_mix():
    g = t.gift("k-000011", "alice", 100, "bob", 80)
    assert {p.currency for p in g.postings if p.account.endswith(":coins")} == {"XCN"}
    assert {p.currency for p in g.postings if ":dm_" in p.account} == {"XDM"}


def test_bad_inputs_are_refused():
    with pytest.raises(InvalidJournal):
        t.gift("k-000012", "alice", 100, "alice", 80)
    with pytest.raises(InvalidJournal):
        t.release("k-000013", "bob", 0)
    with pytest.raises(InvalidJournal):
        t.release("k-000014", "bob", 1.5)  # type: ignore[arg-type]
    with pytest.raises(InvalidJournal):
        t.coin_purchase("k-000015", "a", 10, debt_paid=11)
    with pytest.raises(AccountError):
        t.release("k-000016", "bad:uid", 5)


def test_unbalanced_or_float_journals_are_refused():
    with pytest.raises(InvalidJournal):
        _check(JournalRequest("k-000017", "x_y", [Posting("u:a:coins", "XCN", 5), Posting("sys:coins_issued", "XCN", -4)]))
    with pytest.raises(InvalidJournal):
        _check(JournalRequest("k-000018", "x_y", [Posting("u:a:coins", "XCN", 0.5), Posting("sys:coins_issued", "XCN", -0.5)]))  # type: ignore[arg-type]
    with pytest.raises(InvalidJournal):
        _check(JournalRequest("k-000019", "x_y", [Posting("u:a:coins", "XDM", 5), Posting("sys:dm_issued", "XDM", -5)]))
    with pytest.raises(InvalidJournal):
        _check(JournalRequest("k-000020", "x_y", [Posting("u:a:coins", "XCN", True), Posting("sys:coins_issued", "XCN", -1)]))  # type: ignore[arg-type]


def test_request_hash_ignores_posting_order():
    a = JournalRequest("k-000021", "gift", [Posting("u:a:coins", "XCN", -5), Posting("sys:coins_spent", "XCN", 5)])
    b = JournalRequest("k-000021", "gift", [Posting("sys:coins_spent", "XCN", 5), Posting("u:a:coins", "XCN", -5)])
    assert request_hash(a) == request_hash(b)
