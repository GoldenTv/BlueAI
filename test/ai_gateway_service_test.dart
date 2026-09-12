import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blue_app/src/ai_gateway_service.dart';

void main() {
  test('AiGatewayService parses SSE stream chunks correctly', () {
    final AiGatewayService service = AiGatewayService();

    const String sseData = '''
data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":"สวัสดี"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"ครับ มีอะไร"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"ให้ช่วยไหม"},"finish_reason":null}]}

data: [DONE]
''';

    final String parsed = service.parseResponse(sseData);
    expect(parsed, 'สวัสดีครับ มีอะไรให้ช่วยไหม');
  });

  test('AiGatewayService parses normal JSON response correctly', () {
    final AiGatewayService service = AiGatewayService();

    const String jsonData = '''
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "คำตอบแบบ Non-stream"
      }
    }
  ]
}
''';

    final String parsed = service.parseResponse(jsonData);
    expect(parsed, 'คำตอบแบบ Non-stream');
  });

  test(
    'AiGatewayService streams text chunks and notifies onChunk in real-time',
    () async {
      final http.Client mockClient = MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream bodyStream,
      ) async {
        final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
          <List<int>>[
            utf8.encode('สวัสดี'),
            utf8.encode('ชาว'),
            utf8.encode('โลก!'),
          ],
        );
        return http.StreamedResponse(stream, 200);
      });

      final AiGatewayService service = AiGatewayService(
        backendUrl: 'https://blueai-backend.example.workers.dev',
        client: mockClient,
      );

      final List<String> chunks = <String>[];
      final String reply = await service.sendMessage(
        userPrompt: 'ทักทายหน่อย',
        model: 'openai/gpt-5.6-luna',
        onChunk: (String text) {
          chunks.add(text);
        },
      );

      expect(reply, 'สวัสดีชาวโลก!');
      expect(chunks, contains('สวัสดี'));
      expect(chunks, contains('สวัสดีชาว'));
      expect(chunks, contains('สวัสดีชาวโลก!'));
    },
  );

  test(
    'AiGatewayService allows explicit HTTP when development mode is enabled',
    () async {
      Uri? capturedUri;
      final http.Client mockClient = MockClient((http.Request request) async {
        capturedUri = request.url;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode(<String, dynamic>{'reply': 'เชื่อมต่อสำเร็จ'}),
          ),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final AiGatewayService service = AiGatewayService(
        backendUrl: 'http://100.76.203.45:8787',
        client: mockClient,
        allowInsecureHttp: true,
      );

      final String reply = await service.sendMessage(
        userPrompt: 'Hi',
        model: 'openai/gpt-5.6-luna',
      );

      expect(reply, 'เชื่อมต่อสำเร็จ');
      expect(capturedUri?.scheme, 'http');
      expect(capturedUri?.host, '100.76.203.45');
      expect(capturedUri?.port, 8787);
    },
  );

  test('AiGatewayService defaults scheme-less backend URLs to HTTPS', () async {
    Uri? capturedUri;
    final http.Client mockClient = MockClient((http.Request request) async {
      capturedUri = request.url;
      return http.Response.bytes(utf8.encode('สำเร็จ'), 200);
    });

    final AiGatewayService service = AiGatewayService(
      backendUrl: 'blueai.example.com/chat',
      client: mockClient,
    );

    await service.sendMessage(userPrompt: 'สวัสดี');
    expect(capturedUri, Uri.parse('https://blueai.example.com/chat'));
  });

  test(
    'AiGatewayService blocks HTTP unless development mode is enabled',
    () async {
      final AiGatewayService service = AiGatewayService(
        backendUrl: 'http://192.168.1.20:8787',
        client: MockClient((_) async => http.Response('ไม่ควรถูกเรียก', 200)),
      );

      await expectLater(
        service.sendMessage(userPrompt: 'สวัสดี'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('AiGatewayService propagates an SSE error after partial text', () async {
    final http.Client mockClient = MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream bodyStream,
    ) async {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(
            'data: {"type":"text","delta":"คำตอบบางส่วน"}\n\n'
            'data: {"type":"error","error":"quota exceeded"}\n\n',
          ),
        ),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });

    final AiGatewayService service = AiGatewayService(client: mockClient);
    await expectLater(
      service.sendMessage(userPrompt: 'ทดสอบ'),
      throwsA(
        predicate(
          (Object error) => error.toString().contains('quota exceeded'),
        ),
      ),
    );
  });

  test(
    'AiGatewayService streams SSE thinking and text chunks correctly',
    () async {
      final http.Client mockClient = MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream bodyStream,
      ) async {
        final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
          <List<int>>[
            utf8.encode('data: {"type":"thinking","delta":"กำลังคิดสูตร"}\n\n'),
            utf8.encode(
              'data: {"type":"thinking","delta":"คณิตศาสตร์..."}\n\n',
            ),
            utf8.encode('data: {"type":"text","delta":"คำตอบคือ"}\n\n'),
            utf8.encode('data: {"type":"text","delta":" 42"}\n\n'),
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

      String lastText = '';
      String? lastReasoning;

      final String reply = await service.sendMessage(
        userPrompt: 'คิดโจทย์นี้หน่อย',
        model: 'deepseek/deepseek-r1',
        onReasoningChunk: (String text, String? accumulatedReasoning) {
          lastText = text;
          lastReasoning = accumulatedReasoning;
        },
      );

      expect(reply, 'คำตอบคือ 42');
      expect(lastText, 'คำตอบคือ 42');
      expect(lastReasoning, 'กำลังคิดสูตรคณิตศาสตร์...');
    },
  );

  test(
    'AiGatewayService extracts <think> tags from raw text fallback stream',
    () async {
      final http.Client mockClient = MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream bodyStream,
      ) async {
        final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
          <List<int>>[
            utf8.encode('<think>Let me calculate 2+2'),
            utf8.encode('</think>The answer is 4'),
          ],
        );
        return http.StreamedResponse(
          stream,
          200,
          headers: <String, String>{
            'content-type': 'text/plain; charset=utf-8',
          },
        );
      });

      final AiGatewayService service = AiGatewayService(client: mockClient);

      String lastText = '';
      String? lastReasoning;

      final String reply = await service.sendMessage(
        userPrompt: '2+2',
        onReasoningChunk: (String text, String? accumulatedReasoning) {
          lastText = text;
          lastReasoning = accumulatedReasoning;
        },
      );

      expect(reply, 'The answer is 4');
      expect(lastText, 'The answer is 4');
      expect(lastReasoning, 'Let me calculate 2+2');
    },
  );

  test(
    'AiGatewayService sends credentials only in Authorization header',
    () async {
      String? capturedAuthHeader;
      String? capturedBody;

      final http.Client mockClient = MockClient((http.Request request) async {
        capturedAuthHeader = request.headers['Authorization'];
        capturedBody = request.body;
        return http.Response.bytes(
          utf8.encode(jsonEncode(<String, dynamic>{'reply': 'สำเร็จ'})),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

      final AiGatewayService service = AiGatewayService(
        client: mockClient,
        apiKey: 'sk-test-key-12345',
      );

      final String reply = await service.sendMessage(
        userPrompt: 'สวัสดี',
        model: 'openai/gpt-5.6-luna',
      );

      expect(reply, 'สำเร็จ');
      expect(capturedAuthHeader, 'Bearer sk-test-key-12345');
      expect(capturedBody, isNot(contains('sk-test-key-12345')));
    },
  );

  test('AiGatewayService streams reasoning from thinking, thoughts, and reasoning_text', () async {
    final http.Client mockClient = MockClient.streaming((
      http.BaseRequest request,
      http.ByteStream bodyStream,
    ) async {
      final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
        <List<int>>[
          utf8.encode(
            'data: {"choices":[{"delta":{"thinking":"คิดแบบ Claude "}}]}\n\n',
          ),
          utf8.encode(
            'data: {"choices":[{"delta":{"thoughts":"และ Gemini "}}]}\n\n',
          ),
          utf8.encode(
            'data: {"choices":[{"delta":{"thought_content":"และ Qwen "}}]}\n\n',
          ),
          utf8.encode(
            'data: {"choices":[{"delta":{"reasoning_text":"เสร็จสิ้น"}}]}\n\n',
          ),
          utf8.encode(
            'data: {"choices":[{"delta":{"content":"นี่คือคำตอบ"}}]}\n\n',
          ),
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

    String lastText = '';
    String? lastReasoning;

    final String reply = await service.sendMessage(
      userPrompt: 'ทดสอบ',
      onReasoningChunk: (String text, String? accumulatedReasoning) {
        lastText = text;
        lastReasoning = accumulatedReasoning;
      },
    );

    expect(reply, 'นี่คือคำตอบ');
    expect(lastText, 'นี่คือคำตอบ');
    expect(lastReasoning, 'คิดแบบ Claude และ Gemini และ Qwen เสร็จสิ้น');
  });

  test(
    'AiGatewayService streams reasoning from object, array, and content blocks',
    () async {
      final http.Client mockClient = MockClient.streaming((
        http.BaseRequest request,
        http.ByteStream bodyStream,
      ) async {
        final Stream<List<int>> stream = Stream<List<int>>.fromIterable(
          <List<int>>[
            utf8.encode(
              'data: {"choices":[{"delta":{"thinking":{"text":"Object reasoning "}}}]}\n\n',
            ),
            utf8.encode(
              'data: {"choices":[{"delta":{"content":['
              '{"type":"thinking","thinking":"Block reasoning "},'
              '{"type":"text","text":"Block answer"}'
              ']}}]}\n\n',
            ),
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

      String lastText = '';
      String? lastReasoning;

      final String reply = await service.sendMessage(
        userPrompt: 'ทดสอบ',
        onReasoningChunk: (String text, String? accumulatedReasoning) {
          lastText = text;
          lastReasoning = accumulatedReasoning;
        },
      );

      expect(reply, 'Block answer');
      expect(lastText, 'Block answer');
      expect(lastReasoning, 'Object reasoning Block reasoning ');
    },
  );
}
