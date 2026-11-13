"""HTTP layer: status codes and auth (local auth-off mode only in tests)."""
import pytest
from fastapi.testclient import TestClient

from ledger import api, db


@pytest.fixture
def client(db_url, monkeypatch):
    monkeypatch.setenv("LEDGER_ENV", "local")
    monkeypatch.setenv("LEDGER_AUTH", "off")
    api._pool = db.pool(db_url)
    yield TestClient(api.app)
    api._pool.close()
    api._pool = None


def test_template_post_replay_and_errors(client):
    body = {"idempotency_key": "buy-api-0001", "args": {"uid": "alice", "coins": 700}}
    r1 = client.post("/v1/wallet/coin_purchase", json=body)
    assert r1.status_code == 200 and r1.json()["balances"]["u:alice:coins"] == 700
    r2 = client.post("/v1/wallet/coin_purchase", json=body)
    assert r2.json()["replayed"] is True
    body["args"]["coins"] = 350
    assert client.post("/v1/wallet/coin_purchase", json=body).status_code == 409
    over = {"idempotency_key": "gift-api-0001", "args": {"sender": "alice", "coins": 9999, "receiver": "bob", "receiver_diamonds": 1}}
    assert client.post("/v1/wallet/gift", json=over).status_code == 422
    assert client.post("/v1/wallet/nope", json=body).status_code == 404
    assert client.post("/v1/wallet/release", json={"idempotency_key": "rel-api-0001", "args": {"uid": "bob"}}).status_code == 400
    assert client.get("/v1/accounts/u:alice:coins").json()["balance"] == 700
    assert len(client.get("/v1/accounts/u:alice:coins/entries").json()["entries"]) == 1
    assert client.get("/v1/reconcile").json()["ok"] is True
    q = client.post("/v1/fees/quote", json={"amount_minor": 10_000, "product": "creator_payout", "currency": "USD", "rail": "bank"})
    assert q.status_code == 200 and q.json()["feeMinor"] == 100 and q.json()["payeeCredit"] == 9_900
    assert client.post("/v1/fees/quote", json={"amount_minor": 100, "product": "p2p_transfer", "currency": "USD"}).status_code == 400


def test_auth_required_outside_local(monkeypatch):
    monkeypatch.setenv("LEDGER_ENV", "production")
    monkeypatch.setenv("LEDGER_AUTH", "off")  # ignored outside local
    c = TestClient(api.app)
    assert c.get("/v1/reconcile").status_code == 401
    assert c.get("/v1/reconcile", headers={"Authorization": "Bearer junk"}).status_code in (401, 503)
