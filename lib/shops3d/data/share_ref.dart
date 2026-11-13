import 'package:cloud_functions/cloud_functions.dart';

/// The tracked share link that brought this person into a shop.
///
/// A link (`https://oneova.web.app/s/{code}`) opens the app with `?ref=code`.
/// The code is kept for a day and sent with the next checkout, so the sharer
/// and the seller see the whole path: clicks → opened → checkouts → orders.
class ShareRef {
  ShareRef._();

  static String? _code;
  static DateTime? _at;

  /// Remembers [code] and tells the server the link was opened in the app.
  static void note(String? code) {
    if (code == null || !RegExp(r'^[a-z0-9]{10}$').hasMatch(code) || code == _code) return;
    _code = code;
    _at = DateTime.now();
    FirebaseFunctions.instance.httpsCallable('shareLinkEvent').call({'code': code}).ignore();
  }

  /// The code to credit a checkout to, or null.
  static String? get current {
    final at = _at;
    if (_code == null || at == null || DateTime.now().difference(at) > const Duration(hours: 24)) return null;
    return _code;
  }

  /// A tracked link for a product or shop; [fallback] when it can't be made.
  static Future<String> linkFor(String type, String targetId, {required String fallback}) async {
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('shareLinkCreate', options: HttpsCallableOptions(timeout: const Duration(seconds: 12)))
          .call({'type': type, 'targetId': targetId});
      final url = (r.data as Map?)?['url'];
      return url is String && url.startsWith('https://') ? url : fallback;
    } catch (_) {
      return fallback;
    }
  }
}
