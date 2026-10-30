# ONEOVA COMPANY INFORMATION SECURITY, SOURCE CODE & DATA GOVERNANCE POLICY

**Document ID:** `ONV-SEC-GOV-2026-V1`  
**Classification:** **CONFIDENTIAL — INTERNAL MANDATORY GOVERNANCE STANDARD**  
**Effective Date:** October 25, 2026  
**Policy Owner:** Chief Security Officer & Data Protection Officer (`security@oneova.app` · `dpo@oneova.app`)  
**Applies To:** All Founders, Executives, Employees, Engineers, Trust & Safety Moderators, Contractors, Agencies, Advisors, and Autonomous AI Coding Agents of **Oneova Technologies Inc.**

---

> **Executive Mandate ("In Short"):**  
> Oneova's competitive advantage and public trust rest on two pillars: **(1) our proprietary software, GLSL Studio shaders, AI pipelines, and cloud infrastructure**, and **(2) the personal data and financial balances of millions of African and global users**.  
> Every person and AI agent working on Oneova is legally and contractually bound by this Policy. Violating Tier 0 or Tier 1 rules—especially leaking source code/keys or snooping on user accounts—triggers **immediate revocation of access, termination for cause, and civil/criminal enforcement**.

---

## 1. Corporate Asset & Data Classification Standard

All code, credentials, databases, media, and business records at Oneova are governed by five strict security tiers. **Where classification is uncertain, apply the higher protection tier.**

| Tier | Classification | Covered Assets at Oneova | Authorized Access | Mandatory Storage & Transmission Control |
|---|---|---|---|---|
| **Tier 0** | **Crown Jewels (Critical Secrets)** | Cloud/Firebase Admin service-account private keys, Flutterwave / Stripe / Safaricom Daraja / MTN MoMo API secrets & webhook keys, LiveKit server keys, Android upload keystores (`.jks`), Apple `.p12`/provisioning certificates, DNS/Registrar root credentials | Named Principal Infrastructure Custodians only (Dual-Control / 2-Person Rule) | **Google Cloud Secret Manager or Hardware HSM ONLY.** Strictly forbidden in Git, `.env` commits, mobile binaries, Slack/WhatsApp/Email, or AI prompts. |
| **Tier 1** | **Restricted User PII & Financial Ledgers** | User phone numbers, email addresses, private Chat messages, voice/video calls, KYC identity documents, unpublished Studio drafts, Wallet/Coins double-entry ledgers, CSAM/safety forensic vault | Automated backend microservices; human access **strictly via logged Break-Glass ticket** | Encrypted production Firestore/Cloud Storage with strict `users/{uid}` tenant isolation. **Zero local CSV, SQL, or JSON exports on employee laptops.** |
| **Tier 2** | **Confidential Company IP** | Oneova Flutter & backend source code, custom GLSL Look shaders, `.oneovapack` binary specs, AI Skills prompts & weights, feed ranking logic, product roadmaps, financials, investor & cap-table docs | Active personnel who have signed the **Oneova NDA & IP Assignment Agreement**, scoped by least privilege | Company-owned private Git repositories with branch protection & hardware MFA. Never copy to personal GitHub, public gists, USB drives, or personal cloud folders. |
| **Tier 3** | **Internal Operational** | Engineering runbooks, QA checklists, sprint boards, aggregated non-PII analytics | Authenticated Oneova staff & approved contractors | Corporate workspace protected by SSO + MFA. |
| **Tier 4** | **Public** | Published public Reels/Biz listings, `https://oneova.app` legal policies, approved press & app-store assets | General public | Approved release pipelines only. |

---

## 2. Source Code, Shaders & Intellectual Property Protection

**2.1 Pre-Access Legal Gate.** Zero access to GitHub, Firebase, Google Cloud, Figma, LiveKit, or internal workspaces may be provisioned until HR/Legal confirms a countersigned **[Oneova NDA & Proprietary Invention Assignment Agreement](ONEOVA_NDA_AND_IP_ASSIGNMENT.md)** (`ONV-LEGAL-NDA-PIIA-2026-V1`) and verified government ID on file.

**2.2 Repository Ownership & Branch Protection.**
- All repositories belong exclusively to **Oneova Technologies Inc.** Hosting company code in personal developer accounts is prohibited.
- `main`, `production`, and `release/*` branches enforce: (a) zero direct pushes or force-pushes, (b) mandatory pull-request review, (c) automated `flutter analyze` and guard-test verification (`test/guards/home_lock_test.dart`), and (d) automated secret-scanning gates.

