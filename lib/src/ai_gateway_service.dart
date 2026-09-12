import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class GatewayException implements Exception {
  const GatewayException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Service สำหรับส่งข้อความและสตรีมคำตอบจาก BlueAI Backend
class AiGatewayService {
  AiGatewayService({
    this.backendUrl = defaultBackendUrl,
    this.apiKey = '',
    this.client,
    this.connectionTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 90),
    this.allowInsecureHttp = const bool.fromEnvironment(
      'BLUEAI_ALLOW_INSECURE_HTTP',
      defaultValue: false,
    ),
  });

  static const String defaultBackendUrl = String.fromEnvironment(
    'BLUEAI_BACKEND_URL',
    defaultValue: 'https://blueai-backend.workers.dev',
  );

  String backendUrl;
  String apiKey;
  final http.Client? client;
  final bool allowInsecureHttp;
  final Duration connectionTimeout;
  final Duration idleTimeout;

  /// ประวัติบทสนทนา (Conversation History) สำหรับ backward compatibility
  final List<Map<String, String>> _history = <Map<String, String>>[];

  /// Cancel only the active request, including injected test transports.
  void Function()? _cancelActive;

  /// ยกเลิก request ที่กำลังสตรีมอยู่ทันที (ใช้โดยปุ่ม Stop)
  /// การปิด client กลาง stream จะทำให้การอ่าน stream throw http.ClientException
  void cancelActiveRequest() {
    _cancelActive?.call();
    _cancelActive = null;
  }

  /// ล้างประวัติบทสนทนา
  void clearHistory() {
    _history.clear();
  }

  /// รายชื่อฟิลด์ที่โมเดลและ Gateway ต่างๆ ใช้สำหรับส่งกระบวนการคิด (Reasoning/Thinking)
  static const List<String> reasoningKeys = <String>[
    'reasoning_content',
    'reasoning',
    'thinking',
    'thought',
    'thoughts',
    'thought_content',
    'reasoning_text',
    'reason',
  ];

  /// แปลง dynamic value เป็น string อย่างปลอดภัย (รองรับ String, List, Map)
  static String extractString(dynamic val) {
    if (val == null) return '';
    if (val is String) return val;
    if (val is List) {
      final StringBuffer buf = StringBuffer();
      for (final dynamic item in val) {
        buf.write(extractString(item));
      }
      return buf.toString();
    }
    if (val is Map) {
      if (val['text'] is String) return val['text'] as String;
      if (val['content'] is String) return val['content'] as String;
      if (val['thinking'] is String) return val['thinking'] as String;
      if (val['thought'] is String) return val['thought'] as String;
      if (val['value'] is String) return val['value'] as String;
    }
    return '';
  }

  /// ดึงข้อความกระบวนการคิด (Reasoning/Thinking) ออกจาก Map ทุกรูปแบบ
  static String extractReasoningFromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return '';
    final StringBuffer buf = StringBuffer();
    for (final String key in reasoningKeys) {
      if (map.containsKey(key) && map[key] != null) {
        final String extracted = extractString(map[key]);
        if (extracted.isNotEmpty) {
          buf.write(extracted);
        }
      }
    }
    return buf.toString();
  }

  /// ดึงข้อความคำตอบและ reasoning ออกจาก array of content blocks
  static (String text, String reasoning) extractFromContentBlocks(
    dynamic content,
  ) {
    if (content is! List) return ('', '');
    final StringBuffer textBuf = StringBuffer();
    final StringBuffer reasoningBuf = StringBuffer();

    for (final dynamic block in content) {
      if (block is String) {
        textBuf.write(block);
      } else if (block is Map) {
        final String type = (block['type']?.toString() ?? '').toLowerCase();
        if (type == 'thinking' || type == 'reasoning' || type == 'thought') {
          final String r = extractString(
            block['thinking'] ??
                block['reasoning'] ??
                block['thought'] ??
                block['text'] ??
                block['content'],
          );
          if (r.isNotEmpty) reasoningBuf.write(r);
        } else {
          final String r = extractReasoningFromMap(block);
          if (r.isNotEmpty) reasoningBuf.write(r);

          if (block['text'] is String) {
            textBuf.write(block['text'] as String);
          } else if (block['content'] is String) {
            textBuf.write(block['content'] as String);
          }
        }
      }
    }
    return (textBuf.toString(), reasoningBuf.toString());
  }

  /// ดึงข้อความคำตอบหลัก (Text/Content) ออกจาก Map
  static String extractTextFromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return '';
    if (map['content'] is String) return map['content'] as String;
    if (map['text'] is String) return map['text'] as String;
    if (map['content'] is List) {
      final (String text, _) = extractFromContentBlocks(map['content']);
      return text;
    }
    return '';
  }

  /// แยกข้อความแท็ก `<think>...</think>` ออกจากคำตอบสำหรับ Fallback stream
  static (String text, String? reasoning) extractThinkingFromRawText(
    String raw,
  ) {
    const String openTag = '<think>';
    const String closeTag = '</think>';

    final int openIdx = raw.indexOf(openTag);
    if (openIdx == -1) {
      return (raw, null);
    }

    final String beforeThink = raw.substring(0, openIdx);
    final int afterOpen = openIdx + openTag.length;
    final int closeIdx = raw.indexOf(closeTag, afterOpen);

    if (closeIdx == -1) {
      // ยังไม่ปิดแท็ก </think> แสดงว่ากำลังอยู่ในช่วงคิด
      final String currentReasoning = raw.substring(afterOpen);
      return (beforeThink.trim(), currentReasoning);
    }

    final String reasoning = raw.substring(afterOpen, closeIdx);
    final String afterThink = raw.substring(closeIdx + closeTag.length);
    final String fullText = (beforeThink + afterThink).trim();
    return (fullText, reasoning);
  }

  /// แปลง Response จาก OpenAI-compatible API หรือ BlueAI Backend
  String parseResponse(String responseBody) {
    final String trimmed = responseBody.trim();

    // กรณีเซิร์ฟเวอร์ตอบกลับมาเป็น Server-Sent Events (SSE)
    if (trimmed.startsWith('data:') ||
        trimmed.contains('chat.completion.chunk') ||
        trimmed.contains('"type":"text"') ||
        trimmed.contains('"type":"thinking"')) {
      final List<String> lines = trimmed.split('\n');
      final StringBuffer fullContent = StringBuffer();

      for (final String line in lines) {
        final String lineTrimmed = line.trim();
        if (lineTrimmed.isEmpty ||
            lineTrimmed == 'data: [DONE]' ||
            lineTrimmed == '[DONE]') {
          continue;
        }

        if (lineTrimmed.startsWith('data:')) {
          final String jsonStr = lineTrimmed.substring(5).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

          try {
            final Map<String, dynamic> chunk =
                jsonDecode(jsonStr) as Map<String, dynamic>;

            // BlueAI SSE format
            if (chunk['type'] == 'text' && chunk['delta'] != null) {
              fullContent.write(extractString(chunk['delta']));
              continue;
            }
            if (chunk['type'] == 'thinking') {
              // ข้อความกระบวนการคิดไม่รวมในคำตอบหลัก
              continue;
            }

            // OpenAI chunk format
            final List<dynamic>? choices = chunk['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final dynamic first = choices[0];
              if (first is Map) {
                final dynamic target = first['delta'] ?? first['message'];
                if (target is Map) {
                  final String text = extractTextFromMap(target);
                  if (text.isNotEmpty) fullContent.write(text);
                }
              }
            }
          } catch (_) {
            // ข้าม chunk ที่ format ไม่สมบูรณ์
          }
        }
      }

      final String result = fullContent.toString();
      if (result.isNotEmpty) {
        return result;
      }
    }

    // กรณีเซิร์ฟเวอร์ตอบกลับเป็น JSON ก้อนเดียวปกติ
    try {
      final Map<String, dynamic> data =
          jsonDecode(trimmed) as Map<String, dynamic>;
      final List<dynamic>? choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final dynamic firstChoice = choices[0];
        if (firstChoice is Map) {
          final dynamic target = firstChoice['message'] ?? firstChoice['delta'];
          if (target is Map) {
            final String text = extractTextFromMap(target);
            if (text.isNotEmpty) {
              final (String cleanText, _) = extractThinkingFromRawText(text);
              return cleanText;
            }
          }
        }
      }
    } catch (_) {}

    // กรณีมีแท็ก <think>...</think> ใน Raw Text
    final (String cleanText, _) = extractThinkingFromRawText(trimmed);
    if (cleanText.isNotEmpty && cleanText != trimmed) {
      return cleanText;
    }

    return trimmed.replaceAll(RegExp(r'^data:\s*'), '');
  }

  static String normalizeBackendUrl(String url) {
    final String value = url.trim();
    if (value.isEmpty ||
        value.startsWith(RegExp(r'https?:\/\/', caseSensitive: false))) {
      return value;
    }
    return 'https://$value';
  }

  Uri _backendUri() {
    final String value = normalizeBackendUrl(backendUrl);
    if (value.isEmpty) {
      throw StateError('ยังไม่ได้กำหนดที่อยู่ Backend');
    }

    final Uri? uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw StateError(
        'ที่อยู่ Backend ไม่ถูกต้อง: "$value"\n'
        'โปรดระบุในรูปแบบ http://IP:PORT หรือ https://DOMAIN',
      );
    }
    if (uri.scheme == 'http' && !allowInsecureHttp) {
      throw StateError(
        'ไม่อนุญาตให้ใช้ที่อยู่ Backend แบบ HTTP เนื่องจาก API Key และข้อความจะไม่มีการเข้ารหัส\n'
        'โปรดใช้ HTTPS หรือเปิดโหมดพัฒนาด้วย '
        '--dart-define=BLUEAI_ALLOW_INSECURE_HTTP=true',
      );
    }
    return uri;
  }

  String _parseBackendReply(String responseBody) {
    try {
      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic> && decoded['reply'] is String) {
        final String reply = (decoded['reply'] as String).trim();
        if (reply.isNotEmpty) {
          return reply;
        }
      }
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        throw Exception(decoded['error'] as String);
      }
    } on FormatException {
      // ใช้ข้อความ fallback ด้านล่างเมื่อ response ไม่ใช่ JSON
    }

    final String fallback = responseBody.trim();
    if (fallback.isEmpty) {
      throw Exception('Backend ไม่ได้ส่งข้อความกลับมา');
    }
    return fallback;
  }

  /// ส่งข้อความไปยัง Backend พร้อมรองรับ Real-time Streaming (Text & Thinking)
  Future<String> sendMessage({
    Map<String, String>? cloudRequest,
    String? accessToken,
    List<Map<String, String>>? messages,
    String? userPrompt,
    String? model,
    String? apiKeyOverride,
    void Function(String accumulatedText)? onChunk,
    void Function(String accumulatedText, String? accumulatedReasoning)?
    onReasoningChunk,
  }) async {
    final List<Map<String, String>> messagesToSend = messages != null
        ? List<Map<String, String>>.from(messages)
        : <Map<String, String>>[
            ..._history,
            if (userPrompt != null)
              <String, String>{'role': 'user', 'content': userPrompt},
          ];

    final Map<String, String>? pendingUser =
        userPrompt != null && messages == null
        ? <String, String>{'role': 'user', 'content': userPrompt}
        : null;
    if (pendingUser != null) _history.add(pendingUser);

    final bool shouldCloseClient = client == null;
    final http.Client httpClient = client ?? http.Client();
    final Completer<void> abort = Completer<void>();
    void cancel() {
      if (!abort.isCompleted) abort.complete();
      if (shouldCloseClient) httpClient.close();
    }

    _cancelActive = cancel;
    final Future<Never> cancelled = abort.future.then<Never>((_) {
      throw http.RequestAbortedException();
    });
    // Attach an error handler even if cancellation happens between reads.
    unawaited(cancelled.then<void>((_) {}, onError: (Object _) {}));
    StreamIterator<String>? chunks;

    try {
      final String effectiveApiKey = (apiKeyOverride ?? apiKey).trim();
      final http.AbortableRequest request =
          http.AbortableRequest(
              'POST',
              cloudRequest == null ? _backendUri() : _cloudUri(),
              abortTrigger: abort.future,
            )
            ..headers['Content-Type'] = 'application/json; charset=utf-8'
            ..headers['Accept'] = 'text/event-stream, text/plain; charset=utf-8'
            ..headers['Cache-Control'] = 'no-cache, no-transform';
      if (effectiveApiKey.isNotEmpty) {
        request.headers[cloudRequest == null
            ? 'Authorization'
            : 'X-AI-API-Key'] = cloudRequest == null
            ? 'Bearer $effectiveApiKey'
            : effectiveApiKey;
      }
      if (cloudRequest != null) {
        if (accessToken == null || accessToken.isEmpty) {
          throw const GatewayException('AUTH_REQUIRED', 'กรุณาเข้าสู่ระบบ');
        }
        request.headers['Authorization'] = 'Bearer $accessToken';
      }
      request.body = jsonEncode(
        cloudRequest ??
            <String, dynamic>{
              'messages': messagesToSend,
              if (model != null && model.isNotEmpty) 'model': model,
            },
      );

      final Future<http.StreamedResponse> sending = httpClient
          .send(request)
          .then((response) {
            if (abort.isCompleted) {
              unawaited(response.stream.listen(null).cancel());
              throw http.RequestAbortedException();
            }
            return response;
          });
      final http.StreamedResponse response = await Future.any([
        sending.timeout(connectionTimeout),
        cancelled,
      ]);
      chunks = StreamIterator(response.stream.transform(utf8.decoder));
      Future<bool> moveNext() =>
          Future.any([chunks!.moveNext().timeout(idleTimeout), cancelled]);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final StringBuffer body = StringBuffer();
        while (await moveNext()) {
          body.write(chunks.current);
        }
        String message =
            'Backend ตอบกลับด้วยรหัสสถานะ HTTP ${response.statusCode}';
        try {
          final dynamic decoded = jsonDecode(body.toString());
          if (decoded is Map<String, dynamic> && decoded['error'] is String) {
            message = decoded['error'] as String;
          }
          if (decoded is Map<String, dynamic>) {
            throw GatewayException(
              decoded['code']?.toString() ?? 'HTTP_${response.statusCode}',
              message,
            );
          }
        } on FormatException {
          /* Use HTTP status for non-JSON errors. */
        }
        throw Exception(message);
      }

      final StringBuffer fullReply = StringBuffer();
      final StringBuffer fullReasoning = StringBuffer();
      String buffer = '';
      bool? isSse =
          (response.headers['content-type'] ?? '').contains('text/event-stream')
          ? true
          : null;
      bool completed = false;
      void notifyUpdate(String text, String? reasoning) {
        onChunk?.call(text);
        onReasoningChunk?.call(text, reasoning);
      }

      void consumeLine(String rawLine) {
        final String line = rawLine.trim();
        if (!line.startsWith('data:')) return;
        final String data = line.substring(5).trim();
        if (data == '[DONE]') {
          completed = true;
          return;
        }
        if (data.isEmpty) return;
        final dynamic decoded = jsonDecode(data);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('รูปแบบเหตุการณ์ SSE ไม่ถูกต้อง');
        }
        if (decoded['type'] == 'error' || decoded['error'] != null) {
          throw GatewayException(
            decoded['code']?.toString() ?? 'STREAM_ERROR',
            decoded['error']?.toString() ??
                'เกิดข้อผิดพลาดระหว่างการสตรีมข้อมูล',
          );
        }
        if (decoded['type'] == 'thinking' && decoded['delta'] != null) {
          fullReasoning.write(extractString(decoded['delta']));
        } else if (decoded['type'] == 'text' && decoded['delta'] != null) {
          fullReply.write(extractString(decoded['delta']));
        } else {
          final dynamic choices = decoded['choices'];
          if (choices is List && choices.isNotEmpty) {
            final dynamic firstChoice = choices.first;
            if (firstChoice is Map) {
              final dynamic delta =
                  firstChoice['delta'] ?? firstChoice['message'];
              if (delta is Map) {
                // 1. Text from delta
                final String text = extractTextFromMap(delta);
                if (text.isNotEmpty) fullReply.write(text);

                // 2. Reasoning from content blocks in delta
                if (delta['content'] is List) {
                  final (_, String blockReasoning) = extractFromContentBlocks(
                    delta['content'],
                  );
                  if (blockReasoning.isNotEmpty) {
                    fullReasoning.write(blockReasoning);
                  }
                }

                // 3. Reasoning from delta keys
                final String deltaReasoning = extractReasoningFromMap(delta);
                if (deltaReasoning.isNotEmpty) {
                  fullReasoning.write(deltaReasoning);
                }
              }

              // 4. Reasoning from choice level
              final String choiceReasoning = extractReasoningFromMap(
                firstChoice,
              );
              if (choiceReasoning.isNotEmpty) {
                fullReasoning.write(choiceReasoning);
              }
            }
          }

          // 5. Reasoning from root level of decoded JSON
          final String rootReasoning = extractReasoningFromMap(decoded);
          if (rootReasoning.isNotEmpty) {
            fullReasoning.write(rootReasoning);
          }
        }
        String currentText = fullReply.toString();
        String? currentReasoning = fullReasoning.isEmpty
            ? null
            : fullReasoning.toString();

        if (currentReasoning == null && currentText.contains('<think>')) {
          final (String cleanText, String? extractedReasoning) =
              extractThinkingFromRawText(currentText);
          currentText = cleanText;
          currentReasoning = extractedReasoning;
        }

        notifyUpdate(currentText, currentReasoning);
      }

      while (!completed && await moveNext()) {
        buffer += chunks.current;
        if (isSse == null) {
          final String prefix = buffer.trimLeft();
          if (prefix.startsWith('data:')) {
            isSse = true;
          } else if (prefix.isNotEmpty && !'data:'.startsWith(prefix)) {
            isSse = false;
          } else {
            continue;
          }
        }
        if (isSse) {
          final List<String> lines = buffer.split('\n');
          buffer = lines.removeLast();
          for (final String line in lines) {
            consumeLine(line);
            if (completed) break;
          }
        } else {
          final (String text, String? reasoning) = extractThinkingFromRawText(
            buffer,
          );
          notifyUpdate(text, reasoning);
        }
      }
      if (isSse == true && !completed && buffer.trim().isNotEmpty) {
        consumeLine(buffer);
      }
      if (isSse == true && !completed) {
        throw Exception(
          'คำตอบไม่ครบถ้วน: การเชื่อมต่อสิ้นสุดลงก่อนพบสัญญาณสิ้นสุดคำตอบ',
        );
      }
      String finalReply = fullReply.toString();
      if (isSse == true) {
        if (fullReasoning.isEmpty && finalReply.contains('<think>')) {
          final (String cleanText, String? extractedReasoning) =
              extractThinkingFromRawText(finalReply);
          finalReply = cleanText;
          if (extractedReasoning != null && extractedReasoning.isNotEmpty) {
            fullReasoning.write(extractedReasoning);
          }
        }
      } else {
        final (String text, String? reasoning) = extractThinkingFromRawText(
          buffer,
        );
        finalReply = text;
        if (reasoning != null) fullReasoning.write(reasoning);
      }
      if (finalReply.trim().isEmpty && fullReasoning.isNotEmpty) {
        throw Exception(
          'โมเดลไม่สามารถตอบกลับได้อย่างสมบูรณ์ เนื่องจากได้รับเฉพาะกระบวนการคิดและไม่มีคำตอบหลัก',
        );
      }
      finalReply = _parseBackendReply(finalReply);
      notifyUpdate(
        finalReply,
        fullReasoning.isEmpty ? null : fullReasoning.toString(),
      );
      if (userPrompt != null && messages == null) {
        _history.add(<String, String>{
          'role': 'assistant',
          'content': finalReply,
        });
      }
      return finalReply;
    } catch (error) {
      cancel();
      if (pendingUser != null) _history.remove(pendingUser);
      if (error is TimeoutException) {
        throw TimeoutException(
          'หมดเวลารอการตอบกลับ โปรดลองอีกครั้ง',
          error.duration,
        );
      }
      rethrow;
    } finally {
      if (_cancelActive == cancel) _cancelActive = null;
      if (chunks != null) unawaited(chunks.cancel());
      if (shouldCloseClient) httpClient.close();
    }
  }

  Uri _cloudUri([String suffix = '']) {
    final uri = _backendUri();
    final base = uri.path
        .replaceFirst(RegExp(r'/v1/chat/?$'), '')
        .replaceFirst(RegExp(r'/$'), '');
    return uri.replace(
      path: '$base/v1/chat$suffix',
      query: null,
      fragment: null,
    );
  }

  Future<void> stopCloudRequest(
    String requestId,
    String token,
    String content,
    String? reasoning,
  ) async {
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .post(
            _cloudUri('/$requestId/stop'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'content': content, 'reasoning': reasoning}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const GatewayException(
          'STOP_UNCONFIRMED',
          'ยังยืนยันการบันทึกคำตอบที่หยุดไม่ได้',
        );
      }
    } finally {
      if (client == null) transport.close();
    }
  }
}
