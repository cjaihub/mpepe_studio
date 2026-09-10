import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> makeUserAdminByEmail(String email) async {
  final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: email).get();
  for (var doc in query.docs) {
    await doc.reference.update({'role': 'Admin', 'status': 'active'});
    print('Updated ${doc.id} to Admin');
  }
}
