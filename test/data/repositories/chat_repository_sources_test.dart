// test/data/repositories/chat_repository_sources_test.dart

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/chat_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'API_URL=http://test.local\nUSER_ID=test-user');
  });

  ChatRepository makeRepository(http.Client mockClient) {
    return ChatRepository(
      api: ChatApi(httpClient: AppHttpClient(client: mockClient)),
    );
  }

  http.Response jsonResponse(String body, [int status = 200]) {
    return http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // ============================================================
  // ТЕСТ 1: успех — обёртка {"data": [...]}
  // ============================================================

  test('getSources: обёртка {"data": [...]} читается', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(
        jsonEncode({
          'data': [
            {
              'order': 1,
              'chunk_id': 'chunk-a',
              'document_id': 'doc-1',
              'chunk_index': 0,
              'filename': 'file.pdf',
            },
            {
              'order': 2,
              'chunk_id': 'chunk-b',
              'document_id': 'doc-1',
              'chunk_index': 1,
              'filename': 'file.pdf',
            },
          ],
        }),
      );
    });

    final repo = makeRepository(mockClient);
    final sources = await repo.getSources(
      agentId: 'agentic_rag',
      messageId: 'resp_abc',
    );

    expect(sources.length, 2);
    expect(sources[0].order, 1);
    expect(sources[0].filename, 'file.pdf');
    expect(sources[1].chunkIndex, 1);
  });

  // ============================================================
  // ТЕСТ 2: успех — массив напрямую
  // ============================================================

  test('getSources: массив напрямую читается', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(
        jsonEncode([
          {'order': 1, 'filename': 'file.pdf'},
        ]),
      );
    });

    final repo = makeRepository(mockClient);
    final sources = await repo.getSources(
      agentId: 'agentic_rag',
      messageId: 'resp_abc',
    );

    expect(sources.length, 1);
    expect(sources.first.filename, 'file.pdf');
  });

  // ============================================================
  // ТЕСТ 3: пустой data → пустой список
  // ============================================================

  test('getSources: пустой data → пустой список', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(jsonEncode({'data': []}));
    });

    final repo = makeRepository(mockClient);
    final sources = await repo.getSources(
      agentId: 'agentic_rag',
      messageId: 'resp_abc',
    );

    expect(sources, isEmpty);
  });

  // ============================================================
  // ТЕСТ 4: объект без filename пропускается
  // ============================================================

  test('getSources: объект без filename пропускается', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse(
        jsonEncode({
          'data': [
            {'order': 1},
            {'order': 2, 'filename': 'file.pdf'},
          ],
        }),
      );
    });

    final repo = makeRepository(mockClient);
    final sources = await repo.getSources(
      agentId: 'agentic_rag',
      messageId: 'resp_abc',
    );

    expect(sources.length, 1);
    expect(sources.first.filename, 'file.pdf');
  });

  // ============================================================
  // ТЕСТ 5: 404 → пустой список (не ошибка)
  // ============================================================

  test('getSources: 404 → пустой список', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse('{"error":{"message":"not found"}}', 404);
    });

    final repo = makeRepository(mockClient);
    final sources = await repo.getSources(
      agentId: 'agentic_rag',
      messageId: 'resp_abc',
    );

    expect(sources, isEmpty);
  });
}
