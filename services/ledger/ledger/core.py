"""Posting journals, reading balances and history, reconciling.

All money is integer minor units. The database enforces the invariants
(migrations/001_init.sql); this module adds idempotency, account opening,
deterministic lock order and the hash-chained audit log.
"""
from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import dataclass, field
from typing import Any, Iterable

import psycopg
from psycopg.rows import dict_row

from .policy import account_currency_ok, allow_negative, validate_account_id

GENESIS = "0" * 64
# One lock id for appending to the audit chain (serialises audit appends only).
AUDIT_LOCK = 0x0E0A1ED6
# SQLSTATEs raised by migrations/001_init.sql.
INSUFFICIENT_FUNDS = "OL001"


class LedgerError(Exception):
    code = "invalid"


class InvalidJournal(LedgerError):
    code = "invalid"


class IdempotencyConflict(LedgerError):
    code = "idempotency_conflict"


class InsufficientFunds(LedgerError):
    code = "insufficient_funds"


@dataclass(frozen=True)
class Posting:
    account: str
    currency: str
    amount: int


@dataclass
class JournalRequest:
    idempotency_key: str
    kind: str
    postings: list[Posting]
    memo: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class PostResult:
    journal_id: str
    replayed: bool
    balances: dict[str, int]


def _check(req: JournalRequest) -> None:
    if not (8 <= len(req.idempotency_key) <= 200):
        raise InvalidJournal("idempotency_key must be 8-200 characters")
    if len(req.postings) < 2:
        raise InvalidJournal("a journal needs at least two postings")
    if len(req.postings) > 50:
        raise InvalidJournal("too many postings")
    sums: dict[str, int] = {}
    for p in req.postings:
        # bool is an int in Python; refuse it, and floats, explicitly.
        if not isinstance(p.amount, int) or isinstance(p.amount, bool):
            raise InvalidJournal("amounts must be integers (minor units)")
        if p.amount == 0:
            raise InvalidJournal("zero postings are not allowed")
        if abs(p.amount) > 9_000_000_000_000_000:
            raise InvalidJournal("amount out of range")
        validate_account_id(p.account)
        if not account_currency_ok(p.account, p.currency):
            raise InvalidJournal(f"{p.account} can't hold {p.currency}")
        sums[p.currency] = sums.get(p.currency, 0) + p.amount
    unbalanced = [c for c, s in sums.items() if s != 0]
    if unbalanced:
        raise InvalidJournal(f"journal does not balance in {', '.join(sorted(unbalanced))}")


def request_hash(req: JournalRequest) -> str:
    """Stable hash of what the journal does (same key + different body = conflict)."""
    body = {
        "kind": req.kind,
        "postings": sorted([p.account, p.currency, p.amount] for p in req.postings),
        "memo": req.memo,
        "metadata": req.metadata,
    }
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _balances(cur: psycopg.Cursor, accounts: Iterable[str]) -> dict[str, int]:
    cur.execute("SELECT account_id, balance FROM balances WHERE account_id = ANY(%s)", (list(accounts),))
    return {r["account_id"]: int(r["balance"]) for r in cur.fetchall()}


def _audit(cur: psycopg.Cursor, actor: str, action: str, subject: str, detail: dict[str, Any]) -> None:
    cur.execute("SELECT pg_advisory_xact_lock(%s)", (AUDIT_LOCK,))
    cur.execute("SELECT hash FROM audit_log ORDER BY id DESC LIMIT 1")
    row = cur.fetchone()
    prev = row["hash"] if row else GENESIS
    payload = json.dumps({"actor": actor, "action": action, "subject": subject, "detail": detail}, sort_keys=True, separators=(",", ":"))
    digest = hashlib.sha256((prev + payload).encode()).hexdigest()
    cur.execute(
        "INSERT INTO audit_log (actor, action, subject, detail, prev_hash, hash) VALUES (%s, %s, %s, %s, %s, %s)",
        (actor, action, subject, json.dumps(detail), prev, digest),
    )


