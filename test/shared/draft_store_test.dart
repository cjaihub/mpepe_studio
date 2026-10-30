import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oneova/shared/services/draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DraftStore.instance.init();
  });

  tearDown(() async {
    await DraftStore.instance.clearDraft('test_key');
  });

  test('DraftStore saves and reads draft immediately in memory', () {
    final store = DraftStore.instance;
    expect(store.hasDraft('test_key'), isFalse);

    store.setDraft('test_key', 'Hello Oneova draft');
    expect(store.hasDraft('test_key'), isTrue);
    expect(store.getDraft('test_key'), equals('Hello Oneova draft'));
  });

  test('DraftStore clears draft properly', () async {
    final store = DraftStore.instance;
    store.setDraft('test_key', 'Temporary text');
    expect(store.hasDraft('test_key'), isTrue);

    await store.clearDraft('test_key');
    expect(store.hasDraft('test_key'), isFalse);
    expect(store.getDraft('test_key'), isNull);
  });

  test('DraftStore flushes pending debounce writes to storage', () async {
    final store = DraftStore.instance;
    store.setDraft('chat_123', 'In-flight message draft');
    await store.flush();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('oneova_draft_chat_123'), isTrue);
    await store.clearDraft('chat_123');
  });
}
