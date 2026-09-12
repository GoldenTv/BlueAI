import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import 'blue_ai_theme.dart';
import 'chat_widgets.dart';

/// ตัวประมวลผลไวยากรณ์ LaTeX แบบ Inline และ Block สำหรับ Markdown
/// ป้องกันปัญหา Delimiter สับสนกับตัวหนา (Bold), วงเล็บ หรือสัญลักษณ์พิเศษ
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax()
    : super(
        r'(?:\$\$((?:\\\$|[^\$])+?)\$\$)|'
        r'(?:\$((?!\s)(?:\\\$|[^\$\n])+?(?<!\s))\$)|'
        r'(?:\\\(((?:\\\)|[^\n])+?)\\\))|'
        r'(?:\\\[((?:\\\]|[\s\S])+?)\\\])',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final String? display = match[1];
    final String? inline = match[2];
    final String? parenInline = match[3];
    final String? bracketDisplay = match[4];

    final String equation;
    final String mathStyle;

    if (display != null) {
      equation = display.trim();
      mathStyle = 'display';
    } else if (bracketDisplay != null) {
      equation = bracketDisplay.trim();
      mathStyle = 'display';
    } else if (inline != null) {
      equation = inline.trim();
      mathStyle = 'text';
    } else if (parenInline != null) {
      equation = parenInline.trim();
      mathStyle = 'text';
    } else {
      return false;
    }

    if (equation.isEmpty) return false;

    final md.Element element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = mathStyle;
    parser.addNode(element);
    return true;
  }
}

/// Element Builder สำหรับแสดงผลสูตรคณิตศาสตร์ด้วย FlutterMath
/// ป้องกัน Text Overflow ด้วย SingleChildScrollView แนวนอน และมี Fallback สวยงามหากสูตรผิดไวยากรณ์
class LatexElementBuilder extends MarkdownElementBuilder {
  LatexElementBuilder({this.textStyle, this.textScaleFactor});

  final TextStyle? textStyle;
  final double? textScaleFactor;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String text = element.textContent;
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final TextStyle effectiveStyle =
        preferredStyle ?? parentStyle ?? textStyle ?? const TextStyle();

    final MathStyle mathStyle = element.attributes['MathStyle'] == 'display'
        ? MathStyle.display
        : MathStyle.text;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.antiAlias,
      child: Math.tex(
        text,
        textStyle: effectiveStyle,
        mathStyle: mathStyle,
        textScaleFactor: textScaleFactor,
        onErrorFallback: (FlutterMathException e) {
          // หากสูตรจาก AI ผิดไวยากรณ์ แสดงข้อความสูตรเดิมอย่างเรียบร้อย ไม่แสดงหน้าต่าง error สีแดง
          return Text(
            mathStyle == MathStyle.display ? '\$\$\n$text\n\$\$' : '\$$text\$',
            style: effectiveStyle,
          );
        },
      ),
    );
  }
}

enum _BlockType { markdown, code }

class _ContentBlock {
  const _ContentBlock({
    required this.type,
    required this.content,
    this.language,
    required this.isClosed,
  });

  final _BlockType type;
  final String content;
  final String? language;
  final bool isClosed;
}

/// คอมโพเนนต์สำหรับแสดงผล Markdown พร้อมสูตรคณิตศาสตร์ LaTeX และ CodeSnippetBox
/// รองรับ Incremental Block-Based Parsing เพื่อความลื่นไหลระดับ 60/120 FPS ขณะสตรีมมิ่ง
class MarkdownLatexView extends StatefulWidget {
  const MarkdownLatexView({
    required this.data,
    this.selectable = true,
    this.textStyle,
    super.key,
  });

  final String data;
  final bool selectable;
  final TextStyle? textStyle;

  @override
  State<MarkdownLatexView> createState() => _MarkdownLatexViewState();
}

