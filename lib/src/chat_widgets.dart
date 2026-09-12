import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'blueai_theme.dart';
import 'chat_controller.dart';

/// ปุ่มไอคอนสี่เหลี่ยมมุมมน (Squircle) สำหรับแถบด้านบน — เส้นขอบบาง + พื้นแบรนด์
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    this.selected = false,
    super.key,
  });

  final IconData? icon;
  final Widget? child;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = selected
        ? BlueAIPalette.tint(isDark)
        : Colors.transparent;
    final Color iconColor = BlueAIPalette.text(isDark);
    final BorderRadius borderRadius = BorderRadius.circular(13);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide.none,
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: borderRadius),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: child ?? Icon(icon, size: 20, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar ไอคอนสัญลักษณ์ BlueAI แบบโมเดิร์น
class AiAvatar extends StatelessWidget {
  const AiAvatar({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: Icon(
        Icons.chat_bubble_outline_rounded,
        size: size * 0.7,
        color: BlueAIPalette.textSecondary(isDark),
      ),
    );
  }
}

/// หน้าจอเริ่มต้น (Empty / Welcome Screen) เมื่อยังไม่มีบทสนทนา
class WelcomeView extends StatelessWidget {
  const WelcomeView({required this.onPromptSelected, super.key});

  final ValueChanged<String> onPromptSelected;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    const List<_QuickPromptData> prompts = <_QuickPromptData>[
      _QuickPromptData(
        icon: Icons.lightbulb_outline_rounded,
        title: 'ระดมความคิดและวางแผน',
        description: 'ช่วยวางแผนและออกแบบโปรเจกต์ AI ให้มีประสิทธิภาพ',
        prompt:
            'ช่วยวางแผนและระดมไอเดียการทำโปรเจกต์ AI สำหรับการศึกษาหน่อยครับ',
      ),
      _QuickPromptData(
        icon: Icons.code_rounded,
        title: 'เขียนโค้ดและดีบัก',
        description: 'สร้างฟังก์ชันและเชื่อมต่อ API ใน Flutter พร้อมตัวอย่าง',
        prompt: 'ช่วยเขียนฟังก์ชัน Flutter สำหรับเรียกใช้ REST API พร้อมจัดการ Error และ Loading ให้ดูหน่อย',
      ),
      _QuickPromptData(
        icon: Icons.functions_rounded,
        title: 'คณิตศาสตร์และสูตร',
        description: 'อธิบายทฤษฎีพร้อมเขียนสูตรในรูปแบบ LaTeX สวยงาม',
        prompt: 'ช่วยอธิบายสูตรสมการกำลังสอง Quadratic Formula และทฤษฎีบทพีทาโกรัสพร้อมสูตร LaTeX',
      ),
      _QuickPromptData(
        icon: Icons.article_outlined,
        title: 'สรุปบทความและข้อมูล',
        description: 'ย่อยข้อมูลสำคัญแบบเข้าใจง่าย มีสาระครบถ้วน',
        prompt: 'ช่วยสรุปข้อดีและข้อจำกัดของการใช้งาน Cloudflare Workers ในการทำ Backend Proxy',
      ),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'เริ่มบทสนทนา',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: BlueAIPalette.text(isDark),
                ),
              ),
              const SizedBox(height: 20),
              for (final prompt in prompts)
                TextButton(
                  onPressed: () => onPromptSelected(prompt.prompt),
                  style: TextButton.styleFrom(
                    foregroundColor: BlueAIPalette.textSecondary(isDark),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  child: Text(prompt.title, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPromptData {
  const _QuickPromptData({
    required this.icon,
    required this.title,
    required this.description,
    required this.prompt,
  });
  final IconData icon;
  final String title;
  final String description;
  final String prompt;
}

class MessageActionToolbar extends StatelessWidget {
  const MessageActionToolbar({
    required this.messageText,
    this.modelName,
    super.key,
  });

  final String messageText;
  final String? modelName;

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: messageText));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('คัดลอกข้อความลงคลิปบอร์ดแล้ว'),
          ],
        ),
        backgroundColor: const Color(0xFF27272A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SelectionContainer.disabled(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Row(
          children: <Widget>[
            if (modelName != null && modelName!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF27272A)
                      : const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF3F3F46)
                        : const Color(0xFFE4E4E7),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  modelName!.contains('/')
                      ? modelName!.split('/').last
                      : modelName!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : const Color(0xFF71717A),
                  ),
                ),
              ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16),
              tooltip: 'คัดลอกข้อความ',
              color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _copyToClipboard(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// เมนู Drawer แถบด้านข้าง สไตล์ทันสมัย
class ChatDrawer extends StatelessWidget {
  const ChatDrawer({
    required this.controller,
    required this.onNewChat,
    required this.onShowSettings,
    super.key,
  });

  final ChatController controller;
  final VoidCallback onNewChat;
  final VoidCallback onShowSettings;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      width: math.min(320, MediaQuery.sizeOf(context).width - 24),
      backgroundColor: isDark ? const Color(0xFF202023) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          child: ListView(
            children: <Widget>[
              // Header Brand
              Row(
                children: <Widget>[
                  const AiAvatar(size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'BlueAI',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFFAFAFA)
                                : const Color(0xFF18181B),
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          'AI Mobile Assistant',
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFA1A1AA)
                                : const Color(0xFF71717A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ปุ่ม New Chat โดดเด่น
              ElevatedButton.icon(
                onPressed: onNewChat,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('เริ่มการสนทนาใหม่'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Divider(height: 1),
              const SizedBox(height: 12),

              // ตัวเลือกสลับโหมด Dark / Light / System
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  controller.themeMode == ThemeMode.dark
                      ? Icons.dark_mode_rounded
                      : (controller.themeMode == ThemeMode.light
                            ? Icons.light_mode_rounded
                            : Icons.brightness_auto_rounded),
                  color: isDark
                      ? const Color(0xFFA1A1AA)
                      : const Color(0xFF52525B),
                ),
                title: Text(
                  'โหมดหน้าจอ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFFF4F4F5)
                        : const Color(0xFF27272A),
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF27272A)
                        : const Color(0xFFF4F4F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    switch (controller.themeMode) {
                      ThemeMode.light => 'สว่าง',
                      ThemeMode.dark => 'มืด',
                      ThemeMode.system => 'ระบบ',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFFA1A1AA)
                          : const Color(0xFF52525B),
                    ),
                  ),
                ),
                onTap: () => controller.toggleThemeMode(),
              ),

              // การตั้งค่าระบบ
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(
                  Icons.tune_rounded,
                  color: isDark
                      ? const Color(0xFFA1A1AA)
                      : const Color(0xFF52525B),
                ),
                title: Text(
                  'การตั้งค่าระบบและโมเดล',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFFF4F4F5)
                        : const Color(0xFF27272A),
                  ),
                ),
                onTap: onShowSettings,
              ),

              const SizedBox(height: 24),

              // ล้างแชต
              if (controller.messages.isNotEmpty)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444),
                  ),
                  title: const Text(
                    'ล้างบทสนทนาปัจจุบัน',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    controller.clearChat();
                  },
                ),

              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'BlueAI • มหาวิทยาลัยสงขลานครินทร์ (PSU)',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF71717A)
                        : const Color(0xFFA1A1AA),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Syntax Highlighter ถอดแบบสีตามตัวอย่างใน Image 2 อย่างแม่นยำ
