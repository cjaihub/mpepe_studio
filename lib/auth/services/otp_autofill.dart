import 'package:flutter/widgets.dart';
import 'package:smart_auth/smart_auth.dart';

/// Fills a one-time code from the incoming SMS without any SMS permission.
///
/// Android: Google's SMS User Consent API. When the text arrives, Google asks
/// "Allow Oneova to read this message?" and only that one message is shared.
/// This is the Play-approved way to read login codes.
/// iOS: the keyboard offers the code itself (autofill hint `oneTimeCode`), so
/// nothing runs here.
class OtpAutofill {
  bool _listening = false;

  /// Off: every caller uses it during Firebase phone sign-in, and Firebase
  /// Auth (firebase-auth 24.x) already runs its own SMS Retriever and fills
  /// the code via `verificationCompleted`. Running the User Consent API at the
  /// same time makes Google deliver a consent broadcast with no message text,
  /// and Firebase's receiver crashes the app on it
  /// (NullPointerException in Matcher.reset, zzagp.onReceive) — seen on a
  /// TECNO CL6k, 2026-10-22. Manual entry and Firebase auto-fill still work.
  bool get supported => false;

  /// Starts waiting for one code (up to 5 minutes, Google's limit).
  /// Writes it into [controller] and calls [onCode].
  Future<void> listen(
    TextEditingController controller, {
    int length = 6,
    ValueChanged<String>? onCode,
  }) async {
    if (!supported || _listening) return;
    _listening = true;
    try {
      final res = await SmartAuth.instance.getSmsWithUserConsentApi(matcher: '\\b\\d{$length}\\b');
      final code = res.data?.code;
      if (res.hasData && code != null && code.length == length) {
        controller.text = code;
        controller.selection = TextSelection.collapsed(offset: code.length);
        onCode?.call(code);
      }
    } finally {
      _listening = false;
    }
  }

  /// Drops any earlier wait (a resent code replaces the old one) and listens
  /// again. Errors are swallowed: manual entry always still works.
  Future<void> restart(
    TextEditingController controller, {
    int length = 6,
    ValueChanged<String>? onCode,
  }) async {
    try {
      await cancel();
      await listen(controller, length: length, onCode: onCode);
    } catch (e) {
      debugPrint('[OtpAutofill] $e');
    }
  }

  Future<void> cancel() async {
    if (!supported) return;
    _listening = false;
    await SmartAuth.instance.removeUserConsentApiListener();
  }
}
