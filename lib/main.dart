import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth_session.dart';

import 'app.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  SupabaseClient? client;
  String? error;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      final host = Uri.parse(url).host;
      await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: SecureSessionStorage(host),
          pkceAsyncStorage: SecurePkceStorage(host),
        ),
      );
      client = Supabase.instance.client;
    } catch (_) {
      error = 'เริ่มระบบบัญชีไม่สำเร็จ ตรวจการตั้งค่าและการเชื่อมต่อ แล้วเปิดแอปใหม่';
    }
  }
  runApp(BlueApp(supabaseClient: client, configurationError: error));
}
