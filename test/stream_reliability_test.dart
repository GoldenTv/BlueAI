import 'dart:async';
import 'dart:convert';

import 'package:blue_app/src/ai_gateway_service.dart';
import 'package:blue_app/src/chat_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client sseClient(String body) => MockClient.streaming(
  (_, _) async => http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    headers: {'content-type': 'text/event-stream'},
  ),
);

void main() {
  test(
    'EOF without DONE preserves partial text but marks it incomplete',
    () async {
      final ChatController controller = ChatController(
        gatewayService: AiGatewayService(
          client: sseClient('data: {"type":"text","delta":"partial"}\n\n'),
        ),
      );
      addTearDown(controller.dispose);
      await controller.sendMessage('hello');
      expect(controller.messages.last.isError, isTrue);
      expect(controller.messages.last.text, contains('partial'));
      expect(controller.messages.last.text, contains('คำตอบไม่ครบ'));
      expect(controller.isLoading, isFalse);
    },
  );

  test('reasoning-only response is an error and never enters assistant history', () async {
    int calls = 0;
    List<dynamic>? history;
    final http.Client client = MockClient.streaming((_, body) async {
      history =
          (jsonDecode(await body.bytesToString()) as Map)['messages'] as List;
      calls++;
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            calls == 1
                ? 'data: {"type":"thinking","delta":"private reasoning"}\n\ndata: [DONE]\n\n'
                : 'data: {"type":"text","delta":"answer"}\n\ndata: [DONE]\n\n',
          ),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final ChatController controller = ChatController(
      gatewayService: AiGatewayService(client: client),
    );
    addTearDown(controller.dispose);
    await controller.sendMessage('first');
    expect(controller.messages.last.isError, isTrue);
    expect(controller.messages.last.reasoningText, 'private reasoning');
    expect(controller.messages.last.text, isNot(contains('private reasoning')));
    await controller.sendMessage('second');
    expect(history!.where((dynamic m) => m['role'] == 'assistant'), isEmpty);
  });

  test('raw reasoning-only fallback also fails', () async {
    final AiGatewayService service = AiGatewayService(
      client: MockClient(
        (_) async => http.Response('<think>reasoning only</think>', 200),
      ),
    );
    await expectLater(service.sendMessage(userPrompt: 'hi'), throwsException);
  });

  test('split UTF-8 and final DONE without newline are accepted', () async {
    final List<int> bytes = utf8.encode(
      'data: {"choices":[{"delta":{"content":"คำตอบ","reasoning_content":"คิด"}}]}\r\n\r\ndata: [DONE]',
    );
    final AiGatewayService service = AiGatewayService(
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable(bytes.map((b) => [b])),
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
    );
    expect(await service.sendMessage(userPrompt: 'hi'), 'คำตอบ');
  });

  test('DONE finishes immediately even if the socket stays open', () async {
    bool cancelled = false;
    final StreamController<List<int>> stream = StreamController(
      onCancel: () {
        cancelled = true;
      },
    );
    final AiGatewayService service = AiGatewayService(
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
    );
    final Future<String> reply = service.sendMessage(userPrompt: 'hi');
    stream.add(
      utf8.encode('data: {"type":"text","delta":"answer"}\n\ndata: [DONE]\n\n'),
    );
    expect(await reply.timeout(const Duration(seconds: 1)), 'answer');
    expect(cancelled, isTrue);
    await stream.close();
  });

  test(
    'malformed SSE fails instead of silently dropping answer bytes',
    () async {
      final AiGatewayService service = AiGatewayService(
        client: sseClient('data: {bad json}\n\ndata: [DONE]\n\n'),
      );
      await expectLater(
        service.sendMessage(userPrompt: 'hi'),
        throwsFormatException,
      );
    },
  );

  test(
    'connection timeout aborts transport and disposes a late response',
    () async {
      final Completer<http.StreamedResponse> response = Completer();
      Future<void>? abort;
      bool cancelled = false;
      final StreamController<List<int>> stream = StreamController(
        onCancel: () {
          cancelled = true;
        },
      );
      final AiGatewayService service = AiGatewayService(
        connectionTimeout: const Duration(milliseconds: 25),
        client: MockClient.streaming((request, _) {
          abort = (request as http.AbortableRequest).abortTrigger;
          return response.future;
        }),
      );
      await expectLater(
        service.sendMessage(userPrompt: 'hi'),
        throwsA(isA<TimeoutException>()),
      );
      await abort!.timeout(const Duration(seconds: 1));
      response.complete(http.StreamedResponse(stream.stream, 200));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );

  test(
    'idle timeout cancels a stalled stream and marks partial reply as error',
    () async {
      final Completer<void> aborted = Completer();
      bool cancelled = false;
      final StreamController<List<int>> stream = StreamController(
        onCancel: () {
          cancelled = true;
        },
      );
      final ChatController controller = ChatController(
        gatewayService: AiGatewayService(
          idleTimeout: const Duration(milliseconds: 25),
          client: MockClient.streaming((request, _) async {
            (request as http.AbortableRequest).abortTrigger!.then(
              (_) => aborted.complete(),
            );
            return http.StreamedResponse(
              stream.stream,
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        ),
      );
      addTearDown(controller.dispose);
      final Future<void> sending = controller.sendMessage('hi');
      stream.add(utf8.encode('data: {"type":"text","delta":"partial"}\n\n'));
      await sending;
      await aborted.future.timeout(const Duration(seconds: 1));
      expect(cancelled, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.messages.last.isError, isTrue);
      expect(controller.messages.last.text, contains('partial'));
      await stream.close();
    },
  );

  test('Stop settles a pending request and signals transport abort', () async {
    final Completer<http.StreamedResponse> response = Completer();
    final Completer<void> started = Completer();
    Future<void>? abort;
    final ChatController controller = ChatController(
      gatewayService: AiGatewayService(
        client: MockClient.streaming((request, _) {
          abort = (request as http.AbortableRequest).abortTrigger;
          started.complete();
          return response.future;
        }),
      ),
    );
    addTearDown(controller.dispose);
    final Future<void> sending = controller.sendMessage('hi');
    await started.future;
    controller.stopGeneration();
    await sending.timeout(const Duration(seconds: 1));
    await abort!.timeout(const Duration(seconds: 1));
    expect(controller.isLoading, isFalse);
    expect(controller.messages.where((m) => m.isError), isEmpty);
    response.complete(http.StreamedResponse(const Stream.empty(), 200));
    await Future<void>.delayed(Duration.zero);
  });
}
