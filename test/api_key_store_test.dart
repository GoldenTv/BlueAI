import 'package:blue_app/src/api_key_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class DiscardingStorage extends FlutterSecureStorage {
  const DiscardingStorage();

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test(
    'secure storage adapter writes, reads back, and deletes credentials',
    () async {
      const ApiKeyStore store = ApiKeyStore();
      await store.write('test-key');
      expect(await store.read(), 'test-key');
      await store.write('');
      expect(await store.read(), isNull);
    },
  );

  test('silent platform write failure is detected before migration can delete the old key', () async {
    const ApiKeyStore store = ApiKeyStore(storage: DiscardingStorage());
    await expectLater(store.write('test-key'), throwsStateError);
  });
}
