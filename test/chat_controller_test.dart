import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blue_app/src/ai_gateway_service.dart';
import 'package:blue_app/src/chat_controller.dart';
import 'package:blue_app/src/api_key_store.dart';

class MemoryKeyStore extends ApiKeyStore {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String key) async {
    if (failWrites) throw StateError('Storage unavailable');
    value = key.isEmpty ? null : key;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ChatController initializes with default models and settings', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ChatController controller = ChatController(preferences: prefs);

    expect(controller.messages, isEmpty);
    expect(controller.isLoading, isFalse);
    expect(controller.selectedModel, 'openai/gpt-5.6-luna');
    expect(controller.availableModels, contains('openai/gpt-5.6-luna'));
    expect(
      controller.availableModels,
      contains('deepseek/deepseek-v4-flash-0731'),
    );
    expect(controller.availableModels, contains('PSU-LLM/psu-gemma'));
  });

  test('ChatController manages models and persists changes', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ChatController controller = ChatController(preferences: prefs);

    await controller.addModel('custom/my-model');
    expect(controller.availableModels, contains('custom/my-model'));

    await controller.setSelectedModel('custom/my-model');
    expect(controller.selectedModel, 'custom/my-model');

    // ตรวจสอบว่าถูกเซฟลง SharedPreferences จริง
    expect(prefs.getString(ChatController.keySelectedModel), 'custom/my-model');
    expect(
      prefs.getStringList(ChatController.keyAvailableModels),
      contains('custom/my-model'),
    );

    await controller.removeModel('custom/my-model');
    expect(controller.availableModels, isNot(contains('custom/my-model')));
    expect(controller.selectedModel, 'openai/gpt-5.6-luna');
  });

  test(
    'ChatController sends message, streams reply, and tracks history',
    () async {
      final http.Client mockClient = MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream bodyStream,
      ) async {
        final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
          <List<int>>[utf8.encode('สวัสดี'), utf8.encode('ครับ')],
        );
        return http.StreamedResponse(stream, 200);
      });

      final AiGatewayService service = AiGatewayService(client: mockClient);
      final ChatController controller = ChatController(gatewayService: service);

      await controller.sendMessage('สวัสดี BlueAI');

      expect(controller.messages.length, 2);
      expect(controller.messages[0].isUser, isTrue);
      expect(controller.messages[0].text, 'สวัสดี BlueAI');
      expect(controller.messages[1].isUser, isFalse);
      expect(controller.messages[1].text, 'สวัสดีครับ');
      expect(controller.isLoading, isFalse);

      controller.clearChat();
      expect(controller.messages, isEmpty);
    },
  );

  test('ChatController updates themeModeNotifier independently', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ChatController controller = ChatController(preferences: prefs);

    expect(controller.themeModeNotifier.value, ThemeMode.system);

    await controller.setThemeMode(ThemeMode.dark);
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.themeModeNotifier.value, ThemeMode.dark);

    await controller.toggleThemeMode();
    expect(controller.themeMode, ThemeMode.system);
    expect(controller.themeModeNotifier.value, ThemeMode.system);
  });

  test('stopGeneration aborts streaming and keeps the partial reply', () async {
    final StreamController<List<int>> streamController =
        StreamController<List<int>>();
    final http.Client mockClient = MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream bodyStream,
    ) async {
      return http.StreamedResponse(streamController.stream, 200);
    });

    final AiGatewayService service = AiGatewayService(client: mockClient);
    final ChatController controller = ChatController(gatewayService: service);

    // ยังไม่ await เพราะ stream ยังไม่จบ
    final Future<void> sending = controller.sendMessage('เขียนโค้ดให้หน่อย');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    streamController.add(utf8.encode('คำตอบ'));
    streamController.add(utf8.encode('บางส่วน'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // ระหว่างสตรีม: มีข้อความบางส่วนและ isLoading ต้องยังคงอยู่จนจบจริง
    expect(controller.messages.length, 2);
    expect(controller.messages.last.text, 'คำตอบบางส่วน');
    expect(controller.isLoading, isTrue);

    controller.stopGeneration();
    expect(controller.isLoading, isFalse);

    // chunk ที่มาถึงหลังกด Stop ต้องไม่ถูกนำไปอัปเดตข้อความอีก
    streamController.add(utf8.encode(' ห้ามแสดงส่วนนี้'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.messages.last.text, 'คำตอบบางส่วน');

    await streamController.close();
    await sending;

    // ไม่มี error message และไม่มีข้อความเพิ่มหลัง stream จบ
    expect(controller.messages.length, 2);
    expect(controller.messages.last.isError, isFalse);
    expect(controller.messages.last.text, 'คำตอบบางส่วน');
  });

  test('stream errors mark a partial reply as incomplete and exclude it from history', () async {
    int requestCount = 0;
    List<Map<String, dynamic>>? secondRequestHistory;
    final http.Client mockClient = MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream bodyStream,
    ) async {
      requestCount++;
      final String bodyText = await bodyStream.bytesToString();
      if (requestCount == 2) {
        final Map<String, dynamic> decoded =
            jsonDecode(bodyText) as Map<String, dynamic>;
        secondRequestHistory = (decoded['messages'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }

      final String responseBody = requestCount == 1
          ? 'data: {"type":"text","delta":"คำตอบบางส่วน"}\n\n'
                'data: {"type":"error","error":"quota exceeded"}\n\n'
          : 'data: {"type":"text","delta":"คำตอบใหม่"}\n\n'
                'data: [DONE]\n\n';
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode(responseBody)),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });

    final ChatController controller = ChatController(
      gatewayService: AiGatewayService(client: mockClient),
    );

    await controller.sendMessage('คำถามแรก');
    expect(controller.messages.length, 2);
    expect(controller.messages.last.isError, isTrue);
    expect(controller.messages.last.text, contains('คำตอบบางส่วน'));
    expect(
      controller.messages.last.text,
      contains('การตอบกลับสิ้นสุดลงก่อนดำเนินการเสร็จสมบูรณ์'),
    );

    await controller.sendMessage('คำถามถัดไป');
    expect(
      secondRequestHistory?.any(
        (Map<String, dynamic> message) =>
            message['content'].toString().contains('คำตอบบางส่วน'),
      ),
      isFalse,
    );
  });

  test('sendMessage is blocked while a request is still streaming', () async {
    final StreamController<List<int>> streamController =
        StreamController<List<int>>();
    final http.Client mockClient = MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream bodyStream,
    ) async {
      return http.StreamedResponse(streamController.stream, 200);
    });

    final AiGatewayService service = AiGatewayService(client: mockClient);
    final ChatController controller = ChatController(gatewayService: service);

    final Future<void> first = controller.sendMessage('ข้อความแรก');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    streamController.add(utf8.encode('คำตอบ'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // ส่งซ้อนระหว่างสตรีมไม่ได้ ต้องถูกเมธอดปฏิเสธเงียบ ๆ
    await controller.sendMessage('ข้อความที่สอง');
    expect(controller.messages.where((ChatMessage m) => m.isUser).length, 1);
    expect(controller.messages.first.text, 'ข้อความแรก');

    await streamController.close();
    await first;

    expect(controller.messages.length, 2);
    expect(controller.messages.last.text, 'คำตอบ');
  });

  test('ChatController saves reasoningText and excludes it from next request history', () async {
    List<Map<String, dynamic>>? capturedHistory;

    final http.Client mockClient = MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream bodyStream,
    ) async {
      final String bodyText = await bodyStream.bytesToString();
      final Map<String, dynamic> decoded =
          jsonDecode(bodyText) as Map<String, dynamic>;
      capturedHistory = (decoded['messages'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
        <List<int>>[
          utf8.encode('data: {"type":"thinking","delta":"กำลังคิด"}\n\n'),
          utf8.encode('data: {"type":"thinking","delta":"อย่างละเอียด"}\n\n'),
          utf8.encode('data: {"type":"text","delta":"คำตอบจริง"}\n\n'),
          utf8.encode('data: [DONE]\n\n'),
        ],
      );
      return http.StreamedResponse(
        stream,
        200,
        headers: <String, String>{
          'content-type': 'text/event-stream; charset=utf-8',
        },
      );
    });

    final AiGatewayService service = AiGatewayService(client: mockClient);
    final ChatController controller = ChatController(gatewayService: service);

    // รอบที่ 1: ส่งคำถาม
    await controller.sendMessage('1 + 1 เท่ากับเท่าไหร่?');

    expect(controller.messages.length, 2);
    final ChatMessage aiMessage = controller.messages.last;
    expect(aiMessage.isUser, isFalse);
    expect(aiMessage.text, 'คำตอบจริง');
    expect(aiMessage.reasoningText, 'กำลังคิดอย่างละเอียด');
    expect(aiMessage.thinkingDurationSeconds, isNotNull);

    // รอบที่ 2: ส่งคำถามถัดไป ตรวจสอบว่าประวัติที่ส่งไปมีเฉพาะ content คำตอบจริง ไม่รวม reasoning
    await controller.sendMessage('คำถามที่สอง');
    expect(capturedHistory?.length, 3);
    expect(capturedHistory?[1]['role'], 'assistant');
    expect(capturedHistory?[1]['content'], 'คำตอบจริง');
  });

  test(
    'ChatController persists and deletes API keys in secure storage',
    () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final MemoryKeyStore store = MemoryKeyStore();
      final ChatController controller = ChatController(
        preferences: prefs,
        apiKeyStore: store,
      );
      addTearDown(controller.dispose);
      await controller.setApiKey('  test-secret  ');
      expect(controller.apiKey, 'test-secret');
      expect(store.value, 'test-secret');
      expect(prefs.containsKey(ChatController.keyApiKey), isFalse);
      final ChatController restored = ChatController(
        preferences: prefs,
        apiKeyStore: store,
      );
      addTearDown(restored.dispose);
      await restored.init();
      expect(restored.apiKey, 'test-secret');
      await restored.setApiKey('');
      expect(store.value, isNull);
      expect(restored.apiKey, isEmpty);
    },
  );

  test('legacy key is migrated before its plaintext copy is removed', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(ChatController.keyApiKey, ' legacy-secret ');
    final MemoryKeyStore store = MemoryKeyStore();
    final ChatController controller = ChatController(
      preferences: prefs,
      apiKeyStore: store,
    );
    addTearDown(controller.dispose);
    expect(controller.apiKey, isEmpty);
    await controller.init();
    expect(store.value, 'legacy-secret');
    expect(controller.apiKey, 'legacy-secret');
    expect(prefs.containsKey(ChatController.keyApiKey), isFalse);
  });

  test('failed migration preserves legacy key and blocks sending', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(ChatController.keyApiKey, 'legacy-secret');
    final MemoryKeyStore store = MemoryKeyStore()..failWrites = true;
    final ChatController controller = ChatController(
      preferences: prefs,
      apiKeyStore: store,
    );
    addTearDown(controller.dispose);
    await controller.init();
    expect(prefs.getString(ChatController.keyApiKey), 'legacy-secret');
    expect(controller.apiKey, isEmpty);
    await controller.sendMessage('hello');
    expect(controller.messages.last.isError, isTrue);
    store.failWrites = false;
    await controller.setApiKey('replacement');
    expect(controller.initializationError, isNull);
    expect(store.value, 'replacement');
    expect(prefs.containsKey(ChatController.keyApiKey), isFalse);
  });

  test('existing secure key wins over stale legacy key', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(ChatController.keyApiKey, 'old-key');
    final MemoryKeyStore store = MemoryKeyStore()..value = 'new-key';
    final ChatController controller = ChatController(
      preferences: prefs,
      apiKeyStore: store,
    );
    addTearDown(controller.dispose);
    await controller.init();
    expect(controller.apiKey, 'new-key');
    expect(prefs.containsKey(ChatController.keyApiKey), isFalse);
  });
}
