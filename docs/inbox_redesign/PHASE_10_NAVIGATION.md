# PHASE 10: NAVIGATION

## Cross-Surface Routing
Phase 10 extends the `NavigationContextResolver` concepts applied in Phase 9.

### Transitions
- **Chat -> Tools:** Utilizes standard Flutter bottom sheet modal transitions (`showModalBottomSheet`), keeping the user conceptually rooted in the Chat context without losing visual context.
- **Chat -> Message Actions:** Similar modal bottom sheet transition for discrete object actions.
- **Back State:** Modals natively pop on hardware back, avoiding the pollution of the deep link router history stack with ephemeral contextual panels.

### Future Contexts
When Media and Call screens are formally implemented (upon successful binding of Live credentials), they will push full-page routes atop the Conversation stack, ensuring the user can always navigate backward to the specific conversation thread.
