# INBOX 2.0: RISK REGISTER

| Risk ID | Domain | Description | Impact | Likelihood | Mitigation |
|---|---|---|---|---|---|
| R-01 | UI/Layout | Replacing `InboxDashboardScreen` breaks desktop view. | High | High | Keep dashboard for wide screens, introduce `InboxMobileScreen` for constrained widths. |
| R-02 | Performance | Client-side aggregation of 5 streams causes UI stutter. | High | High | Implement lazy loading/pagination. Offload counting to server-side aggregations. |
| R-03 | Database | Adding new filters (Priority, Assigned) requires complex Firestore indexes which fail at runtime. | Medium | Medium | Generate and deploy `firestore.indexes.json` early. |
| R-04 | UX | Capabilities are mismatched; UI shows "Reply" for a platform that doesn't support it. | High | Low | Enforce strict capability checks (`requireCapability`) at the UI builder level. |
| R-05 | Integrity | Duplicate webhooks cause duplicate messages in chat view. | Critical | Medium | Introduce idempotency keys (externalMessageId) in Firestore rules or Cloud Functions. |
| R-06 | Security | Users bypass UI capability limits to send messages on restricted channels via API. | Critical | Low | Validate capabilities server-side before processing send requests. |
