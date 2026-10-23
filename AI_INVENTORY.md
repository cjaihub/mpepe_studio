# AI Features Inventory

## Capabilities
- **Gemini Live Voice Mode**: Real-time voice interaction (`LiveVoiceModeScreen`).
- **Background Agents**: AI tasks running independently in the background (e.g. YouTube management, video analysis).
- **TikTok AI Assistant**: Platform-specific agent for content ideation and scheduling.
- **Workflow Automation**: AI-powered automation rules accessible via the workflow builder.
- **AI Personalization**: Users can configure AI behavior and voice settings in preferences.

## Security & Governance
- **AiSecurityGateway**: Central interception point for AI inputs and outputs.
- Ensures AI interactions do not result in prompt injections or execute privileged tools without explicit authorization.
- Logs all tool requests to `ai_audit_logs`.

## Agents Directory (`lib/backend/agents/`)
- `ai_security_gateway.dart`: Permission enforcer.
- `background_agent_service.dart`: Manages long-running AI processes.
- `youtube_agent.dart`: Specialized agent for YouTube channel intelligence.
