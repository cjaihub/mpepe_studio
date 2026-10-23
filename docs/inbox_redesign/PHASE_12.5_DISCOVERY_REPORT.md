# PHASE 12.5 DISCOVERY REPORT: Omni Command + Personal AI Integration

## 1. EXECUTIVE SUMMARY
This report details the discovery, research, and implementation plan for integrating the existing Phase 12 Omni Command backend and Personal AI logic directly into the real Inbox Dashboard UI. The analysis confirms that a solid, tested backend (Omni Command Service, Intent Engine, Tool Registry, Risk Engine) exists, successfully resolving intents and handling tool executions. The core objective is to expose this AI securely in the frontend without creating an embedded secondary app, ensuring natural language commands augment the real user flow across desktop and mobile.

## 2. CURRENT SYSTEM STATE
The MPEPE STUDIO application contains a mature `UnifiedInbox` and `OmniCommand` layer. The frontend (`InboxListPanel`, `ChatViewPanel`) currently acts as the user-facing presentation, and the AI backend is built on `flutter_riverpod` state management. The `OmniCommandButton` exists in the codebase and is instantiated in `InboxListPanel` and `OmniCommandSheet`. The foundational AI services (`OmniIntentEngine`, `OmniRiskEngine`, `OmniContextResolver`) are implemented and functioning.

## 3. PHASE 12 STATUS
Phase 12 (Omni Command architecture foundation) is complete and highly tested. The backend correctly registers tools, enforces context (`OmniContext`), maps user queries to intents (`OmniIntent`), and flags risks (`RiskLevel`).

## 4. GLOBAL TEST BASELINE
- **Flutter Test Suite:** Passed (`184+` backend integration tests confirmed passing).
- **Functions Build:** Passed (`tsc` succeeds).
- **Functions Tests:** Currently failing due to missing configuration (`Error: no test specified`). *Note: This represents a validation gap in the backend.*
- **Static Analysis:** `flutter analyze` reported 516 minor issues (mostly deprecations and unused variables), but no critical blockers.

## 5. REPOSITORY ARCHITECTURE MAP
- **AI Core:** `/lib/backend/ai_agents/omni_command/`
  - `omni_command_service.dart` (Orchestrator)
  - `omni_intent_engine.dart` (NLP parsing)
  - `omni_risk_engine.dart` (Security and auth validation)
  - `omni_tool_registry.dart` (Function execution registry)
  - `omni_context_resolver.dart` (Environment aware contexts)
- **UI Integrations:** `/lib/features/omni_command/omni_command_sheet.dart`
- **Inbox UI:** `/lib/inbox/screens/inbox_dashboard_screen.dart`, `/lib/inbox/components/inbox_list_panel.dart`, `/lib/inbox/components/chat_view_panel.dart`
- **Backend Infrastructure:** `/functions/` (TypeScript Firebase functions).

## 6. OMNI COMMAND ARCHITECTURE
The Omni Command architecture relies on `OmniCommandService` as the central orchestrator. It receives a `rawInput` from the UI, delegates to `OmniIntentEngine` to resolve an `OmniIntent`, verifies permissions via `OmniRiskEngine`, and invokes actions via `OmniToolRegistry`. It is heavily context-driven, fetching capabilities and active routes from `OmniContextResolver`.

## 7. PERSONAL AI ARCHITECTURE
Personal AI uses `OmniCommandState` and `OmniTurnMessage` history. It does not replace the UI but augments it by executing commands (e.g. "draft a reply", "mark as read", "set priority") on behalf of the user using strictly registered backend tools.

## 8. CONTEXT ARCHITECTURE
`OmniContextResolver` constructs the context payload sent to the AI. It extracts `sessionId`, `userId`, `activeRoute`, `surface`, `conversationId`, `messageId`, and active UI modes (e.g., `draft`, `approval`). Critically, it strips out raw content and tokens, sending only IDs for security. `OmniContextNotifier` manages UI-side context updates.

## 9. TOOL ARCHITECTURE
Defined in `OmniToolRegistry`. Tools are registered with `OmniToolDefinition` defining `inputSchema`, `requiredPermission`, `riskLevel`, and `requiredCapabilities`. Executing a tool (e.g. `send_message`) routes through `ControlPlaneService`, guaranteeing idempotency and preventing raw API calls from the LLM model.

## 10. RESULT ARCHITECTURE
Executions yield a `ToolResult` containing `success`, `data`, `statusMessage`, and `executionState`. These structured results are sanitized and safe for consumption by the UI or subsequent AI turns.

## 11. SECURITY BOUNDARIES
- **Risk Engine:** Prevents unauthorized execution of `High` or `Critical` risk actions (e.g., `send_message`) without explicit confirmation.
- **Context Stripping:** PII and raw database content are not embedded in context; only IDs are used.
- **Backend Execution:** Tool executions are backed by Firebase Functions and Firestore security rules. Models never directly execute network requests.
- **Mode Enforcement:** `AiOperatingMode` limits operations (e.g. `assist`, `draft`, `approval`, `auto`).

