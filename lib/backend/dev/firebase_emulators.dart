import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Dev/test only: point Auth, Firestore and Functions at the local Firebase
/// emulators. Enabled with `--dart-define=USE_EMULATORS=<host>`, e.g.
/// `127.0.0.1` with `adb reverse` port tunnels (tools/livekit/README.md).
/// Normal builds leave this empty and never touch the emulators.
const String kEmulatorHost = String.fromEnvironment('USE_EMULATORS');

bool get usingFirebaseEmulators => kEmulatorHost.isNotEmpty;

/// Call once, right after `Firebase.initializeApp`, before any other
/// Firebase use.
Future<void> connectFirebaseEmulatorsIfRequested() async {
  if (!usingFirebaseEmulators) return;
  try {
    await FirebaseAuth.instance.useAuthEmulator(kEmulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(kEmulatorHost, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(kEmulatorHost, 5001);
    debugPrint('[Emulators] Auth/Firestore/Functions → $kEmulatorHost');
  } catch (e) {
    debugPrint('[Emulators] could not connect: $e');
  }
}
