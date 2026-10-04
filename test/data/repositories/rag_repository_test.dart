// test/data/repositories/rag_repository_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tidi_assistant_flutter/core/errors/network_exceptions.dart';
import 'package:tidi_assistant_flutter/core/errors/rag_exceptions.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/rag_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/rag_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/rag_status.dart';

// ============================================================
// FAKE — ПОДМЕНА RagApi
// ============================================================

/// Fake-реализация [RagApi] для тестов `RagRepository`.
///
/// **Почему fake, а не mock-пакет.** Мокаем **границу** между
/// слоями (`RagApi`), а не внутренность (`AppHttpClient`).
/// Никаких новых зависимостей. Полный контроль над ответами.
///
/// **Соглашение.** Поля `xxxResponse` / `xxxError` — задаются
/// тестом **перед** вызовом. Если `xxxResponse` **не** задан —
/// метод **упадёт** с явной ошибкой (не вернёт `null`).
/// Это **правильно**: тест **скажет**, если забыли настроить.
class FakeRagApi extends RagApi {
  // ---- Настройки ответов ----
  http.Response? createResponse;
  http.Response? listResponse;
  http.Response? getResponse;
  http.Response? updateResponse;
  http.Response? deleteResponse;

  // ---- Настройки ошибок (если заданы — метод их бросает) ----
  Object? createError;
  Object? listError;
  Object? getError;
  Object? updateError;
  Object? deleteError;

  // ---- Записанные параметры вызова (для проверки) ----
  String? lastCreateName;
  String? lastGetRagId;
  String? lastUpdateRagId;
  String? lastDeleteRagId;

  FakeRagApi() : super();

  @override
  Future<http.Response> createRag({
    required String name,
    String? description,
    Map<String, dynamic>? config,
  }) async {
    lastCreateName = name;
    if (createError != null) throw createError!;
    return createResponse!;
  }

  @override
  Future<http.Response> listRags() async {
    if (listError != null) throw listError!;
    return listResponse!;
  }

  @override
  Future<http.Response> getRag({required String ragId}) async {
    lastGetRagId = ragId;
    if (getError != null) throw getError!;
    return getResponse!;
  }

  @override
  Future<http.Response> updateRag({
    required String ragId,
    String? name,
    String? description,
    Map<String, dynamic>? config,
  }) async {
    lastUpdateRagId = ragId;
    if (updateError != null) throw updateError!;
    return updateResponse!;
  }

  @override
  Future<http.Response> deleteRag({required String ragId}) async {
    lastDeleteRagId = ragId;
    if (deleteError != null) throw deleteError!;
    return deleteResponse!;
  }
}

// ============================================================
// УТИЛИТЫ ДЛЯ ТЕСТОВ
// ============================================================

