import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:blue_app/src/markdown_latex_view.dart';

void main() {
  testWidgets(
    'renders AI math cheatsheet with headers, block latex and code blocks',
    (WidgetTester tester) async {
      const String sampleData = r'''
นี่คือสูตรคณิตศาสตร์ที่ใช้บ่อย พร้อม
โค้ด LaTeX ที่พร้อมคัดลอกไปใช้ได้เลย

### สูตรพื้นฐาน
**สมการกำลังสอง (Quadratic Formula)**
\[ x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a} \]
```latex
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
```

**ทฤษฎีบทพีทาโกรัส**
\[ a^2 + b^2 = c^2 \]
```latex
a^2 + b^2 = c^2
```
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownLatexView(data: sampleData),
            ),
          ),
        ),
      );

      expect(find.byType(Math), findsNWidgets(2));
      expect(
        find.textContaining('นี่คือสูตรคณิตศาสตร์ที่ใช้บ่อย'),
        findsOneWidget,
      );
      expect(find.textContaining('สูตรพื้นฐาน'), findsOneWidget);
    },
  );

  testWidgets(
    'renders unclosed streaming code block immediately as CodeSnippetBox',
    (WidgetTester tester) async {
      const String streamingCodeSample =
          'ตัวอย่างโค้ดที่กำลังพิมพ์:\n```dart\nvoid main() {\n  print("hello");';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownLatexView(data: streamingCodeSample),
            ),
          ),
        ),
      );

      // ตรวจสอบว่าพบ CodeSnippetBox และภาษา Dart ทันที แม้ยังไม่มี ``` ปิดท้าย
      expect(find.text('Dart'), findsOneWidget);
      expect(find.textContaining('print("hello")'), findsOneWidget);
    },
  );

  testWidgets(
    'renders streaming code blocks with complex language tags and spaces as CodeSnippetBox',
    (WidgetTester tester) async {
      const String trickySample = '''
คำอธิบายก่อนเริ่ม:

```dart:lib/main.dart
void run() {
  print("dart with file path");
}
```

และตัวอย่าง Python ที่มี space:

```python 
def hello():
    print("python with trailing space")
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownLatexView(data: trickySample),
            ),
          ),
        ),
      );

      // ตรวจสอบว่าทั้ง dart:lib/main.dart และ python (มี space) ถูกแปลงเป็น CodeSnippetBox ทั้งคู่
      expect(find.text('Dart'), findsOneWidget);
      expect(find.text('Python'), findsOneWidget);
      expect(find.textContaining('dart with file path'), findsOneWidget);
      expect(find.textContaining('python with trailing space'), findsOneWidget);
    },
  );

  testWidgets(
    'renders blockquote and unordered list bullets correctly with custom styles',
    (WidgetTester tester) async {
      const String quoteAndListSample = '''
### 2. ทฤษฎีบทพีทาโกรัส
> "ในรูปสามเหลี่ยมมุมฉาก กำลังสองของความยาวด้านตรงข้ามมุมฉาก จะเท่ากับผลบวกของกำลังสองของความยาวด้านประกอบมุมฉาก"

* หัวข้อแรก
* หัวข้อที่สอง
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MarkdownLatexView(data: quoteAndListSample),
            ),
          ),
        ),
      );

      expect(find.textContaining('ทฤษฎีบทพีทาโกรัส'), findsOneWidget);
      expect(find.textContaining('ในรูปสามเหลี่ยมมุมฉาก'), findsOneWidget);
      expect(find.textContaining('หัวข้อแรก'), findsOneWidget);
      expect(find.textContaining('หัวข้อที่สอง'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);

      // ตรวจสอบว่า bulletBuilder ทำงานจริง
      final Finder circleFinders = find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(circleFinders, findsNWidgets(2));
    },
  );

  testWidgets(
    'renders inline math inside parenthesis and bold properly without latex parser error',
    (WidgetTester tester) async {
      const String sample =
          r'*   **ค่า Discriminant ($D$):** ส่วนที่อยู่ใต้เครื่องหมายรากคือ $b^2 - 4ac$ ซึ่งเป็นตัวบอกลักษณะของคำตอบ:';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: MarkdownLatexView(data: sample)),
          ),
        ),
      );

      expect(find.textContaining("Can't use function"), findsNothing);
      expect(find.textContaining('**'), findsNothing);
      expect(find.textContaining('ค่า Discriminant'), findsOneWidget);
      expect(
        find.textContaining('ส่วนที่อยู่ใต้เครื่องหมายรากคือ'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'renders ordered list with compact number spacing and tight alignment',
    (WidgetTester tester) async {
      const String sample = '''
1. Dot Product และ Cross Product  
2. Vector Space  
3. Linear Independence  
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: MarkdownLatexView(data: sample)),
          ),
        ),
      );

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.textContaining('Dot Product'), findsOneWidget);
    },
  );
}
