"""Who may call the ledger.

On Cloud Run the service has no public access (IAM invoker only). As a second
lock, every request must carry a Google ID token for LEDGER_AUDIENCE whose
email is in LEDGER_ALLOWED_CALLERS (the Cloud Functions service account).
LEDGER_AUTH=off is accepted only together with LEDGER_ENV=local.
"""
from __future__ import annotations

import os

from fastapi import Header, HTTPException


def _allowed() -> set[str]:
    return {e.strip() for e in os.environ.get("LEDGER_ALLOWED_CALLERS", "").split(",") if e.strip()}


def auth_disabled() -> bool:
    return os.environ.get("LEDGER_AUTH") == "off" and os.environ.get("LEDGER_ENV") == "local"


def caller(authorization: str | None = Header(default=None)) -> str:
    if auth_disabled():
        return "local-dev"
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing token")
    audience = os.environ.get("LEDGER_AUDIENCE")
    if not audience:
        raise HTTPException(503, "ledger audience not configured")
    from google.auth.transport import requests as grequests
    from google.oauth2 import id_token

    try:
        info = id_token.verify_oauth2_token(authorization[7:], grequests.Request(), audience=audience)
    except Exception:
        raise HTTPException(401, "invalid token") from None
    email = info.get("email", "")
    if not info.get("email_verified") or email not in _allowed():
        raise HTTPException(403, "caller not allowed")
    return email
