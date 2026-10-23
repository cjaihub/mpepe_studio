# PHASE 8: UPLOAD SECURITY

## Audit of `requestSecureAttachmentUpload`
The Phase 7.5 endpoint provides a secure, predictable namespace mechanism.

## Security Contract
- **Authentication:** Cannot request URL without valid `request.auth`.
- **Namespace Ownership:** The generated upload target string is strictly constrained to `attachments/{userId}/{uuid}_{filename}`.
- **Payload Limits:** Before returning an authorization path, the function enforces a hard maximum of 50MB against `fileSize`.
- **Storage Rules:** Assuming Firebase Storage rules are locked down to `match /attachments/{userId}/{file} { allow write: if request.auth.uid == userId; }`, it is impossible for User A to upload a payload directly into User B's object namespace.

## No Long-Lived Client Access
Clients do NOT receive service-account keys or unrestricted bucket write tokens. They receive a dynamically generated upload namespace path and must conform to the Firebase SDK identity requirements.
