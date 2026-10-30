import 'package:firebase_auth/firebase_auth.dart';

/// Where OpenRouter-style AI calls go.
///
/// The app ships no AI key. Signed-in users reach OpenRouter through the
/// `aiProxy` Cloud Function, which holds the key in Secret Manager and checks
/// the caller's Firebase ID token. A user who saved their own OpenRouter key
/// in AI Settings calls OpenRouter directly with it.
class OneovaAiGateway {
  OneovaAiGateway._();

  static const String _openRouterBase = 'https://openrouter.ai/api/v1';
  static const String _proxyBase =
      'https://us-central1-mpepe-2b4bd.cloudfunctions.net/aiProxy/api/v1';

  static bool get signedIn => FirebaseAuth.instance.currentUser != null;

  /// True when an AI call can be made: the user's own key, or a signed-in user.
  static bool canCall(String userKey) => userKey.isNotEmpty || signedIn;

  static Uri chatUri(String userKey) => Uri.parse(
      '${userKey.isNotEmpty ? _openRouterBase : _proxyBase}/chat/completions');

  static Uri modelsUri(String userKey) =>
      Uri.parse('${userKey.isNotEmpty ? _openRouterBase : _proxyBase}/models');

  /// Bearer value for [chatUri]/[modelsUri]: the user's key or their ID token.
  static Future<String> bearer(String userKey) async {
    if (userKey.isNotEmpty) return userKey;
    return await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
  }
}
