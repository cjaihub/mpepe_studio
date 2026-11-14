"""Oneova voice server (Cloud Run, NVIDIA L4, no public access).

HTTP (only Oneova's Cloud Functions; Google ID token, see auth.py):
  POST /v1/profile/build  {uid}                  build the voice from the uploaded minute
  POST /v1/speak          {uid, text, language}  24 kHz PCM16 in the person's own voice
  POST /v1/convert        {uid, sr, audio(b64)}  other speech → the person's voice
  DELETE /v1/profile/{uid}                       delete everything for that person
WebSocket (the caller's phone during a call; short-lived token from Cloud Functions):
  /v1/stream?token=…      {"t":"say","id",text,lang} or {"t":"convert","id","sr"} + binary PCM16
                          ← binary frames: [0x01][id:4 bytes BE][PCM16 24 kHz]; {"t":"done","id"}

Safety: the voice used is always the uid from the verified caller (Functions
pass the signed-in user's own uid; stream tokens bind one uid). There is no
"speak as someone else" input. Text per request is capped.
"""
from __future__ import annotations

import base64
import json
import os
import struct
import tempfile

from fastapi import Depends, FastAPI, HTTPException, Response, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field

from . import engine, store
from .auth import caller
from .logic import MAX_TEXT_CHARS, engine_for, safe_uid, verify_stream_token

app = FastAPI(title="Oneova voice")


def _uid(uid: str) -> str:
    if not safe_uid(uid):
        raise HTTPException(400, "bad uid")
    return uid


def _ensure_loaded(uid: str) -> None:
    if engine.known(uid):
        return
    with tempfile.TemporaryDirectory() as d:
        conds, se = store.fetch_model(uid, d)
        if not conds and not se:
            raise HTTPException(404, "no voice profile")
        engine.remember(uid, conds, se)


@app.get("/health")
def health() -> dict:
    return {"ok": True}


class BuildIn(BaseModel):
    uid: str


@app.post("/v1/profile/build")
def build(body: BuildIn, _who: str = Depends(caller)) -> dict:
    uid = _uid(body.uid)
    clips = store.read_clips(uid)
    if not clips:
        raise HTTPException(404, "no recordings")
    with tempfile.TemporaryDirectory() as d:
        report = engine.build_profile(clips, d)
        if report.get("built"):
            store.save_model(uid, d)
            engine.forget(uid)
            engine.remember(uid, os.path.join(d, "conds.pt"), os.path.join(d, "se.pt"))
    return report


class SpeakIn(BaseModel):
    uid: str
    text: str = Field(max_length=MAX_TEXT_CHARS)
    language: str = Field(max_length=12)


@app.post("/v1/speak")
def speak(body: SpeakIn, _who: str = Depends(caller)) -> Response:
    uid = _uid(body.uid)
    if engine_for(body.language) != "clone":
        raise HTTPException(422, "use /v1/convert for this language")
    _ensure_loaded(uid)
    pcm = b"".join(engine.speak_phrases(uid, body.text, body.language))
    return Response(pcm, media_type="audio/L16; rate=24000; channels=1")


class ConvertIn(BaseModel):
    uid: str
    sr: int = Field(ge=8000, le=48000)
    audio: str = Field(max_length=4 * 1024 * 1024)


@app.post("/v1/convert")
def convert(body: ConvertIn, _who: str = Depends(caller)) -> Response:
    uid = _uid(body.uid)
    _ensure_loaded(uid)
    pcm = engine.convert_voice(uid, base64.b64decode(body.audio), body.sr)
    return Response(pcm, media_type="audio/L16; rate=24000; channels=1")


@app.delete("/v1/profile/{uid}")
def delete(uid: str, _who: str = Depends(caller)) -> dict:
    uid = _uid(uid)
    engine.forget(uid)
    return {"deleted": store.delete_all(uid)}


def _frame(seq_id: int, pcm: bytes) -> bytes:
    return b"\x01" + struct.pack(">I", seq_id & 0xFFFFFFFF) + pcm


@app.websocket("/v1/stream")
async def stream(ws: WebSocket) -> None:
    key = os.environ.get("VOICE_STREAM_KEY", "").encode()
    claims = verify_stream_token(key, ws.query_params.get("token", "")) if key else None
    if not claims:
        await ws.close(code=4401)
        return
    uid = claims["uid"]
    await ws.accept()
    try:
        _ensure_loaded(uid)
    except HTTPException:
        await ws.send_text(json.dumps({"t": "error", "error": "no_profile"}))
        await ws.close(code=4404)
        return
    pending: dict | None = None
    buf = bytearray()
    try:
        while True:
            msg = await ws.receive()
            if msg.get("type") == "websocket.disconnect":
                break
            if msg.get("bytes") is not None:
                if pending and len(buf) < 4 * 1024 * 1024:
                    buf.extend(msg["bytes"])
                continue
            data = json.loads(msg.get("text") or "{}")
            kind, sid = data.get("t"), int(data.get("id", 0))
            if kind == "say":
                text = str(data.get("text", ""))[:MAX_TEXT_CHARS]
                lang = str(data.get("lang", ""))[:12]
                if engine_for(lang) == "clone":
                    for pcm in engine.speak_phrases(uid, text, lang):
                        await ws.send_bytes(_frame(sid, pcm))
                await ws.send_text(json.dumps({"t": "done", "id": sid}))
            elif kind == "convert":
                pending, buf = {"id": sid, "sr": int(data.get("sr", 24000))}, bytearray()
            elif kind == "end" and pending:
                pcm = engine.convert_voice(uid, bytes(buf), pending["sr"])
                await ws.send_bytes(_frame(pending["id"], pcm))
                await ws.send_text(json.dumps({"t": "done", "id": pending["id"]}))
                pending, buf = None, bytearray()
    except WebSocketDisconnect:
        pass
