"""HTTP API for the ledger (FastAPI on Cloud Run, internal callers only).

  POST /v1/journals             a raw balanced journal
  POST /v1/wallet/{template}    a wallet movement built from templates.py
  GET  /v1/accounts/{id}        balance
  GET  /v1/accounts/{id}/entries?before=&limit=   history (newest first)
  GET  /v1/reconcile            cached balances == sum(postings), audit chain intact
  POST /v1/fees/quote           fee for an amount under the current rules (no posting)
  GET  /health   (Cloud Run reserves /healthz)
"""
from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import core, db, templates
from .auth import caller
from .fees import FeeError
from .policy import AccountError

_pool = None


def get_pool():
    global _pool
    if _pool is None:
        _pool = db.pool()
    return _pool


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if os.environ.get("LEDGER_MIGRATE_ON_START") == "true":
        with get_pool().connection() as conn:
            db.migrate(conn)
    yield
    if _pool is not None:
        _pool.close()


app = FastAPI(title="Oneova ledger", version="1", lifespan=lifespan, docs_url=None, redoc_url=None)


class PostingIn(BaseModel):
    account: str
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    amount: int


class JournalIn(BaseModel):
    idempotency_key: str = Field(min_length=8, max_length=200)
    kind: str = Field(pattern=r"^[a-z_]{2,40}$")
    postings: list[PostingIn]
    memo: str = Field(default="", max_length=500)
    metadata: dict[str, Any] = Field(default_factory=dict)


class TemplateIn(BaseModel):
    idempotency_key: str = Field(min_length=8, max_length=200)
    args: dict[str, Any]


def _post(req: core.JournalRequest, who: str) -> dict[str, Any]:
    try:
        with get_pool().connection() as conn:
            r = core.post_journal(conn, req, who)
    except core.IdempotencyConflict as e:
        raise HTTPException(409, {"code": e.code, "message": str(e)}) from None
    except core.InsufficientFunds as e:
        raise HTTPException(422, {"code": e.code, "message": str(e)}) from None
    except (core.InvalidJournal, AccountError) as e:
        raise HTTPException(400, {"code": "invalid", "message": str(e)}) from None
    return {"journalId": r.journal_id, "replayed": r.replayed, "balances": r.balances}


@app.get("/health")
def health() -> dict[str, str]:
    return {"ok": "true"}


@app.post("/v1/journals")
def post_journal(body: JournalIn, who: str = Depends(caller)) -> dict[str, Any]:
    req = core.JournalRequest(
        body.idempotency_key, body.kind,
        [core.Posting(p.account, p.currency, p.amount) for p in body.postings],
        body.memo, body.metadata,
    )
    return _post(req, who)


@app.post("/v1/wallet/{template}")
def post_template(template: str, body: TemplateIn, who: str = Depends(caller)) -> dict[str, Any]:
    build = templates.TEMPLATES.get(template)
    if not build:
        raise HTTPException(404, "unknown template")
    try:
        req = build(body.idempotency_key, **body.args)
    except TypeError as e:
        raise HTTPException(400, {"code": "invalid", "message": f"bad arguments: {e}"}) from None
    except (core.InvalidJournal, AccountError) as e:
        raise HTTPException(400, {"code": "invalid", "message": str(e)}) from None
    return _post(req, who)


@app.get("/v1/accounts/{account}")
def get_balance(account: str, _who: str = Depends(caller)) -> dict[str, Any]:
    try:
        with get_pool().connection() as conn:
            return core.balance(conn, account)
    except AccountError as e:
        raise HTTPException(400, str(e)) from None


@app.get("/v1/accounts/{account}/entries")
def get_entries(account: str, before: int | None = None, limit: int = 50, _who: str = Depends(caller)) -> dict[str, Any]:
    try:
        with get_pool().connection() as conn:
            return {"entries": core.history(conn, account, before, limit)}
    except AccountError as e:
        raise HTTPException(400, str(e)) from None


class QuoteIn(BaseModel):
    amount_minor: int = Field(gt=0)
    product: str
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    rail: str | None = None
    from_country: str | None = Field(default=None, pattern=r"^[A-Z]{2}$")
    to_country: str | None = Field(default=None, pattern=r"^[A-Z]{2}$")
    partner: str | None = None


@app.post("/v1/fees/quote")
def post_quote(body: QuoteIn, _who: str = Depends(caller)) -> dict[str, Any]:
    try:
        return templates.fee_book().quote(
            body.amount_minor, product=body.product, currency=body.currency, rail=body.rail,
            from_country=body.from_country, to_country=body.to_country, partner=body.partner,
        ).to_dict()
    except FeeError as e:
        raise HTTPException(400, {"code": "no_fee_rule", "message": str(e)}) from None


@app.get("/v1/reconcile")
def get_reconcile(_who: str = Depends(caller)) -> dict[str, Any]:
    with get_pool().connection() as conn:
        return core.reconcile(conn)
