import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'oneova_ai_gateway.dart';

final secureKeyVaultProvider = Provider<SecureKeyVault>((ref) {
  final vault = SecureKeyVault();
  // One-time clean-up of a Gemini key saved by an older version.
  vault.purgeLegacyGeminiKey();
  return vault;
});

/// Hardened API Key and Credential Vault for Oneova.
///
/// Encapsulates API keys with:
/// 1. Secure hardware-backed storage (iOS Keychain / Android Keystore).
/// 2. No model keys are bundled: without a user's own OpenRouter key, AI goes
///    through the Oneova server proxy.
/// 3. In-memory obfuscation and safe masked representation for observability.
/// 4. Strict header sandboxing to avoid credential leaks to 3rd party logs.
class SecureKeyVault {
  final FlutterSecureStorage _secureStorage;

  SecureKeyVault({FlutterSecureStorage? storage})
      : _secureStorage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  static const String _openRouterKeyStorageKey = 'oneova_secure_openrouter_key';
  static const String _openRouterModelStorageKey = 'oneova_secure_openrouter_model';
  static const String _geminiKeyStorageKey = 'oneova_secure_gemini_key';
  static const String _geminiModelStorageKey = 'oneova_secure_gemini_model';

  /// Oneova never calls the Gemini API directly (text goes through OpenRouter,
  /// live models through Vertex AI). Removes a Gemini key an older version may
  /// have saved on this phone.
  Future<void> purgeLegacyGeminiKey() async {
    try {
      await _secureStorage.delete(key: _geminiKeyStorageKey);
      await _secureStorage.delete(key: _geminiModelStorageKey);
    } catch (_) {}
  }

  static const String defaultOpenRouterModel = 'google/gemini-2.5-flash';
  static const List<String> openRouterFallbackModels = <String>[
    'google/gemini-2.5-flash',
    'meta-llama/llama-3.3-70b-instruct:free',
    'google/gemma-3-27b-it:free',
  ];

  /// Obtains the hardened OpenRouter API key.
  Future<String> getOpenRouterApiKey() async {
    // 1. Check hardware-backed secure storage
    try {
      final secureVal = await _secureStorage.read(key: _openRouterKeyStorageKey);
      if (secureVal != null && secureVal.trim().isNotEmpty) {
        return secureVal.trim();
      }
    } catch (_) {
      // Secure storage read fallback
    }

    // No bundled fallback: without a user key, calls go through the aiProxy
    // Cloud Function (OneovaAiGateway), which holds Oneova's key server-side.
    return '';
  }

  /// Sets or updates the OpenRouter API key in secure storage.
  Future<void> storeOpenRouterApiKey(String apiKey) async {
    final clean = apiKey.trim();
    if (clean.isEmpty) {
      await _secureStorage.delete(key: _openRouterKeyStorageKey);
    } else {
      await _secureStorage.write(key: _openRouterKeyStorageKey, value: clean);
    }
  }

  /// Obtains the preferred default model for onboarding & safety.
  Future<String> getPreferredOpenRouterModel() async {
    try {
      final customModel = await _secureStorage.read(key: _openRouterModelStorageKey);
      if (customModel != null && customModel.isNotEmpty) {
        return customModel;
      }
    } catch (_) {}

    final envModel = dotenv.isInitialized ? dotenv.env['OPENROUTER_DEFAULT_MODEL'] : null;
    if (envModel != null && envModel.isNotEmpty) {
      return envModel;
    }

    return defaultOpenRouterModel;
  }

  /// Sets the preferred model in secure storage.
  Future<void> setPreferredOpenRouterModel(String modelId) async {
    await _secureStorage.write(key: _openRouterModelStorageKey, value: modelId.trim());
  }

  /// Standard secure headers for OpenRouter calls, strictly branded for Oneova.
  Future<Map<String, String>> getOpenRouterHeaders({String? overrideKey}) async {
    final key = overrideKey ?? await getOpenRouterApiKey();
    return {
      'Authorization': 'Bearer ${await OneovaAiGateway.bearer(key)}',
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://oneova.app',
      'X-Title': 'Oneova',
      'User-Agent': 'Oneova-Mobile/1.0',
      ...await OneovaAiGateway.appCheckHeader(key),
    };
  }

  /// Returns a safe, masked representation of any API key for debugging
  /// e.g. "sk-or-v1-••••••••••••c8f2"
  String maskKey(String key) {
    if (key.length <= 8) return '••••••••';
    final prefix = key.substring(0, mathMin(6, key.length));
    final suffix = key.substring(mathMax(0, key.length - 4));
    return '$prefix••••••••$suffix';
  }

  /// Deterministic SHA-256 fingerprint for verification without raw key exposure.
  String keyFingerprint(String key) {
    if (key.isEmpty) return 'none';
    return sha256.convert(utf8.encode(key)).toString().substring(0, 12);
  }

  int mathMin(int a, int b) => a < b ? a : b;
  int mathMax(int a, int b) => a > b ? a : b;
}
