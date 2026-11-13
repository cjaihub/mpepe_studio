"""Integration tests against a real Postgres (see conftest.py)."""
import random
import threading

import psycopg
import pytest

from ledger import core, db
from ledger import templates as t


def post(conn, req):
    return core.post_journal(conn, req, "test")


def bal(conn, account):
    return core.balance(conn, account)["balance"]


def test_wallet_life_cycle(conn):
    post(conn, t.coin_purchase("buy-0001", "alice", 700))
    post(conn, t.gift("gift-0001", "alice", 100, "bob", 80))
    post(conn, t.release("rel-00001", "bob", 80))
    post(conn, t.withdrawal_lock("lock-0001", "bob", 50, "w1"))
    post(conn, t.withdrawal_paid("paid-0001", "bob", 50, "w1"))
    assert bal(conn, "u:alice:coins") == 600
    assert bal(conn, "u:bob:dm_available") == 30
    assert bal(conn, "u:bob:dm_locked") == 0
    assert bal(conn, "sys:dm_paid_out") == 50
    assert core.reconcile(conn)["ok"]


def test_idempotent_replay_and_conflict(conn):
    a = post(conn, t.coin_purchase("buy-0002", "alice", 70))
    b = post(conn, t.coin_purchase("buy-0002", "alice", 70))
    assert b.replayed and b.journal_id == a.journal_id
    assert bal(conn, "u:alice:coins") == 70
    with pytest.raises(core.IdempotencyConflict):
        post(conn, t.coin_purchase("buy-0002", "alice", 350))


def test_no_overdraft(conn):
    post(conn, t.coin_purchase("buy-0003", "alice", 50))
    with pytest.raises(core.InsufficientFunds):
        post(conn, t.gift("gift-0002", "alice", 100, "bob", 80))
    assert bal(conn, "u:alice:coins") == 50
    assert bal(conn, "u:bob:dm_pending") == 0  # the whole journal rolled back


def test_refund_with_debt_then_next_pack_pays_it(conn):
    post(conn, t.coin_purchase("buy-0004", "alice", 700))
    post(conn, t.gift("gift-0003", "alice", 500, "bob", 400))
    post(conn, t.coin_void("void-0001", "alice", 200, 500))
    assert bal(conn, "u:alice:coins") == 0
    assert bal(conn, "u:alice:coin_debt") == -500
    post(conn, t.coin_purchase("buy-0005", "alice", 700, debt_paid=500))
    assert bal(conn, "u:alice:coins") == 200
    assert bal(conn, "u:alice:coin_debt") == 0
    assert core.reconcile(conn)["ok"]


def test_entries_are_append_only(conn):
    post(conn, t.coin_purchase("buy-0006", "alice", 70))
    for sql in ("UPDATE postings SET amount = 1", "DELETE FROM postings", "UPDATE journals SET memo = 'x'",
                "DELETE FROM audit_log", "TRUNCATE postings CASCADE"):
        with pytest.raises(psycopg.Error):
            with conn.transaction():
                conn.execute(sql)


def test_balances_cannot_be_written_directly(conn):
    post(conn, t.coin_purchase("buy-0007", "alice", 70))
    with pytest.raises(psycopg.Error):
        with conn.transaction():
            conn.execute("UPDATE balances SET balance = 1000000 WHERE account_id = 'u:alice:coins'")
    assert bal(conn, "u:alice:coins") == 70


def test_database_refuses_unbalanced_journal_even_without_the_app(conn):
    with pytest.raises(psycopg.Error):
        with conn.transaction():
            conn.execute("INSERT INTO accounts (id, currency) VALUES ('u:x:coins', 'XCN')")
            conn.execute("""INSERT INTO journals (id, idempotency_key, request_hash, kind, actor)
                            VALUES ('00000000-0000-0000-0000-000000000001', 'raw-00001', 'h', 'raw', 't')""")
            conn.execute("""INSERT INTO postings (journal_id, account_id, currency, amount)
                            VALUES ('00000000-0000-0000-0000-000000000001', 'u:x:coins', 'XCN', 5)""")
    assert bal(conn, "u:x:coins") == 0


def test_tampering_breaks_the_audit_chain(conn):
    post(conn, t.coin_purchase("buy-0008", "alice", 70))
    post(conn, t.coin_purchase("buy-0009", "alice", 70))
    assert core.reconcile(conn)["audit_broken_at"] is None
    # A superuser bypassing the triggers is still caught by the hash chain.
    with conn.transaction():
        conn.execute("ALTER TABLE audit_log DISABLE TRIGGER audit_immutable")
        conn.execute("UPDATE audit_log SET detail = '{\"kind\":\"forged\"}' WHERE id = (SELECT min(id) FROM audit_log)")
        conn.execute("ALTER TABLE audit_log ENABLE TRIGGER audit_immutable")
    assert core.reconcile(conn)["audit_broken_at"] is not None


