"""Pure logic for the Oneova voice server (no GPU, no numpy): testable anywhere.

- Which engine speaks a language (Chatterbox clones directly; other languages
  are spoken by Vertex Live and converted into the user's voice with OpenVoice).
- Splitting text into short phrases for streaming.
- Picking the best seconds of a person's recordings to build their voice.
- Short-lived signed tokens for live call streams (minted by Cloud Functions).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import re
import time
from dataclasses import dataclass

# Chatterbox Multilingual (MIT): speaks these with the cloned voice directly.
CLONE_LANGUAGES = frozenset(
    "ar da de el en es fi fr he hi it ja ko ms nl no pl pt ru sv sw tr zh".split()
)

MIN_ENROLL_SECONDS = 55.0  # "about a minute"; a little slack for silences trimmed
MAX_TEXT_CHARS = 400
MAX_PHRASE_CHARS = 160


def base_lang(code: str) -> str:
    return re.split(r"[-_]", (code or "").strip().lower())[0]


def engine_for(language: str) -> str:
    """'clone' (Chatterbox speaks it in the user's voice) or 'convert' (another
    voice speaks it, then OpenVoice turns it into the user's voice)."""
    return "clone" if base_lang(language) in CLONE_LANGUAGES else "convert"


_SENTENCE = re.compile(r"(?<=[.!?。！？؟])\s+")


def split_phrases(text: str, max_chars: int = MAX_PHRASE_CHARS) -> list[str]:
    """Short phrases, so a call hears the first words while the rest is made."""
    text = re.sub(r"\s+", " ", (text or "")).strip()
    if not text:
        return []
    out: list[str] = []
    for sentence in _SENTENCE.split(text):
        s = sentence.strip()
        while len(s) > max_chars:
            cut = s.rfind(",", 0, max_chars)
            if cut < max_chars // 3:
                cut = s.rfind(" ", 0, max_chars)
            if cut < max_chars // 3:
                cut = max_chars
            out.append(s[: cut + (1 if s[cut : cut + 1] == "," else 0)].strip())
            s = s[cut + 1 :].strip()
        if s:
            out.append(s)
    return out


@dataclass(frozen=True)
class ClipStats:
    """Measured on the server for each uploaded clip."""
    name: str
    seconds: float
    rms_db: float      # loudness of speech
    noise_db: float    # loudness of the quietest parts (background)
    clipped: float     # share of samples at full scale (0..1)

    @property
    def snr_db(self) -> float:
        return self.rms_db - self.noise_db


def clip_problems(c: ClipStats) -> list[str]:
    """Plain-language problems the wizard shows ('Too quiet', …)."""
    p: list[str] = []
    if c.seconds < 4:
        p.append("too_short")
    if c.rms_db < -38:
        p.append("too_quiet")
    if c.clipped > 0.002:
        p.append("too_loud")
    if c.snr_db < 15:
        p.append("noisy")
    return p


def enrollment_report(clips: list[ClipStats]) -> dict:
    """Is there enough clean speech to build an exact voice? Which clips to use?"""
    good = [c for c in clips if not clip_problems(c)]
    total = sum(c.seconds for c in clips)
    good_s = sum(c.seconds for c in good)
    # The reference used to condition the voice: the cleanest clips first, ~20 s.
    ranked = sorted(good, key=lambda c: (-c.snr_db, -c.seconds))
    reference, acc = [], 0.0
    for c in ranked:
        if acc >= 20:
            break
        reference.append(c.name)
        acc += c.seconds
    return {
        "totalSeconds": round(total, 1),
        "goodSeconds": round(good_s, 1),
        "enough": good_s >= MIN_ENROLL_SECONDS,
        "reference": reference,
        "retake": [{"clip": c.name, "problems": clip_problems(c)} for c in clips if clip_problems(c)],
    }


# ── Stream tokens (Cloud Functions mints, the voice server checks) ──────────

def _b64(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _unb64(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def sign_stream_token(key: bytes, uid: str, call_id: str, ttl_s: int = 900, now: float | None = None) -> str:
    body = json.dumps({"uid": uid, "call": call_id, "exp": int((now or time.time()) + ttl_s)}, separators=(",", ":"), sort_keys=True)
    sig = hmac.new(key, body.encode(), hashlib.sha256).digest()
    return f"{_b64(body.encode())}.{_b64(sig)}"


def verify_stream_token(key: bytes, token: str, now: float | None = None) -> dict | None:
    """The token's claims, or None if forged, malformed or expired."""
    try:
        body_b64, sig_b64 = token.split(".", 1)
        body = _unb64(body_b64)
        if not hmac.compare_digest(hmac.new(key, body, hashlib.sha256).digest(), _unb64(sig_b64)):
            return None
        claims = json.loads(body)
        if not isinstance(claims, dict) or not isinstance(claims.get("uid"), str) or not claims["uid"]:
            return None
        if int(claims.get("exp", 0)) < (now or time.time()):
            return None
        return claims
    except Exception:
        return None


def safe_uid(uid: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_-]{6,128}", uid or ""))
