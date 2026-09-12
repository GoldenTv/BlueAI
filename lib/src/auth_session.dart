import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage(this.namespace);
  final String namespace;
  static const storage = FlutterSecureStorage();
  String get key => 'blueai_session_$namespace';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() => storage.read(key: key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => storage.delete(key: key);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage(this.namespace);
  final String namespace;
  static const storage = FlutterSecureStorage();
  @override
  Future<String?> getItem({required String key}) =>
      storage.read(key: 'blueai_pkce_${namespace}_$key');
  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.write(key: 'blueai_pkce_${namespace}_$key', value: value);
  @override
  Future<void> removeItem({required String key}) =>
      storage.delete(key: 'blueai_pkce_${namespace}_$key');
}

Future<String> sessionToken(SupabaseClient client) async {
  var session = client.auth.currentSession;
  if (session == null) throw const AuthException('กรุณาเข้าสู่ระบบ');
  if (session.isExpired) session = (await client.auth.refreshSession()).session;
  if (session == null) throw const AuthException('กรุณาเข้าสู่ระบบอีกครั้ง');
  return session.accessToken;
}
