import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/oneova_biometrics_service.dart';

final passkeyAuthServiceProvider = Provider<PasskeyAuthService>((ref) {
  return PasskeyAuthService(ref.watch(oneovaBiometricsServiceProvider));
});

class PasskeyAuthService {
  final OneovaBiometricsService _biometricsService;

  PasskeyAuthService(this._biometricsService);

  /// Checks if passkeys / biometrics are supported on the current device.
  Future<bool> isSupported() async {
    return await _biometricsService.isDeviceSupported();
  }

  /// Initiates the registration of a new passkey (WebAuthn).
  /// [challenge] and [relyingPartyId] are typically fetched from your backend.
  Future<void> registerPasskey({
    required String challenge,
    required String relyingPartyId,
    required String relyingPartyName,
    required String userId,
    required String userName,
  }) async {
    // Note: To successfully register, your backend needs to generate a valid
    // challenge and verify the resulting attestation object.
    
    // Example call using the passkeys package:
    // final request = RegisterResponseType(
    //   challenge: challenge,
    //   rp: RelyingPartyType(name: relyingPartyName, id: relyingPartyId),
    //   user: UserType(id: userId, name: userName, displayName: userName),
    //   pubKeyCredParams: [
    //     PubKeyCredParamType(type: 'public-key', alg: -7), // ES256
    //     PubKeyCredParamType(type: 'public-key', alg: -257), // RS256
    //   ],
    // );
    
    // final response = await _passkeyAuth.register(request);
    // Send response.attestationObject and response.clientDataJSON to backend
  }

  /// Initiates a login using a registered passkey / biometric credential.
  Future<bool> loginWithPasskey(String challenge, String relyingPartyId) async {
    return await _biometricsService.authenticate(reason: 'Authenticate with Oneova Passkey');
  }
}
