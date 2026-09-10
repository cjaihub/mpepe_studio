class FriendlyErrorParser {
  /// Translates raw, technical exceptions into friendly, conversational UI messages
  static String parse(dynamic error) {
    if (error == null) return "Oops! Something went wrong on our end.";
    
    final errStr = error.toString().toLowerCase();

    if (errStr.contains('network') || errStr.contains('socket') || errStr.contains('timeout') || errStr.contains('offline')) {
      return "We lost connection to the internet. Please check your connection and try again.";
    }

    if (errStr.contains('permission') || errStr.contains('unauthorized') || errStr.contains('denied')) {
      return "It looks like you don't have permission to do this right now. Make sure you're logged in!";
    }

    if (errStr.contains('firebase_functions') || errStr.contains('internal') || errStr.contains('server-error')) {
      return "Our servers hit a little snag. Please give it another try in a moment.";
    }

    if (errStr.contains('not-found')) {
      return "We couldn't find what you were looking for.";
    }
    
    if (errStr.contains('quota') || errStr.contains('limit')) {
       return "You've hit a limit for now. Please take a quick break and try again later.";
    }

    // Default friendly fallback
    return "Oops! Something went wrong on our end. Please try again.";
  }
}
