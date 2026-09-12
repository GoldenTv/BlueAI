import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/auth_gate.dart';

import 'src/blue_ai_theme.dart';
import 'src/chat_controller.dart';
import 'src/chat_page.dart';

class BlueApp extends StatefulWidget {
  const BlueApp({
    this.controller,
    this.supabaseClient,
    this.configurationError,
    super.key,
  });

  final ChatController? controller;
  final SupabaseClient? supabaseClient;
  final String? configurationError;

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: BlueAiPalette.accentDeep,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: BlueAiPalette.lightText,
      secondary: BlueAiPalette.lightTextSecondary,
      secondaryContainer: BlueAiPalette.lightTint,
      onSecondaryContainer: BlueAiPalette.lightText,
      surfaceTint: Colors.transparent,
      outline: BlueAiPalette.lightBorder,
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: BlueAiPalette.lightBorder),
      ),
      color: Colors.white,
    ),
    dividerTheme: const DividerThemeData(
      color: BlueAiPalette.lightBorder,
      thickness: 1,
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: BlueAiPalette.accent,
      onPrimary: Colors.white,
      surface: BlueAiPalette.darkSurface,
      onSurface: BlueAiPalette.darkText,
      secondary: BlueAiPalette.darkTextSecondary,
      secondaryContainer: BlueAiPalette.darkTint,
      onSecondaryContainer: BlueAiPalette.darkText,
      surfaceTint: Colors.transparent,
      outline: BlueAiPalette.darkBorder,
    ),
    scaffoldBackgroundColor: BlueAiPalette.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: BlueAiPalette.darkBorder),
      ),
      color: BlueAiPalette.darkSurface,
    ),
    dividerTheme: const DividerThemeData(
      color: BlueAiPalette.darkBorder,
      thickness: 1,
    ),
  );

  /// เก็บ compatibility สำหรับโค้ดที่อ้างอิง BlueApp.theme เดิม
  static ThemeData get theme => lightTheme;

  @override
  State<BlueApp> createState() => _BlueAppState();
}

class _BlueAppState extends State<BlueApp> {
  late final ChatController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = ChatController();
      _ownsController = true;
      // Production credentials are loaded only inside the authenticated account.
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _controller.themeModeNotifier,
      builder:
          (BuildContext context, ThemeMode currentThemeMode, Widget? child) {
            return MaterialApp(
              title: 'BlueAI',
              debugShowCheckedModeBanner: false,
              theme: BlueApp.lightTheme,
              darkTheme: BlueApp.darkTheme,
              themeMode: currentThemeMode,
              home: widget.controller != null
                  ? ChatPage(controller: _controller)
                  : widget.supabaseClient != null
                  ? AuthGate(client: widget.supabaseClient!)
                  : MissingConfigurationScreen(error: widget.configurationError),
            );
          },
    );
  }
}
