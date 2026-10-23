# Login hardening — for your approval

Status: **proposal only.** Nothing below is deployed, and `firestore.rules` is unchanged.

Today the two-step check runs only inside the app. Someone with a modified app could skip it. This proposal moves the final decision to the server in three parts:

1. **A Cloud Function** decides whether a sign-in passed two checks. It then marks that one session as verified.
2. **Firestore rules** accept writes and private reads only from marked sessions. They also close a few holes found in the audit.
3. **App Check** makes sure requests come from the real Oneova app on a real phone.

---

## 1. Cloud Function — `functions/src/session_gate.ts` (written, compiles, not exported)

| Function | What it does |
|---|---|
| `recordSignInCheck({deviceId})` | Called after each step. It reads the step from the person's fresh sign-in token, so the app cannot fake it. The step can be: text code, password, Google/Facebook, or the fingerprint key. A text-code step also marks the phone as known; only the server can write that. |
| `confirmSignInChecks({deviceId})` | Applies the same policy as the app: a new phone needs a text code, every sign-in needs 2 different checks, and one of them must be a password, Google/Facebook, or the fingerprint key. If the checks pass, it adds this session to the `mfaSessions` claim (the last 5 sessions are kept, so up to 5 phones). It then deletes any old password hash from the profile and logs a `security_events` entry. |
| `revokeTrustedDevice({deviceId})` | "Sign out this phone": forgets the phone, clears the marks and ends all sessions. |
| `lookupAccountByPhone({phone})` | The login screen calls this to show the person's photo, name and @username. It replaces the app reading phone numbers straight from public profiles. |
| `scrubLegacyPasswordHashes()` | Admin only, run once. It removes the old password hashes from every profile. Today those hashes are readable by anyone. |

All of these except the one-off cleanup require App Check (`enforceAppCheck: true`).

**To deploy after you approve:** add `export * from './session_gate';` to `functions/src/index.ts`, then run:

```bash
cd functions && npm run build && firebase deploy --only functions:recordSignInCheck,functions:confirmSignInChecks,functions:revokeTrustedDevice,functions:lookupAccountByPhone,functions:scrubLegacyPasswordHashes
```

---

## 2. Firestore rules — exact changes to `firestore.rules`

### 2a. New helper; `isOwner` now requires a verified session

```diff
     function isSignedIn() {
       return request.auth != null;
     }
 
+    // This sign-in passed the server two-check gate (functions/src/session_gate.ts).
+    // A new sign-in has a new auth_time, so it is blocked until it passes again.
+    function isVerifiedSession() {
+      return isSignedIn() &&
+             request.auth.token.firebase.sign_in_provider != 'anonymous' &&
+             request.auth.token.get('mfaSessions', []).hasAny([request.auth.token.auth_time]);
+    }
+
     function isOwner(uid) {
-      return isSignedIn() && request.auth.uid == uid;
+      return isVerifiedSession() && request.auth.uid == uid;
     }
```

### 2b. Every write that uses `isSignedIn() && !isSuspended()` (35 places)

```diff
-      allow create: if isSignedIn() && !isSuspended() && ...
+      allow create: if isVerifiedSession() && !isSuspended() && ...
```

This is the same mechanical swap in each of the 35 places. Guests and half-signed-in sessions can still **read** public content, but they cannot post, comment, like, follow or message.

### 2c. `users/{uid}`: stop self-promotion and password material

Today any user can set their own `role: 'admin'`, and `isAdmin()` trusts that field. Any user can also set someone's follower count to any number.

```diff
     match /users/{uid} {
       allow read: if true;
-      allow write: if isOwner(uid) || isAdmin();
-      // Follow / unfollow bumps the other user's follower counters.
-      allow update: if isSignedIn() && !isSuspended() &&
-                       onlyChanges(['followers', 'following', 'followersCount', 'followingCount', 'likeCount']);
+      allow create: if isOwner(uid) &&
+                       request.resource.data.get('role', 'creator') in ['creator', 'business'] &&
+                       request.resource.data.get('status', 'active') == 'active' &&
+                       request.resource.data.get('isVerified', false) == false &&
+                       !request.resource.data.keys().hasAny(['passwordHash', 'password', 'verifiedBadge']);
+      allow update: if (isOwner(uid) &&
+                        !request.resource.data.diff(resource.data).affectedKeys().hasAny(
+                          ['role', 'status', 'isVerified', 'verifiedBadge', 'passwordHash', 'password',
+                           'followers', 'following', 'followersCount', 'followingCount'])) ||
+                       isAdmin();
+      allow delete: if isAdmin();
+      // Follow / unfollow: each counter moves by exactly one.
+      allow update: if isVerifiedSession() && !isSuspended() &&
+                       onlyChanges(['followers', 'following']) &&
+                       math.abs(request.resource.data.get('followers', 0) - resource.data.get('followers', 0)) <= 1 &&
+                       math.abs(request.resource.data.get('following', 0) - resource.data.get('following', 0)) <= 1;
```

