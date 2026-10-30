# Oneova — Google Play Console draft (paste-ready)

Package: `com.oneova.app` · Version 1.0.0 (versionCode 1) · Firebase `mpepe-2b4bd`
Signed bundle: `build/play/oneova-1.0.0-1.aab` (upload key alias `upload`, SHA1 `BC:4C:F1:82:BB:0C:60:C8:22:BA:2D:F1:71:27:1C:E8:5B:4C:BE:B1`)

> Review every answer against what the app ships. Items marked ⚠️ are things Google is likely to question.

---

## 1. Store listing

**App name (≤30):**
Oneova

**Short description (≤80):**
Short videos, chat, calls, live streams and a full video studio in one app.

**Full description (≤4000):**
Oneova brings creating, sharing and connecting together in one app.

REELS
Watch a full-screen feed of short videos, made for you or from the people you follow. Like, comment, share, save, remix and follow creators. Use Following, For You and Biz to switch feeds, and tune your recommendations in Feed Controls.

STORIES
Share photos and short clips with your followers that disappear after 24 hours.

STUDIO
Create, edit and export videos on your phone. Trim clips, add music and text, apply Looks, then post to Oneova. Exporting happens on your device.

CHAT & CALLS
Send private messages, photos, voice notes and your location to friends, and make voice and video calls.

LIVE
Go live, invite guests and share your screen with your audience. Viewers can comment and react in real time.

AI LAB & OVA ASSISTANT
Ask Ova for help with captions, ideas and everyday tasks. With your permission, Ova can also open apps, set alarms, make calls and help you control your phone hands-free.

BIZ
Discover products and businesses from creators in your community.

SAFETY & CONTROL
Report or block anyone, choose who can see and message you, and download or delete your account and data at any time from Me → Settings → Privacy & Security.

**App category:** Social
**Tags:** Social networking, Short video, Video editor
**Contact email:** (your support email, e.g. support@… — must be monitored)
**Website:** https://mpepe-2b4bd.web.app
**Privacy policy URL:** https://mpepe-2b4bd.web.app/privacy
⚠️ The policy text links to `oneova.app`, which does not load right now. Use the web.app URLs here, or connect the domain first.

**Graphics needed (not created yet):**
- App icon 512×512 PNG (from `assets/images/oneova_logo.png`)
- Feature graphic 1024×500
- At least 2 phone screenshots (16:9 or 9:16, 320–3840 px), ideally 4–8: Reels feed, Studio editor, Chat, Live, Ova

---

## 2. App content

| Section | Answer |
|---|---|
| Privacy policy | https://mpepe-2b4bd.web.app/privacy |
| App access | Login required → give reviewers a working test account (phone/email + password or test OTP). Create a dedicated reviewer account; don't use a personal one. |
| Ads | No ads (change this if any ad SDK is added) |
| Content rating (IARC) | Social category. Users interact: yes. Shares location: yes. User-generated content: yes. Digital purchases: yes (if Coins stay). Expect Teen/12+ or higher. |
| Target audience | 13+ (or 18+ if Wallet/Biz payouts stay). Don't pick under-13 age groups. |
| News app | No |
| COVID-19 apps | No |
| Data safety | See section 3 |
| Government app | No |
| Financial features | Pick "None" unless you keep the Wallet. If you keep it: "Mobile payments and digital wallets". |
| Health | No |
| Child safety standards (required for social apps) | Published standards URL: https://mpepe-2b4bd.web.app/child-safety · CSAM contact: (named person/email) · In-app reporting: yes (Report on posts and profiles) |
| Account deletion | In-app: Me → Settings → Privacy & Security. Web URL: https://mpepe-2b4bd.web.app/deletion |

---

## 3. Data safety form

**Overview answers**
- Does the app collect or share user data? **Yes**
- Is all data encrypted in transit? **Yes** (HTTPS/TLS only; cleartext is blocked except on localhost)
- Can users request deletion? **Yes** (in-app + deletion URL)

