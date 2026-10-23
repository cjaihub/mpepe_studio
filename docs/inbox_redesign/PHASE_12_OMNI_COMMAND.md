# PHASE 12: OMNI COMMAND & PERSONAL AI CONTROL PLANE

## OBJECTIVE
Implement a unified, mobile-first AI command center that provides intelligent assistance across all MPEPE STUDIO platforms without bypassing the existing canonical backend architecture.

## ARCHITECTURE COMPONENTS
1. **OmniContextResolver**: Safely builds context (Session ID, UI state) without exposing raw credentials.
2. **OmniIntentEngine**: Classifies user natural language into structured operations (Search, Draft, Summarize, Send).
3. **OmniRiskEngine**: Applies strict risk classifications (LOW, MEDIUM, HIGH, CRITICAL) to all AI actions.
4. **OmniToolRegistry**: Single source of truth for all tools (e.g., search_inbox, draft_reply, send_message) with safety boundaries.
5. **OmniPlanner**: Generates step-by-step execution plans from intents.
6. **OmniCommandService**: The central orchestrator that wires context, intents, risks, and tools into a cohesive user session.

## AI OPERATING MODES
- **OFF**: AI completely disabled.
- **ASSIST**: Read-only queries, summarizations, and UI guidance.
- **DRAFT**: Can draft replies but cannot execute mutations.
- **APPROVAL**: Can prepare mutations (e.g., send messages) but REQUIRES explicit user confirmation.
- **AUTO**: Fully autonomous execution of authorized tools (requires explicit opt-in).

## FRONTEND INTEGRATION (PHASE 12.5)
- `OmniCommandSheet`: Unified UI for OmniCommand interactions.
- `OmniCommandButton`: Context-aware entry points injected into global and conversation views.
- `AiSettingsScreen`: Settings UI wired directly to `SharedPreferences` via `AiSettingsNotifier` for persistent mode, memory, and learning toggles.

## SECURITY & COMPLIANCE
- All tool definitions strip execution implementations before being sent to the LLM.
- Unregistered tools fail securely.
- Cross-user data bleed is prevented by context masking.
- Idempotency ensures duplicate execution is mitigated.