def post_journal(conn: psycopg.Connection, req: JournalRequest, actor: str) -> PostResult:
    """Posts a balanced journal exactly once per idempotency key."""
    _check(req)
    h = request_hash(req)
    accounts = sorted({p.account for p in req.postings})
    with conn.transaction():
        cur = conn.cursor(row_factory=dict_row)
        cur.execute("SELECT id, request_hash FROM journals WHERE idempotency_key = %s", (req.idempotency_key,))
        seen = cur.fetchone()
        if seen:
            if seen["request_hash"] != h:
                raise IdempotencyConflict("this idempotency key was used for a different journal")
            return PostResult(str(seen["id"]), True, _balances(cur, accounts))

        for p in sorted(req.postings, key=lambda x: x.account):
            cur.execute(
                # No conflict target: covers both unique indexes when two journals open it at once.
                "INSERT INTO accounts (id, currency, allow_negative) VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
                (p.account, p.currency, allow_negative(p.account)),
            )
        jid = uuid.uuid4()
        cur.execute(
            """INSERT INTO journals (id, idempotency_key, request_hash, kind, memo, metadata, actor)
               VALUES (%s, %s, %s, %s, %s, %s, %s) ON CONFLICT (idempotency_key) DO NOTHING RETURNING id""",
            (jid, req.idempotency_key, h, req.kind, req.memo, json.dumps(req.metadata), actor),
        )
        if cur.fetchone() is None:
            # Another request with the same key committed between our check and insert.
            cur.execute("SELECT id, request_hash FROM journals WHERE idempotency_key = %s", (req.idempotency_key,))
            other = cur.fetchone()
            if other["request_hash"] != h:
                raise IdempotencyConflict("this idempotency key was used for a different journal")
            return PostResult(str(other["id"]), True, _balances(cur, accounts))

        # Same lock order for every journal (sorted accounts) avoids deadlocks.
        try:
            for p in sorted(req.postings, key=lambda x: (x.account, x.amount)):
                cur.execute(
                    "INSERT INTO postings (journal_id, account_id, currency, amount) VALUES (%s, %s, %s, %s)",
                    (jid, p.account, p.currency, p.amount),
                )
        except psycopg.errors.ForeignKeyViolation as e:
            raise InvalidJournal("account currency mismatch") from e
        except psycopg.Error as e:
            if e.sqlstate == INSUFFICIENT_FUNDS:  # from the balance trigger
                raise InsufficientFunds(str(e).split("\n")[0]) from e
            raise
        _audit(cur, actor, "post", str(jid), {"kind": req.kind, "key": req.idempotency_key, "postings": len(req.postings)})
        return PostResult(str(jid), False, _balances(cur, accounts))


def balance(conn: psycopg.Connection, account: str) -> dict[str, Any]:
    validate_account_id(account)
    cur = conn.cursor(row_factory=dict_row)
    cur.execute("SELECT account_id, currency, balance, version, updated_at FROM balances WHERE account_id = %s", (account,))
    r = cur.fetchone()
    if not r:
        return {"account": account, "balance": 0, "version": 0}
    return {"account": account, "currency": r["currency"], "balance": int(r["balance"]), "version": int(r["version"])}


def history(conn: psycopg.Connection, account: str, before_id: int | None = None, limit: int = 50) -> list[dict[str, Any]]:
    validate_account_id(account)
    limit = max(1, min(limit, 200))
    cur = conn.cursor(row_factory=dict_row)
    cur.execute(
        """SELECT p.id, p.amount, p.currency, p.created_at, j.id AS journal_id, j.kind, j.memo, j.metadata
           FROM postings p JOIN journals j ON j.id = p.journal_id
           WHERE p.account_id = %s AND (%s::bigint IS NULL OR p.id < %s)
           ORDER BY p.id DESC LIMIT %s""",
        (account, before_id, before_id, limit),
    )
    return [
        {**r, "journal_id": str(r["journal_id"]), "amount": int(r["amount"]), "created_at": r["created_at"].isoformat()}
        for r in cur.fetchall()
    ]


def reconcile(conn: psycopg.Connection) -> dict[str, Any]:
    """Checks that cached balances equal the sum of postings, every currency nets
    to zero, and the audit hash chain is intact."""
    cur = conn.cursor(row_factory=dict_row)
    cur.execute(
        """SELECT a.id, coalesce(b.balance, 0) AS cached, coalesce(s.total, 0) AS derived
           FROM accounts a
           LEFT JOIN balances b ON b.account_id = a.id
           LEFT JOIN (SELECT account_id, sum(amount) AS total FROM postings GROUP BY account_id) s ON s.account_id = a.id
           WHERE coalesce(b.balance, 0) <> coalesce(s.total, 0)"""
    )
    drift = [{"account": r["id"], "cached": int(r["cached"]), "derived": int(r["derived"])} for r in cur.fetchall()]
    cur.execute("SELECT currency, sum(amount) AS total FROM postings GROUP BY currency HAVING sum(amount) <> 0")
    unbalanced = {r["currency"]: int(r["total"]) for r in cur.fetchall()}
    cur.execute("SELECT id, actor, action, subject, detail, prev_hash, hash FROM audit_log ORDER BY id")
    prev, broken_at = GENESIS, None
    for r in cur.fetchall():
        payload = json.dumps({"actor": r["actor"], "action": r["action"], "subject": r["subject"], "detail": r["detail"]}, sort_keys=True, separators=(",", ":"))
        if r["prev_hash"] != prev or hashlib.sha256((prev + payload).encode()).hexdigest() != r["hash"]:
            broken_at = int(r["id"])
            break
        prev = r["hash"]
    return {"ok": not drift and not unbalanced and broken_at is None, "drift": drift, "unbalanced": unbalanced, "audit_broken_at": broken_at}
