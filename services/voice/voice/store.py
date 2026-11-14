"""Where voices live: Cloud Storage, server-only paths (storage.rules let the
owner upload their clips and nobody read anything back).

  voice_profiles/{uid}/clips/*.m4a      the minute of recordings (kept for retraining)
  voice_profiles/{uid}/consent.m4a      the spoken consent line (proof of consent)
  voice_profiles/{uid}/model/conds.pt   Chatterbox voice
  voice_profiles/{uid}/model/se.pt      OpenVoice voice colour
"""
from __future__ import annotations

import os

from google.cloud import storage

_client = None


def bucket():
    global _client
    if _client is None:
        _client = storage.Client()
    return _client.bucket(os.environ["VOICE_BUCKET"])


def prefix(uid: str) -> str:
    return f"voice_profiles/{uid}/"


def read_clips(uid: str) -> dict[str, bytes]:
    out: dict[str, bytes] = {}
    for blob in bucket().list_blobs(prefix=prefix(uid) + "clips/"):
        if blob.size and blob.size < 8 * 1024 * 1024:
            out[blob.name.rsplit("/", 1)[-1]] = blob.download_as_bytes()
    return out


def save_model(uid: str, local_dir: str) -> None:
    for name in ("conds.pt", "se.pt"):
        p = os.path.join(local_dir, name)
        if os.path.exists(p):
            bucket().blob(prefix(uid) + "model/" + name).upload_from_filename(p)


def fetch_model(uid: str, local_dir: str) -> tuple[str | None, str | None]:
    paths = []
    for name in ("conds.pt", "se.pt"):
        blob = bucket().blob(prefix(uid) + "model/" + name)
        if blob.exists():
            p = os.path.join(local_dir, name)
            blob.download_to_filename(p)
            paths.append(p)
        else:
            paths.append(None)
    return paths[0], paths[1]


def delete_all(uid: str) -> int:
    n = 0
    for blob in bucket().list_blobs(prefix=prefix(uid)):
        blob.delete()
        n += 1
    return n
