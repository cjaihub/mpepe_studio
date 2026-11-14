# Self-hosted voice cloning for translated calls and voice notes

Status (2026-11-14): code built for V0 to V5, **off until the GPU is approved and deployed**.
- V0: licences checked (Chatterbox MIT, archived Aug 2026 so pinned; OpenVoice MIT; weights URL confirmed).
  The listening test runs on the GPU.
- V1: `services/voice`.
- V2: `lib/voice/my_voice_wizard_screen.dart` and `functions/src/voice/voice.ts`. The user asked to keep the
  minute of recordings under the profile, so the clips are kept (not deleted after 24 h) and deleted on
  "Turn off".
- V3: your own voice notes in another language.
- V4: calls in your own voice, with a preset-voice fallback.
- V5: OpenVoice conversion for languages Chatterbox lacks.
Plan (step G4 of `docs/architecture/translated_calls.md`). Rules:
`.agents/rules/oneova_build_vision.md` (security first). Same infrastructure idea as self-hosted 3D
(`packages/three_d_model_server`, Cloud Run GPU, IAM only).

Goal: when you speak in a call or send a voice note, the other person hears **your own voice** in **their
language**. It must be safe: only you can use your voice, only for your own words, always labelled as AI.

## 1. What we have today
| Piece | Today | Gap |
|---|---|---|
| Live calls | Vertex Live interprets speech to speech in one of 4 preset voices (`lib/backend/calling/interpreter/`) | Not your voice |
| Voice notes | `chatAssist` `translateVoice`: transcript, translation and the closest preset voice with pitch and rate | Close, not your voice |
| GPU servers | 3D model server planned on Cloud Run GPU (L4), scale to zero, IAM only | Nothing for voice yet |

## 2. Choice of model (licences must be checked before use; they change)
We need: cloning from a short sample (10–30 s), streaming output for calls, many languages, a licence that
allows commercial use, and ideally a built-in watermark.

| Model | Why it fits | Watch out |
|---|---|---|
| **Chatterbox Multilingual** (Resemble AI) | Zero-shot cloning, about 23 languages including Swahili, Arabic, French and Portuguese, built-in inaudible watermark, MIT licence (as last known) | Not every African language |
| **CosyVoice 2** (Alibaba) | Streaming with low first-audio delay, good for calls, Apache-2.0 (as last known) | Mostly Chinese, English, Japanese and Korean |
| **OpenVoice v2** (MyShell) | Tone-colour converter: makes *any* TTS voice sound like you, MIT (as last known) | Quality lower than full cloning |
| XTTS-v2, F5-TTS, Fish-Speech | Strong quality | Weights licensed **non-commercial** (as last known), so not usable |

**Plan:**
- Chatterbox Multilingual is the main voice for its languages.
- For languages it lacks (Yoruba, Hausa, Igbo, Zulu, Amharic and more), use a commercially licensed TTS for
  that language, then OpenVoice to turn it into your voice.
- CosyVoice 2 only if Chatterbox can't stream fast enough.

## 3. How it works

### 3.1 Voice enrolment (once, with consent)
- Settings → Voice → "Translate in my own voice".
- You read a short consent line ("I agree that Oneova may use my voice to speak my own translated words"),
  then two short sentences: about 20 s in all.
- The phone uploads it to a private, owner-only Storage path.
- The GPU server makes a **speaker embedding** (a voice fingerprint). The embedding is stored encrypted,
  keyed to your account (`voice_profiles/{uid}`, server-only).
- The minute of recordings is kept under the profile (owner-upload-only storage), so the voice can be
  rebuilt or improved later. The consent clip is kept as proof of consent.
- Turning it off deletes the embedding and the consent clip, and the feature stops at once.

### 3.2 Voice notes (first, easiest)
1. The voice note is transcribed and translated as today (`translateVoice`).
2. The translated text goes to the GPU server's `speak` with the sender's embedding, and comes back as audio.
3. The audio is cached per message and language, so it's made only once.
- The listener sees a small "AI voice · translated" label and can play the original.