def test_concurrent_spends_never_overdraw(db_url):
    with db.connect(db_url) as c:
        post(c, t.coin_purchase("buy-0010", "alice", 1000))
    ok, refused = [], []

    def spend(i):
        with db.connect(db_url) as c:
            try:
                post(c, t.gift(f"gift-c{i:04d}", "alice", 30, f"r{i % 7}", 24))
                ok.append(i)
            except core.InsufficientFunds:
                refused.append(i)
            except Exception as e:  # surfaced in the assert below
                other.append(repr(e))

    other: list[str] = []
    threads = [threading.Thread(target=spend, args=(i,)) for i in range(60)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    with db.connect(db_url) as c:
        assert not other, other
        assert len(ok) == 33 and len(refused) == 27  # 33 × 30 = 990 ≤ 1000
        assert bal(c, "u:alice:coins") == 10
        assert core.reconcile(c)["ok"]


def test_random_journals_keep_every_invariant(conn):
    rng = random.Random(7)
    users = ["a", "b", "c", "d"]
    for u in users:
        post(conn, t.coin_purchase(f"seed-{u}-0001", u, 10_000))
    for i in range(300):
        s, r = rng.sample(users, 2)
        coins = rng.randint(1, 400)
        try:
            post(conn, t.gift(f"rg-{i:05d}", s, coins, r, max(1, coins * 4 // 5)))
            if rng.random() < 0.5:
                pending = bal(conn, f"u:{r}:dm_pending")
                if pending:
                    post(conn, t.release(f"rr-{i:05d}", r, rng.randint(1, pending)))
        except core.InsufficientFunds:
            pass
    rep = core.reconcile(conn)
    assert rep["ok"], rep
    for u in users:
        assert bal(conn, f"u:{u}:coins") >= 0
        assert bal(conn, f"u:{u}:dm_pending") >= 0


def test_fee_journals_post_and_reconcile(conn):
    post(conn, t.payout_cash("pc-000001", "bob", "w1", "USD", 10_000, "mobile_money"))
    post(conn, t.biz_order_paid("bp-000001", "o1", "KES", 170_000))
    post(conn, t.biz_order_release("br-000001", "o1", "KES", 150_000, "seller1", 20_000, "rider1"))
    assert bal(conn, "sys:fees_usd") == 150
    assert bal(conn, "sys:payout_clearing_usd") == 9_850
    assert bal(conn, "sys:fees_kes") == 15_000
    assert bal(conn, "u:seller1:biz_payable_kes") == 135_000
    assert bal(conn, "u:rider1:biz_payable_kes") == 20_000
    assert bal(conn, "sys:biz_escrow_kes") == 0
    assert core.reconcile(conn)["ok"]


def test_escrow_cannot_release_more_than_was_paid(conn):
    post(conn, t.biz_order_paid("bp-000002", "o2", "KES", 100_000))
    with pytest.raises(core.InsufficientFunds):
        post(conn, t.biz_order_release("br-000002", "o2", "KES", 150_000, "seller1"))


def test_oneova_pay_postings_mirror_and_escrow_cannot_overpay(conn):
    paid = [{"account": "clearing:mpesa", "currency": "KES", "amountMinor": -170_000},
            {"account": "escrow:ord1", "currency": "KES", "amountMinor": 170_000}]
    post(conn, t.pay_posting("pay_ord1_paid", "order_paid", paid))
    post(conn, t.pay_posting("pay_ord1_paid", "order_paid", paid))  # retried: applied once
    release = [{"account": "escrow:ord1", "currency": "KES", "amountMinor": -170_000},
               {"account": "user:seller1", "currency": "KES", "amountMinor": 135_000, "bucket": "pending"},
               {"account": "user:rider1", "currency": "KES", "amountMinor": 20_000, "bucket": "available"},
               {"account": "platform:revenue", "currency": "KES", "amountMinor": 15_000}]
    post(conn, t.pay_posting("pay_ord1_release", "order_release", release))
    assert bal(conn, "o:ord1:escrow_kes") == 0
    assert bal(conn, "u:seller1:pay_pending_kes") == 135_000
    with pytest.raises(core.InsufficientFunds):  # a second release finds an empty escrow
        post(conn, t.pay_posting("pay_ord1_release2", "order_release", release))
    with pytest.raises(core.InvalidJournal):
        t.pay_posting("pay_bad_000001", "x_y", [{"account": "weird:1", "currency": "KES", "amountMinor": 1},
                                                 {"account": "user:a", "currency": "KES", "amountMinor": -1}])
    assert core.reconcile(conn)["ok"]


def test_business_and_personal_balances_are_separate(conn):
    sale = [{"account": "clearing:mpesa", "currency": "KES", "amountMinor": -100_000},
            {"account": "biz:shop1", "currency": "KES", "amountMinor": 99_000, "bucket": "available"},
            {"account": "platform:revenue", "currency": "KES", "amountMinor": 1_000}]
    post(conn, t.pay_posting("pay_sale_0001", "merchant_payin", sale))
    move = [{"account": "biz:shop1", "currency": "KES", "amountMinor": -40_000, "bucket": "available"},
            {"account": "user:shop1", "currency": "KES", "amountMinor": 40_000, "bucket": "available"}]
    post(conn, t.pay_posting("pay_move_0001", "business_to_personal", move))
    assert bal(conn, "u:shop1:biz_available_kes") == 59_000
    assert bal(conn, "u:shop1:pay_available_kes") == 40_000
    with pytest.raises(core.InsufficientFunds):  # can't move more than the business has
        post(conn, t.pay_posting("pay_move_0002", "business_to_personal", [
            {"account": "biz:shop1", "currency": "KES", "amountMinor": -60_000, "bucket": "available"},
            {"account": "user:shop1", "currency": "KES", "amountMinor": 60_000, "bucket": "available"}]))
