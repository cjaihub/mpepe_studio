# PHASE 10: SECURITY

## Architecture
1. **Permission Isolation:** AI contexts ONLY operate on data the current `uid` is strictly authorized to view via canonical Firebase Rules.
2. **No UI Bypasses:** Displaying a "Delete" button via the contextual action sheet does not bypass backend verification. If a forged command is dispatched, the `ControlPlaneService` drops it and the UI optimally reverts.
3. **Secret Protection:** Provider Tokens (like OpenAI / OpenRouter keys) NEVER hit the Flutter client. The AI Gateway proxy injects them server-side.
4. **Data Ownership:** Media workspace paths are resolved using canonical Firebase Storage secure URL rules.