class CodeSyntaxHighlighter {
  static final RegExp _tokenRegex = RegExp(
    r'(//.*)|' // 1: single-line comment
    r'("(?:\\.|[^"\\])*"|'
    r"'(?:\\.|[^'\\])*')|" // 2: string literals
    r'(#\s*(?:include|define|undef|ifdef|ifndef|if|elif|else|endif|error|pragma|import)\b)|' // 3: preprocessor
    r'(<[a-zA-Z0-9_\.\-\/]+>)|' // 4: header angle bracket
    r'(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?:f|u|l|ul|ll|ull)?\b)|' // 5: number
    r'(\b(?:using\s+namespace|using|namespace|return|for|while|do|if|else|switch|case|break|continue|default|goto|try|catch|throw|class|struct|enum|public|private|protected|template|typename|virtual|override|constexpr|const|static|inline|explicit|typedef|new|delete|import|export|from|as|async|await|fn|pub|mut|let|def|lambda)\b)|' // 6: keyword
    r'(\b(?:int|long|short|char|bool|float|double|void|auto|size_t|uint8_t|uint16_t|uint32_t|uint64_t|int8_t|int16_t|int32_t|int64_t|vector|string|map|set|unordered_map|unordered_set|pair|list|deque|queue|stack|unique_ptr|shared_ptr|String|Widget|BuildContext|List|Map|Set|Future|Stream|num)\b)|' // 7: type
    r'(\b(?:cout|cin|endl|cerr|printf|scanf|sort|reverse|max|min|push_back|emplace_back|size|length|empty|clear|begin|end|print|println)\b)|' // 8: builtin
    r'([a-zA-Z_][a-zA-Z0-9_]*)|' // 9: identifier
    r'(<<|>>|::|->|==|!=|<=|>=|&&|\|\||\+\+|--|\+=|-=|\*=|/=|[{}\(\)\[\];,\.\+\-\*\/\%\=\!\&\|\^\~<>])|' // 10: operator
    r'(\s+)', // 11: whitespace
  );

