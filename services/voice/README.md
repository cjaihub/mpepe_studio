# Oneova voice server (self-hosted voice cloning)

Plan and safety rules: `docs/architecture/voice_cloning_selfhosted.md`.

- `voice/logic.py`: pure logic (language routing, phrases, recording quality, stream tokens), tested with
  `python3 -m unittest tests/test_logic.py` (no GPU needed).
- `voice/engine.py`: Chatterbox Multilingual (23 languages, the person's own voice) and OpenVoice v2
  (any other language converted into the person's voice). Runs on the GPU.
- `voice/api.py`: HTTP for Cloud Functions, plus a WebSocket stream for calls.
- `deploy.sh`: Cloud Run with an NVIDIA L4. **Costs money; run only after the user approves.** Needs the
  `VOICE_STREAM_KEY` secret first (shared with Cloud Functions).

Off by default: the app and Functions skip it until the `VOICE_SERVER_URL` secret is set.

V0 (to do on the GPU before launch):
- Listening test in each language; pin `requirements.txt` and the OpenVoice commit.
- Check the OpenVoice weights URL and checksum.
- Confirm Chatterbox Multilingual's `prepare_conditionals` with about 20 s of reference, and the Perth watermark.