### 2d. Known phones and the security log: only the server writes them

The login screen must still read them before the gate passes.

```diff
-      // Other user subcollections (settings, private data, etc.)
-      match /{document=**} {
-        allow read, write: if isOwner(uid) || isAdmin();
-      }
+      match /trusted_devices/{deviceId} {
+        allow read: if isSignedIn() && request.auth.uid == uid;
+        allow write: if false; // session_gate.ts only
+      }
+      match /security_events/{eventId} {
+        allow read: if isSignedIn() && request.auth.uid == uid;
+        allow write: if false; // session_gate.ts only
+      }
+      // Other user subcollections (settings, private data, etc.)
+      match /{sub}/{rest=**} {
+        allow read, write: if (isOwner(uid) || isAdmin()) &&
+                              !(sub in ['trusted_devices', 'security_events']);
+      }
```

`auth_checks/*` and `biometric_keys/*` are already covered by the deny-everything rule at the bottom.

### 2e. Later (phase 2, not part of this approval)

Profiles still show `phoneNumber` publicly. Once the login screen uses `lookupAccountByPhone`, move phone numbers to `users/{uid}/private/contact` and drop `phoneNumber` from public profiles.

---

## 3. App changes I'll make after you approve (before deploying the rules)

- `LoginSecurity`:
  - call `recordSignInCheck` after each server-checked step (password, text code, Google/Facebook, fingerprint key);
  - make `markVerified` call `confirmSignInChecks` and then refresh the token;
  - stop writing `trusted_devices` and `security_events` from the phone.
- Login screen:
  - find accounts with `lookupAccountByPhone`;
  - save a new user's profile after the confirm step;
  - drop the in-app hash clean-up (the server does it).
- Signup wizard and the login screen's "new account" step: stop writing `isVerified` / `verifiedBadge`, which the new create rule refuses. Badges should be granted by an admin or the server.
- Profile numbers: drop the "fix my own counters" write (2c blocks it); counts still come live from count queries.
- A reopened app on a known phone keeps working: its session was already marked when it first passed.

---

## 4. App Check — console steps (done by you, or by me with your OK)

The app already turns App Check on (`FirebaseService.activateAppCheck`): Play Integrity in release builds, a debug provider in debug builds, DeviceCheck on iOS.

1. **Firebase console → App Check → Apps → Android `com.oneova.app` → Play Integrity → Register.**
   - Paste the **SHA-256 of the signing key**. If you use Play App Signing, it's in Play Console → Setup → App integrity. Otherwise run `keytool -list -v -keystore <release.jks>`.
   - Also link the Google Cloud project in Play Console → App integrity → Play Integrity API.
2. **Debug token for your TECNO:**
   - run a **debug** build and look in logcat for `DebugAppCheckProvider ... Enter this debug secret into the allow list`;
   - add that secret under App Check → Apps → ⋮ → **Manage debug tokens**.
3. **iOS:** the bundle ID is still `com.example.mpepeStudio`. Fix it first, then register App Attest (preferred) or DeviceCheck.
4. **Watch for ~1 week:** App Check → APIs → Cloud Firestore / Storage / Cloud Functions / Authentication. Wait until "Verified requests" is close to 100% from the current app version.
5. **Enforce:** press **Enforce** for Cloud Firestore, Cloud Storage and Authentication. Cloud Functions are enforced in code (`enforceAppCheck: true`).

   ⚠️ After this, older app versions and sideloaded or modified builds stop working.

### Also in the console (Authentication → Settings), small and safe

- **SMS region policy:** allow only the countries you serve, for example Kenya. This blocks SMS-pumping fraud that burns your SMS bill.
- **Password policy:** minimum 8 characters, enforced by the server. The app already asks for 8.
- **Email enumeration protection:** already on. I checked; leave it.

---

## 5. Safe rollout order (so nobody gets locked out)

1. Deploy the functions. This blocks nothing yet.
2. Release the app update from §3. Sessions get marked as people sign in.
3. Run `scrubLegacyPasswordHashes` once. Old accounts then set a new password after their text code; the app already handles this.
4. Deploy the rules from §2 (`firebase deploy --only firestore:rules`). Anyone on an old app version or an unmarked session is sent back to the "one more step" screen.
5. Turn on App Check enforcement (§4.5).

**Rollback:** redeploy the previous `firestore.rules` from git (`git show HEAD:firestore.rules`). The claims are harmless if left in place.

---

## Approve with one line each

- [ ] Deploy the functions in §1
- [ ] Make the app changes in §3
- [ ] Deploy the rules in §2 (after the app update is out)
- [ ] Run the one-time hash clean-up
- [ ] App Check: register (§4.1–4.3) / enforce (§4.5) — you do it, or tell me to
- [ ] SMS region policy + password policy
