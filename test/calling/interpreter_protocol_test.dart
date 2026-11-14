import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/calling/interpreter/interpreter_protocol.dart';

void main() {
  test('audio is split into small tagged chunks and read back whole', () {
    final pcm = Uint8List.fromList(List.generate(30001, (i) => i % 251));
    final frames = InterpProtocol.frameAudio(pcm);
    expect(frames.every((f) => f.length <= InterpProtocol.maxChunkBytes && f[0] == InterpProtocol.audioTag), isTrue);
    final joined = <int>[for (final f in frames) ...InterpProtocol.audioOf(f)!];
    expect(joined, pcm.sublist(0, 30000)); // the odd last byte is dropped
  });

  test('non-audio and malformed messages are refused', () {
    expect(InterpProtocol.audioOf(Uint8List.fromList([0x02, 1, 2])), isNull);
    expect(InterpProtocol.audioOf(Uint8List.fromList([0x01, 1])), isNull);
    expect(InterpProtocol.decodeText('not json'), isNull);
    expect(InterpProtocol.decodeText('{"x":1}'), isNull);
    expect(InterpProtocol.decodeText(InterpProtocol.hello('sw'))!['lang'], 'sw');
  });

  test('16 kHz to 24 kHz keeps length ratio and endpoints', () {
    final b = ByteData(8);
    for (var i = 0; i < 4; i++) {
      b.setInt16(i * 2, i * 1000, Endian.little);
    }
    final out = ByteData.sublistView(InterpProtocol.resample16kTo24k(b.buffer.asUint8List()));
    expect(out.lengthInBytes, 12);
    expect(out.getInt16(0, Endian.little), 0);
    expect(out.getInt16(6, Endian.little), 2000); // sample 3 of 6 ↔ input sample 2
  });

  test('captions are capped', () {
    final c = InterpProtocol.decodeText(InterpProtocol.caption('a' * 900, 'b', 'en'))!;
    expect((c['o'] as String).length, 600);
  });
}