class _MarkdownLatexViewState extends State<MarkdownLatexView> {
  static final md.ExtensionSet _latexExtensionSet = md.ExtensionSet(
    <md.BlockSyntax>[
      LatexBlockSyntax(),
      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    ],
    <md.InlineSyntax>[
      LatexInlineSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );

  final Map<String, Widget> _completedBlockCache = <String, Widget>{};
  String? _lastData;
  bool? _lastIsDark;
  TextStyle? _lastTextStyle;
  bool? _lastSelectable;
  Widget? _cachedWidget;

  /// แปลงและเตรียมข้อความ LaTeX ให้อยู่ในรูปแบบที่ parser รองรับได้อย่างสมบูรณ์
  static String _preprocessLatex(String text) {
    // 1. แปลง \[ ... \] เป็น $$ ... $$ (Block LaTeX จาก AI)
    String processed = text.replaceAllMapped(
      RegExp(r'\\\[(.*?)\\\]', dotAll: true),
      (Match m) => '\n\$\$${m[1]}\$\$\n',
    );

    // 2. แปลง \( ... \) เป็น $ ... $ (Inline LaTeX จาก AI)
    processed = processed.replaceAllMapped(
      RegExp(r'\\\((.*?)\\\)'),
      (Match m) => '\$${m[1]}\$',
    );

    return processed;
  }

  /// สกัดชื่อภาษาจาก Info String เช่น "dart:lib/main.dart" -> "dart", "python " -> "python"
  static String _sanitizeLanguage(String rawInfo) {
    final String trimmed = rawInfo.trim();
    if (trimmed.isEmpty) return '';
    final int sepIndex = trimmed.indexOf(RegExp(r'[\s:;\{]'));
    if (sepIndex != -1) {
      return trimmed.substring(0, sepIndex).trim();
    }
    return trimmed;
  }

  /// ค้นหาจุดเริ่มต้นของ Code Fence (``` ที่อยู่ต้นบรรทัด)
  static int _findFenceStart(String data, int from) {
    int pos = from;
    while (pos < data.length) {
      final int index = data.indexOf('```', pos);
      if (index == -1) return -1;

      bool isLineStart = false;
      if (index == 0) {
        isLineStart = true;
      } else {
        int i = index - 1;
        int spaces = 0;
        while (i >= 0 && data[i] == ' ') {
          spaces++;
          i--;
        }
        if (i < 0 || data[i] == '\n' || data[i] == '\r') {
          if (spaces <= 3) {
            isLineStart = true;
          }
        }
      }

      if (isLineStart) {
        return index;
      }
      pos = index + 3;
    }
    return -1;
  }

  /// ค้นหาจุดปิด Code Fence (``` ที่อยู่ต้นบรรทัดใหม่)
  static int _findClosingFence(String data, int from) {
    int pos = from;
    while (pos < data.length) {
      final int index = data.indexOf('```', pos);
      if (index == -1) return -1;

      bool isLineStart = false;
      int i = index - 1;
      int spaces = 0;
      while (i >= from && data[i] == ' ') {
        spaces++;
        i--;
      }
      if (i >= from && (data[i] == '\n' || data[i] == '\r')) {
        if (spaces <= 3) {
          isLineStart = true;
        }
      } else if (index == from) {
        isLineStart = true;
      }

      if (isLineStart) {
        return index;
      }
      pos = index + 3;
    }
    return -1;
  }

  /// แยกข้อความ Markdown ออกเป็นย่อหน้าๆ (แยกด้วย \n\s*\n+)
  static void _splitMarkdownParagraphs(
    String mdText, {
    required bool isClosedTail,
    required List<_ContentBlock> into,
  }) {
    if (mdText.trim().isEmpty) return;

    final List<String> rawParts = mdText.split(RegExp(r'\n\s*\n+'));
    for (int i = 0; i < rawParts.length; i++) {
      final String part = rawParts[i].trim();
      if (part.isEmpty) continue;

      final bool isLastPart = (i == rawParts.length - 1);
      final bool partIsClosed =
          !isLastPart || isClosedTail || mdText.endsWith('\n\n');

      into.add(
        _ContentBlock(
          type: _BlockType.markdown,
          content: part,
          isClosed: partIsClosed,
        ),
      );
    }
  }

  /// แยกเอกสารทั้งหมดออกเป็นบล็อก (Markdown Blocks & Code Blocks) อย่างแม่นยำ
  static List<_ContentBlock> _extractBlocks(String data) {
    final List<_ContentBlock> blocks = <_ContentBlock>[];
    int cursor = 0;

    while (cursor < data.length) {
      final int fenceStart = _findFenceStart(data, cursor);

      if (fenceStart == -1) {
        final String remaining = data.substring(cursor);
        _splitMarkdownParagraphs(remaining, isClosedTail: false, into: blocks);
        break;
      }

      if (fenceStart > cursor) {
        final String mdBefore = data.substring(cursor, fenceStart);
        _splitMarkdownParagraphs(mdBefore, isClosedTail: true, into: blocks);
      }

      final int fenceLineEnd = data.indexOf('\n', fenceStart + 3);

      if (fenceLineEnd == -1) {
        // บรรทัดเปิด Fence กำลังพิมพ์อยู่ (เช่น ``` หรือ ```dart)
        final String rawInfo = data.substring(fenceStart + 3);
        final String lang = _sanitizeLanguage(rawInfo);
        blocks.add(
          _ContentBlock(
            type: _BlockType.code,
            content: '',
            language: lang.isNotEmpty ? lang : null,
            isClosed: false,
          ),
        );
        break;
      }

      final String rawInfo = data.substring(fenceStart + 3, fenceLineEnd);
      final String lang = _sanitizeLanguage(rawInfo);
      final int codeStart = fenceLineEnd + 1;

      final int closeFence = _findClosingFence(data, codeStart);

      if (closeFence == -1) {
        // บล็อกโค้ดยังไม่ปิด (กำลังสตรีมโค้ด)
        final String streamingCode = data.substring(codeStart);
        blocks.add(
          _ContentBlock(
            type: _BlockType.code,
            content: streamingCode,
            language: lang.isNotEmpty ? lang : null,
            isClosed: false,
          ),
        );
        break;
      }

      final String completedCode = data.substring(codeStart, closeFence);
      blocks.add(
        _ContentBlock(
          type: _BlockType.code,
          content: completedCode,
          language: lang.isNotEmpty ? lang : null,
          isClosed: true,
        ),
      );

      final int closeLineEnd = data.indexOf('\n', closeFence + 3);
      if (closeLineEnd == -1) {
        cursor = data.length;
      } else {
        cursor = closeLineEnd + 1;
      }
    }

    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ถ้าไม่มีการเปลี่ยนแปลง ให้ใช้ Widget ที่แคชไว้ทันที เพื่อป้องกันการ Re-parse ตอนเลื่อนหน้าจอ
    if (_cachedWidget != null &&
        _lastData == widget.data &&
        _lastIsDark == isDark &&
        _lastTextStyle == widget.textStyle &&
        _lastSelectable == widget.selectable) {
      return _cachedWidget!;
    }

    // หาก Theme หรือการตั้งค่าเปลี่ยน ล้างแคชบล็อกเพื่อเรนเดอร์ใหม่ด้วยสีที่ถูกต้อง
    if (_lastIsDark != isDark ||
        _lastTextStyle != widget.textStyle ||
        _lastSelectable != widget.selectable) {
      _completedBlockCache.clear();
      _cachedStyleSheet = null;
    }

    _lastData = widget.data;
    _lastIsDark = isDark;
    _lastTextStyle = widget.textStyle;
    _lastSelectable = widget.selectable;

    final Widget content = _buildContent(context, isDark);
    _cachedWidget = widget.selectable ? SelectionArea(child: content) : content;
    return _cachedWidget!;
  }

  MarkdownStyleSheet? _cachedStyleSheet;
  bool? _cachedStyleSheetIsDark;
  TextStyle? _cachedStyleSheetTextStyle;

  MarkdownStyleSheet _getStyleSheet(
    BuildContext context,
    TextStyle defaultStyle,
    bool isDark,
  ) {
    if (_cachedStyleSheet != null &&
        _cachedStyleSheetIsDark == isDark &&
        _cachedStyleSheetTextStyle == defaultStyle) {
      return _cachedStyleSheet!;
    }

    _cachedStyleSheetIsDark = isDark;
    _cachedStyleSheetTextStyle = defaultStyle;
    _cachedStyleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(
          p: defaultStyle,
          pPadding: const EdgeInsets.only(bottom: 4),
          blockSpacing: 6.0,
          blockquoteDecoration: BoxDecoration(
            color: BlueAIPalette.tint(isDark).withValues(alpha: 0.72),
            border: Border(
              left: BorderSide(color: BlueAIPalette.accent, width: 3.5),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
          ),
          blockquotePadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          blockquote: defaultStyle.copyWith(
            color: BlueAIPalette.textSecondary(isDark),
            fontStyle: FontStyle.italic,
          ),
          listIndent: 20.0,
          listBullet: defaultStyle.copyWith(
            color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF3F3F46),
            fontWeight: FontWeight.w600,
          ),
          listBulletPadding: const EdgeInsets.only(right: 6.0),
          horizontalRuleDecoration: CleanDividerDecoration(
            color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
            thickness: 1.0,
            verticalSpacing: 16.0,
          ),
          h1: TextStyle(
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h1Padding: const EdgeInsets.only(top: 18, bottom: 8),
          h2: TextStyle(
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
            fontSize: 17.5,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h2Padding: const EdgeInsets.only(top: 16, bottom: 6),
          h3: TextStyle(
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h3Padding: const EdgeInsets.only(top: 14, bottom: 6),
          h4: TextStyle(
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
          h4Padding: const EdgeInsets.only(top: 10, bottom: 4),
          strong: TextStyle(
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
            fontWeight: FontWeight.w700,
          ),
          code: TextStyle(
            color: isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
            backgroundColor: isDark
                ? const Color(0xFF27272A)
                : const Color(0xFFF4F4F5),
            fontSize: 14.5,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
          tableBorder: TableBorder(
            top: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
              width: 1,
            ),
            bottom: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
              width: 1,
            ),
            left: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
              width: 1,
            ),
            right: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFE5E7EB),
              width: 1,
            ),
            horizontalInside: BorderSide(
              color: isDark ? const Color(0xFF27272A) : const Color(0xFFF1F5F9),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          tableHead: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
          ),
          tableBody: TextStyle(
            fontSize: 14.5,
            color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
            height: 1.4,
          ),
          tableCellsPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          tableHeadAlign: TextAlign.left,
        );
    return _cachedStyleSheet!;
  }

  Widget _buildContent(BuildContext context, bool isDark) {
    final TextStyle defaultStyle =
        widget.textStyle ??
        TextStyle(
          color: isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B),
          fontSize: 16.5,
          height: 1.55,
        );

    final List<_ContentBlock> blocks = _extractBlocks(widget.data);
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }

    final List<Widget> widgets = <Widget>[];

    for (int i = 0; i < blocks.length; i++) {
      final _ContentBlock block = blocks[i];
      if (block.type == _BlockType.code) {
        if (block.isClosed) {
          final String cacheKey = 'code_${block.language}_${block.content}';
          final Widget w = _completedBlockCache.putIfAbsent(
            cacheKey,
            () => RepaintBoundary(
              child: CodeSnippetBox(code: block.content, language: block.language),
            ),
          );
          widgets.add(w);
        } else {
          // โค้ดที่กำลังสตรีมอยู่: แสดงผลเป็น CodeSnippetBox ทันทีตั้งแต่เริ่มพิมพ์
          widgets.add(
            RepaintBoundary(
              child: CodeSnippetBox(code: block.content, language: block.language),
            ),
          );
        }
      } else {
        if (block.content.trim().isEmpty) continue;

        if (block.isClosed) {
          final String cacheKey = 'md_${block.content}';
          final Widget w = _completedBlockCache.putIfAbsent(
            cacheKey,
            () => RepaintBoundary(
              child: _buildMarkdownBody(
                context,
                block.content,
                defaultStyle,
                isDark,
              ),
            ),
          );
          widgets.add(w);
        } else {
          // ย่อหน้าส่วนท้ายสุดที่กำลังสตรีม
          widgets.add(
            RepaintBoundary(
              child: _buildMarkdownBody(
                context,
                block.content,
                defaultStyle,
                isDark,
              ),
            ),
          );
        }
      }
    }

    if (widgets.isEmpty) {
      return const SizedBox.shrink();
    }

    if (widgets.length == 1) {
      return widgets.first;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  Widget _buildMarkdownBody(
    BuildContext context,
    String rawMarkdown,
    TextStyle defaultStyle,
    bool isDark,
  ) {
    final String processedData = _preprocessLatex(rawMarkdown);

    return MarkdownBody(
      data: processedData,
      selectable: false,
      bulletBuilder: (MarkdownBulletParameters params) {
        if (params.style == BulletStyle.unorderedList) {
          final Color bulletColor = isDark
              ? const Color(0xFFA1A1AA)
              : const Color(0xFF3F3F46);

          return Padding(
            padding: const EdgeInsets.only(top: 10.5),
            child: Container(
              width: 6,
              height: 5.5,
              decoration: BoxDecoration(
                color: bulletColor,
                shape: BoxShape.circle,
              ),
            ),
          );
        }

        final TextStyle numberStyle = TextStyle(
          color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF3F3F46),
          fontSize: defaultStyle.fontSize ?? 16.0,
          fontWeight: FontWeight.w600,
          height: defaultStyle.height ?? 1.5,
        );

        return Align(
          alignment: Alignment.centerRight,
          child: Text('${params.index + 1}.', style: numberStyle),
        );
      },
      builders: <String, MarkdownElementBuilder>{
        'latex': LatexElementBuilder(textStyle: defaultStyle),
      },
      extensionSet: _latexExtensionSet,
      styleSheet: _getStyleSheet(context, defaultStyle, isDark),
    );
  }
}

/// ตกแต่งเส้นคั่นแนวนอน (Horizontal Rule / ---) สไตล์มินิมอล เส้นบาง 1.0px พร้อมระยะเว้นบน-ล่าง
class CleanDividerDecoration extends Decoration {
  const CleanDividerDecoration({
    required this.color,
    this.thickness = 1.0,
    this.verticalSpacing = 16.0,
  });

  final Color color;
  final double thickness;
  final double verticalSpacing;

  @override
  EdgeInsetsGeometry get padding =>
      EdgeInsets.symmetric(vertical: verticalSpacing);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _CleanDividerPainter(this);
  }
}

class _CleanDividerPainter extends BoxPainter {
  _CleanDividerPainter(this.decoration);
  final CleanDividerDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final Size size = configuration.size ?? Size.zero;
    final double y = offset.dy + size.height / 2;
    final Paint paint = Paint()
      ..color = decoration.color
      ..strokeWidth = decoration.thickness
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(offset.dx, y),
      Offset(offset.dx + size.width, y),
      paint,
    );
  }
}
