import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// "Is there an Oneova account for this phone / e-mail?" without reading
/// other people's profiles: the `accountLookup` Cloud Function answers with
/// only the sign-in header fields (name, handle, photo, password flags).
///
/// Until that function is deployed (or if it is unreachable) this falls back
/// to the profile query, so sign-in keeps working on every backend.
class AccountLookupService {
  AccountLookupService._();

  /// The profile fields the sign-in screens use, with `uid`, or null.
  static Future<Map<String, dynamic>?> byPhone(String e164) =>
      _lookup({'phone': e164}, () => _legacyQuery(['phoneNumber', 'phone'], _phoneVariants(e164)));

  static Future<Map<String, dynamic>?> byEmail(String email) {
    final e = email.trim().toLowerCase();
    return _lookup({'email': e}, () => _legacyQuery(['email'], [e]));
  }

  static Future<Map<String, dynamic>?> _lookup(
    Map<String, dynamic> data,
    Future<Map<String, dynamic>?> Function() fallback,
  ) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('accountLookup', options: HttpsCallableOptions(timeout: const Duration(seconds: 8)))
          .call<Map<String, dynamic>>(data);
      final m = Map<String, dynamic>.from(res.data);
      return m['found'] == true ? m : null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unavailable' || e.code == 'internal' || e.code == 'unimplemented') {
        return fallback();
      }
      rethrow;
    } catch (e) {
      debugPrint('[AccountLookup] $e');
      return fallback();
    }
  }

  static List<String> _phoneVariants(String e164) => [
        e164,
        if (e164.startsWith('+254')) '0${e164.substring(4)}',
        if (e164.startsWith('+')) e164.substring(1),
      ];

  static Future<Map<String, dynamic>?> _legacyQuery(List<String> fields, List<String> values) async {
    final users = FirebaseFirestore.instance.collection('users');
    for (final v in values) {
      for (final f in fields) {
        try {
          final q = await users.where(f, isEqualTo: v).limit(1).get();
          if (q.docs.isNotEmpty) return {...q.docs.first.data(), 'uid': q.docs.first.id};
        } catch (e) {
          debugPrint('[AccountLookup] fallback $f: $e');
        }
      }
    }
    return null;
  }
}
