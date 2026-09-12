import 'package:blue_app/src/chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expanded thinking updates while still thinking and stays open for answer', (tester) async {
    Widget view(String text, bool thinking) => MaterialApp(
      home: Scaffold(body: ThinkingIndicatorWidget(
        isThinking: thinking, thinkingSeconds: 3, reasoningText: text,
      )),
    );
    await tester.pumpWidget(view('first', true));
    await tester.tap(find.text('กำลังคิด · 3 วิ'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('first'), findsOneWidget);
    await tester.pumpWidget(view('first second', true));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('first second'), findsOneWidget);
    await tester.pumpWidget(view('first second', false));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('first second'), findsOneWidget);
    expect(find.text('คิด 3 วิ'), findsOneWidget);
  });
  group('ThinkingIndicatorWidget Tests', () {
    testWidgets('displays collapsed "คิด 4 วิ >" matching Image 1', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThinkingIndicatorWidget(
              isThinking: false,
              thinkingSeconds: 4,
              reasoningText: '- We need to generate C++ code for sorting.\n\nMake sure the code compiles.',
            ),
          ),
        ),
      );

      // Header text exists
      expect(find.text('คิด 4 วิ'), findsOneWidget);
      // Collapsed right arrow exists
      expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);
      // Reasoning content is collapsed by default
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets(
      'tapping header expands to "คิด 4 วิ ˇ" and shows reasoning matching Image 2',
      (WidgetTester tester) async {
        const String sampleReasoning =
            '• We need to generate C++ code for sorting. The user said "code c++ sort".\n\n'
            'I\'ll provide a short program that sorts a vector of integers.\n\n'
            'Make sure the code compiles and is correct.';

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ThinkingIndicatorWidget(
                isThinking: false,
                thinkingSeconds: 4,
                reasoningText: sampleReasoning,
              ),
            ),
          ),
        );

        // Tap the header to expand
        await tester.tap(find.text('คิด 4 วิ'));
        await tester.pumpAndSettle();

        // Arrow changes to down chevron
        expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsNothing);

        // Markdown content is rendered
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(
          find.textContaining('We need to generate C++ code for sorting'),
          findsOneWidget,
        );

        // Verify left border line container exists
        final containerFinder = find.byWidgetPredicate((widget) {
          if (widget is Container && widget.decoration is BoxDecoration) {
            final decoration = widget.decoration as BoxDecoration;
            final border = decoration.border;
            return border is Border && border.left.width == 2.0;
          }
          return false;
        });
        expect(containerFinder, findsOneWidget);

        // Tap again to collapse
        await tester.tap(find.text('คิด 4 วิ'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);
        expect(find.byType(MarkdownBody), findsNothing);
      },
    );

    testWidgets(
      'displays ThinkingOrb and "กำลังคิด · X วิ" while actively thinking',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ThinkingIndicatorWidget(
                isThinking: true,
                thinkingSeconds: 3,
                reasoningText: 'Analyzing problem...',
              ),
            ),
          ),
        );

        expect(find.byType(ThinkingOrb), findsOneWidget);
        expect(find.text('กำลังคิด · 3 วิ'), findsOneWidget);
        expect(find.byIcon(Icons.keyboard_arrow_right_rounded), findsOneWidget);
      },
    );

    testWidgets('formats 1 second correctly as "คิด 1 วิ"', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ThinkingIndicatorWidget(
              isThinking: false,
              thinkingSeconds: 1,
              reasoningText: 'Quick thought.',
            ),
          ),
        ),
      );

      expect(find.text('คิด 1 วิ'), findsOneWidget);
    });

    testWidgets(
      'renders SizedBox.shrink when not thinking and no reasoning text',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ThinkingIndicatorWidget(
                isThinking: false,
                thinkingSeconds: 2,
                reasoningText: null,
              ),
            ),
          ),
        );

        expect(find.textContaining('คิด'), findsNothing);
        expect(find.byType(ThinkingOrb), findsNothing);
      },
    );
  });
}
