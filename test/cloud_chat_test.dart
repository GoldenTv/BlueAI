import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blue_app/app.dart';
import 'package:blue_app/src/api_key_store.dart';
import 'package:blue_app/src/auth_session.dart';
import 'package:blue_app/src/ai_gateway_service.dart';
import 'package:blue_app/src/chat_controller.dart';
import 'package:blue_app/src/cloud_chat_controller.dart';
import 'package:blue_app/src/cloud_repository.dart';

class MemoryRepository implements ChatRepository {
  @override
  String get userId => 'a';
  final data = <String, Conversation>{};
  final history = <String, List<ChatMessage>>{};
  bool fail = false, disposed = false;
  void Function()? changed;
  void Function(bool)? connected;
  int messagesLimit = 0, roomsLimit = 0;
  @override
  Future<List<Conversation>> rooms(int limit) async {
    if (fail) throw Exception('offline');
    roomsLimit = limit;
    return data.values.take(limit).toList();
  }

  @override
  Future<Conversation?> room(String id) async => data[id];
  @override
  Future<List<ChatMessage>> messages(String id, int limit) async {
    messagesLimit = limit;
    return history[id] ?? [];
  }

  @override
  Future<void> create(String id, String title, String model) async {
    data[id] = Conversation(id: id, title: title, model: model);
  }

  @override
  Future<void> edit(
    String id, {
    String? title,
    String? model,
    bool? pinned,
  }) async {
    final old = data[id]!;
    data[id] = Conversation(
      id: id,
      title: title ?? old.title,
      model: model ?? old.model,
      pinned: pinned ?? old.pinned,
    );
  }

  @override
  Future<void> delete(String id) async {
    data.remove(id);
    history.remove(id);
  }

