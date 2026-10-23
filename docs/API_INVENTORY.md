# MPEPE STUDIO API Inventory (v1)

*Status: ACTIVE*  
*Compliance: OWASP API Security Top 10 (API9:2023 Improper Inventory Management)*

This document maintains the canonical inventory of all backend API endpoints (Cloud Functions / REST) for MPEPE STUDIO. It ensures strict versioning, deprecation tracking, and consistent schema definitions.

## Global Conventions

All APIs under `/api/v1/` adhere to the following standards:
- **Authentication**: Required on all endpoints unless marked `[PUBLIC]`. Uses Firebase Auth Bearer tokens.
- **Errors**: Consistent JSON response: `{ "error": { "code": 400, "message": "...", "details": {} } }`
- **Pagination**: Cursor-based using `pageToken` and `limit`. Responses include `nextPageToken`.
- **Idempotency**: All `POST`, `PUT`, and `DELETE` requests must include an `Idempotency-Key` header.
- **Audit**: High-sensitivity routes are marked `[AUDIT_REQUIRED]`, meaning events are logged to the `ai_audit_logs` or system logs.

---

## 1. Authentication (`/api/v1/auth`)

### `POST /api/v1/auth/revoke-sessions`
- **Description**: Revokes all active sessions for the user globally.
- **Auth Requirement**: Bearer Token
- **Authorization**: Must be self (UID match).
- **Request Schema**: `{}`
- **Response Schema**: `{ "success": true }`
- **Errors**: `401 Unauthorized`, `500 Internal Server Error`
- **Rate Limit**: 1 request per minute.
- **Idempotency**: Required.
- **Audit**: `[AUDIT_REQUIRED]`

---

## 2. Users & Profiles (`/api/v1/profiles`)

### `GET /api/v1/profiles/{userId}`
- **Description**: Fetches user profile data, applying visibility ACLs.
- **Auth Requirement**: Bearer Token
- **Authorization**: Public, Connected, or Trusted based on viewer relationship.
- **Request Schema**: `{}`
- **Response Schema**: `{ "id": "...", "displayName": "...", "username": "..." }` (Fields stripped based on ACL).
- **Errors**: `404 Not Found`, `403 Forbidden` (if totally blocked).
- **Rate Limit**: 60 requests per minute.
- **Pagination**: None.

---

## 3. Messaging & Conversations (`/api/v1/messages`)

### `POST /api/v1/messages/send`
- **Description**: Dispatches a new message.
- **Auth Requirement**: Bearer Token
- **Authorization**: Sender must be a participant in the target conversation.
- **Request Schema**: `{ "conversationId": "str", "text": "str", "attachments": [...] }`
- **Response Schema**: `{ "messageId": "str", "timestamp": 123456789 }`
- **Errors**: `403 Forbidden` (not participant), `413 Payload Too Large`
- **Rate Limit**: 30 requests per minute.
- **Idempotency**: Required.

---

## 4. Search (`/api/v1/search`)

### `POST /api/v1/search/query`
- **Description**: Global production search across permitted entities.
- **Auth Requirement**: Bearer Token
- **Authorization**: Restricted by `allowedViewers` array (ACL).
- **Request Schema**: `{ "query": "str", "targetEntities": ["message", "person"], "filter": { "exactMatch": bool }, "pageToken": "str", "limit": 20 }`
- **Response Schema**: `{ "results": [...], "nextPageToken": "str", "totalEstimatedHits": int }`
- **Errors**: `400 Bad Request` (invalid filter).
- **Rate Limit**: 20 requests per minute.
- **Pagination**: Cursor-based.

---

## 5. Automation & AI (`/api/v1/automation`)

### `POST /api/v1/automation/trigger`
- **Description**: Manually triggers or registers a workflow automation.
- **Auth Requirement**: Bearer Token
- **Authorization**: Must own the workflow.
- **Request Schema**: `{ "workflowId": "str", "payload": {} }`
- **Response Schema**: `{ "executionId": "str", "status": "pending" }`
- **Errors**: `429 Too Many Requests` (loop/rate limit breached).
- **Rate Limit**: 100 requests per minute (per workflow).
- **Idempotency**: Required (`Idempotency-Key` checked in cache).
- **Audit**: `[AUDIT_REQUIRED]`

### `PUT /api/v1/ai/auto-mode`
- **Description**: Updates the autonomous capability level of the local AI agent.
- **Auth Requirement**: Bearer Token
- **Authorization**: Self (UID match).
- **Request Schema**: `{ "mode": "suggestionsOnly | drafts | autoApprove | fullAuto" }`
- **Response Schema**: `{ "success": true, "updatedMode": "str" }`
- **Errors**: `400 Bad Request`
- **Rate Limit**: 5 requests per minute.
- **Audit**: `[AUDIT_REQUIRED]`

---

## 6. Settings & Data Export (`/api/v1/settings`)

### `POST /api/v1/settings/export`
- **Description**: Queues a job to zip and email all user data.
- **Auth Requirement**: Bearer Token
- **Authorization**: Self.
- **Request Schema**: `{}`
- **Response Schema**: `{ "jobId": "str", "status": "queued" }`
- **Rate Limit**: 1 request per day.
- **Audit**: `[AUDIT_REQUIRED]`

### `DELETE /api/v1/settings/account`
- **Description**: Submits an irreversible account deletion request.
- **Auth Requirement**: Bearer Token (requires recent auth).
- **Authorization**: Self.
- **Request Schema**: `{ "confirmationWord": "CONFIRM" }`
- **Response Schema**: `{ "success": true }`
- **Idempotency**: Required.
- **Audit**: `[AUDIT_REQUIRED]`

---

## Deprecated Endpoints (API Inventory Tracking)

*No endpoints are currently deprecated in v1. When endpoints are superseded by v2, they will be listed here with sunset dates to fulfill OWASP API inventory security requirements.*
