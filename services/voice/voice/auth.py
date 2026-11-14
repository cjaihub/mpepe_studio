"""Who may call the voice server.

On Cloud Run the service has no public access (IAM invoker only). Callers send
the same Google ID token twice: X-Serverless-Authorization (checked by Cloud
Run's IAM) and X-Voice-Token (checked here; Cloud Run doesn't forward the
Authorization header to the container). Its audience must be VOICE_AUDIENCE and its email must be in
VOICE_ALLOWED_CALLERS (the Cloud Functions service account).
VOICE_AUTH=off is accepted only together with VOICE_ENV=local.
"""
from __future__ import annotations

import os

from fastapi import Header, HTTPException


def _allowed() -> set[str]:
    return {e.strip() for e in os.environ.get("VOICE_ALLOWED_CALLERS", "").split(",") if e.strip()}


def auth_disabled() -> bool:
    return os.environ.get("VOICE_AUTH") == "off" and os.environ.get("VOICE_ENV") == "local"


def caller(x_voice_token: str | None = Header(default=None), authorization: str | None = Header(default=None)) -> str:
    if auth_disabled():
        return "local-dev"
    authorization = x_voice_token or authorization
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing token")
    audience = os.environ.get("VOICE_AUDIENCE")
    if not audience:
        raise HTTPException(503, "voice audience not configured")
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
