# INBOX 2.0: NAVIGATION ARCHITECTURE

## Context-Aware Bottom Navigation
The bottom navigation must not be static globally if the user enters a deep workflow.

### States
1. **Global Inbox Level**
   - Bottom Nav: Inbox, Social, CRM, Profile.
2. **Conversation Level**
   - Bottom Nav is hidden. The Composer takes the bottom space. The keyboard pushes the composer up.
3. **Selection Level**
   - If multiple messages are selected, Bottom Nav transforms into contextual actions (Delete, Assign, Mark Unread).

## Routing
- Use `context.push('/inbox/conversation/:id')` instead of `context.go()`.
- `context.go()` replaces the stack and destroys the back button, violating UX guidelines.
- Always implement explicit `IconButton(icon: Icon(Icons.arrow_back))` calling `context.pop()` if standard AppBar is hidden.

## State Management for Navigation
Create a `NavigationContextResolver` that reads the current GoRouter state and the active capabilities to determine what tabs and floating buttons to render.
