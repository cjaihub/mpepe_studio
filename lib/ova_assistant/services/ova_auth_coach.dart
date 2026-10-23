/// Ova's live sign-in coach: short, friendly feedback while the user types
/// a password, enters an SMS code, scans the device or uses a fingerprint.
///
/// Runs fully on the device and in real time; nothing typed here (passwords,
/// codes) is ever sent to the language model or the network.
library;

enum OvaHintTone { info, working, success, warning, error }

class OvaHint {
  final String text;
  final OvaHintTone tone;

  const OvaHint(this.text, [this.tone = OvaHintTone.info]);

  @override
  bool operator ==(Object other) => other is OvaHint && other.text == text && other.tone == tone;

  @override
  int get hashCode => Object.hash(text, tone);
}

/// Passwords that show up first in public breach lists. Kept short on
/// purpose: Ova warns on these, Firebase still decides what is accepted.
const _commonPasswords = {
  '123456', '1234567', '12345678', '123456789', '1234567890', '111111', '000000',
  '123123', '654321', '666666', '121212', '112233', '159753', '147258', 'qwerty',
  'qwerty123', 'qwertyuiop', 'asdfgh', 'zxcvbnm', 'password', 'password1',
  'password123', 'passw0rd', 'abc123', 'abcd1234', 'iloveyou', 'welcome',
  'welcome1', 'admin', 'admin123', 'letmein', 'monkey', 'dragon', 'football',
  'baseball', 'sunshine', 'princess', 'master', 'shadow', 'superman', 'michael',
  'jesus', 'love123', 'mustang', 'trustno1', '1q2w3e4r', '1qaz2wsx', 'oneova',
};

class OvaAuthCoach {
  const OvaAuthCoach._();

  /// 0..4 strength score (length, case mix, digits, symbols, not common).
  static int passwordScore(String pw) {
    if (pw.isEmpty) return 0;
    var score = 0;
    if (pw.length >= 8) score++;
    if (pw.length >= 12) score++;
    if (RegExp(r'[a-z]').hasMatch(pw) && RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'\d').hasMatch(pw)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;
    if (isCommonPassword(pw)) score = 0;
    return score.clamp(0, 4);
  }

  static bool isCommonPassword(String pw) {
    final p = pw.toLowerCase();
    if (_commonPasswords.contains(p)) return true;
    if (RegExp(r'^(.)\1+$').hasMatch(p)) return true; // aaaaaa, 111111
    const seq = '0123456789abcdefghijklmnopqrstuvwxyz';
    return p.length >= 6 && seq.contains(p);
  }

  /// Caps Lock guess for soft keyboards (which do not report it): the
  /// password so far is all capital letters.
  static bool looksLikeCapsLock(String pw, {bool hardwareCapsLock = false}) {
    if (hardwareCapsLock) return true;
    final letters = pw.replaceAll(RegExp(r'[^A-Za-z]'), '');
    return letters.length >= 3 && RegExp(r'^[A-Z]+$').hasMatch(letters);
  }

