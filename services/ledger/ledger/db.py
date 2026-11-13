"""Connection pool and migrations.

DATABASE_URL comes from the environment (Cloud Run: a Secret Manager secret
mounted as an env var, Cloud SQL over the private-IP connector). Never commit it.
"""
from __future__ import annotations

import os
from pathlib import Path

import psycopg
from psycopg_pool import ConnectionPool

MIGRATIONS = Path(__file__).resolve().parent.parent / "migrations"


def connect(url: str | None = None) -> psycopg.Connection:
    # autocommit: every `with conn.transaction()` block is one real transaction.
    return psycopg.connect(url or os.environ["DATABASE_URL"], autocommit=True)


def pool(url: str | None = None) -> ConnectionPool:
    return ConnectionPool(
        url or os.environ["DATABASE_URL"],
        min_size=1,
        max_size=int(os.environ.get("LEDGER_POOL_MAX", "10")),
        kwargs={"autocommit": True},
        open=True,
    )


def migrate(conn: psycopg.Connection) -> list[str]:
    """Applies migrations/NNN_*.sql in order, once each. Returns what it applied."""
    applied: list[str] = []
    with conn.transaction():
        # Lock first: several workers start at once and must not race on CREATE TABLE.
        conn.execute("SELECT pg_advisory_xact_lock(42)")
        conn.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())")
        done = {r[0] for r in conn.execute("SELECT version FROM schema_migrations").fetchall()}
        for f in sorted(MIGRATIONS.glob("*.sql")):
            version = f.stem
            if version in done:
                continue
            conn.execute(f.read_text())
            if version not in {r[0] for r in conn.execute("SELECT version FROM schema_migrations").fetchall()}:
                conn.execute("INSERT INTO schema_migrations (version) VALUES (%s)", (version,))
            applied.append(version)
    return applied