  @override
  Future<void> recover(String id) async {}
  @override
  Future<Map<String, dynamic>?> run(String id) async => null;
  @override
  void watch(
    String? room,
    void Function() changed,
    void Function(bool) connected,
  ) {
    this.changed = changed;
    this.connected = connected;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    changed = null;
    connected = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('cloud reasoning notifies listeners before answer and stream completion', () async {
    final input = StreamController<List<int>>();
    final entered = Completer<void>();
    final c = CloudChatController(
      repository: MemoryRepository(),
      tokenProvider: () async => 'token',
      keyStore: const ApiKeyStore(userId: 'a'),
      monitorConnectivity: false,
      gatewayService: AiGatewayService(
        client: MockClient.streaming((_, _) async {
          entered.complete();
          return http.StreamedResponse(input.stream, 200,
              headers: {'content-type': 'text/event-stream'});
        }),
      ),
    );
    addTearDown(c.dispose);
    await c.init();
    await c.setApiKey('key');
    final first = Completer<void>(), second = Completer<void>();
    c.addListener(() {
      if (c.messages.isEmpty) return;
      final last = c.messages.last;
      if (last.reasoningText == 'first' && !first.isCompleted) first.complete();
      if (last.reasoningText == 'first second' && !second.isCompleted) second.complete();
    });
    final sending = c.sendMessage('hello');
    await entered.future;
    try {
      input.add(utf8.encode('data: {"type":"thinking","delta":"first"}\n\n'));
      await first.future.timeout(const Duration(seconds: 2));
      expect(c.isLoading, isTrue);
      expect(c.messages.last.text, isEmpty);
      input.add(utf8.encode('data: {"type":"thinking","delta":" second"}\n\n'));
      await second.future.timeout(const Duration(seconds: 2));
      expect(c.isLoading, isTrue);
      expect(c.messages.last.text, isEmpty);
    } finally {
      input.add(utf8.encode('data: {"type":"text","delta":"answer"}\n\ndata: [DONE]\n\n'));
      await input.close();
      await sending;
    }
  });
  test(
    'repository pages messages by sequence and preserves persisted metadata',
    () async {
      final pages = <int?>[];
      final client = SupabaseClient(
        'https://project.test',
        'publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/messages');
          expect(request.url.queryParameters['limit'], '50');
          final cursor = request.url.queryParameters['sequence'];
          final before = cursor == null ? null : int.parse(cursor.substring(3));
          pages.add(before);
          final rows = [
            for (var n = 51; n >= 1; n--)
              if (before == null || n < before)
                {
                  'id': 'm$n',
                  'turn_id': 'turn',
                  'sequence': n,
                  'content': 'answer $n',
                  'role': 'assistant',
                  'status': 'stopped',
                  'error_message': null,
                  'reasoning': 'reason',
                  'model': 'model',
                  'created_at': '2026-09-10T00:00:00Z',
                  'thinking_seconds': 3,
                },
          ].take(50).toList();
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final repository = SupabaseChatRepository(client, 'a');
      final messages = await repository.messages('room', 100);
      expect(pages, [null, 2]);
      expect(messages.length, 51);
      expect(messages.first.sequence, 1);
      expect(messages.last.status, 'stopped');
      expect(messages.last.reasoningText, 'reason');
      await repository.dispose();
      await client.dispose();
    },
  );
  test(
    'API keys, sessions and PKCE verifier are isolated by account/project',
    () async {
      const a = ApiKeyStore(userId: 'a'), b = ApiKeyStore(userId: 'b');
      await a.write('key-a');
      expect(await b.read(), isNull);
      await b.write('key-b');
      await a.write('');
      expect(await b.read(), 'key-b');
      const session = SecureSessionStorage('project-a');
      await session.persistSession('session-json');
      expect(await session.hasAccessToken(), isTrue);
      expect(
        await const SecureSessionStorage('project-b').accessToken(),
        isNull,
      );
      await session.removePersistedSession();
      expect(await session.hasAccessToken(), isFalse);
      final pkce = SecurePkceStorage('a');
      await pkce.setItem(key: 'verifier', value: 'proof');
      expect(await SecurePkceStorage('b').getItem(key: 'verifier'), isNull);
      await pkce.removeItem(key: 'verifier');
      expect(await pkce.getItem(key: 'verifier'), isNull);
    },
  );
  testWidgets('production has no guest chat when Supabase is missing', (
    tester,
  ) async {
    await tester.pumpWidget(const BlueApp());
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('configured signed-out app requires Google login', (
    tester,
  ) async {
    final client = (await tester.runAsync(() async {
      final value = SupabaseClient(
        'https://project.test',
        'publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await Future<void>.delayed(Duration.zero);
      return value;
    }))!;
    await tester.pumpWidget(BlueApp(supabaseClient: client));
    await tester.pump();
    expect(find.text('เข้าสู่ระบบด้วย Google'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });
  test(
    'cloud controller does not silently migrate legacy credentials',
    () async {
      FlutterSecureStorage.setMockInitialValues({ApiKeyStore.key: 'legacy'});
      SharedPreferences.setMockInitialValues({
        ChatController.keyApiKey: 'legacy-pref',
      });
      final c = CloudChatController(
        repository: MemoryRepository(),
        tokenProvider: () async => 'token',
        keyStore: const ApiKeyStore(userId: 'a'),
        monitorConnectivity: false,
      );
      await c.init();
      expect(c.apiKey, isEmpty);
      expect(await const ApiKeyStore().read(), 'legacy');
      await c.setApiKey('account-key');
      expect(
        (await SharedPreferences.getInstance()).getString(
          ChatController.keyApiKey,
        ),
        'legacy-pref',
      );
      c.dispose();
    },
  );
  test('new chat preserves old room; reconnect refreshes, remote streaming blocks send', () async {
    final repo = MemoryRepository();
    await repo.create('old', 'Old', 'model');
    repo.history['old'] = [
      ChatMessage(id: 'm', text: 'saved', isUser: false, status: 'streaming'),
    ];
    final c = CloudChatController(
      repository: repo,
      tokenProvider: () async => 'token',
      keyStore: const ApiKeyStore(userId: 'a'),
      monitorConnectivity: false,
    );
    await c.init();
    await c.openRoom('old');
    expect(c.messages.single.text, 'saved');
    expect(c.canSend, isFalse);
    await c.openRoom(null);
    expect(repo.data.containsKey('old'), isTrue);
    expect(c.messages, isEmpty);
    await c.openRoom('old');
    repo.fail = true;
    await c.refresh();
    expect(c.online, isFalse);
    expect(c.messages.single.text, 'saved');
    repo.fail = false;
    repo.history['old'] = [
      ChatMessage(id: 'm', text: 'finished', isUser: false),
    ];
    repo.connected!(true);
    await c.refresh();
    expect(c.online, isTrue);
    expect(c.messages.single.text, 'finished');
    await c.moreRooms();
    await c.moreMessages();
    expect(repo.roomsLimit, 60);
    expect(repo.messagesLimit, 100);
    await c.deleteRoom('old');
    expect(c.activeRoomId, isNull);
    c.dispose();
    expect(repo.disposed, isTrue);
  });
  test(
    'cloud transport separates credentials and sends only the turn identifiers',
    () async {
      final service = AiGatewayService(
        backendUrl: 'https://worker.test',
        apiKey: 'ai-key',
        client: MockClient((request) async {
          expect(request.url.path, '/v1/chat');
          expect(request.headers['authorization'], 'Bearer session-token');
          expect(request.headers['x-ai-api-key'], 'ai-key');
          final body = jsonDecode(request.body) as Map;
          expect(body.containsKey('messages'), isFalse);
          expect(body.containsKey('apiKey'), isFalse);
          return http.Response(
            'data: {"type":"text","delta":"answer"}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      expect(
        await service.sendMessage(
          cloudRequest: {
            'conversationId': 'room',
            'requestId': 'run',
            'messageId': 'msg',
            'prompt': 'hello',
            'model': 'model',
          },
          accessToken: 'session-token',
        ),
        'answer',
      );
    },
  );
  test(
    'duplicate retry keeps request ID; room switch isolates delayed callbacks',
    () async {
      final repo = MemoryRepository();
      await repo.create('other', 'Other', 'model');
      final payloads = <Map<String, dynamic>>[];
      final gate = Completer<http.Response>();
      final entered = Completer<void>();
      final service = AiGatewayService(
        backendUrl: 'https://worker.test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/stop')) {
            return http.Response('{"status":"stopped"}', 200);
          }
          payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (payloads.length == 1) {
            return http.Response(
              '{"code":"STORAGE_UNAVAILABLE","error":"offline"}',
              503,
            );
          }
          entered.complete();
          return gate.future;
        }),
      );
      final c = CloudChatController(
        repository: repo,
        tokenProvider: () async => 'token',
        keyStore: const ApiKeyStore(userId: 'a'),
        gatewayService: service,
        monitorConnectivity: false,
      );
      await c.init();
      await c.setApiKey('key');
      await c.sendMessage('hello');
      expect(c.canRetry, isTrue);
      final retry = c.retryLastRequest();
      await entered.future;
      expect(payloads[0]['requestId'], payloads[1]['requestId']);
      await c.openRoom('other');
      gate.complete(
        http.Response(
          'data: {"type":"text","delta":"late"}\n\ndata: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      await retry;
      expect(c.activeRoomId, 'other');
      expect(c.messages, isEmpty);
      expect(repo.data.length, 2);
      c.dispose();
    },
  );
}
