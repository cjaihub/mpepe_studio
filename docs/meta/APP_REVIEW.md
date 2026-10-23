# Oneova · Meta App Review pack

Everything to paste into **developers.facebook.com → Oneova (App ID 1793552618518208)** for review.

**Done in the dashboard (2026-10-23):** Basic settings (domain, privacy, terms,
data-deletion callback, category), Facebook Login for Business settings
(redirect URI, deauthorize callback), the Page permissions added to the
"Manage everything on your Page" use case, and the login configuration
**"Oneova creator connect", ID 994479442939228** (user access token) with:
pages_show_list, pages_read_engagement, pages_read_user_content,
pages_manage_posts, pages_manage_engagement, pages_messaging,
pages_manage_metadata (added by Meta as a dependency), instagram_basic,
instagram_content_publish, instagram_manage_comments.

---

## 1. App settings → Basic

| Field | Value |
|---|---|
| Display name | Oneova |
| App domains | `mpepe-2b4bd.web.app` |
| Contact email | `privacy@oneova.app` |
| Privacy Policy URL | `https://mpepe-2b4bd.web.app/privacy` |
| Terms of Service URL | `https://mpepe-2b4bd.web.app/terms` |
| User data deletion | **Data deletion callback URL** → `https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDataDeletion` |
| Category | Entertainment (or "Social networking") |
| App icon | 1024 × 1024, `assets/images/oneova_logo.png` |

**Platform → Android**: package `com.oneova.app`, class `com.oneova.app.MainActivity`,
key hashes from both keys (run on your Mac, paste the output):

```bash
keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore | openssl sha1 -binary | openssl base64
```
```bash
keytool -exportcert -alias [[your release key alias]] -keystore [[path from android/key.properties]] | openssl sha1 -binary | openssl base64
```

**Platform → iOS**: bundle ID `[[your iOS bundle id]]` (still `com.example.mpepeStudio`
in Xcode; change it before release).

---

## 2. Facebook Login for Business → Settings

| Field | Value |
|---|---|
| Client OAuth login | On |
| Web OAuth login | On |
| Enforce HTTPS | On |
| Use Strict Mode for redirect URIs | On |
| **Valid OAuth Redirect URIs** | `https://mpepe-2b4bd.web.app/meta-callback` |
| **Deauthorize callback URL** | `https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDeauthorize` |
| Data deletion request URL | `https://us-central1-mpepe-2b4bd.cloudfunctions.net/metaDataDeletion` |

How the login works (for your own reference): the app opens Facebook's login
dialog with `config_id=994479442939228` (Login for Business uses the
configuration instead of a scope list) → Facebook sends the user to `/meta-callback` on Firebase Hosting → that
page hands the one-time code to the app (`oneova://meta-callback`) → the app
sends the code to the `metaExchangeCode` Cloud Function, which holds the app
secret, exchanges it and returns the Pages. **The app secret is never in the app.**

---

## 3. Permissions to request (Advanced Access)

Paste the **"How will your app use this permission?"** text for each one.

### pages_show_list
> Oneova is a creator studio app. When a creator taps "Connect Facebook" in
> Oneova (Me → Social Hub → Connect → Facebook), we use pages_show_list to show
> the Facebook Pages they manage so they can choose which Page to connect.
> We only list the Pages; nothing is posted or changed.

### pages_read_engagement
> After a creator connects a Page, Oneova shows that Page's follower count,
> recent posts with like and comment counts, and Page insights (reach,
> impressions, engagement) on the creator's Social Hub dashboard and in the
> Ova assistant ("show my Facebook page"). This lets creators track how their
> Page content performs next to their other platforms.

### pages_read_user_content
> Oneova shows the creator the latest comments people leave on their Page's
> posts (Social Hub → Comments, and Ova: "show my Facebook comments") so they
> can read and answer them from one inbox. We only read comments on Pages the
> creator connected.

### pages_manage_posts
> Creators edit a video in Oneova Studio and choose "Publish → Facebook Page".
> Oneova uses pages_manage_posts to publish that video or text post to the Page
> they connected. Every post is written by the creator and is only published
> after they press Post and confirm (press-and-hold) in the app.

### pages_manage_engagement
> When a creator chooses to reply to a comment on their Page from Oneova
> (Social Hub → Comments → Reply, or the Ova assistant), we use
> pages_manage_engagement to post that reply as the Page. The creator writes or
> approves the exact text on a confirmation card before it is sent.

### pages_messaging
> Oneova shows the connected Page's Messenger conversations in the creator's
> inbox and lets the creator answer a message from the app (Ova assistant →
> "show my Facebook messages" → Reply). Replies are only sent after the creator
> confirms the exact text, only to people who messaged the Page first, and
> within Messenger's 24-hour standard messaging window. No promotional or
> automated broadcast messages are sent.

### pages_manage_metadata
> Meta selects this automatically as a dependency of pages_messaging and
> pages_manage_engagement. Oneova doesn't use it on its own and doesn't change
> any Page settings.

*(Before submitting: if Page webhooks for comments and messages get built,
replace this with how they use it; otherwise ask Meta in the submission notes
whether it can be dropped.)*

### instagram_basic
> Creators connect the Instagram professional account linked to their Page.
> We read the account's username, profile picture, follower count and recent
> media so Oneova can show them on the Social Hub dashboard and in the Ova
> assistant ("show my Instagram posts").

