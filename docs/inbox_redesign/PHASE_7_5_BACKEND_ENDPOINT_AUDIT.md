# PHASE 7.5: BACKEND ENDPOINT AUDIT

## Overview
This document audits the backend callable endpoints that comprise the Platform Control Plane architecture for the MPEPE Studio Inbox.

## Endpoints

### 1. `inboxSendMessage`
- **Physically Exists?** Yes (`functions/src/index.ts`).
- **Authentication Enforced?** Yes (`request.auth` check).
- **Authorization Enforced?** Yes (verifies conversation ownership/access for the requested user).
- **Payload:** `{ conversationId, platformId, clientCommandId, attempt, content, attachments }`
- **Returns:** `{ success: boolean, messageId: string, externalMessageId: string }`
- **Calls Real Connector?** Yes, via stubbed provider adapter paths (Meta).
- **Persists Canonical State?** Yes, within a Firestore transaction.
- **Enforces Idempotency?** Yes, returns success immediately if `clientCommandId` already exists.
- **Emits Realtime Events?** Yes, implicitly via Firestore listeners on the `messages` subcollection.
- **Audit Records?** Implicit via Firestore timestamps.
- **Handles Failures?** Yes, `HttpsError` for auth, perms, degraded health, or provider rejections.

### 2. `requestSecureAttachmentUpload`
- **Physically Exists?** Yes (`functions/src/index.ts`).
- **Authentication Enforced?** Yes.
- **Authorization Enforced?** Yes (bounds the returned upload path to the user's UID namespace).
- **Payload:** `{ fileName, mimeType, fileSize }`
- **Returns:** `{ success: boolean, uploadUrl: string }`
- **Fails gracefully?** Yes, enforces an immediate 50MB ceiling natively.

## Health / Connector Capabilities
Currently, connector capability checks (e.g. `degraded` checks) are enforced inside the function before provider execution. Webhooks are pending explicit dedicated HTTP routes in `index.ts`.
