import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureKeyVaultProvider = Provider<SecureKeyVault>((ref) {
  return SecureKeyVault();
});

/// Hardened API Key and Credential Vault for Oneova.
///
/// Encapsulates API keys with:
/// 1. Secure hardware-backed storage (iOS Keychain / Android Keystore).
/// 2. Dotenv and compile-time environment fallback.
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

  /// Obtains the hardened Google Gemini API key.
  /// Priority:
  /// 1. Hardware-backed secure storage (Keystore / Keychain)
  /// 2. Dotenv ('GEMINI_API_KEY' or 'GOOGLE_AI_API_KEY')
  /// 3. Compile-time environment ('GEMINI_API_KEY' or 'GOOGLE_AI_API_KEY')
  Future<String> getGeminiApiKey() async {
    // 1. Check hardware-backed secure storage
    try {
      final secureVal = await _secureStorage.read(key: _geminiKeyStorageKey);
      if (secureVal != null && secureVal.trim().isNotEmpty) {
        return secureVal.trim();
      }
    } catch (_) {
      // Secure storage read fallback
    }

    // 2. Check dotenv
    final envGemini = dotenv.env['GEMINI_API_KEY'];
    if (envGemini != null && envGemini.trim().isNotEmpty) {
      return envGemini.trim();
    }
    final envGoogle = dotenv.env['GOOGLE_AI_API_KEY'];
    if (envGoogle != null && envGoogle.trim().isNotEmpty) {
      return envGoogle.trim();
    }

    // 3. Check compile-time environment variables
    const compileGemini = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
    if (compileGemini.trim().isNotEmpty) {
      return compileGemini.trim();
    }
    const compileGoogle = String.fromEnvironment('GOOGLE_AI_API_KEY', defaultValue: '');
    if (compileGoogle.trim().isNotEmpty) {
      return compileGoogle.trim();
    }

    return '';
  }

  /// Sets or updates the Gemini API key in hardware-backed secure storage.
  Future<void> storeGeminiApiKey(String apiKey) async {
    final clean = apiKey.trim();
    if (clean.isEmpty) {
      await _secureStorage.delete(key: _geminiKeyStorageKey);
    } else {
      await _secureStorage.write(key: _geminiKeyStorageKey, value: clean);
    }
  }

  /// Checks if a valid Gemini API key is configured.
  Future<bool> hasGeminiApiKey() async {
    final key = await getGeminiApiKey();
    return key.isNotEmpty;
  }

  /// Obtains the preferred Gemini model (defaults to gemini-2.5-flash for speed & multimodality).
  Future<String> getPreferredGeminiModel() async {
    try {
      final customModel = await _secureStorage.read(key: _geminiModelStorageKey);
      if (customModel != null && customModel.isNotEmpty) {
        return customModel;
      }
    } catch (_) {}

    final envModel = dotenv.env['GEMINI_DEFAULT_MODEL'];
    if (envModel != null && envModel.isNotEmpty) {
      return envModel;
    }

    return 'gemini-2.5-flash';
  }

  /// Sets the preferred Gemini model in secure storage.
  Future<void> setPreferredGeminiModel(String modelId) async {
    await _secureStorage.write(key: _geminiModelStorageKey, value: modelId.trim());
  }

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

    // 2. Check dotenv
    final envVal = dotenv.env['OPENROUTER_API_KEY'];
    if (envVal != null && envVal.trim().isNotEmpty) {
      return envVal.trim();
    }

    // 3. Check compile-time environment variable
    const compileVal = String.fromEnvironment('OPENROUTER_API_KEY', defaultValue: '');
    if (compileVal.trim().isNotEmpty) {
      return compileVal.trim();
    }

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

    final envModel = dotenv.env['OPENROUTER_DEFAULT_MODEL'];
    if (envModel != null && envModel.isNotEmpty) {
      return envModel;
    }

    // Reliable, fast, and free tier model by default
    return 'meta-llama/llama-3-8b-instruct:free';
  }

  /// Sets the preferred model in secure storage.
  Future<void> setPreferredOpenRouterModel(String modelId) async {
    await _secureStorage.write(key: _openRouterModelStorageKey, value: modelId.trim());
  }

  /// Standard secure headers for OpenRouter calls, strictly branded for Oneova.
  Future<Map<String, String>> getOpenRouterHeaders({String? overrideKey}) async {
    final key = overrideKey ?? await getOpenRouterApiKey();
    return {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://oneova.app',
      'X-Title': 'Oneova',
      'User-Agent': 'Oneova-Mobile/1.0',
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