/// Создать `http.Response` с JSON-телом **в UTF-8**.
///
/// **Зачем helper.** Конструктор `http.Response` по умолчанию
/// кодирует тело **в Latin1**, если не указан `charset` в заголовке
/// `content-type`. А Latin1 **не умеет** русские буквы — падает
/// с `Invalid argument (string): Contains invalid characters`.
///
/// **Почему не пишем `headers` руками в каждом тесте.** Дублирование
/// и **риск забыть**. Один helper — **одна** точка правды.
http.Response jsonResponse(String body, int statusCode) {
  return http.Response(
    body,
    statusCode,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

/// Собрать JSON-объект набора **как Map** — для вставки в ответы.
///
/// **Почему Map, а не String.** В тесте `list` нам нужно собрать
/// `{"data": [<set1>, <set2>]}`. Если бы `buildSetMap` возвращал
/// String, пришлось бы делать `jsonDecode(...)`, потом опять
/// `jsonEncode(...)`. **Некрасиво.** Отдаём Map — тест сам решает,
/// как встроить.
///
/// **Про `id`, `name`.** `name` — русский, поэтому ответ идёт
/// через [jsonResponse] (UTF-8), а не через `http.Response` напрямую.
Map<String, dynamic> buildSetMap({
  String id = 'rag-1',
  String name = 'Тестовый',
  String status = 'empty',
  int total = 0,
  int ready = 0,
  int failed = 0,
  int pending = 0,
  int chunksTotal = 0,
  bool hasPending = false,
  bool hasIcon = false,
  String? createdAt,
  String? updatedAt,
}) {
  return {
    'id': id,
    'name': name,
    'status': status,
    'documents': {
      'total': total,
      'ready': ready,
      'failed': failed,
      'pending': pending,
    },
    'chunks_total': chunksTotal,
    'has_pending': hasPending,
    'has_icon': hasIcon,
    'config': {
      'prompt': null,
      'temperature': 0.3,
      'top_k': 5,
      'score_threshold': 0.4,
    },
    'created_at': createdAt ?? '2026-01-01T00:00:00Z',
    'updated_at': updatedAt ?? '2026-01-01T00:00:00Z',
  };
}

// ============================================================
// ТЕСТЫ
// ============================================================

void main() {
  group('RagRepository.create', () {
    test('201 → возвращает RagSet', () async {
      final api = FakeRagApi()
        ..createResponse = jsonResponse(
          jsonEncode(buildSetMap(id: 'rag-42', name: 'Регламенты')),
          201,
        );
      final repo = RagRepository(api: api);

      final set = await repo.create(name: 'Регламенты');

      expect(set.id, 'rag-42');
      expect(set.name, 'Регламенты');
      expect(set.status, RagStatus.empty);
      expect(api.lastCreateName, 'Регламенты');
    });

    test('409 → RagException.limitReached', () async {
      final api = FakeRagApi()
        ..createResponse = jsonResponse('{"error": {"message": "limit"}}', 409);
      final repo = RagRepository(api: api);

      expect(
        () => repo.create(name: 'X'),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_LIMIT_REACHED',
          ),
        ),
      );
    });

    test('400 → RagException.createFailed', () async {
      final api = FakeRagApi()
        ..createResponse = jsonResponse(
          '{"error": {"message": "bad request"}}',
          400,
        );
      final repo = RagRepository(api: api);

      expect(
        () => repo.create(name: 'X'),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_CREATE_FAILED',
          ),
        ),
      );
    });

    test('транспортная ошибка → RagException.createFailed', () async {
      final api = FakeRagApi()
        ..createError = NetworkException.connectionError();
      final repo = RagRepository(api: api);

      expect(
        () => repo.create(name: 'X'),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_CREATE_FAILED',
          ),
        ),
      );
    });

    test('невалидный JSON → RagException.createFailed', () async {
      final api = FakeRagApi()..createResponse = jsonResponse('не json', 201);
      final repo = RagRepository(api: api);

      expect(
        () => repo.create(name: 'X'),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_CREATE_FAILED',
          ),
        ),
      );
    });
  });

  group('RagRepository.list', () {
    test('200 → возвращает список RagSet', () async {
      final body = jsonEncode({
        'data': [
          buildSetMap(id: 'rag-1', name: 'Первый'),
          buildSetMap(id: 'rag-2', name: 'Второй'),
        ],
      });
      final api = FakeRagApi()..listResponse = jsonResponse(body, 200);
      final repo = RagRepository(api: api);

      final sets = await repo.list();

      expect(sets.length, 2);
      expect(sets[0].id, 'rag-1');
      expect(sets[0].name, 'Первый');
      expect(sets[1].id, 'rag-2');
      expect(sets[1].name, 'Второй');
    });

    test('200 с пустым data → пустой список', () async {
      final api = FakeRagApi()
        ..listResponse = jsonResponse('{"data": []}', 200);
      final repo = RagRepository(api: api);

      final sets = await repo.list();

      expect(sets, isEmpty);
    });

    test('200 без data → RagException.createFailed', () async {
      final api = FakeRagApi()
        ..listResponse = jsonResponse('{"foo": "bar"}', 200);
      final repo = RagRepository(api: api);

      expect(
        () => repo.list(),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_CREATE_FAILED',
          ),
        ),
      );
    });

    test('500 → RagException.createFailed', () async {
      final api = FakeRagApi()
        ..listResponse = jsonResponse('{"error": {}}', 500);
      final repo = RagRepository(api: api);

      expect(() => repo.list(), throwsA(isA<RagException>()));
    });
  });

  group('RagRepository.get', () {
    test('200 → возвращает RagSet', () async {
      final api = FakeRagApi()
        ..getResponse = jsonResponse(
          jsonEncode(
            buildSetMap(id: 'rag-42', name: 'Регламенты', status: 'ready'),
          ),
          200,
        );
      final repo = RagRepository(api: api);

      final set = await repo.get('rag-42');

      expect(set.id, 'rag-42');
      expect(set.status, RagStatus.ready);
      expect(api.lastGetRagId, 'rag-42');
    });

    test('404 → RagException.notFound', () async {
      final api = FakeRagApi()
        ..getResponse = jsonResponse('{"error": {}}', 404);
      final repo = RagRepository(api: api);

      expect(
        () => repo.get('rag-missing'),
        throwsA(
          isA<RagException>().having((e) => e.code, 'code', 'RAG_NOT_FOUND'),
        ),
      );
    });

    test('500 → RagException.createFailed', () async {
      final api = FakeRagApi()
        ..getResponse = jsonResponse('{"error": {}}', 500);
      final repo = RagRepository(api: api);

      expect(
        () => repo.get('rag-1'),
        throwsA(
          isA<RagException>().having(
            (e) => e.code,
            'code',
            'RAG_CREATE_FAILED',
          ),
        ),
      );
    });
  });

  group('RagRepository.update', () {
    test('200 → возвращает обновлённый RagSet', () async {
      final api = FakeRagApi()
        ..updateResponse = jsonResponse(
          jsonEncode(buildSetMap(id: 'rag-1', name: 'Новое имя')),
          200,
        );
      final repo = RagRepository(api: api);

      final set = await repo.update(ragId: 'rag-1', name: 'Новое имя');

      expect(set.name, 'Новое имя');
      expect(api.lastUpdateRagId, 'rag-1');
    });

    test('404 → RagException.notFound', () async {
      final api = FakeRagApi()
        ..updateResponse = jsonResponse('{"error": {}}', 404);
      final repo = RagRepository(api: api);

      expect(
        () => repo.update(ragId: 'rag-1', name: 'X'),
        throwsA(
          isA<RagException>().having((e) => e.code, 'code', 'RAG_NOT_FOUND'),
        ),
      );
    });
  });

  group('RagRepository.delete', () {
    test('204 → успешно', () async {
      final api = FakeRagApi()..deleteResponse = jsonResponse('', 204);
      final repo = RagRepository(api: api);

      await repo.delete('rag-1');

      expect(api.lastDeleteRagId, 'rag-1');
    });

    test('200 → тоже успешно', () async {
      final api = FakeRagApi()..deleteResponse = jsonResponse('{}', 200);
      final repo = RagRepository(api: api);

      await repo.delete('rag-1');
    });

    test('404 → RagException.notFound', () async {
      final api = FakeRagApi()
        ..deleteResponse = jsonResponse('{"error": {}}', 404);
      final repo = RagRepository(api: api);

      expect(
        () => repo.delete('rag-1'),
        throwsA(
          isA<RagException>().having((e) => e.code, 'code', 'RAG_NOT_FOUND'),
        ),
      );
    });
  });
}
