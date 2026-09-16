// test/data/repositories/chat_repository_route_test.dart

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tidi_assistant_flutter/core/errors/network_exceptions.dart';
import 'package:tidi_assistant_flutter/core/errors/server_exceptions.dart';
import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/chat_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';

void main() {
  // ============================================================
  // ИНФРАСТРУКТУРА
  // ============================================================

  setUp(() {
    // AppConfig.baseUrl требует эти ключи — иначе упадёт с Exception.
    dotenv.testLoad(fileInput: 'API_URL=http://test.local\nUSER_ID=test-user');
  });

  // ------------------------------------------------------------
  // ХЕЛПЕР: репозиторий с подменённым http.Client
  // ------------------------------------------------------------
  ChatRepository makeRepository(MockClient mockClient) {
    return ChatRepository(
      api: ChatApi(httpClient: AppHttpClient(client: mockClient)),
    );
  }

  // ------------------------------------------------------------
  // ХЕЛПЕР: http.Response с UTF-8 (иначе кириллица падает на Latin-1)
  // ------------------------------------------------------------
  http.Response jsonResponse(String body, int status) {
    return http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // ============================================================
  // УСПЕХ
  // ============================================================

  group('успешный роутинг', () {
    test('возвращает agent_id из ответа', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"agent": "epoz"}', 200);
      });

      final repo = makeRepository(mockClient);
      final agentId = await repo.getRoute('как подать заявку на тендер');

      expect(agentId, 'epoz');
    });

    test('возвращает document_chat', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"agent": "document_chat"}', 200);
      });

      final repo = makeRepository(mockClient);
      final agentId = await repo.getRoute('про что документ');

      expect(agentId, 'document_chat');
    });

    test('отправляет POST на /route с телом {"message": ...}', () async {
      late http.Request capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return jsonResponse('{"agent": "chat"}', 200);
      });

      final repo = makeRepository(mockClient);
      await repo.getRoute('привет');

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.path, endsWith('/route'));

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['message'], 'привет');
    });
  });

  // ============================================================
  // ОШИБКИ СЕРВЕРА
  // ============================================================

  group('ошибки сервера', () {
    test('500 → ServerException', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"error": {"message": "boom"}}', 500);
      });

      final repo = makeRepository(mockClient);

      expect(() => repo.getRoute('привет'), throwsA(isA<ServerException>()));
    });

    test('404 → ServerException', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"error": {"message": "not found"}}', 404);
      });

      final repo = makeRepository(mockClient);

      expect(() => repo.getRoute('привет'), throwsA(isA<ServerException>()));
    });
  });

  // ============================================================
  // НЕВАЛИДНЫЙ ОТВЕТ (200, но контракт нарушен)
  // ============================================================

  group('невалидный ответ', () {
    test('не-JSON в теле → ServerException.parseError', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('это не JSON', 200);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.getRoute('привет'),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', 'PARSE_ERROR'),
        ),
      );
    });

    test('отсутствует поле agent → ServerException.parseError', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"foo": "bar"}', 200);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.getRoute('привет'),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', 'PARSE_ERROR'),
        ),
      );
    });

    test('пустой agent → ServerException.parseError', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"agent": ""}', 200);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.getRoute('привет'),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', 'PARSE_ERROR'),
        ),
      );
    });

    test('agent — число, а не строка → ServerException.parseError', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('{"agent": 123}', 200);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.getRoute('привет'),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'code', 'PARSE_ERROR'),
        ),
      );
    });
  });

  // ============================================================
  // СЕТЕВЫЕ ОШИБКИ
  // ============================================================

  group('сетевые ошибки', () {
    test('ClientException → NetworkException', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection refused');
      });

      final repo = makeRepository(mockClient);

      expect(() => repo.getRoute('привет'), throwsA(isA<NetworkException>()));
    });
  });
}
