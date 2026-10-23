import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/security/studio_e2ee_session.dart';
import 'package:oneova/backend/live_studio/security/studio_security_models.dart';

StudioMediaKey key(int index, [int fill = 1]) => StudioMediaKey(Uint8List(32)..fillRange(0, 32, fill), index);

void main() {
  late List<String> log;
  late StudioMediaKey? serverKey;
  late StudioE2eeSession s;

  setUp(() {
    log = [];
    serverKey = key(1, 2);
    s = StudioE2eeSession(
      fetchKey: () async {
        log.add('fetch');
        return serverKey;
      },
      installKey: (k) async => log.add('install:${k.keyIndex}'),
      useIndex: (i) async => log.add('use:$i'),
      switchDelay: const Duration(milliseconds: 80),
    );
  });

  test('start installs the key and uses its index', () async {
    expect(s.active, isFalse);
    await s.start(key(0));
    expect(log, ['install:0', 'use:0']);
    expect(s.currentIndex, 0);
    await s.reapply();
    expect(log.last, 'use:0');
  });

  test('key.update: fetch, install, then switch senders after the delay', () async {
    await s.start(key(0));
    log.clear();
    final done = s.onKeyUpdate(1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(log, ['fetch', 'install:1']); // receivers can already decrypt index 1
    expect(await done, isTrue);
    expect(log.last, 'use:1');
    expect(s.currentIndex, 1);
  });

  test('same index, inactive session, or E2EE turned off: no change', () async {
    expect(await s.onKeyUpdate(1), isFalse); // not started
    await s.start(key(1));
    log.clear();
    expect(await s.onKeyUpdate(1), isFalse);
    expect(log, isEmpty);
    serverKey = null;
    expect(await s.onKeyUpdate(2), isFalse);
    expect(log, ['fetch']);
    expect(s.currentIndex, 1);
  });

  test('fetch failure keeps the old key', () async {
    final failing = StudioE2eeSession(
      fetchKey: () async => throw StateError('offline'),
      installKey: (k) async => log.add('install:${k.keyIndex}'),
      useIndex: (i) async => log.add('use:$i'),
      switchDelay: Duration.zero,
    );
    await failing.start(key(0));
    expect(await failing.onKeyUpdate(1), isFalse);
    expect(failing.currentIndex, 0);
  });
}
