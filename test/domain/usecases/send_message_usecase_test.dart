// test/domain/usecases/send_message_usecase_test.dart

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/chat_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';
import 'package:tidi_assistant_flutter/domain/usecases/send_message_usecase.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'API_URL=http://test.local\nUSER_ID=test-user');
  });

  // ============================================================
  // ХЕЛПЕРЫ
  // ============================================================

  /// Собирает SendMessageUseCase с подменённым HTTP-клиентом.
  ///
  /// `_FakeStreamedClient` (наш класс ниже) возвращает то, что мы
  /// скажем, — по сети не ходит.
  SendMessageUseCase makeUseCase(http.BaseClient fakeClient) {
    return SendMessageUseCase(
      repository: ChatRepository(
        api: ChatApi(httpClient: AppHttpClient(client: fakeClient)),
      ),
    );
  }

  /// Собирает StreamedResponse с SSE-телом и content-type `text/event-stream`.
  http.StreamedResponse sseResponse(String body) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }

  /// Параметры запроса — минимум, чтобы SendMessageUseCase заработал.
  SendMessageParams params() => const SendMessageParams(
    text: 'вопрос',
    agentId: 'agentic_rag',
    sessionId: 'conv-123',
    ragId: 'rag-456',
  );

  /// SSE-строка для плоского формата (`agentic_rag`).
  String flatSseBody({String messageId = 'resp_abc-123'}) {
    return [
      'event: response.created',
      'data: {"id":"$messageId","status":"in_progress"}',
      '',
      'event: response.output_text.delta',
      'data: {"id":"$messageId","delta":"Ответ AI"}',
      '',
      'event: response.completed',
      'data: {"id":"$messageId","status":"completed","model":"rag/rag-456"}',
      '',
      '',
    ].join('\n');
  }

  /// SSE-строка для вложенного формата (OpenAI-стандарт).
  String nestedSseBody({String messageId = 'resp_xyz-789'}) {
    return [
      'event: response.created',
      'data: {"id":"$messageId","status":"in_progress"}',
      '',
      'event: response.output_text.delta',
      'data: {"id":"$messageId","delta":"Ответ AI"}',
      '',
      'event: response.completed',
      'data: {"response":{"id":"$messageId","status":"completed","model":"epoz"}}',
      '',
      '',
    ].join('\n');
  }

  // ============================================================
  // ТЕСТ 1: плоский формат (agentic_rag)
  // ============================================================

  test(
    'response.completed (плоский, agentic_rag): id читается из event["id"]',
    () async {
      final fakeClient = _FakeStreamedClient((request) {
        return sseResponse(flatSseBody(messageId: 'resp_flat-42'));
      });

      final useCase = makeUseCase(fakeClient);

      final events = await useCase.execute(params()).toList();

      final last = events.last;

      expect(last.isStreaming, isFalse);
      expect(last.id, 'resp_flat-42');
      expect(last.content, 'Ответ AI');
      expect(last.conversationId, 'conv-123');
    },
  );

  // ============================================================
  // ТЕСТ 2: вложенный формат (OpenAI)
  // ============================================================

  test(
    'response.completed (вложенный, OpenAI): id читается из event["response"]["id"]',
    () async {
      final fakeClient = _FakeStreamedClient((request) {
        return sseResponse(nestedSseBody(messageId: 'resp_nested-99'));
      });

      final useCase = makeUseCase(fakeClient);

      final events = await useCase.execute(params()).toList();

      final last = events.last;

      expect(last.isStreaming, isFalse);
      expect(last.id, 'resp_nested-99');
      expect(last.content, 'Ответ AI');
    },
  );

  // ============================================================
  // ТЕСТ 3: поток без response.completed
  // ============================================================

  test('поток без response.completed: финального DTO нет', () async {
    final body = [
      'event: response.created',
      'data: {"id":"resp_x","status":"in_progress"}',
      '',
      '',
    ].join('\n');

    final fakeClient = _FakeStreamedClient((request) {
      return sseResponse(body);
    });

    final useCase = makeUseCase(fakeClient);

    final events = await useCase.execute(params()).toList();

    final hasFinal = events.any((e) => !e.isStreaming);
    expect(hasFinal, isFalse);
  });
}

// ============================================================
// ФЕЙКОВЫЙ HTTP-КЛИЕНТ ДЛЯ СТРИМОВ
// ============================================================

/// Подменяет `send()` — базовый метод `http.BaseClient`.
///
/// `MockClient` из `package:http/testing` возвращает обычный `Response`,
/// а нам нужен `StreamedResponse` (SSE). Поэтому — свой класс.
///
/// `AppHttpClient` внутри зовёт `_client.send(...)` — и наш `send()`
/// отдаёт то, что мы скажем.
class _FakeStreamedClient extends http.BaseClient {
  final http.StreamedResponse Function(http.BaseRequest request) handler;

  _FakeStreamedClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return handler(request);
  }
}
