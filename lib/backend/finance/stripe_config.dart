/// Client-side Stripe configuration for Oneova.
///
/// Only the publishable key (`pk_...`) lives in the app. It is injected at
/// build time from the gitignored `.env.json`:
///
///   flutter run --dart-define-from-file=.env.json
///
/// Secret keys (`sk_...`) and webhook secrets must never ship in the app;
/// they belong in Firebase Functions secrets (STRIPE_SECRET_KEY,
/// STRIPE_WEBHOOK_SECRET).
class StripeConfig {
  StripeConfig._();

  static const String publishableKey =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY', defaultValue: '');

  static bool get isConfigured => publishableKey.startsWith('pk_');

  static bool get isTestMode => publishableKey.startsWith('pk_test_');
}
