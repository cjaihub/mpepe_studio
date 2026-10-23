# MPEPE STUDIO AI Architecture

## Background Agents
Regulated by `BackgroundAgentService` (`lib/backend/agents/background_agent_service.dart`).
- **Constraints**: Enforces global `killSwitchEnabled`, daily quotas, and allowed actions.

## Security Gateway
Regulated by `AiSecurityGateway` (`lib/backend/agents/ai_security_gateway.dart`).
- **Schema Validation**: Explicit JSON schema argument checks.
- **Independent Auth**: Tool executions are checked against Firestore IAM rules dynamically.
- **Auditing**: Every tool call (blocked or permitted) is logged immutably to `ai_audit_logs`.
