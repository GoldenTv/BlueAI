import 'package:blue_app/app.dart';
import 'package:blue_app/src/chat_controller.dart';
import 'package:blue_app/src/chat_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('thinking dots rotate, respect reduced motion, and dispose', (
    tester,
  ) async {
    Future<void> show(bool reduce) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: const Center(child: ThinkingOrb()),
        ),
      ),
    );
    await show(false);
    final rotation = tester.widget<RotationTransition>(
      find.byType(RotationTransition),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(rotation.turns.value, closeTo(0.25, 0.01));
    await show(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(rotation.turns.value, 0);
    await show(false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(rotation.turns.value, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final dark in <bool>[false, true]) {
    testWidgets('narrow chat, large text, keyboard and drawer: dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      final prefs = await SharedPreferences.getInstance();
      final controller = ChatController(preferences: prefs);
      await controller.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
      await tester.pumpWidget(BlueApp(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final menu = find.byTooltip('เปิดเมนู');
      expect(tester.getSize(menu).width, greaterThanOrEqualTo(48));
      expect(find.text('BlueAI'), findsNothing);
      await tester.enterText(find.byType(TextField), 'ข้อความทดสอบ');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('โหมดหน้าจอ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('การตั้งค่าระบบและโมเดล'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