  static TextSpan highlight(
    String code, {
    String? language,
    required bool isDark,
  }) {
    final Color preprocessorColor = isDark
        ? const Color(0xFFF472B6)
        : const Color(0xFFC026D3);
    final Color stringColor = isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFDC2626);
    final Color headerColor = isDark
        ? const Color(0xFFFB7185)
        : const Color(0xFFBE123C);
    final Color commentColor = isDark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF15803D);
    final Color typeColor = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    final Color keywordColor = isDark
        ? const Color(0xFFF472B6)
        : const Color(0xFFC026D3);
    final Color builtinColor = isDark
        ? const Color(0xFF38BDF8)
        : const Color(0xFF0284C7);
    final Color numberColor = isDark
        ? const Color(0xFF34D399)
        : const Color(0xFF059669);
    final Color operatorColor = isDark
        ? const Color(0xFFA1A1AA)
        : const Color(0xFF3F3F46);
    final Color defaultColor = isDark
        ? const Color(0xFFF4F4F5)
        : const Color(0xFF27272A);

    final List<TextSpan> spans = <TextSpan>[];

    final Iterable<RegExpMatch> matches = _tokenRegex.allMatches(code);
    int lastEnd = 0;

    for (final RegExpMatch match in matches) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: code.substring(lastEnd, match.start),
            style: TextStyle(color: defaultColor),
          ),
        );
      }

      final String text = match.group(0)!;

      if (match.group(1) != null) {
        // Comment
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: commentColor, fontStyle: FontStyle.normal),
          ),
        );
      } else if (match.group(2) != null) {
        // String
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: stringColor),
          ),
        );
      } else if (match.group(3) != null) {
        // Preprocessor
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(
              color: preprocessorColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      } else if (match.group(4) != null) {
        // Header
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: headerColor),
          ),
        );
      } else if (match.group(5) != null) {
        // Number
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: numberColor, fontWeight: FontWeight.w600),
          ),
        );
      } else if (match.group(6) != null) {
        // Keyword
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: keywordColor, fontWeight: FontWeight.w600),
          ),
        );
      } else if (match.group(7) != null) {
        // Type
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: typeColor, fontWeight: FontWeight.w600),
          ),
        );
      } else if (match.group(8) != null) {
        // Builtin
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: builtinColor),
          ),
        );
      } else if (match.group(9) != null) {
        // Identifier
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: defaultColor),
          ),
        );
      } else if (match.group(10) != null) {
        // Operator
        spans.add(
          TextSpan(
            text: text,
            style: TextStyle(color: operatorColor),
          ),
        );
      } else {
        // Whitespace
        spans.add(TextSpan(text: text));
      }

      lastEnd = match.end;
    }

    if (lastEnd < code.length) {
      spans.add(
        TextSpan(
          text: code.substring(lastEnd),
          style: TextStyle(color: defaultColor),
        ),
      );
    }

    return TextSpan(
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 14.5,
        height: 1.48,
        color: defaultColor,
      ),
      children: spans,
    );
  }
}

