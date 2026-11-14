# Multilingual chats and live translated calls

Rules: `.agents/rules/oneova_build_vision.md` (security first). Steps: Stage G in `docs/plans/BUILD_LOG.md`.
AI providers: OpenRouter for text, Vertex AI for live models and dictation, never the Gemini API directly.

## 1. Chats: detect every language, translate on request or automatically
- **Detection on the phone** with ML Kit Language ID (offline, free, about 100 languages, including
  Swahili, Yoruba, Hausa, Igbo, Zulu, Amharic, Somali, Arabic, French and Portuguese). No message leaves
  the phone just to find its language.
- A message in another language than yours shows a small "Translate from Swahili" chip. One tap
  translates it through `chatAssist`.
- **Automatic translation** is a choice: per chat ("Always translate here") or for all chats (Settings →
  Chat). Chats are end-to-end encrypted, so translating means the text goes to Oneova's AI. We ask once
  and never do it silently.
- "Your language" is the app language (Settings → Language), else the phone language. Several languages
  can be marked "I read these" so they're never offered for translation.
- Voice notes: the existing `translateVoice` (transcript + translation) is used when the detected spoken
  language isn't yours.

## 2. Calls: three stages

### G2. Live translated captions
- Each phone transcribes its own speaker. The speaker's text is sent to the other people in the call over a
  WebRTC **data channel**, which is end-to-end encrypted with the call, with no server in between.
- Each listener translates the captions into their own language (`chatAssist` translate, cached per
  sentence) and sees them as small two-line captions on the call screen. They can show the original too.
- Risk to check on real phones first: Android may not let speech recognition and the call share the
  microphone. If not, captions come from the same single mic capture used in G3.

### G3. Interpreter mode: speech to speech in near real time (Vertex Live)
```
Speaker's phone                                                 Listener's phone
mic ──record (PCM 16 kHz, one capture)──► Vertex Live (Gemini native audio)
                                          "Interpret everything into <listener language>;
                                           speak only the translation"
                                          ◄── translated speech (PCM 24 kHz) + transcripts
          ──WebRTC data channel (encrypted, ~48 KB/s)──────────────► flutter_pcm_sound plays it
          the original mic track is muted while interpreting          captions: original + translation
```
- About 1–2 seconds behind the speaker. Each person hears everyone in their own language.
- Group calls: one Live session per target language, not per listener.
- Turn it on per call ("Translate this call"). Both sides see a "Translated by Oneova AI" badge.
- Vertex Live is called from the phone through Firebase AI Logic (`FirebaseAI.agentPlatform`), with no
  key in the app. App Check is enforced for it.

### G4. In the speaker's own voice
> Plan for self-hosted cloning on Oneova's own GPU: `docs/architecture/voice_cloning_selfhosted.md`.
- Vertex Live speaks with a choice of natural preset voices. We pick the one closest to the speaker
  (pitch and tone from a short sample). That's available now.
- **The exact same voice** (voice cloning) isn't offered by the Live models. Google's cloned-voice option,
  Cloud Text-to-Speech "Instant Custom Voice", needs Google to approve the project, and needs each
  speaker's recorded consent. 🤝
- Safety rules when it comes:
  - only your own voice, with your recorded consent;
  - used only to say your own translated words;
  - never used for payments or identity (voice is never a security factor, `SECURITY_MODEL.md`);
  - the listener always sees that it's AI-translated;
  - your voice sample is encrypted and deleted on request.

## 3. Privacy
- Detection is on the phone. Translation sends text or audio to Oneova's AI only when the user turned it
  on. Nothing is stored after translating. Captions and interpreted audio travel over the call's
  encrypted channel.
- Children's accounts and business calls with a "no AI" policy can't turn interpretation on.