**2.3 Prohibition on Code Exfiltration.** Copying, mirroring, emailing, AirDropping, or syncing Oneova source code, GLSL shader graphs, AI system prompts, or architecture blueprints to personal laptops, personal Google Drive/iCloud/Dropbox, messaging apps, or external repositories is strictly prohibited.

**2.4 Open-Source License Firewall.**
- Only dependencies with permissive commercial-safe licenses (**MIT, Apache-2.0, BSD-2/3-Clause, ISC**) may be added to Oneova client or backend packages.
- **Strictly Prohibited Without Written Counsel Sign-Off:** Copy-left or source-available viral licenses (**AGPL, GPL, LGPL-static, SSPL, Commons Clause**) that could encumber Oneova's proprietary IP.

**2.5 Clean-Room Originality.** Personnel must never introduce proprietary source code, internal docs, or trade secrets belonging to any prior employer or third party into Oneova repositories.

---

## 3. Cloud Infrastructure, Secrets & Cryptographic Hygiene

**3.1 Client vs. Server Secret Separation.**
- Assume every distributed Android APK/AAB, iOS IPA, and Web bundle is publicly inspectable via reverse engineering.
- Public Firebase client config files (`google-services.json` / `GoogleService-Info.plist`) must always be paired with **Firebase App Check** and hardened `firestore.rules` / `storage.rules`.
- **Server secrets** (payment-gateway secret keys, mobile-money B2C/C2B credentials, LiveKit room-admin tokens, LLM API keys, signing keys) must execute **exclusively inside Cloud Functions / Cloud Run** injected from Secret Manager at runtime.

**3.2 Environment Isolation (`dev` / `staging` / `prod`).**
- Engineers develop and run automated tests solely against isolated `dev` and `staging` projects.
- **Production user PII must never be cloned into `dev` or `staging`**, and synthetic/mock seed data must never be written to `prod`.

**3.3 Phishing-Resistant MFA (Passkeys / Hardware Keys).**
- Every account with access to GitHub, Google Cloud, Firebase, Apple Developer, Google Play Console, Cloudflare/DNS, Flutterwave, or Stripe **must** enforce FIDO2 Passkeys or hardware security keys (`WebAuthn`). SMS-based 2FA is prohibited on admin consoles to eliminate SIM-swap takeover risk.

**3.4 Key Rotation Cadence.** Tier 0 API keys and webhook signing secrets are rotated every **90 days** and **immediately** upon any suspected exposure or personnel offboarding.

---

## 4. Application, Database & Financial Ledger Security Rules

1. **Zero Client Trust:** Client payloads are untrusted. `firestore.rules` and `storage.rules` enforce strict `request.auth.uid == uid` ownership, explicit `hasOnly` field allowlists, schema/size validation, and `allowedViewers` ACL arrays.
2. **Immutable Server-Only Financial Ledgers:** Mobile/web clients have **zero write permission** (`allow write: if false;`) to Wallet balances, Coin ledgers, Creator earnings, payout records, verification badges, or strike counts. All monetary state transitions execute via idempotent, server-side **double-entry ledger transactions** verified against cryptographic payment-provider webhook signatures (HMAC-SHA256).
3. **AI Prompt-Injection Isolation:** Every untrusted user string, caption, comment, or external web snippet passed to internal or user-facing AI pipelines must pass through `AiSecurityGateway` delimiter isolation (`[START UNTRUSTED CONTENT]`) with strict tool-call schema validation.

---

## 5. Staff Access to User Data, Anti-Snooping & Anti-Bribery Law

> **ZERO-TOLERANCE RULE:** Accessing, searching, screenshotting, or sharing any user's private messages, phone number, location, KYC ID, unpublished drafts, or Wallet records without an assigned, legitimate ticket is a **terminable offense on first occurrence** and will be referred for prosecution under applicable computer-misuse and data-protection statutes.

**5.1 Zero Standing Access to Private Communications.** Engineers and moderators have no open query access to private Chat threads or unpublished drafts.

**5.2 PII Masking in Trust & Safety Consoles.** Moderation queues display only the reported artifact and minimal policy context; phone numbers, national IDs, and payout numbers are masked (`***`) by default.

**5.3 Audited Break-Glass Protocol.** Emergency production database inspection requires: (a) a valid incident/support ticket ID, (b) dual approval from an Infrastructure Lead, (c) automatic session expiry within **4 hours**, and (d) immutable Cloud Audit Logging.