### 3.3 Live calls
```
Speaker's phone ── mic ──► Vertex Live (interpret, TEXT output + input transcription)   ~0.7–1.2 s
                                     │ translated phrases
                                     ▼
                     Oneova voice server (GPU): streaming TTS with the speaker's embedding  ~0.3–0.6 s
                                     │ audio chunks (24 kHz PCM)
Speaker's phone ◄────────────────────┘ ──► call data channel (encrypted) ──► listener plays it
```
- This reuses today's interpreter. Vertex Live returns **text** instead of its own voice, and the GPU
  server speaks that text in your voice.
- Target delay is about 1.5–2.5 s behind the speaker. Today it's 1–2 s.
- If the GPU server is slow or down, fall back to today's preset voice automatically.
- Later: self-hosted streaming speech recognition and translation on the same GPU to cut delay further.

## 4. Security and safety (must all be done before launch)
1. **Only your own voice:** the server takes the voice from the signed-in caller's own embedding, never
   from a request field. Nobody can make someone else's voice speak.
2. **Only your own words:**
   - Calls: only text that came from your own live transcription in that call.
   - Voice notes: only the translation of your own note.
   - No free-text "say anything" endpoint.
3. **Labelled:** every cloned clip has an inaudible watermark (Chatterbox's, or Meta AudioSeal), and the
   app always shows "AI voice". The watermark lets us prove a clip came from Oneova.
4. **Never a security factor:** voice is not used for payments, sign-in or identity
   (`docs/payments/platform/SECURITY_MODEL.md`).
5. **Consent and age:**
   - Explicit consent with the time recorded.
   - Not available to under-18 accounts.
   - Turning it off deletes everything.
6. **Abuse limits:**
   - Per-user rate limits.
   - Short output per request.
   - Reports go to the admin review queue.
   - Accounts flagged for impersonation lose the feature.
7. **Access:**
   - The GPU server only accepts calls with a Google ID token from Oneova's functions service account, or a
     verified Firebase ID token plus App Check for streaming.
   - Embeddings are encrypted at rest with KMS.
   - No audio is stored after the call.
8. **Privacy policy:** a new section on voice profiles before launch.

## 5. Infrastructure and cost
- `packages/voice_model_server`: Python (FastAPI plus WebSocket for streaming), Docker, Cloud Run with one
  NVIDIA L4 GPU in `us-central1`. Same pattern and deploy script as the 3D model server.
- Scaling:
  - Voice notes can scale to zero (the first one after idle waits for a cold start, about 20–60 s).
  - Calls need a warm instance while anyone is in a translated call. Keep `min-instances=1` during busy
    hours, or start it when a call begins and accept the first phrase in a preset voice.
- Cost: a Cloud Run L4 GPU costs on the order of a dollar per hour while running (check current pricing).
  One L4 can serve several calls at once.
- Functions callables: `voiceEnroll`, `voiceDisable`, `voiceSpeakNote` (server-side), and a short-lived
  token for the call stream.

## 6. Build order
| Step | What | Done when |
|---|---|---|
| V0 | Check model licences and quality in each target language; pick the models | Listening test notes in this file |
| V1 | `voice_model_server` with `embed` and `speak`, IAM only, watermark on every clip | Runs on a Cloud Run L4 |
| V2 | Enrolment screen, consent, embeddings, delete | A user can turn it on and off |
| V3 | Voice notes in your own voice (cached per language) | Two phones, two languages |
| V4 | Live calls: Vertex text, then cloned streaming TTS, falling back to the preset voice | Delay under 2.5 s on 4G |
| V5 | More African languages through TTS plus OpenVoice conversion | Yoruba, Hausa, Zulu and Amharic tested |

## 7. Decisions for you
- GPU cost: OK to run an L4 for voice (shared with 3D if both are on)?
- Calls: always-warm GPU at busy hours (instant, costs more) or start on demand (first phrase in a preset
  voice)?
- Launch languages for your own voice: start with Chatterbox's list (including Swahili, French, Arabic and
  Portuguese) and add others with step V5?
