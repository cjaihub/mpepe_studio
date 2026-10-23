/// Custom annotations for generating the Canonical Versioned API documentation
/// These enforce that every endpoint explicitly defines its operating parameters.
class ApiEndpoint {
  final String path;
  final String method;
  final String version;
  final bool requiresAuth;
  final String authorizationLevel;
  final String validationRules;
  final String rateLimit;
  final bool isPaginated;
  final bool isIdempotent;
  final String auditBehavior;
  final String errorStructure;

  const ApiEndpoint({
    required this.path,
    required this.method,
    this.version = 'v1',
    this.requiresAuth = true,
    this.authorizationLevel = 'user', // user, creator, admin
    required this.validationRules,
    required this.rateLimit,
    this.isPaginated = false,
    required this.isIdempotent,
    required this.auditBehavior,
    this.errorStructure = 'StandardApiError',
  });
}