**5.4 Anti-Bribery & Insider Threat Reporting.** Criminal syndicates actively target social-platform staff with cash or mobile-money bribes to unban scam accounts, grant blue badges, or leak creator phone numbers. Any approach must be reported within **1 hour** to `security@oneova.app`.

---

## 6. Autonomous AI Coding Agents & Third-Party Vendor Governance

1. **Repository Guardrails (`AGENTS.md`):** All AI coding assistants operating on Oneova code must comply with `AGENTS.md`, preserve locked routes and Oneova branding (`#0C4FA8` / `#FF2D87`), pass `flutter test test/guards/home_lock_test.dart` and `flutter analyze`, and never commit secrets or mock production stubs.
2. **Ban on Unvetted External AI Uploads:** Personnel must never paste Tier 0 secrets, Tier 1 user PII, or proprietary shader/algorithm modules into unapproved consumer AI websites that retain prompts for model training.
3. **Third-Party SDK Vetting:** No new third-party SDK may be added to `pubspec.yaml` or `package.json` without Security & Legal review of its data collection behavior (ensuring 100% accuracy of Apple Privacy Nutrition Labels and Google Play Data Safety disclosures) and a signed Vendor DPA.

---

## 7. Endpoint Security & 15-Minute Offboarding Protocol

### 7.1 Mandatory Endpoint Controls
- Full-disk encryption enabled (**FileVault** on macOS, **BitLocker** on Windows, **LUKS** on Linux);
- Automatic screen lock set to **≤ 5 minutes** requiring password/biometrics;
- OS, browser, and IDE security updates applied within **7 days** of release;
- Physical privacy discipline in co-working hubs, airports, and cafés; test devices wiped before disposal or transfer.

### 7.2 Mandatory 15-Minute Offboarding Checklist
Upon departure or contract completion of any team member, contractor, or moderator, Infrastructure + HR execute within **15 minutes**:
- [ ] Suspend corporate email/SSO and force-revoke all active OAuth/device tokens;
- [ ] Remove user from GitHub organization, revoke SSH keys and Personal Access Tokens;
- [ ] Revoke IAM roles across Google Cloud, Firebase, LiveKit, Flutterwave, Stripe, Apple Developer, and Google Play Console;
- [ ] Rotate any shared staging/webhook credentials touched during the engagement;
- [ ] Collect company hardware and obtain signed Certificate of Data & Code Destruction.

---

## 8. Security Incident & 72-Hour Data Breach Response Playbook

| Window | Mandatory Action | Owner |
|---|---|---|
| **0 – 15 Mins** | **Blameless Escalation:** Report suspected key leak, intrusion, vulnerability, or data exposure immediately to `security@oneova.app` & `dpo@oneova.app`. Concealing an incident is strictly prohibited. | Discovering Person |
| **15 – 60 Mins** | **Contain & Rotate:** Revoke compromised keys/sessions, isolate affected function/route, deploy emergency `firestore.rules` / WAF block, and snapshot forensic logs. | Security & Infra Lead |
| **1 – 24 Hours** | **Forensic Scope Assessment:** Identify affected collections, exact user count, countries impacted, and whether data was encrypted/tokenized. | Security + DPO |
| **≤ 72 Hours** | **Statutory & User Notification:** File formal notifications with applicable Data Protection Authorities within **72 hours** (or shorter national window, e.g., Rwanda NCSA, Kenya ODPC, Nigeria NDPC, SA Information Regulator, GDPR/ICO) and notify affected users clearly. | DPO + Legal Counsel |
| **≤ 7 Days** | **Root-Cause Remediation:** Complete written post-mortem and land permanent automated regression tests preventing recurrence. | Engineering Lead |

---

## 9. Personnel Compliance Acknowledgment (Sign-Off Record)

I acknowledge that I have read, understood, and agree to strictly abide by the **Oneova Company Information Security, Source Code & Data Governance Policy (`ONV-SEC-GOV-2026-V1`)**. I understand that unauthorized disclosure of Company IP/Secrets or unauthorized access to User Data may result in immediate termination and civil or criminal liability.

- **Full Legal Name:** `____________________________________________________`
- **Role / Department / Engagement:** `______________________________________`
- **Signature:** `____________________________________` · **Date:** `____ / ____ / 202__`

---
*© 2026 Oneova Technologies Inc. Confidential & Proprietary.*
