import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/money/money_models.dart';
import '../backend/money/money_service.dart' show kycProvider;

/// Oneova ID: the person's and the business's verified identity.
///
/// The verification itself is the payments KYC (`kyc/{uid}`, screen
/// `/wallet/verify`). Everything here is read-only from Firestore; changes go
/// through Cloud Functions (`functions/src/identity`).

final _db = FirebaseFirestore.instance;
String? get _uid => FirebaseAuth.instance.currentUser?.uid;

/// Level shown on the profile: 0 account, 1 contact verified, 2 ID verified.
class IdentityState {
  const IdentityState({
    required this.kyc,
    this.level = 0,
    this.credentialId,
    this.credentialExpiresAt,
    this.contactVerified = false,
  });
  final KycState kyc;
  final int level;
  final String? credentialId;
  final DateTime? credentialExpiresAt;
  final bool contactVerified;

  bool get verified => kyc.status == 'verified';
  int get shownLevel => verified ? 2 : (contactVerified ? 1 : 0);
}

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

final _identityDocProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const {});
  return _db.doc('identity/$uid').snapshots().map((d) => d.data() ?? const {});
});

final identityProvider = Provider<IdentityState>((ref) {
  final kyc = ref.watch(kycProvider).value ?? const KycState();
  final doc = ref.watch(_identityDocProvider).value ?? const {};
  final user = FirebaseAuth.instance.currentUser;
  final contact = (user?.emailVerified ?? false) || (user?.phoneNumber?.isNotEmpty ?? false);
  return IdentityState(
    kyc: kyc,
    level: (doc['level'] as num?)?.toInt() ?? 0,
    credentialId: doc['credentialId'] as String?,
    credentialExpiresAt: _date(doc['credentialExpiresAt']),
    contactVerified: contact,
  );
});

class BusinessIdentity {
  const BusinessIdentity(this.data);
  final Map<String, dynamic> data;
  String get status => (data['status'] as String?) ?? 'none';
  int get level => (data['level'] as num?)?.toInt() ?? 0;
  String get legalName => (data['legalName'] as String?) ?? '';
  String get country => (data['country'] as String?) ?? '';
  String get businessType => (data['businessType'] as String?) ?? '';
  String? get sessionId => data['sessionId'] as String?;
  String? get rejectReason => (data['rejectReason'] ?? data['expiredReason']) as String?;
  String get registrationNumber => (data['registrationNumber'] as String?) ?? '';
  String get taxIdLast4 => (data['taxIdLast4'] as String?) ?? '';
  DateTime? get expiresAt => _date(data['expiresAt']);
  bool get verified => status == 'verified';
}

final businessIdentityProvider = StreamProvider<BusinessIdentity>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const BusinessIdentity({}));
  return _db.doc('business_identity/$uid').snapshots().map((d) => BusinessIdentity(d.data() ?? const {}));
});

final businessOwnersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db.collection('business_identity/$uid/owners').snapshots().map((s) => s.docs.map((d) => d.data()).toList());
});

/// Businesses that listed me as an owner and wait for my answer.
final ownerInvitesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('identity/$uid/ownerInvites')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());
});

final identityAuditProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('identity/$uid/audit')
      .orderBy('at', descending: true)
      .limit(60)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());
});

final activeSharesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('identity/$uid/shares')
      .where('revokedAt', isNull: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((m) => (_date(m['expiresAt']) ?? DateTime(0)).isAfter(DateTime.now()))
          .toList());
});

class KybRequirements {
  KybRequirements(this.raw);
  final Map<String, dynamic> raw;
  String get registry => '${raw['registry'] ?? ''}';
  Map<String, dynamic> get registrationNumber => Map<String, dynamic>.from(raw['registrationNumber'] as Map);
  Map<String, dynamic> get taxId => Map<String, dynamic>.from(raw['taxId'] as Map);
  int get ownershipThreshold => (raw['ownershipThreshold'] as num?)?.toInt() ?? 25;
  List<Map<String, dynamic>> get documents =>
      (raw['documents'] as List? ?? const []).map((d) => Map<String, dynamic>.from(d as Map)).toList();

  static bool fieldOk(Map<String, dynamic> f, String v) {
    if (v.isEmpty) return f['required'] != true;
    try {
      return RegExp('${f['pattern']}', caseSensitive: false).hasMatch(v);
    } catch (_) {
      return v.length >= 3;
    }
  }
}

class IdShareLink {
  IdShareLink(this.shareId, this.url, this.expiresAt);
  final String shareId;
  final String url;
  final DateTime expiresAt;
}

final identityServiceProvider = Provider((ref) => IdentityService());

class IdentityService {
  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final res = await FirebaseFunctions.instance.httpsCallable(name).call(data ?? const {});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// A fresh signed credential; the caller keeps it in [IdentityVault].
  Future<({String id, String token, DateTime expiresAt})> fetchCredential({String kind = 'person'}) async {
    final r = await _call('idCredential', {'kind': kind});
    return (id: '${r['id']}', token: '${r['token']}', expiresAt: DateTime.parse('${r['expiresAt']}'));
  }

  Future<IdShareLink> share({required String kind, required List<String> fields, required int minutes}) async {
    final r = await _call('idShare', {'kind': kind, 'fields': fields, 'minutes': minutes});
    return IdShareLink('${r['shareId']}', '${r['url']}', DateTime.parse('${r['expiresAt']}'));
  }

  Future<void> stopShare(String shareId) => _call('idShareRevoke', {'shareId': shareId});

  Future<void> deletePersonal() => _call('kycDelete', {'confirm': true});

  Future<KybRequirements> requirements(String country, String businessType) async =>
      KybRequirements(await _call('kybRequirements', {'country': country, 'businessType': businessType}));

  Future<({String status, String? sessionId, String? path, KybRequirements? requirements})> startBusiness(
      String country, String businessType) async {
    final r = await _call('kybStart', {'country': country, 'businessType': businessType});
    return (
      status: '${r['status']}',
      sessionId: r['sessionId'] as String?,
      path: r['path'] as String?,
      requirements: r['requirements'] is Map ? KybRequirements(Map<String, dynamic>.from(r['requirements'] as Map)) : null,
    );
  }

  Future<void> submitBusiness(Map<String, dynamic> data) => _call('kybSubmit', data);

  Future<void> respondOwner(String bizUid, bool accept) => _call('kybOwnerRespond', {'bizUid': bizUid, 'accept': accept});

  Future<void> deleteBusiness() => _call('kybDelete', {'confirm': true});
}

String identityError(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? 'Something went wrong. Please try again.';
  return 'Something went wrong. Please try again.';
}
