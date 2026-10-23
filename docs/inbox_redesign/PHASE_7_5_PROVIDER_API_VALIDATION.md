# PHASE 7.5: PROVIDER API VALIDATION

## Official API Integration References

### WhatsApp Cloud API (Meta)
- **API Version:** Graph API v19.0+
- **Official Documentation:** [WhatsApp Business Platform - Cloud API](https://developers.facebook.com/docs/whatsapp/cloud-api)
- **Required Scopes:** `whatsapp_business_messaging`
- **Media Limitations:** Images (5MB), Video (16MB), Audio (16MB).
- **Webhook Requirements:** SHA256 HMAC verification via `X-Hub-Signature-256`.
- **Known Restrictions:** 24-hour customer service window for free-form responses. Marketing messages require pre-approved templates.

### Instagram Graph API (Meta)
- **API Version:** Graph API v19.0+
- **Official Documentation:** [Instagram Messaging API](https://developers.facebook.com/docs/messenger-platform/instagram)
- **Required Scopes:** `instagram_manage_messages`, `instagram_basic`
- **Media Limitations:** Images (8MB JPEG), Video (25MB).
- **Webhook Requirements:** SHA256 HMAC verification.
- **Known Restrictions:** 7-day message send window from last user interaction.

### TikTok Marketing API / TikTok Shop (Future)
- **API Version:** TikTok API v1.3
- **Required Scopes:** Not yet finalized (Pending official SDK release for Unified DM access).
- **Status:** Messaging endpoints are heavily restricted and mostly scoped to TikTok Shop/Customer Support.

### YouTube (Google)
- **Status:** Does not support private unified messaging. Supports comments and community posts, which do not map 1:1 with the Inbox Canonical Message schema.

**All capabilities outside of WhatsApp and Instagram Direct are explicitly UNVERIFIED or NOT APPLICABLE.**
