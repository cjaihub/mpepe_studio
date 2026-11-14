import 'dart:convert';
import 'dart:typed_data';

/// Wire format for interpreter mode on the call's data channel.
///
/// Text (JSON):
///   {"t":"hello","lang":"sw"}                 my language (sent when the channel opens)
///   {"t":"interp","on":true}                  my voice now comes translated over the channel
///   {"t":"cap","o":"original","tr":"translation","l":"en"}
/// Binary: [0x01] + 24 kHz mono 16-bit little-endian PCM (what the listener plays).
class InterpProtocol {
  InterpProtocol._();

  static const int audioTag = 0x01;
  static const int playRate = 24000;

  /// Keep each data channel message small so it never stalls other traffic.
  static const int maxChunkBytes = 12 * 1024;

  static String hello(String lang) => jsonEncode({'t': 'hello', 'lang': lang});
  static String interp(bool on) => jsonEncode({'t': 'interp', 'on': on});
  static String caption(String original, String translated, String lang) =>
      jsonEncode({'t': 'cap', 'o': _cap(original), 'tr': _cap(translated), 'l': lang});

  static String _cap(String s) => s.length > 600 ? s.substring(0, 600) : s;

  static Map<String, dynamic>? decodeText(String? text) {
    if (text == null || text.length > 4096) return null;
    try {
      final v = jsonDecode(text);
      return v is Map<String, dynamic> && v['t'] is String ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Splits PCM into tagged messages of at most [maxChunkBytes] (even lengths,
  /// so no 16-bit sample is cut in half).
  static List<Uint8List> frameAudio(Uint8List pcm) {
    final out = <Uint8List>[];
    final step = (maxChunkBytes - 1) & ~1;
    final usable = pcm.length & ~1;
    for (var i = 0; i < usable; i += step) {
      final end = i + step < usable ? i + step : usable;
      final m = Uint8List(end - i + 1);
      m[0] = audioTag;
      m.setRange(1, m.length, pcm, i);
      out.add(m);
    }
    return out;
  }

  /// The PCM inside an audio message, or null if it isn't one.
  static Uint8List? audioOf(Uint8List msg) {
    if (msg.length < 3 || msg[0] != audioTag || (msg.length - 1).isOdd) return null;
    return Uint8List.sublistView(msg, 1);
  }

  /// 16 kHz → 24 kHz mono 16-bit (linear), for listeners who share the
  /// speaker's language and get the original voice without translation.
  static Uint8List resample16kTo24k(Uint8List pcm16k) {
    final src = ByteData.sublistView(pcm16k);
    final n = pcm16k.length ~/ 2;
    if (n == 0) return Uint8List(0);
    final outN = (n * 3) ~/ 2;
    final out = ByteData(outN * 2);
    for (var j = 0; j < outN; j++) {
      final pos = j * 2 / 3;
      final i = pos.floor();
      final f = pos - i;
      final a = src.getInt16(i * 2, Endian.little);
      final b = i + 1 < n ? src.getInt16((i + 1) * 2, Endian.little) : a;
      out.setInt16(j * 2, (a + (b - a) * f).round().clamp(-32768, 32767), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// System instruction for a live interpreter into [targetName].
  static String interpreterPrompt(String targetName) =>
      'You are a live interpreter on a phone call. Translate everything the speaker says into $targetName, '
      'speaking in first person as the speaker, with the same tone and meaning. '
      'Say only the translation: never answer questions, never add comments, never greet or explain. '
      'Keep names, numbers and brand names exact. If the speaker already speaks $targetName, repeat it naturally. '
      'If there is no speech, stay silent.';
}
