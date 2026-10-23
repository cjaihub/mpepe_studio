import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/auth/security/login_security.dart';
import 'package:oneova/ova_assistant/services/ova_auth_coach.dart';

AuthFactor? next(Set<AuthFactor> f, {bool trusted = false, bool pw = true, bool bio = false}) =>
    LoginSecurity.missingFactor(f, deviceTrusted: trusted, hasPassword: pw, biometricReady: bio);

void main() {
  group('two-check policy', () {
    test('new device: password alone needs an SMS code', () {
      expect(next({AuthFactor.password}), AuthFactor.smsOtp);
      expect(next({AuthFactor.password, AuthFactor.smsOtp}), isNull);
    });

    test('SMS code alone needs a password (or fingerprint on a trusted device)', () {
      expect(next({AuthFactor.smsOtp}), AuthFactor.password);
      expect(next({AuthFactor.smsOtp}, trusted: true, bio: true), AuthFactor.biometric);
      expect(next({AuthFactor.smsOtp, AuthFactor.biometric}, trusted: true, bio: true), isNull);
    });

    test('fingerprint never signs in alone', () {
      expect(next({AuthFactor.biometric}), AuthFactor.smsOtp);
      expect(next({AuthFactor.deviceKey, AuthFactor.biometric}), AuthFactor.smsOtp);
      expect(next({AuthFactor.deviceKey, AuthFactor.biometric}, trusted: true, bio: true), isNull);
    });

    test('trusted device + password, plus fingerprint when it is on', () {
      expect(next({AuthFactor.password}, trusted: true), isNull);
      expect(next({AuthFactor.password}, trusted: true, bio: true), AuthFactor.biometric);
    });

    test('social sign-in on a new device needs an SMS code', () {
      expect(next({AuthFactor.federated}), AuthFactor.smsOtp);
      expect(next({AuthFactor.federated}, trusted: true), isNull);
    });

    test('an existing session with no checks is asked for them', () {
      expect(next({}), AuthFactor.smsOtp);
      expect(next({}, trusted: true), AuthFactor.password);
      expect(next({}, trusted: true, bio: true), AuthFactor.biometric);
    });

    test('PIN counts only on a known phone, like fingerprint', () {
      AuthFactor? n(Set<AuthFactor> f, {bool trusted = false}) =>
          LoginSecurity.missingFactor(f, deviceTrusted: trusted, hasPassword: true, biometricReady: false, pinReady: true);
      expect(n({AuthFactor.smsOtp}, trusted: true), AuthFactor.pin);
      expect(n({AuthFactor.smsOtp, AuthFactor.pin}, trusted: true), isNull);
      expect(n({AuthFactor.pin}), AuthFactor.smsOtp);
      expect(n({AuthFactor.password}, trusted: true), AuthFactor.pin);
    });

    test('meetsPolicy mirrors missingFactor', () {
      expect(LoginSecurity.meetsPolicy({AuthFactor.smsOtp}, deviceTrusted: true), isFalse);
      expect(LoginSecurity.meetsPolicy({AuthFactor.smsOtp, AuthFactor.password}, deviceTrusted: false), isTrue);
    });

    test('phone -> auth email', () {
      expect(LoginSecurity.authEmailForPhone('+254 712 345 678'), 'p254712345678@phone.oneova.app');
    });

    test('guest routes', () {
      expect(LoginSecurity.isGuestRoute('/hub/home'), isTrue);
      expect(LoginSecurity.isGuestRoute('/profile/abc'), isTrue);
      expect(LoginSecurity.isGuestRoute('/profile/me'), isFalse);
      expect(LoginSecurity.isGuestRoute('/hub/messages'), isFalse);
    });
  });

  group('Ova auth coach', () {
    test('flags breached and weak passwords', () {
      expect(OvaAuthCoach.newPassword('password123')!.tone, OvaHintTone.error);
      expect(OvaAuthCoach.newPassword('123456')!.tone, OvaHintTone.error);
      expect(OvaAuthCoach.newPassword('abc')!.text, contains('more character'));
      expect(OvaAuthCoach.newPassword('Tr4il-Mango-92')!.tone, OvaHintTone.success);
    });

    test('caps lock guess', () {
      expect(OvaAuthCoach.signInPassword('HELLOW')!.text, contains('Caps Lock'));
      expect(OvaAuthCoach.signInPassword('Hello'), isNull);
    });

    test('OTP states', () {
      expect(OvaAuthCoach.otp(phone: '+254712345678', code: '', resendSeconds: 40).text, contains('New code in 40s'));
      expect(OvaAuthCoach.otp(phone: '+254712345678', code: '123', resendSeconds: 40).text, contains('3 more digits'));
      expect(OvaAuthCoach.otp(phone: '+254712345678', code: '', resendSeconds: 0, errorCode: 'session-expired').tone,
          OvaHintTone.warning);
      expect(OvaAuthCoach.otp(phone: '+254712345678', code: '123456', resendSeconds: 0, errorCode: 'invalid-verification-code').tone,
          OvaHintTone.error);
      expect(OvaAuthCoach.maskPhone('+254712345678'), '+254 ••• •• 678');
    });

    test('device and fingerprint states', () {
      expect(OvaAuthCoach.device(scanning: false, trusted: false).text, contains('New phone'));
      expect(OvaAuthCoach.device(scanning: false, trusted: true).tone, OvaHintTone.success);
      expect(OvaAuthCoach.biometric(available: true, enrolledOnDevice: false).text, contains('No fingerprint'));
      expect(OvaAuthCoach.biometric(available: true, enrolledOnDevice: true, success: false).tone, OvaHintTone.error);
    });
  });
}
