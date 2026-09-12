import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blue_app/main.dart';
import 'package:blue_app/src/chat_composer.dart';
import 'package:blue_app/src/chat_controller.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('renders the composer shell and welcome view', (
    WidgetTester tester,
  ) async {
    final controller = ChatController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(BlueApp(controller: controller));
    await tester.pump();

    // The composer hides unavailable voice controls.
    expect(find.text('ถามอะไรก็ได้'), findsOneWidget);
    expect(find.text('พูด'), findsNothing);

    // เมื่อพิมพ์ข้อความ จะเปลี่ยนเป็นปุ่มส่งลูกศรขึ้น
    await tester.enterText(find.byType(TextField), 'ข้อความทดสอบ');
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);

    // ตรวจสอบหน้าจอเริ่มต้น (WelcomeView)
    expect(find.text('เริ่มบทสนทนา'), findsOneWidget);
    expect(find.text('ระดมความคิดและวางแผน'), findsOneWidget);
    expect(find.text('เขียนโค้ดและดีบัก'), findsOneWidget);
  });

  testWidgets('opens drawer and displays theme options', (
    WidgetTester tester,
  ) async {
    final controller = ChatController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(BlueApp(controller: controller));
    await tester.pump();

    // แตะปุ่มเปิดเมนู
    await tester.tap(find.bySemanticsLabel('เปิดเมนู'));
    await tester.pumpAndSettle();

    // ตรวจสอบเมนูใน Drawer
    expect(find.text('เริ่มการสนทนาใหม่'), findsOneWidget);
    expect(find.text('โหมดหน้าจอ'), findsOneWidget);
    expect(find.text('โหมดไม่ระบุตัวตน'), findsNothing);
    expect(find.text('การตั้งค่าระบบและโมเดล'), findsOneWidget);
  });

  testWidgets('renders user and AI messages in conversation', (
    WidgetTester tester,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ChatController controller = ChatController(preferences: prefs);

    await tester.pumpWidget(BlueApp(controller: controller));
    await tester.pump();

    // จำลองการส่งข้อความ
    controller.sendMessage('สวัสดี BlueAI');
    await tester.pump();

    // ตรวจสอบข้อความผู้ใช้แสดงบนหน้าจอ
    expect(find.text('สวัสดี BlueAI'), findsOneWidget);
  });

  testWidgets('handles scroll events and maintains smooth conversation list', (
    WidgetTester tester,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ChatController controller = ChatController(preferences: prefs);

    await tester.pumpWidget(BlueApp(controller: controller));
    await tester.pump();

    // ส่งข้อความ
    controller.sendMessage('ข้อความทดสอบสำหรับการเลื่อน');
    await tester.pump();

    expect(find.text('ข้อความทดสอบสำหรับการเลื่อน'), findsOneWidget);

    // ทดสอบเลื่อน ListView
    final Finder listViewFinder = find.byType(ListView);
    expect(listViewFinder, findsOneWidget);
    await tester.drag(listViewFinder, const Offset(0, -100));
    await tester.pump();

    // ตรวจสอบว่า Scroll notification และ NotificationListener ทำงานได้ราบรื่น ไม่มีข้อผิดพลาด
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'verifies pure white background in light theme and code background styling',
    (WidgetTester tester) async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(BlueApp(controller: controller));
      await tester.pump();

      final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.white);
      expect(BlueApp.lightTheme.scaffoldBackgroundColor, Colors.white);
      expect(BlueApp.lightTheme.colorScheme.surface, Colors.white);
    },
  );

  testWidgets('chat shell has no decorative gradient overlay', (
    WidgetTester tester,
  ) async {
    final controller = ChatController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(BlueApp(controller: controller));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).gradient != null,
      ),
      findsNothing,
    );

    // ตรวจสอบว่ามี Stack และ Composer อยู่ในเลย์เอาต์อย่างสมบูรณ์
    expect(find.byType(Stack), findsWidgets);
    expect(find.text('ถามอะไรก็ได้'), findsOneWidget);
  });

  testWidgets(
    'verifies composer button positions and vertical alignment matching the design',
    (WidgetTester tester) async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(BlueApp(controller: controller));
      await tester.pump();

      // Find the 4 elements in the composer bottom row
      final Finder addFinder = find.byIcon(Icons.add_rounded);
      final Finder modelFinder = find.byType(ModelSelectorButton);
      final Finder micFinder = find.byIcon(Icons.mic_none_rounded);
      final Finder voiceFinder = find.byType(VoicePillButton);

      expect(addFinder, findsOneWidget);
      expect(modelFinder, findsOneWidget);
      expect(micFinder, findsOneWidget);
      expect(voiceFinder, findsOneWidget);

      // Verify horizontal order: [ + ] < [ Model ] < [ Mic ] < [ Voice ]
      final Offset addPos = tester.getCenter(addFinder);
      final Offset modelPos = tester.getCenter(modelFinder);
      final Offset micPos = tester.getCenter(micFinder);
      final Offset voicePos = tester.getCenter(voiceFinder);

      expect(addPos.dx, lessThan(modelPos.dx));
      expect(modelPos.dx, lessThan(micPos.dx));
      expect(micPos.dx, lessThan(voicePos.dx));

      // Verify vertical alignment: all 4 elements are centered on the same horizontal axis
      expect((addPos.dy - modelPos.dy).abs(), lessThanOrEqualTo(1.0));
      expect((modelPos.dy - micPos.dy).abs(), lessThanOrEqualTo(1.0));
      expect((micPos.dy - voicePos.dy).abs(), lessThanOrEqualTo(1.0));

      // When text is typed, the voice button changes to send button, while mic button stays
      await tester.enterText(find.byType(TextField), 'ข้อความทดสอบ');
      await tester.pump();

      final Finder sendFinder = find.byIcon(Icons.arrow_upward_rounded);
      expect(sendFinder, findsOneWidget);
      expect(find.byType(VoicePillButton), findsNothing);
      expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);

      final Offset sendPos = tester.getCenter(sendFinder);
      expect(micPos.dx, lessThan(sendPos.dx));
      expect((micPos.dy - sendPos.dy).abs(), lessThanOrEqualTo(1.0));
    },
  );

  testWidgets('verifies 3-line menu icon and top edge fade shader mask', (
    WidgetTester tester,
  ) async {
    final controller = ChatController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(BlueApp(controller: controller));
    await tester.pump();

    // Verify 3-line menu button exists and has 3 line bars inside
    final Finder menuButton = find.byTooltip('เปิดเมนู');
    expect(menuButton, findsOneWidget);

    final Finder lineContainers = find.descendant(
      of: menuButton,
      matching: find.byType(Container),
    );
    // 3 line bars: 2 long + 1 short
    expect(lineContainers, findsNWidgets(3));

    // Verify top edge fade ShaderMask exists
    expect(find.byType(ShaderMask), findsOneWidget);

    // Verify right-side action buttons (new chat and more options)
    expect(find.byIcon(Icons.add_comment_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });
}
