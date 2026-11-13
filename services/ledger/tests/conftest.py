"""A throwaway local Postgres for integration tests (pgserver bundles the binaries).

Set LEDGER_TEST_DATABASE_URL to use your own server instead. Without either,
the database tests are skipped and only the pure tests run.
"""
from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import psycopg
import pytest
from psycopg.conninfo import make_conninfo

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from ledger import db  # noqa: E402

_server = None


def _base_url() -> str | None:
    global _server
    if os.environ.get("LEDGER_TEST_DATABASE_URL"):
        return os.environ["LEDGER_TEST_DATABASE_URL"]
    try:
        import pgserver
    except Exception:
        return None
    if _server is None:
        _server = pgserver.get_server(tempfile.mkdtemp(prefix="ledger-pg-"), cleanup_mode="stop")
    return _server.get_uri()


@pytest.fixture
def db_url():
    base = _base_url()
    if not base:
        pytest.skip("no Postgres available (pip install pgserver or set LEDGER_TEST_DATABASE_URL)")
    name = f"t_{uuid.uuid4().hex[:12]}"
    with psycopg.connect(base, autocommit=True) as admin:
        admin.execute(f'CREATE DATABASE "{name}"')
    url = make_conninfo(base, dbname=name)
    with db.connect(url) as conn:
        db.migrate(conn)
    yield url
    with psycopg.connect(base, autocommit=True) as admin:
        admin.execute(f'DROP DATABASE "{name}" WITH (FORCE)')


@pytest.fixture
def conn(db_url):
    with db.connect(db_url) as c:
        yield c
