import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Categorises why a cloud AI call did not complete so Ova can either recover
/// automatically or show actionable next steps instead of a generic error.
enum OvaAiIssueKind {
  offline,
  cloudUnavailable,
  authRequired,
  rateLimited,
  invalidKey,
  quotaOrBilling,
}

/// Structured diagnostic attached when cloud AI falls back to local synthesis
/// or needs user action.
class OvaAiDiagnostic {
  final OvaAiIssueKind kind;
  final String badgeLabel;
  final String detail;
  final bool usedLocalAssistant;
  final int? httpStatus;

  const OvaAiDiagnostic({
    required this.kind,
    required this.badgeLabel,
    required this.detail,
    this.usedLocalAssistant = true,
    this.httpStatus,
  });

  bool get suggestAiKey =>
      kind == OvaAiIssueKind.cloudUnavailable ||
      kind == OvaAiIssueKind.invalidKey ||
      kind == OvaAiIssueKind.quotaOrBilling;
}

/// Where OpenRouter-style AI calls go, plus proxy health tracking.
///
/// The app ships no server AI key. Signed-in users reach OpenRouter through the
/// `aiProxy` Cloud Function, which holds the key in Secret Manager and checks
/// the caller's Firebase ID token. A user who saved their own OpenRouter or
/// Gemini key in AI Settings calls that provider directly from hardware-backed
/// storage without touching `aiProxy`.
class OneovaAiGateway {
  OneovaAiGateway._();

  static const String _openRouterBase = 'https://openrouter.ai/api/v1';
  static const String _proxyBase =
      'https://us-central1-mpepe-2b4bd.cloudfunctions.net/aiProxy/api/v1';

  /// Short cooldown after a 502/503/504 from `aiProxy` so subsequent messages
  /// fail over immediately instead of waiting on doomed retries.
  static DateTime? _proxyCooldownUntil;
  static int? _lastProxyErrorStatus;

  static bool get _firebaseReady => Firebase.apps.isNotEmpty;

  static bool get signedIn {
    if (!_firebaseReady) return false;
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// True when `aiProxy` recently returned 5xx and is cooling down.
  static bool get isProxyCoolingDown {
    final until = _proxyCooldownUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _proxyCooldownUntil = null;
      return false;
    }
    return true;
  }

  static int? get lastProxyErrorStatus => _lastProxyErrorStatus;

  static void recordProxyFailure(int statusCode) {
    _lastProxyErrorStatus = statusCode;
    if (statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504) {
      _proxyCooldownUntil = DateTime.now().add(const Duration(seconds: 45));
    }
  }

  static void recordProxySuccess() {
    _proxyCooldownUntil = null;
    _lastProxyErrorStatus = null;
  }

  static void resetCooldown() {
    _proxyCooldownUntil = null;
    _lastProxyErrorStatus = null;
  }

  /// True when an OpenRouter-compatible call can be made: user key or signed-in user.
  static bool canCall(String userKey, {bool ignoreCooldown = false}) {
    if (userKey.trim().isNotEmpty) return true;
    if (!signedIn) return false;
    return ignoreCooldown || !isProxyCoolingDown;
  }

  static Uri chatUri(String userKey) => Uri.parse(
      '${userKey.trim().isNotEmpty ? _openRouterBase : _proxyBase}/chat/completions');

  static Uri modelsUri(String userKey) =>
      Uri.parse('${userKey.trim().isNotEmpty ? _openRouterBase : _proxyBase}/models');

  /// Bearer value for [chatUri]/[modelsUri]: the user's key or their ID token.
  static Future<String> bearer(String userKey, {bool forceRefresh = false}) async {
    if (userKey.trim().isNotEmpty) return userKey.trim();
    if (!_firebaseReady) return '';
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// App Check header for calls through `aiProxy` (empty for the user's own
  /// key). The proxy rejects calls without it once App Check is enforced.
  static Future<Map<String, String>> appCheckHeader(String userKey) async {
    if (userKey.trim().isNotEmpty || !_firebaseReady) return const {};
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      return token == null ? const {} : {'X-Firebase-AppCheck': token};
    } catch (_) {
      return const {};
    }
  }

  /// Converts raw HTTP error payloads (including HTML 502/503 pages) into
  /// clean, concise human-readable explanations.
  static OvaAiDiagnostic classifyHttpFailure(
    int statusCode,
    String rawBody, {
    bool usingUserKey = false,
  }) {
    final lower = rawBody.toLowerCase();
    if (statusCode == 401) {
      if (usingUserKey) {
        return const OvaAiDiagnostic(
          kind: OvaAiIssueKind.invalidKey,
          badgeLabel: 'Invalid AI Key',
          detail: 'Your saved API key was rejected. Update or clear it in AI Settings.',
          httpStatus: 401,
        );
      }
      return const OvaAiDiagnostic(
        kind: OvaAiIssueKind.authRequired,
        badgeLabel: 'Sign-In Needed',
        detail: 'Sign in again to refresh your Oneova AI session, or add a personal AI key in AI Settings.',
        httpStatus: 401,
      );
    }
    if (statusCode == 429) {
      return const OvaAiDiagnostic(
        kind: OvaAiIssueKind.rateLimited,
        badgeLabel: 'Rate Limit Reached',
        detail: 'Cloud AI is rate-limited right now. Wait a moment or add your own Gemini/OpenRouter key in AI Settings.',
        httpStatus: 429,
      );
    }
    if (statusCode == 402 ||
        (statusCode == 403 && (lower.contains('billing') || lower.contains('quota') || lower.contains('credit')))) {
      return OvaAiDiagnostic(
        kind: OvaAiIssueKind.quotaOrBilling,
        badgeLabel: 'Cloud AI Paused',
        detail: usingUserKey
            ? 'Your API key has reached its credit or quota limit. Check your provider dashboard or switch keys in AI Settings.'
            : 'Oneova Cloud AI is temporarily paused for maintenance. Local Ova is active—add a free Gemini or OpenRouter key in AI Settings for instant full cloud AI.',
        httpStatus: statusCode,
      );
    }
    if (statusCode >= 500) {
      return OvaAiDiagnostic(
        kind: OvaAiIssueKind.cloudUnavailable,
        badgeLabel: 'Cloud AI Busy',
        detail:
            'Oneova Cloud AI is temporarily unavailable ($statusCode). Local Ova answered below—tap Retry or add a personal AI key in AI Settings.',
        httpStatus: statusCode,
      );
    }
    // Strip any HTML markup if present
    final stripped = rawBody
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final preview = stripped.isEmpty
        ? 'Cloud AI returned status $statusCode.'
        : (stripped.length > 130 ? '${stripped.substring(0, 130)}…' : stripped);
    return OvaAiDiagnostic(
      kind: usingUserKey ? OvaAiIssueKind.invalidKey : OvaAiIssueKind.cloudUnavailable,
      badgeLabel: 'Cloud AI Notice',
      detail: preview,
      httpStatus: statusCode,
    );
  }
}
