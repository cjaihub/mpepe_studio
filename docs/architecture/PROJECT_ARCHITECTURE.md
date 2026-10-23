# MPEPE STUDIO Architecture

**Stack**: Flutter (Frontend), Dart (Logic), Firebase (Backend/Auth/Firestore), Riverpod (State Management).

## Core Principles
1. **Unidirectional Data Flow**: Services mutate state in Firebase. Riverpod Notifiers listen to Firestore streams or internal events and rebuild the UI.
2. **Modular Architecture**:
   - `lib/backend/`: Pure business logic, API integrations, and database schemas.
   - `lib/shared/`: Reusable components (e.g., `AppModals`), theme constants, and layouts.
   - `lib/settings/`, `lib/social_hub/`, etc.: Feature-specific UI layers.
3. **Decoupled AI**: The AI (Gemini/Background Agents) acts as a strictly permissioned client. It does not possess root privileges and must route through the `AiSecurityGateway`.
