import 'package:envied/envied.dart';

part 'env.g.dart';

@Envied(path: '.env', obfuscate: true)
abstract class Env {
  @EnviedField(varName: 'META_APP_ID')
  static final String metaAppId = _Env.metaAppId;

  // META_APP_SECRET is deliberately not here: it lives only in Cloud Functions
  // (Secret Manager) and the token exchange runs server-side (metaExchangeCode).

  @EnviedField(varName: 'META_REDIRECT_URI')
  static final String metaRedirectUri = _Env.metaRedirectUri;

  @EnviedField(varName: 'TIKTOK_CLIENT_KEY')
  static final String tiktokClientKey = _Env.tiktokClientKey;

  @EnviedField(varName: 'TIKTOK_CLIENT_SECRET')
  static final String tiktokClientSecret = _Env.tiktokClientSecret;
}