  /// Feedback while creating a password.
  static OvaHint? newPassword(
    String pw, {
    String? name,
    String? username,
    String? phone,
    bool hardwareCapsLock = false,
  }) {
    if (pw.isEmpty) return const OvaHint('Use 8+ characters with a mix of letters, numbers and a symbol.');
    if (looksLikeCapsLock(pw, hardwareCapsLock: hardwareCapsLock)) {
      return const OvaHint('Caps Lock looks on — passwords are case-sensitive.', OvaHintTone.warning);
    }
    if (isCommonPassword(pw)) {
      return const OvaHint('Lots of people use this one. Pick something only you know.', OvaHintTone.error);
    }
    final lower = pw.toLowerCase();
    final personal = <String>[
      if (name != null) ...name.toLowerCase().split(RegExp(r'\s+')).where((s) => s.length >= 3),
      if (username != null && username.length >= 3) username.toLowerCase(),
    ];
    if (personal.any(lower.contains)) {
      return const OvaHint('Avoid your name or username — they are easy to guess.', OvaHintTone.warning);
    }
    final digits = phone?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.length >= 6 && lower.contains(digits.substring(digits.length - 6))) {
      return const OvaHint('Avoid your phone number in your password.', OvaHintTone.warning);
    }
    if (pw.length < 8) return OvaHint('${8 - pw.length} more character${8 - pw.length == 1 ? '' : 's'} to go.', OvaHintTone.warning);
    switch (passwordScore(pw)) {
      case 0:
      case 1:
        return const OvaHint('Weak — add capitals, numbers or a symbol.', OvaHintTone.warning);
      case 2:
        return const OvaHint('Fair — one more number or symbol makes it strong.', OvaHintTone.info);
      case 3:
        return const OvaHint('Strong password. Nice.', OvaHintTone.success);
      default:
        return const OvaHint('Excellent — very hard to guess.', OvaHintTone.success);
    }
  }

  /// Feedback while entering an existing password.
  static OvaHint? signInPassword(String pw, {bool hardwareCapsLock = false, int failedAttempts = 0, int cooldownSeconds = 0}) {
    if (cooldownSeconds > 0) {
      return OvaHint('Too many tries. Try again in ${cooldownSeconds}s, or use a text code.', OvaHintTone.error);
    }
    if (looksLikeCapsLock(pw, hardwareCapsLock: hardwareCapsLock)) {
      return const OvaHint('Caps Lock looks on — passwords are case-sensitive.', OvaHintTone.warning);
    }
    if (failedAttempts > 0) {
      final left = 5 - failedAttempts;
      return OvaHint(
        left > 0
            ? 'That password didn\'t match. $left ${left == 1 ? 'try' : 'tries'} left before a short pause.'
            : 'That password didn\'t match.',
        OvaHintTone.error,
      );
    }
    return null;
  }

  /// Feedback on the SMS code step.
  static OvaHint otp({
    required String phone,
    required String code,
    required int resendSeconds,
    bool sending = false,
    bool verifying = false,
    bool autoVerified = false,
    String? errorCode,
    int wrongAttempts = 0,
  }) {
    final masked = maskPhone(phone);
    if (autoVerified) return const OvaHint('Got your code automatically.', OvaHintTone.success);
    if (sending) return OvaHint('Texting a code to $masked…', OvaHintTone.working);
    if (verifying) return const OvaHint('Checking…', OvaHintTone.working);
    switch (errorCode) {
      case 'invalid-verification-code':
        return OvaHint(
          wrongAttempts >= 3
              ? 'Still not matching. Tap Resend for a fresh code.'
              : 'That code didn\'t match. Check the latest SMS and try again.',
          OvaHintTone.error,
        );
      case 'session-expired':
      case 'code-expired':
        return const OvaHint('This code is too old. Tap Resend for a new one.', OvaHintTone.warning);
      case 'too-many-requests':
        return const OvaHint('Too many attempts. Wait a few minutes, then resend.', OvaHintTone.error);
      case 'user-mismatch':
        return const OvaHint('That number is for a different account.', OvaHintTone.error);
      case 'credential-already-in-use':
        return const OvaHint('That number is already used by another Oneova account.', OvaHintTone.error);
      case 'network-request-failed':
        return const OvaHint('No connection. Check your internet and try again.', OvaHintTone.error);
    }
    if (code.isNotEmpty && code.length < 6) {
      final left = 6 - code.length;
      return OvaHint('$left more digit${left == 1 ? '' : 's'}…');
    }
    if (resendSeconds > 0) return OvaHint('Code texted to $masked. New code in ${resendSeconds}s.');
    return const OvaHint('No text yet? Tap Resend.', OvaHintTone.warning);
  }

  /// Feedback for the device scan.
  static OvaHint device({required bool scanning, bool? trusted, String? label, bool isPhysical = true}) {
    if (scanning) return const OvaHint('Checking this phone…', OvaHintTone.working);
    if (!isPhysical) return const OvaHint('This looks like a test phone, so we\'ll text you a code.', OvaHintTone.warning);
    if (trusted == true) return OvaHint('We know this phone${label != null ? ' ($label)' : ''}.', OvaHintTone.success);
    return OvaHint('New phone${label != null ? ' ($label)' : ''} — we\'ll text you a code once.', OvaHintTone.warning);
  }

  /// Feedback for the fingerprint step.
  static OvaHint biometric({
    required bool available,
    required bool enrolledOnDevice,
    bool scanning = false,
    bool? success,
    bool lockedOut = false,
    bool canceled = false,
    String? error,
  }) {
    if (!available) return const OvaHint('Fingerprint isn\'t ready on this phone. Use your password or a text code.', OvaHintTone.warning);
    if (!enrolledOnDevice) {
      return const OvaHint('No fingerprint saved on this phone. Add one in Settings, or use password.', OvaHintTone.warning);
    }
    if (scanning) return const OvaHint('Touch the sensor…', OvaHintTone.working);
    if (lockedOut) return const OvaHint('Too many tries. Unlock your phone screen, or use your password.', OvaHintTone.error);
    if (success == true) return const OvaHint('Fingerprint matched.', OvaHintTone.success);
    if (canceled) return const OvaHint('Scan cancelled. Tap to try again.', OvaHintTone.info);
    if (success == false) return OvaHint(error ?? 'Fingerprint didn\'t match. Try again.', OvaHintTone.error);
    return const OvaHint('Touch the sensor to continue.');
  }

  /// +254712345678 -> +254 ••• •• 678
  static String maskPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.length < 6) return phone;
    return '${d.substring(0, d.startsWith('+') ? 4 : 3)} ••• •• ${d.substring(d.length - 3)}';
  }
}