## 12. DATABASE / FIRESTORE MAP
- `conversations/`: Inbox message collections.
- `connectors/`: Platform integrators (Meta, WhatsApp, etc).
- `notifications/`: User notifications.
- `projects/`, `media/`: Production domain assets.
*Note: AI tools interact with these through canonical repositories, not raw firestore requests.*

## 13. UI INTEGRATION MAP
- **Entry Points:** `OmniCommandButton` located in `InboxListPanel` header.
- **Action Surface:** `OmniCommandSheet` provides the user dialog.
- **Context Injection:** `InboxListPanel` and `ChatViewPanel` must correctly inform the `OmniContextNotifier` of the user's active selections (e.g., `selectedItem`).

## 14. MOBILE / DESKTOP PLAN
The UI gracefully degrades using `LayoutBuilder` in `InboxDashboardScreen`. Omni Command sheet will render as a bottom sheet on mobile and a side-panel or floating modal on desktop. The `OmniCommandButton` works seamlessly across both form factors.

## 15. EXTERNAL RESEARCH
No external APIs need to be integrated directly for this phase as the Omni Command backend already exists and wraps internal Firebase Cloud Functions and existing `inboxRepo` calls.

## 16. FACT / ASSUMPTION MATRIX
- **Fact:** `flutter test` shows all Omni Command tools correctly validate and enforce logic.
- **Fact:** `OmniContextNotifier` exists to track the user's focus.
- **Assumption:** `InboxDashboardScreen` child components appropriately update `omniContextProvider` when a conversation is tapped. (Needs validation).
- **Fact:** Backend tests (`functions/`) are unconfigured.

## 17. DEPENDENCY MAP
`OmniCommandButton` -> `OmniCommandSheet` -> `OmniCommandService` -> (`OmniIntentEngine`, `OmniRiskEngine`, `OmniContextResolver`, `OmniToolRegistry`) -> (`CanonicalInboxRepository`, `FirebaseFunctions`).

## 18. FAILURE MODE MATRIX
- **Missing Context:** Intent cannot be resolved due to missing `conversationId`. Falls back to explicit prompting.
- **Risk Denial:** User attempts a write operation in `assist` mode. Rejected by `OmniRiskEngine`.
- **Backend Failure:** Function timeout during `send_message`. AI catches `FirebaseFunctionsException` and outputs a sanitized error.

## 19. PERFORMANCE ANALYSIS
- Local NLP pattern matching (`OmniIntentEngine`) is instantaneous.
- Firebase Functions are used for heavy lifting (e.g., `searchMessages`).
- Riverpod state minimizes rebuilds on the `InboxListPanel`.

## 20. RACE / CANCELLATION ANALYSIS
`OmniCommandState` manages `isProcessing`. Idempotency keys (`clientCommandId`) are required for executing mutating tools (`send_message`), mitigating double-submit race conditions if the UI is mashed.

## 21. RISK REGISTER
- UI context not synchronizing accurately when rapidly switching conversations.
- Lack of backend test coverage for Firebase functions invoked by tools.
- Overloading the prompt window if context objects grow too large.

## 22. PROPOSED IMPLEMENTATION PHASES
1. **Context Hydration:** Wire `selectedInboxItemProvider` updates directly to `omniContextProvider` so the AI always knows what conversation is open.
2. **UI Polish:** Ensure the `OmniCommandSheet` dynamically reacts to the `OmniCommandState`.
3. **Draft Mode Integration:** Specifically test the "draft a reply" tool to ensure it injects into the `ChatViewPanel` input field.

## 23. TEST STRATEGY
- Write widget tests for `OmniCommandButton` interactions.
- Mock `OmniCommandService` to verify UI responsiveness to state changes.
- End-to-end integration test of a "Read conversation -> Draft Reply -> Approve" flow.

## 24. LIVE VERIFICATION STRATEGY
1. Boot the application on both Desktop and Mobile simulators.
2. Open a conversation.
3. Invoke Omni Command and type "Draft a polite reply".
4. Verify the draft appears in the chat compose box WITHOUT being sent.

## 25. ACCEPTANCE CRITERIA
- User can open Omni Command from the Inbox.
- Omni Command recognizes the actively selected conversation.
- Omni Command correctly refuses high-risk actions without confirmation.
- The UI reflects the AI's actions (e.g. unread counters updating when AI marks as read).

## 26. OPEN QUESTIONS / UNKNOWN FACTS
- Do we need to inject the Draft directly into the `ChatViewPanel`'s text controller, or is there a dedicated draft state provider? (Will investigate during implementation).
- Should we prioritize fixing the `functions/` test suite before proceeding with Flutter UI integration?

## 27. RECOMMENDED NEXT IMPLEMENTATION STEP
**Phase 1:** Implement proper context syncing. Ensure that whenever `selectedInboxItemProvider` changes in `InboxDashboardScreen`, the `OmniContextNotifier` receives the updated `conversationId` and `connectorId`.
