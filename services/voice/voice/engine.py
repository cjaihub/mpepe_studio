"""GPU engine: builds a person's voice and speaks in it. Runs only on the GPU server.

- Chatterbox Multilingual (MIT, Resemble AI; archived Aug 2026, pinned here):
  speaks the 23 CLONE_LANGUAGES directly in the person's voice. Every clip it
  makes carries Resemble's inaudible Perth watermark.
- OpenVoice v2 tone-colour converter (MIT, MyShell): turns speech in any other
  language (e.g. Vertex Live's translation in Yoruba) into the person's voice,
  with an inaudible watermark message.

Everything leaves as 24 kHz mono 16-bit PCM, the format the app plays.
"""
from __future__ import annotations

import io
import os
import tempfile
import threading
from collections import OrderedDict

import numpy as np

from .logic import ClipStats, enrollment_report, split_phrases

OUT_SR = 24000
_lock = threading.Lock()
_tts = None
_tcc = None
_se_extractor = None
_profiles: "OrderedDict[str, dict]" = OrderedDict()  # uid → {conds, se}; small LRU
_PROFILE_CACHE = 64


def _device() -> str:
    import torch
    return "cuda" if torch.cuda.is_available() else "cpu"


def tts():
    global _tts
    with _lock:
        if _tts is None:
            from chatterbox.mtl_tts import ChatterboxMultilingualTTS
            _tts = ChatterboxMultilingualTTS.from_pretrained(device=_device(), t3_model=os.environ.get("CHATTERBOX_T3", "v3"))
        return _tts


def converter():
    global _tcc, _se_extractor
    with _lock:
        if _tcc is None:
            from openvoice import se_extractor
            from openvoice.api import ToneColorConverter
            ckpt = os.environ.get("OPENVOICE_CKPT", "/models/openvoice_v2/converter")
            _tcc = ToneColorConverter(f"{ckpt}/config.json", device=_device())
            _tcc.load_ckpt(f"{ckpt}/checkpoint.pth")
            _se_extractor = se_extractor
        return _tcc, _se_extractor


# ── Audio helpers ─────────────────────────────────────────────────────────

def load_mono(data: bytes, sr: int = OUT_SR) -> np.ndarray:
    """Any audio file (wav, m4a…) → float32 mono at [sr]."""
    import librosa
    y, _ = librosa.load(io.BytesIO(data), sr=sr, mono=True)
    return y.astype(np.float32)


def to_pcm16(y: np.ndarray) -> bytes:
    return (np.clip(y, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()


def measure(name: str, y: np.ndarray, sr: int = OUT_SR) -> ClipStats:
    frame = int(sr * 0.03)
    if y.size < frame:
        return ClipStats(name, y.size / sr, -120.0, -120.0, 0.0)
    frames = y[: y.size // frame * frame].reshape(-1, frame)
    rms = 20 * np.log10(np.sqrt((frames ** 2).mean(axis=1)) + 1e-9)
    speech = rms[rms > np.percentile(rms, 40)]
    return ClipStats(
        name=name,
        seconds=float(y.size / sr),
        rms_db=float(speech.mean() if speech.size else rms.mean()),
        noise_db=float(np.percentile(rms, 10)),
        clipped=float((np.abs(y) > 0.995).mean()),
    )


def _trim(y: np.ndarray, sr: int = OUT_SR) -> np.ndarray:
    import librosa
    t, _ = librosa.effects.trim(y, top_db=35)
    return t


def _normalize(y: np.ndarray, target_db: float = -20.0) -> np.ndarray:
    rms = np.sqrt((y ** 2).mean()) + 1e-9
    return (y * (10 ** (target_db / 20) / rms)).clip(-1, 1).astype(np.float32)


# ── Building a voice ──────────────────────────────────────────────────────

def build_profile(clips: dict[str, bytes], workdir: str) -> dict:
    """[clips]: name → audio bytes (about a minute in all). Writes conds.pt and
    se.pt into [workdir] when there is enough clean speech."""
    audio = {n: _trim(load_mono(b)) for n, b in clips.items()}
    stats = [measure(n, y) for n, y in audio.items()]
    report = enrollment_report(stats)
    if not report["enough"]:
        return report
    gap = np.zeros(int(OUT_SR * 0.25), dtype=np.float32)
    ref = np.concatenate([np.concatenate([_normalize(audio[n]), gap]) for n in report["reference"]])
    ref_path = os.path.join(workdir, "reference.wav")
    import soundfile as sf
    sf.write(ref_path, ref, OUT_SR)
    import torch
    model = tts()
    with _lock:
        model.prepare_conditionals(ref_path, exaggeration=0.5)
        conds = model.conds
    torch.save(conds, os.path.join(workdir, "conds.pt"))
    tcc, se_ex = converter()
    se, _ = se_ex.get_se(ref_path, tcc, vad=True)
    torch.save(se, os.path.join(workdir, "se.pt"))
    report["built"] = True
    return report


def remember(uid: str, conds_path: str | None, se_path: str | None) -> None:
    import torch
    entry = {
        "conds": torch.load(conds_path, map_location=_device(), weights_only=False) if conds_path else None,
        "se": torch.load(se_path, map_location=_device(), weights_only=False) if se_path else None,
    }
    _profiles[uid] = entry
    _profiles.move_to_end(uid)
    while len(_profiles) > _PROFILE_CACHE:
        _profiles.popitem(last=False)


def known(uid: str) -> bool:
    return uid in _profiles


def forget(uid: str) -> None:
    _profiles.pop(uid, None)


# ── Speaking ──────────────────────────────────────────────────────────────

def speak_phrases(uid: str, text: str, language: str):
    """Yields 24 kHz PCM16 per phrase in [uid]'s own voice (clone languages)."""
    import librosa
    entry = _profiles.get(uid)
    if not entry or entry.get("conds") is None:
        raise LookupError("no voice profile")
    model = tts()
    for phrase in split_phrases(text):
        with _lock:
            model.conds = entry["conds"]
            wav = model.generate(phrase, language_id=language, exaggeration=0.5, cfg_weight=0.5, temperature=0.7)
        y = wav.squeeze().detach().cpu().numpy().astype(np.float32)
        if model.sr != OUT_SR:
            y = librosa.resample(y, orig_sr=model.sr, target_sr=OUT_SR)
        yield to_pcm16(y)


def convert_voice(uid: str, pcm16: bytes, sr: int) -> bytes:
    """Speech in another voice (any language) → the same words in [uid]'s voice."""
    import soundfile as sf
    import librosa
    entry = _profiles.get(uid)
    if not entry or entry.get("se") is None:
        raise LookupError("no voice profile")
    y = np.frombuffer(pcm16, dtype="<i2").astype(np.float32) / 32768.0
    tcc, se_ex = converter()
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "src.wav")
        out = os.path.join(d, "out.wav")
        sf.write(src, y, sr)
        src_se, _ = se_ex.get_se(src, tcc, vad=False)
        with _lock:
            tcc.convert(audio_src_path=src, src_se=src_se, tgt_se=entry["se"], output_path=out, message="@Oneova")
        z, zsr = sf.read(out, dtype="float32")
    if zsr != OUT_SR:
        z = librosa.resample(z, orig_sr=zsr, target_sr=OUT_SR)
    return to_pcm16(z)
