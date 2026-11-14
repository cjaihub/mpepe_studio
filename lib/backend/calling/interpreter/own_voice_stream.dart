import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../voice/my_voice_service.dart';

/// The call's link to Oneova's voice server: my translated words come back in
/// my own voice (services/voice, /v1/stream). Opened only when My voice is set
/// up and the server is on; the token is short-lived and bound to my account,
/// so the server can only ever speak in my voice.
class OwnVoiceStream {
  OwnVoiceStream._(this._ws, this.onAudio, this.onBroken) {
    _sub = _ws.listen(_onData, onError: (_) => _broken(), onDone: _broken, cancelOnError: true);
  }

  final WebSocket _ws;
  final void Function(String lang, Uint8List pcm24k) onAudio;
  final VoidCallback onBroken;
  StreamSubscription? _sub;
  int _next = 1;
  final Map<int, String> _langOf = {};
  bool _closed = false;

  /// Null when My voice isn't ready or the server can't be reached.
  static Future<OwnVoiceStream?> open({
    required String callId,
    required void Function(String lang, Uint8List pcm24k) onAudio,
    required VoidCallback onBroken,
  }) async {
    try {
      final s = await MyVoiceService.instance.status();
      if (!s.available || !s.ready) return null;
      final t = await MyVoiceService.instance.streamToken(callId);
      final uri = Uri.parse(t.url).replace(queryParameters: {'token': t.token});
      final ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 8));
      ws.pingInterval = const Duration(seconds: 15);
      return OwnVoiceStream._(ws, onAudio, onBroken);
    } catch (e) {
      debugPrint('[OwnVoice] not available: $e');
      return null;
    }
  }

  /// Speak [text] (a translated phrase) in my voice, in [lang].
  void say(String text, String lang) {
    if (_closed || text.trim().isEmpty) return;
    final id = _next++;
    _langOf[id] = lang;
    _ws.add(jsonEncode({'t': 'say', 'id': id, 'text': text, 'lang': lang}));
  }

  /// Turn speech in another voice (24 kHz PCM16) into my voice.
  void convert(Uint8List pcm24k, String lang) {
    if (_closed || pcm24k.isEmpty) return;
    final id = _next++;
    _langOf[id] = lang;
    _ws.add(jsonEncode({'t': 'convert', 'id': id, 'sr': 24000}));
    _ws.add(pcm24k);
    _ws.add(jsonEncode({'t': 'end', 'id': id}));
  }

  void _onData(dynamic data) {
    if (data is List<int>) {
      final b = data is Uint8List ? data : Uint8List.fromList(data);
      if (b.length < 7 || b[0] != 0x01) return;
      final id = ByteData.sublistView(b, 1, 5).getUint32(0);
      final lang = _langOf[id];
      if (lang != null) onAudio(lang, Uint8List.sublistView(b, 5));
    } else if (data is String && data.contains('"error"')) {
      _broken();
    } else if (data is String) {
      try {
        final m = jsonDecode(data);
        if (m is Map && m['t'] == 'done') _langOf.remove(m['id']);
      } catch (_) {}
    }
  }

  void _broken() {
    if (_closed) return;
    _closed = true;
    onBroken();
  }

  Future<void> close() async {
    _closed = true;
    await _sub?.cancel();
    try {
      await _ws.close();
    } catch (_) {}
  }
}
