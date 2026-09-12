import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials are kept outside the application's ordinary preferences.
class ApiKeyStore {
  const ApiKeyStore({this.storage = const FlutterSecureStorage(), this.userId});

  static const key = 'blueai_api_key';
  final FlutterSecureStorage storage;
  final String? userId;
  String get storageKey => userId == null ? key : '${key}_$userId';

  Future<String?> read() => storage.read(key: storageKey);

  Future<void> write(String value) async {
    if (value.isEmpty) {
      await storage.delete(key: storageKey);
    } else {
      await storage.write(key: storageKey, value: value);
    }
    if (await read() != (value.isEmpty ? null : value)) {
      throw StateError('Secure credential storage verification failed');
    }
  }
}
