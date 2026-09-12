import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_key_store.dart';
import 'auth_session.dart';
import 'google_auth.dart';
import 'chat_controller.dart';
import 'chat_page.dart';
import 'cloud_chat_controller.dart';
import 'cloud_repository.dart';
import '../app.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({required this.client, super.key});
  final SupabaseClient client;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _auth;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = widget.client.auth.onAuthStateChange.listen(
      (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = null;
          });
        }
      },
      onError: (Object _) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่';
          });
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!usesNativeGoogleSignIn &&
        state == AppLifecycleState.resumed &&
        mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_auth?.cancel());
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (usesNativeGoogleSignIn) {
        await GoogleAuth.signIn(widget.client);
        return;
      }
      final launched = await widget.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? Uri.base.origin : 'blueai://auth/callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(() => _error = 'เปิดหน้าเข้าสู่ระบบไม่สำเร็จ');
      }
    } on GoogleSignInException catch (error) {
      if (mounted && error.code != GoogleSignInExceptionCode.canceled) {
        setState(
          () => _error =
              error.code == GoogleSignInExceptionCode.clientConfigurationError
              ? 'การตั้งค่า Google Sign-In ไม่ถูกต้อง ตรวจ Client ID และ SHA ของแอป'
              : 'เข้าสู่ระบบ Google ไม่สำเร็จ กรุณาลองใหม่',
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'เข้าสู่ระบบไม่สำเร็จ ตรวจการเชื่อมต่อแล้วลองใหม่',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.client.auth.currentUser;
    if (user != null) {
      return AccountChat(
        key: ValueKey(user.id),
        client: widget.client,
        user: user,
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 54),
                  const SizedBox(height: 24),
                  Text(
                    'ยินดีต้อนรับสู่ BlueAI',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'เข้าสู่ระบบเพื่อบันทึกบทสนทนาและใช้งานต่อบนอุปกรณ์อื่น',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _busy ? null : _login,
                    icon: const Icon(Icons.login),
                    label: Text(
                      _busy ? 'กำลังเข้าสู่ระบบ…' : 'เข้าสู่ระบบด้วย Google',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccountChat extends StatefulWidget {
  const AccountChat({required this.client, required this.user, super.key});
  final SupabaseClient client;
  final User user;
  @override
  State<AccountChat> createState() => _AccountChatState();
}

class _AccountChatState extends State<AccountChat> with WidgetsBindingObserver {
  late final CloudChatController _controller;
  bool _signingOut = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CloudChatController(
      repository: SupabaseChatRepository(widget.client, widget.user.id),
      tokenProvider: () => sessionToken(widget.client),
      keyStore: ApiKeyStore(userId: widget.user.id),
      onAuthExpired: () => unawaited(_signOut()),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _controller.init();
    if (!mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      const legacy = ApiKeyStore();
      final old =
          await legacy.read() ?? prefs.getString(ChatController.keyApiKey);
      final decisionKey = 'blueai_legacy_key_decided_${widget.user.id}';
      if (old == null ||
          old.isEmpty ||
          prefs.getBool(decisionKey) == true ||
          _controller.apiKey.isNotEmpty ||
          !mounted) {
        return;
      }
      final use = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('พบ API Key เดิมในเครื่อง'),
          content: Text(
            'ใช้ API Key เดิมกับบัญชี ${widget.user.email ?? ''} หรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ไม่ใช้'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ใช้กับบัญชีนี้'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (use == true) {
        await _controller.setApiKey(old);
        await legacy.write('');
        if (prefs.containsKey(ChatController.keyApiKey) &&
            !await prefs.remove(ChatController.keyApiKey)) {
          throw StateError('Migration failed');
        }
      }
      await prefs.setBool(decisionKey, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ย้าย API Key ไม่สำเร็จ สำเนาเดิมยังอยู่ กรุณาตั้งค่าอีกครั้ง',
            ),
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await _controller.stopAndSave();
    try {
      await widget.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ออกจากระบบไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _signingOut
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : ValueListenableBuilder<ThemeMode>(
          valueListenable: _controller.themeModeNotifier,
          builder: (context, mode, _) => Theme(
            data:
                (mode == ThemeMode.dark ||
                    mode == ThemeMode.system &&
                        MediaQuery.platformBrightnessOf(context) ==
                            Brightness.dark)
                ? BlueApp.darkTheme
                : BlueApp.lightTheme,
            child: ChatPage(
              controller: _controller,
              accountEmail: widget.user.email,
              onSignOut: _signOut,
            ),
          ),
        );
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({this.error, super.key});
  final String? error;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            error ?? 'ยังไม่ได้เชื่อมต่อระบบบัญชี BlueAI\nตั้งค่า SUPABASE_URL และ SUPABASE_PUBLISHABLE_KEY แล้วเปิดแอปใหม่',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
