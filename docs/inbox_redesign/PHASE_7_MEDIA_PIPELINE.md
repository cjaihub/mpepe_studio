# PHASE 7: MEDIA / ATTACHMENT PIPELINE

## Architecture
The media pipeline has been structured into a real production architecture to handle large files securely and efficiently.

1. **Pick & Validate:** Mobile user selects a file using standard pickers. Validation checks MIME type and limits (e.g., 50MB max for video) locally.
2. **Secure Upload Preparation:**
   `ControlPlaneService.requestSecureUploadUrl` makes a backend call to generate a signed URL or dedicated token to avoid exposing global storage bucket permissions.
3. **Storage:** The file is pushed directly to Cloud Storage.
4. **Canonical Attachment Reference:** The local state binds an `Attachment` object pointing to the final GS bucket URI.
5. **Provider Send:** The `clientCommandId` carries the attachment manifest to the backend, which proxies the blob securely via the provider API endpoints.

## Attachment States
`AttachmentModel` tracks statuses including:
`VALIDATING`, `UPLOADING`, `UPLOADED`, `SENDING`, `SENT`, `FAILED`

## Security Optimization
Client MIME types are treated as suggestions. Final typing and validation (including optional virus scanning) run server-side via storage triggers before authorizing the file dispatch to a provider.
