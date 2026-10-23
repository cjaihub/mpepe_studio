# PHASE 8: NAVIGATION CONTEXT

## Context Coherence
The `NavigationContextResolver` manages stateful URL transitions across the app.

## Bottom Navigation Context Matrices

- **Global Shell:** Home, Inbox, Create, Studio, Profile
- **Inbox Context:** Conversations, Comments, Mentions, System Alerts
- **Conversation Context:** Chat Feed, Media Vault, Voice (if applicable)

## Implementation Law
Sub-navigational tabs ONLY change when traversing down a tier. Clicking into a Conversation dynamically pushes a secondary view structure while preserving the ability to safely traverse back (`context.pop()`) using Flutter GoRouter to the exact Inbox scroll position. 

Random bottom nav morphing is forbidden. Context is hierarchical.
