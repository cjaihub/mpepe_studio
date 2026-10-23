# Security Inventory

## Authentication & Sessions
- Requires robust authentication for virtually all routes via `_requireAuth` interceptor in GoRouter.
- Session timeout policy enforced: the application forces re-authentication (`/auth/main_login`) if resumed after 5 minutes of inactivity (`main.dart`).
- Supports workspace locking and explicit linked device management.

## Authorization & API Security
- Follows OWASP API Top 10 guidance by validating user permissions on the backend before data operations.
- `AiSecurityGateway` enforces structural schema validation and business logic access control before any AI tool call is executed.
- App Check is enforced during application initialization (`FirebaseService.activateAppCheck()`).

## Privacy & Data Governance
- Dedicated privacy models (`privacy_enums.dart`) structure data visibility.
- Conversations support specific security settings (`conversation_security_settings.dart`).

## Vulnerability Prevention
- Hardened database rules (enforced at Firestore layer).
- No direct exposure of environment variables or API keys in the client without proxying or remote config validation.
