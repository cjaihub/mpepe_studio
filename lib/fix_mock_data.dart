
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  await Firebase.initializeApp();
  final firestore = FirebaseFirestore.instance;
  final docs = await firestore.collection('content').get();
  for (var doc in docs.docs) {
    if (doc.data().containsKey('likeCount') || doc.data().containsKey('commentCount')) {
      await doc.reference.update({
        'likeCount': 0,
        'commentCount': 0,
        'saveCount': 0,
        'repostCount': 0,
        'viewCount': 0,
      });
    }
  }
  print("Mock data reset to 0");
}