/// กล่องแสดงผลโค้ด (Code Box) สไตล์โมเดิร์น คมชัดและมินิมอล
class BlueCodeBox extends StatefulWidget {
  const BlueCodeBox({required this.code, this.language, super.key});

  final String code;
  final String? language;

  @override
  State<BlueCodeBox> createState() => _BlueCodeBoxState();
}

class _BlueCodeBoxState extends State<BlueCodeBox> {
  bool _copied = false;
  String? _lastCode;
  String? _lastLanguage;
  bool? _lastIsDark;
  TextSpan? _cachedSpan;

  TextSpan _getHighlightedSpan(bool isDark) {
    if (_cachedSpan != null &&
        _lastCode == widget.code &&
        _lastLanguage == widget.language &&
        _lastIsDark == isDark) {
      return _cachedSpan!;
    }
    _lastCode = widget.code;
    _lastLanguage = widget.language;
    _lastIsDark = isDark;
    _cachedSpan = CodeSyntaxHighlighter.highlight(
      widget.code.trimRight(),
      language: widget.language,
      isDark: isDark,
    );
    return _cachedSpan!;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  String _formatLanguage(String? lang) {
    if (lang == null || lang.trim().isEmpty) return 'Code';
    final String clean = lang.trim();
    if (clean.toLowerCase() == 'cpp' || clean.toLowerCase() == 'c++') {
      return 'C++';
    }
    if (clean.toLowerCase() == 'c') return 'C';
    if (clean.toLowerCase() == 'csharp' || clean.toLowerCase() == 'c#') {
      return 'C#';
    }
    if (clean.toLowerCase() == 'dart') return 'Dart';
    if (clean.toLowerCase() == 'python' || clean.toLowerCase() == 'py') {
      return 'Python';
    }
    if (clean.toLowerCase() == 'javascript' || clean.toLowerCase() == 'js') {
      return 'JavaScript';
    }
    if (clean.toLowerCase() == 'typescript' || clean.toLowerCase() == 'ts') {
      return 'TypeScript';
    }
    if (clean.toLowerCase() == 'html') return 'HTML';
    if (clean.toLowerCase() == 'css') return 'CSS';
    if (clean.toLowerCase() == 'json') return 'JSON';
    if (clean.toLowerCase() == 'sql') return 'SQL';
    return clean[0].toUpperCase() + clean.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = BlueAIPalette.codeBackground(isDark);
    final Color borderColor = BlueAIPalette.border(isDark);
    final Color titleColor = BlueAIPalette.text(isDark);
    final Color iconColor = BlueAIPalette.textSecondary(isDark);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Header
          SelectionContainer.disabled(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.code_rounded,
                        size: 17,
                        color: BlueAIPalette.textSecondary(isDark),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatLanguage(widget.language),
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _copied
                            ? const Icon(
                                Icons.check_rounded,
                                key: ValueKey<String>('check'),
                                size: 18,
                                color: Color(0xFF16A34A),
                              )
                            : Icon(
                                Icons.copy_rounded,
                                key: const ValueKey<String>('copy'),
                                size: 18,
                                color: iconColor,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Code Area
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText.rich(_getHighlightedSpan(isDark)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three neutral dots rotate as an equilateral triangle while thinking.
class ThinkingOrb extends StatefulWidget {
  const ThinkingOrb({super.key, this.size = 18});
  final double size;
  @override
  State<ThinkingOrb> createState() => _ThinkingOrbState();
}

class _ThinkingOrbState extends State<ThinkingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _ThinkingDotsPainter(BlueAIPalette.textSecondary(isDark)),
        ),
      ),
    );
  }
}

class _ThinkingDotsPainter extends CustomPainter {
  const _ThinkingDotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double dimension = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double orbit = dimension * 0.30;
    final Paint paint = Paint()..color = color;
    for (int i = 0; i < 3; i++) {
      final double angle = -math.pi / 2 + i * 2 * math.pi / 3;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * orbit,
        dimension * 0.105,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThinkingDotsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// วิดเจ็ตแสดงสถานะการคิด (Chain of Thought / Reasoning):
/// - Image 1: ย่ออยู่ -> แสดง "Thought for X seconds >"
/// - Image 2: ขยายออก -> แสดง "Thought for X seconds ˇ" พร้อมเส้นขอบซ้ายและเนื้อหาการคิดแบบ Markdown
class ThinkingIndicatorWidget extends StatefulWidget {
  const ThinkingIndicatorWidget({
    required this.isThinking,
    this.thinkingSeconds,
    this.reasoningText,
    this.initiallyExpanded = false,
    super.key,
  });

  final bool isThinking;
  final int? thinkingSeconds;
  final String? reasoningText;
  final bool initiallyExpanded;

  @override
  State<ThinkingIndicatorWidget> createState() =>
      _ThinkingIndicatorWidgetState();
}

class _ThinkingIndicatorWidgetState extends State<ThinkingIndicatorWidget> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color secondaryColor = isDark
        ? const Color(0xFFA1A1AA)
        : const Color(0xFF71717A);
    final bool hasReasoning =
        widget.reasoningText != null && widget.reasoningText!.trim().isNotEmpty;

    // ถ้าคิดเสร็จแล้วและไม่มีข้อความกระบวนการคิด ไม่ต้องแสดงแถบพับว่าง
    if (!widget.isThinking && !hasReasoning) {
      return const SizedBox.shrink();
    }

    final int secs =
        (widget.thinkingSeconds != null && widget.thinkingSeconds! > 0)
        ? widget.thinkingSeconds!
        : 1;

    final String durationStr = '$secs วิ';

    final Widget header = InkWell(
      onTap: hasReasoning
          ? () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            }
          : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (widget.isThinking) ...<Widget>[
              const ThinkingOrb(size: 14),
              const SizedBox(width: 8),
              Text(
                secs > 0 ? 'กำลังคิด · $durationStr' : 'กำลังคิด...',
                style: TextStyle(
                  fontSize: 14.5,
                  color: secondaryColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ] else ...<Widget>[
              Text(
                'คิด $durationStr',
                style: TextStyle(
                  fontSize: 14.5,
                  color: secondaryColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
            if (hasReasoning) ...<Widget>[
              const SizedBox(width: 4),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 16,
                color: secondaryColor,
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          header,
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: (_expanded && hasReasoning)
                ? _buildReasoningBox(context, isDark, secondaryColor)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildReasoningBox(
    BuildContext context,
    bool isDark,
    Color textColor,
  ) {
    final Color borderColor = isDark
        ? const Color(0xFF3F3F46)
        : const Color(0xFFE4E4E7);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: borderColor, width: 2.0)),
      ),
      child: MarkdownBody(
        data: widget.reasoningText!.trim(),
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: TextStyle(
            fontSize: 14.5,
            height: 1.5,
            color: textColor,
            fontWeight: FontWeight.w400,
          ),
          listBullet: TextStyle(
            fontSize: 14.5,
            color: textColor,
            fontWeight: FontWeight.w400,
          ),
          listIndent: 18.0,
          blockSpacing: 10.0,
          code: TextStyle(
            fontSize: 13.5,
            fontFamily: 'monospace',
            color: textColor,
            backgroundColor: isDark
                ? const Color(0xFF27272A)
                : const Color(0xFFF4F4F5),
          ),
          codeblockDecoration: BoxDecoration(
            color: isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 0.8),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มลอยสำหรับเลื่อนกลับลงมาด้านล่างสุด (Floating Scroll-To-Bottom Button)
class ScrollToBottomButton extends StatelessWidget {
  const ScrollToBottomButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'เลื่อนลงล่างสุด',
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF27272A) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7),
            width: 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Center(
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 22,
                color: isDark
                    ? const Color(0xFFD4D4D8)
                    : const Color(0xFF52525B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
