import 'dart:collection';

class RateLimitException implements Exception {
  final String message;
  RateLimitException(this.message);
  @override
  String toString() => message;
}

/// A simple sliding-window rate limiter for critical endpoints (e.g., AI generation, Uploads).
/// In production, this logic belongs primarily on the backend (Redis/Cloud Armor).
/// We implement it here for defense-in-depth on the client to prevent runaway loops.
class ClientRateLimiter {
  final int maxRequests;
  final Duration window;
  
  final Queue<DateTime> _requests = Queue<DateTime>();

  ClientRateLimiter({required this.maxRequests, required this.window});

  /// Checks if a request is allowed. Throws [RateLimitException] if limit exceeded.
  void checkLimit() {
    final now = DateTime.now();
    
    // Remove expired timestamps
    while (_requests.isNotEmpty && now.difference(_requests.first) > window) {
      _requests.removeFirst();
    }

    if (_requests.length >= maxRequests) {
      throw RateLimitException('Client-side rate limit exceeded. Please wait.');
    }

    _requests.addLast(now);
  }
}
