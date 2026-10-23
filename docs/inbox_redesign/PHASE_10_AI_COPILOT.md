# PHASE 10: AI COPILOT

## OpenRouter Gateway Integration
AI features within the workspace (such as "AI Summarize" exposed in the Message long-press actions and "AI Copilot" in the Tools sheet) explicitly defer to the centralized AI Gateway.

## Mechanics
- **Draft Flow:** User requests a summary or a draft. The UI spins up a scoped cancellation token. The backend proxies to OpenRouter securely. The text is populated in the `CapabilityAwareComposer` as a Draft, NOT immediately sent.
- **Stale Protection:** Nonces track requests. If a user spam-clicks "Generate", older responses are silently dropped upon network return.
- **Permissions:** AI models are never handed direct access to secrets, tokens, or unauthorized cross-conversation data. Access is strictly scoped to the payload passed via the authenticated function call.
