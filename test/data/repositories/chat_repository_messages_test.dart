// test/data/repositories/chat_repository_messages_test.dart

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tidi_assistant_flutter/core/errors/business_exceptions.dart';
import 'package:tidi_assistant_flutter/core/errors/server_exceptions.dart';
import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/chat_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'API_URL=http://test.local\nUSER_ID=test-user');
  });

  // ============================================================
  // ХЕЛПЕРЫ
  // ============================================================

  ChatRepository makeRepository(http.Client mockClient) {
    return ChatRepository(
      api: ChatApi(httpClient: AppHttpClient(client: mockClient)),
    );
  }

  /// JSON-сообщение — минимальный набор полей, который читает MessageDto.
  Map<String, dynamic> messageJson({
    String id = 'msg-1',
    String role = 'user',
    String content = 'привет',
  }) {
    return {
      'id': id,
      'object': 'message',
      'role': role,
      'content': content,
      'status': 'ok',
      'error': null,
      'created_at': '2026-10-08T06:09:58.741980Z',
    };
  }

  http.Response jsonResponse(String body, [int status = 200]) {
    return http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // ============================================================
  // ТЕСТ 1: формат A — массив (document_chat)
  // ============================================================

  test('getMessages: массив напрямую (document_chat) читается', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(jsonEncode([messageJson(id: 'm-A')]));
    });

    final repo = makeRepository(mockClient);
    final messages = await repo.getMessages(
      agentId: 'document_chat',
      conversationId: 'chat-1',
    );

    expect(messages.length, 1);
    expect(messages.first.id, 'm-A');
    expect(messages.first.isFromUser, isTrue);
  });

  // ============================================================
  // ТЕСТ 2: формат B — обёртка {"data": [...]} (agentic_rag)
  // ============================================================

  test('getMessages: обёртка {"data": [...]} (agentic_rag) читается', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(
        jsonEncode({
          'data': [
            messageJson(id: 'm-1', role: 'user', content: 'вопрос'),
            messageJson(id: 'm-2', role: 'assistant', content: 'ответ'),
          ],
          'has_more': false,
        }),
      );
    });

    final repo = makeRepository(mockClient);
    final messages = await repo.getMessages(
      agentId: 'agentic_rag',
      conversationId: 'chat-1',
    );

    expect(messages.length, 2);
    expect(messages[0].id, 'm-1');
    expect(messages[0].isFromUser, isTrue);
    expect(messages[1].id, 'm-2');
    expect(messages[1].isFromUser, isFalse);
  });

  // ============================================================
  // ТЕСТ 3: невалидный ответ — parseError
  // ============================================================

  test('getMessages: ответ без data и не массив — parseError', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(jsonEncode({'data': 'не массив'}));
    });

    final repo = makeRepository(mockClient);

    expect(
      () => repo.getMessages(agentId: 'agentic_rag', conversationId: 'chat-1'),
      throwsA(isA<ServerException>()),
    );
  });

  // ============================================================
  // ТЕСТ 4: 404 → BusinessException.chatNotFound
  // ============================================================

  test(
    'getMessages: 404 превращается в BusinessException.chatNotFound',
    () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"error":{"message":"not found"}}', 404);
      });

      final repo = makeRepository(mockClient);

      expect(
        () =>
            repo.getMessages(agentId: 'agentic_rag', conversationId: 'chat-1'),
        throwsA(isA<BusinessException>()),
      );
    },
  );
}
