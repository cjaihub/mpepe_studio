// LIVE STUDIO v2 — data packet decoding (pure).

import 'dart:convert';

import '../contracts/studio_contracts.dart';

/// Decodes one LiveKit data packet into a [StudioEvent].
///
/// Returns null for packets that must be ignored:
/// - sent by a participant ([fromParticipant] true). Only the server sends
///   data (`canPublishData` is false for everyone), so anything else is
///   spoofed;
/// - with no topic, or a body that is not a JSON object.
StudioEvent? decodeStudioPacket(List<int> data, {String? topic, bool fromParticipant = false}) {
  if (fromParticipant || topic == null || topic.isEmpty) return null;
  try {
    final j = jsonDecode(utf8.decode(data));
    if (j is! Map) return null;
    return StudioEvent.decode(topic, Map<String, dynamic>.from(j));
  } on FormatException {
    return null;
  }
}
