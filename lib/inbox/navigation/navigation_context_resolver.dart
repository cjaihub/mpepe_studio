
enum NavigationContext {
  global,
  conversation,
  selection,
}

class NavigationContextResolver {
  /// Determines the current context based on routing path or active selection.
  static NavigationContext resolveContext(String currentRoute, {bool hasSelection = false}) {
    if (hasSelection) {
      return NavigationContext.selection;
    }
    
    if (currentRoute.contains('/conversation/')) {
      return NavigationContext.conversation;
    }
    
    return NavigationContext.global;
  }

  /// Returns whether the global bottom navigation bar should be visible
  static bool shouldShowGlobalBottomNav(NavigationContext context) {
    return context == NavigationContext.global;
  }
}
