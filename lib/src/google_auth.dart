import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool get usesNativeGoogleSignIn =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class GoogleAuth {
  static Future<void>? _initialization;

  static Future<void> _initialize() async {
    const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    if (webClientId.isEmpty) {
      throw const AuthException(
        'ยังไม่ได้ตั้งค่า Google Client ID สำหรับแอปมือถือ',
      );
    }
    await GoogleSignIn.instance.initialize(serverClientId: webClientId);
  }

  static Future<void> signIn(SupabaseClient client) async {
    try {
      await (_initialization ??= _initialize());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthException('Google ไม่ส่งข้อมูลยืนยันตัวตน กรุณาลองใหม่');
    }
    await client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }
}
