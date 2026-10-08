// test/data/repositories/chat_repository_conversations_test.dart

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  /// Репозиторий с подменённым HTTP-клиентом.
  ///
  /// `MockClient` здесь подходит: `getConversations` — обычный GET,
  /// стрима нет. Возвращаем `http.Response`.
  ChatRepository makeRepository(http.Client mockClient) {
    return ChatRepository(
      api: ChatApi(httpClient: AppHttpClient(client: mockClient)),
    );
  }

  /// JSON-ответ с одним чатом — для простоты.
  Map<String, dynamic> chatJson({
    String id = 'chat-1',
    String title = 'Название',
  }) {
    return {
      'id': id,
      'title': title,
      'created_at': '2026-10-08T06:09:24.807597Z',
      'updated_at': '2026-10-08T06:21:43.266685Z',
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

  test('getConversations: массив напрямую (document_chat) читается', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(jsonEncode([chatJson(id: 'chat-A')]));
    });

    final repo = makeRepository(mockClient);
    final chats = await repo.getConversations(agentId: 'document_chat');

    expect(chats.length, 1);
    expect(chats.first.id, 'chat-A');
  });

  // ============================================================
  // ТЕСТ 2: формат B — обёртка {"data": [...]} (agentic_rag)
  // ============================================================

  test(
    'getConversations: обёртка {"data": [...]} (agentic_rag) читается',
    () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(
          jsonEncode({
            'data': [chatJson(id: 'chat-B')],
          }),
        );
      });

      final repo = makeRepository(mockClient);
      final chats = await repo.getConversations(agentId: 'agentic_rag');

      expect(chats.length, 1);
      expect(chats.first.id, 'chat-B');
    },
  );

  // ============================================================
  // ТЕСТ 3: невалидный ответ — должен быть ServerException.parseError
  // ============================================================

  test('getConversations: ответ без data и не массив — parseError', () async {
    final mockClient = MockClient((request) async {
      // Обёртка есть, но data — не массив.
      return jsonResponse(jsonEncode({'data': 'не массив'}));
    });

    final repo = makeRepository(mockClient);

    expect(
      () => repo.getConversations(agentId: 'agentic_rag'),
      throwsA(isA<ServerException>()),
    );
  });

  // ============================================================
  // ТЕСТ 4: 404 → пустой список (как было раньше)
  // ============================================================

  test('getConversations: 404 возвращает пустой список', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse('{"error":{"message":"not found"}}', 404);
    });

    final repo = makeRepository(mockClient);
    final chats = await repo.getConversations(agentId: 'document_chat');

    expect(chats, isEmpty);
  });
}
