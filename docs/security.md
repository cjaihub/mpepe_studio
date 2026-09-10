# Security Guidelines

## Firebase Authentication
MPEPE STUDIO utilizes Firebase Authentication to securely manage user identities.

## Developer Bypass Note
In `lib/auth/auth_repository.dart`, there is a developer bypass method (`devBypassLogin`) which provides a fast-track login flow during local development, primarily on Desktop/Windows environments. 
- **CRITICAL**: This bypass is strictly disabled in production builds via `kReleaseMode` checks. Do not modify or remove this guard.

## Firestore Rules
Data isolation is essential.
- Users can only read and write data associated with their own `uid`.
- Sensitive operations (such as role modifications and admin approvals) are restricted by checking user roles and statuses.
- Roles (`Admin`, `Manager`, `Client`, `Employee`) dictate visibility across the CRM dashboard.

## Third-Party Connects
The Social Hub never asks for passwords directly. It delegates to the official platform OAuth flows to generate and store tokens securely.