**Data types** (Collected = sent off the device. "Shared" means passed to a third party for its own use. Service providers that only process data for Oneova, like Firebase, don't count as sharing.)

| Category → type | Collected | Shared | Optional? | Purposes |
|---|---|---|---|---|
| Personal info → Name | Yes | No | Required | App functionality, Account management |
| Personal info → Email address | Yes | No | Optional (sign-in method) | Account management, App functionality |
| Personal info → User IDs | Yes | No | Required | App functionality, Account management, Analytics, Fraud prevention |
| Personal info → Phone number | Yes | No | Optional (sign-in method) | Account management, Fraud prevention |
| Personal info → Other (date of birth / age bracket, bio) | Yes | No | Required (age) | App functionality, Account management |
| Financial info → Purchase history | Yes (if Wallet/Coins ship) | No | Optional | App functionality, Fraud prevention |
| Location → Approximate location | Yes | No | Optional | App functionality (location sharing in chat, Ova) |
| Location → Precise location | Yes | No | Optional | App functionality (share live location in chat) |
| Messages → Other in-app messages | Yes | No | Optional | App functionality |
| Photos and videos → Photos, Videos | Yes | No | Optional | App functionality (posts, stories, chat) |
| Audio → Voice or sound recordings | Yes | No | Optional | App functionality (voice notes, live, calls) |
| Contacts → Contacts | Check: is the address book uploaded? If contacts only stay on the device for Ova calling, answer **Not collected**. | No | Optional | App functionality |
| App activity → App interactions, In-app search history, Other user-generated content | Yes | No | Required | App functionality, Analytics, Personalization |
| App info & performance → Crash logs, Diagnostics | Yes | No | Required | Analytics (Crashlytics, Performance) |
| Device or other IDs → Device or other IDs | Yes | No | Required | App functionality (push tokens), Analytics, Fraud prevention (App Check) |

⚠️ **AI prompts:** Ova/AI Lab send prompts to OpenRouter and Google Gemini directly from the phone. If those prompts include user content, either list them as collected with the AI provider acting as a service provider, or move the calls to Cloud Functions.

⚠️ **Accessibility and notification access:** Ova reads screen content and notifications. If any of that leaves the device (for example sent to the LLM), declare it under App activity / Messages, and cover it in the prominent disclosure.

---

## 4. Permission & API declarations

**Accessibility API (OvaAccessibilityService)** ⚠️ highest rejection risk
- Oneova isn't an accessibility tool, so declare it as *not* one (`android:isAccessibilityTool="false"`, Play's default).
- Justification: "Ova is a voice assistant that, only after the user turns it on in Settings › Accessibility, performs actions the user asks for by voice in other apps (tap, scroll, go back, read what's on screen to answer a question). Screen content is processed only to carry out the current command and is not stored or used for ads."
- Needs: a prominent in-app disclosure plus consent before sending users to Settings, and a short video of the disclosure and the feature in use.

**Foreground service types** (one video per type)
- `mediaProjection | microphone | camera` (LiveScreenCaptureService): "Keeps a live stream running while the user shares their screen, camera and microphone with viewers. Starts only when the user taps Share screen / Go Live, and shows an ongoing notification with Stop."
- `phoneCall` (calls via flutter_callkit_incoming / WebRTC): "Keeps an active voice/video call connected while the app is in the background."
- `specialUse` (OvaOverlayService), subtype "Floating interactive assistant and quick command interface over apps": "Shows the floating Ova button over other apps after the user turns it on, so they can call the assistant from anywhere."
- `location` (FOREGROUND_SERVICE_LOCATION): "Keeps live-location sharing in chat running for the period the user chose." ⚠️ If no service actually uses the location type, remove this permission instead of declaring it.

**Full-screen intent (USE_FULL_SCREEN_INTENT):** Declare as "Calling" (incoming voice/video calls ring over the lock screen).

**Photo & video permissions (READ_MEDIA_IMAGES / READ_MEDIA_VIDEO):** "Studio is a video editor and needs to browse the user's whole gallery repeatedly to build multi-clip timelines, which the one-time photo picker can't support." ⚠️ Google often rejects this for social apps. If it's rejected, switch to the Android photo picker.

**Other sensitive items (no form, but keep the disclosures):** SYSTEM_ALERT_WINDOW (overlay), Notification Listener (Ova reads notifications aloud, opt-in), READ_CONTACTS (call/message a contact by voice), CAMERA, RECORD_AUDIO, ACCESS_FINE_LOCATION, default assistant (ACTION_ASSIST).

---

## 5. Pre-launch blockers / risks

1. ✅ **Secrets removed from the app (2026-10-30):** AI calls now go through the `aiProxy` Cloud Function, and the TikTok code exchange through `tiktokExchangeCode`. `.env` no longer holds either secret (values moved to the gitignored `.env.secrets.local`). Server-side Gemini (aiGateway, guardExplainEvent, Looks, live-health monitor) runs on Vertex AI as the functions' service account, so there is no Gemini key. Still to do: run `tools/play/backend_setup.sh` to enable Vertex and deploy. Gemini Live voice mode (`generateLiveApiToken`) is not deployed: Vertex has no ephemeral client tokens, so that screen stays offline in v1. Also **rotate the TikTok client secret** in the TikTok developer portal: an obfuscated copy was committed to the public GitHub repo in `lib/core/env/env.g.dart`.
2. ⚠️ **Payments policy:** Wallet Coins are topped up through Flutterwave/M-Pesa. Coins spent on digital items (gifts, tips, Looks, AI credits) must use Google Play Billing. Physical goods or real-world services in Biz may use other payment methods. Either hide Coin top-up in the Play build or add Play Billing.
3. Add the Play **app-signing** SHA-1/SHA-256 (Play Console › Setup › App signing) to Firebase › Project settings › Android app, or Google sign-in and phone sign-in will fail in the store build.
4. Back up `android/app/upload-keystore.jks` and `android/key.properties` (passwords) somewhere safe outside this Mac.
5. Bump `version:` in `pubspec.yaml` (for example `1.0.1+2`) for every new upload. Play rejects a versionCode it has already seen.
