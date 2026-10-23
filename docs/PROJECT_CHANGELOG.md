# Changelog

## [2026-09-25] Sprint Completion
- **Added**: Background AI Agent with permission gating and `PAUSE ALL AI` kill switch.
- **Added**: Command Palette (`Cmd+K`) for rapid navigation and action execution.
- **Added**: Centralized `AppModals` system to prevent destructive silent actions.
- **Added**: `WorkflowEngine` for automation with infinite loop detection and rate limiting.
- **Added**: `SystemStatusService` for exponential backoff realtime recovery.
- **Added**: `AiSecurityGateway` preventing prompt injection and enforcing backend IAM on AI tools.
- **Added**: `ApmService` for data-driven APM trace profiling.
- **Added**: OWASP Top 10 API Security compliance via `docs/API_INVENTORY.md` and `PROJECT_SECURITY_MODEL.md`.