### instagram_content_publish
> From Oneova Studio a creator can choose "Publish → Instagram Reels". Oneova
> uploads the finished video with the creator's caption to their own connected
> Instagram professional account. It is published only when the creator taps
> Post and confirms.

### instagram_manage_comments
> Oneova lists the comments on the creator's Instagram posts (Social Hub →
> Comments, Ova: "show Instagram comments") and lets the creator reply,
> hide or delete a comment on their own media after confirming in the app.

*(Don't request `instagram_manage_insights` or any `whatsapp_*` permission in
this round; Oneova doesn't use them yet.)*

---

## 4. Test instructions for the reviewer

Paste into **App Review → Requests → Testing instructions**:

```
1. Install the Android build from [[link to internal test / APK]].
2. Sign in with the Oneova test account:
   phone or email: [[test account login]]  (password / code: [[given in the secure field]])
3. Tap "Me" (bottom right) → Social Hub → Connect → Facebook.
4. Log in with your Facebook test user and allow the requested permissions.
   Choose the test Page "[[Test Page name]]" and tap Connect.
5. Page info and posts: Social Hub shows the Page, followers and recent posts.
   (pages_show_list, pages_read_engagement)
6. Comments: open Social Hub → Comments, or tap the Ova button and type
   "show my facebook comments". Tap Reply on a comment, type a reply, then
   press and hold "Hold to Reply" on the confirmation card.
   (pages_read_user_content, pages_manage_engagement)
7. Messages: send a Messenger message to the test Page from another account.
   In Oneova type "show my facebook messages" to Ova, tap Reply, confirm.
   (pages_messaging)
8. Publish: Studio (+) → pick or record a short video → Publish → Facebook Page
   → Post → hold to confirm. The post appears on the Page. (pages_manage_posts)
9. Instagram: Social Hub → Connect → Instagram, choose the Page with the linked
   Instagram professional account. Repeat steps 5–8 with Instagram.
   (instagram_basic, instagram_manage_comments, instagram_content_publish)
10. Disconnect / data deletion: Social Hub → Facebook → Disconnect, or remove
    Oneova in Facebook Settings → Apps and websites (deauthorize callback).
```

Give Meta a **test Oneova account**. Create it yourself and type its login only
into Meta's secure "test credentials" field, never in this file.

---

## 5. Screencasts (one per permission, 1–3 minutes each)

Record on the phone (Android screen recorder), English UI, captions on:

1. **Connect**: Me → Social Hub → Connect → Facebook → Facebook login →
   permission screen (pause so the permissions are readable) → choose Page →
   Connected. Covers pages_show_list.
2. **Page data**: dashboard with followers, posts, likes and comments; then
   the Ova "show my Facebook page" card. Covers pages_read_engagement.
3. **Comments + reply**: list comments → Reply → confirmation card → hold →
   open the Page in a browser and show the reply. Covers pages_read_user_content
   and pages_manage_engagement.
4. **Messenger**: message the Page from another account → Ova shows it →
   reply → confirm → show it arrived in Messenger. Covers pages_messaging.
5. **Publish**: Studio → Publish → Facebook → hold to post → show the post on
   the Page. Covers pages_manage_posts.
6. **Instagram**: connect, show media and comments, reply, publish a Reel.
   Covers instagram_basic, instagram_manage_comments, instagram_content_publish.

---

## 6. WhatsApp (later)

Oneova doesn't send WhatsApp Business messages through Meta's Cloud API yet
(the in-app WhatsApp connector is a placeholder). Ova uses WhatsApp only on
the phone itself (notifications, opening a chat). Requesting
`whatsapp_business_messaging` now would be rejected. When the Cloud API
integration exists it needs a Business portfolio, a verified phone number
and Embedded Signup.

---

## 7. Business verification & data handling (you do these)

- **Business verification** (Settings → Basic → Verification): legal business
  name, address, phone and a document such as a certificate of incorporation or
  utility bill. Only you can upload these.
- **Data handling questions**:
  - Data processors: Google Cloud / Firebase (hosting, database, functions).
  - Responsible entity: [[Oneova Technologies legal name]], [[country]].
  - Public-authority requests: "We review each request for legal validity and
    only disclose the minimum required; we have not received any."
- **Data Use Checkup**: answer yearly, confirming each permission is still used
  as described above.

---

## 8. Before you submit: checklist

- [ ] `GMAIL_USER` and `GMAIL_APP_PASSWORD` secrets set, so the Cloud Functions
      deploy (metaExchangeCode, metaDataDeletion, metaDeauthorize, metaDeletionStatus).
- [ ] Hosting deployed (serves `/meta-callback`, `/privacy`, `/terms`, `/deletion`).
- [ ] Reset the app secret in **Settings → Basic → App secret → Reset**, then:
      `firebase functions:secrets:set META_APP_SECRET --project mpepe-2b4bd`.
      (The old secret was inside every APK built before this change.)
- [ ] `/deletion` page: it describes an in-app "Delete Account & Purge Media"
      button that doesn't exist yet. Build it, or change the page to the email
      method, before reviewers read it.
- [ ] Test Facebook user + test Page with an Instagram professional account.
- [ ] Screencasts recorded; test account ready.
