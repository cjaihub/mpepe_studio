# Oneova Canonical API (v1)

*Auto-generated from `lib/backend/api/mpepe_api.dart`*

## Standard Error Structure
All endpoints return standard HTTP status codes. In the event of an error, the body will match the `StandardApiError` interface:
```json
{
  "code": "BAD_REQUEST",
  "message": "Missing required fields",
  "details": {}
}
```

---

## Domain: Content & Videos

### `POST /v1/videos`
Creates a new video asset entry after media processing is complete.

*   **Authentication**: Required
*   **Authorization**: `creator`
*   **Validation**: Video payload must contain valid mediaId and title
*   **Rate Limit**: 10 requests per minute
*   **Pagination**: false
*   **Idempotency**: false
*   **Audit Behavior**: Logs upload initiation to `audit_log` table

### `GET /v1/videos`
Retrieves a paginated list of videos.

*   **Authentication**: Required
*   **Authorization**: `user`
*   **Validation**: cursor must be valid string if provided
*   **Rate Limit**: 100 requests per minute
*   **Pagination**: true (Requires `cursor` string)
*   **Idempotency**: true
*   **Audit Behavior**: None

---

## Domain: Moderation

### `POST /v1/moderation/report`
Files a trust & safety ticket against a user, post, or comment.

*   **Authentication**: Required
*   **Authorization**: `user`
*   **Validation**: Must provide targetId, targetType, and categories
*   **Rate Limit**: 5 requests per minute
*   **Pagination**: false
*   **Idempotency**: true
*   **Audit Behavior**: Logs reporting event for trust & safety tracking

---

## Domain: Messages

### `POST /v1/messages/send`
Sends a message or E2EE encrypted payload to a chat session.

*   **Authentication**: Required
*   **Authorization**: `user`
*   **Validation**: Message must not exceed 2000 chars. E2EE payload must be base64.
*   **Rate Limit**: 60 requests per minute
*   **Pagination**: false
*   **Idempotency**: true (Requires client-generated `messageId`)
*   **Audit Behavior**: Message metadata logged. E2EE payload strictly not logged.

---
*Note: Domains (Users, Profiles, Relationships, Stories, Live, Monetization, Privacy, AI, etc.) follow this exact annotation and enforcement structure within the `MpepeApi` singleton.*
