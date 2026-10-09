// test/domain/usecases/create_rag_usecase_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tidi_assistant_flutter/core/config/app_config.dart';
import 'package:tidi_assistant_flutter/core/errors/rag_exceptions.dart';
import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/rag_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/rag_repository.dart';
import 'package:tidi_assistant_flutter/domain/usecases/create_rag_usecase.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'API_URL=http://test.local\nUSER_ID=test-user');
  });

  // ============================================================
  // ХЕЛПЕРЫ
  // ============================================================

  CreateRagUseCase makeUseCase(http.Client mockClient) {
    return CreateRagUseCase(
      repository: RagRepository(
        api: RagApi(httpClient: AppHttpClient(client: mockClient)),
      ),
    );
  }

  /// Реальный временный файл — нужен для `_validateFile`, который
  /// вызывает `file.length()`.
  File createTempFile({required String filename, int sizeBytes = 100}) {
    final dir = Directory.systemTemp.createTempSync('rag_test_');
    final file = File('${dir.path}/$filename');
    file.writeAsBytesSync(List.filled(sizeBytes, 0));
    return file;
  }

  void cleanupTempFile(File file) {
    try {
      file.parent.deleteSync(recursive: true);
    } catch (_) {}
  }

  http.Response jsonResponse(String body, [int status = 200]) {
    return http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// Минимальный JSON набора — такой, чтобы `RagSetMapper` не упал.
  Map<String, dynamic> ragSetJson({
    String id = 'rag-1',
    String name = 'Набор',
    String status = 'empty',
    int total = 0,
    int ready = 0,
    int failed = 0,
    int pending = 0,
    bool hasPending = false,
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
      'chunks_total': 0,
      'has_pending': hasPending,
      'has_icon': false,
      'config': {
        'prompt': null,
        'temperature': 0.3,
        'top_k': 5,
        'score_threshold': 0.4,
      },
      'created_at': '2026-10-08T06:09:24.807597Z',
      'updated_at': '2026-10-08T06:09:24.807597Z',
    };
  }

  /// JSON одного документа набора.
  Map<String, dynamic> ragDocumentJson({
    String id = 'doc-1',
    String filename = 'file.pdf',
    String status = 'pending',
  }) {
    return {
      'id': id,
      'filename': filename,
      'status': status,
      'created_at': '2026-10-08T06:09:24.807597Z',
    };
  }

  /// JSON ошибки в формате бэкенда.
  String errorJson(String message) {
    return jsonEncode({
      'error': {
        'message': message,
        'type': 'invalid_request_error',
        'param': null,
        'code': null,
      },
    });
  }

  // ============================================================
  // ТЕСТ 1: полный успех
  // ============================================================

  test('полный успех: create → upload → get → documents передан', () async {
    final file = createTempFile(filename: 'договор.pdf');
    addTearDown(() => cleanupTempFile(file));

    final mockClient = MockClient((request) async {
      final path = request.url.path;
      final method = request.method;

      // create
      if (method == 'POST' && path.endsWith('/rags')) {
        return jsonResponse(jsonEncode(ragSetJson(id: 'rag-42')), 201);
      }
      // uploadDocuments
      if (method == 'POST' && path.endsWith('/documents')) {
        return jsonResponse(
          jsonEncode({
            'documents': [
              ragDocumentJson(id: 'doc-1', filename: 'договор.pdf'),
            ],
          }),
          202,
        );
      }
      // get
      if (method == 'GET' && path.endsWith('/rags/rag-42')) {
        return jsonResponse(
          jsonEncode(
            ragSetJson(
              id: 'rag-42',
              status: 'ingesting',
              total: 1,
              pending: 1,
              hasPending: true,
            ),
          ),
        );
      }

      return jsonResponse('{"error":{"message":"unexpected request"}}', 500);
    });

    final useCase = makeUseCase(mockClient);
    final result = await useCase.execute(name: 'Регламенты', files: [file]);

    expect(result.isPartial, isFalse);
    expect(result.uploadError, isNull);
    expect(result.set.id, 'rag-42');
    expect(result.set.status.name, 'ingesting');
    expect(result.documents.length, 1);
    expect(result.documents.first.filename, 'договор.pdf');
  });

  // ============================================================
  // ТЕСТ 2: частичная загрузка — upload упал, документы перечитаны
  // ============================================================

  test(
    'частичная загрузка: upload 413 → isPartial, документы перечитаны',
    () async {
      final file = createTempFile(filename: 'большой.pdf');
      addTearDown(() => cleanupTempFile(file));

      final mockClient = MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        // create
        if (method == 'POST' && path.endsWith('/rags')) {
          return jsonResponse(jsonEncode(ragSetJson(id: 'rag-77')), 201);
        }
        // uploadDocuments → 413 (частичная загрузка)
        if (method == 'POST' && path.endsWith('/documents')) {
          return jsonResponse(errorJson('Файл слишком большой'), 413);
        }
        // get (перечитать набор)
        if (method == 'GET' && path.endsWith('/rags/rag-77')) {
          return jsonResponse(
            jsonEncode(
              ragSetJson(id: 'rag-77', status: 'ready', total: 1, ready: 1),
            ),
          );
        }
        // listDocuments (перечитать документы)
        if (method == 'GET' && path.endsWith('/rags/rag-77/documents')) {
          return jsonResponse(
            jsonEncode({
              'data': [
                ragDocumentJson(
                  id: 'doc-A',
                  filename: 'приняли.pdf',
                  status: 'success',
                ),
              ],
            }),
          );
        }

        return jsonResponse('{"error":{"message":"unexpected"}}', 500);
      });

      final useCase = makeUseCase(mockClient);
      final result = await useCase.execute(name: 'Регламенты', files: [file]);

      expect(result.isPartial, isTrue);
      expect(result.uploadError, isNotNull);
      expect(result.uploadError!.code, 'RAG_FILE_TOO_LARGE');
      expect(result.set.id, 'rag-77');
      expect(result.set.status.name, 'ready');
      expect(result.documents.length, 1);
      expect(result.documents.first.filename, 'приняли.pdf');
    },
  );

  // ============================================================
  // ТЕСТ 3: частичная загрузка + listDocuments упал → пустой список
  // ============================================================

  test(
    'частичная загрузка + listDocuments 500 → isPartial, documents = []',
    () async {
      final file = createTempFile(filename: 'файл.pdf');
      addTearDown(() => cleanupTempFile(file));

      final mockClient = MockClient((request) async {
        final path = request.url.path;
        final method = request.method;

        if (method == 'POST' && path.endsWith('/rags')) {
          return jsonResponse(jsonEncode(ragSetJson(id: 'rag-88')), 201);
        }
        if (method == 'POST' && path.endsWith('/documents')) {
          return jsonResponse(errorJson('Сервер упал'), 502);
        }
        if (method == 'GET' && path.endsWith('/rags/rag-88')) {
          return jsonResponse(jsonEncode(ragSetJson(id: 'rag-88')));
        }
        if (method == 'GET' && path.endsWith('/rags/rag-88/documents')) {
          // listDocuments падает — use-case должен вернуть пустой список
          return jsonResponse(errorJson('server error'), 500);
        }

        return jsonResponse('{"error":{"message":"unexpected"}}', 500);
      });

      final useCase = makeUseCase(mockClient);
      final result = await useCase.execute(name: 'Регламенты', files: [file]);

      expect(result.isPartial, isTrue);
      expect(result.uploadError, isNotNull);
      expect(result.set.id, 'rag-88');
      expect(result.documents, isEmpty);
    },
  );

  // ============================================================
  // ТЕСТ 4: create упал → исключение летит наружу
  // ============================================================

  test('create вернул 400 → исключение наружу (не partial)', () async {
    final file = createTempFile(filename: 'файл.pdf');
    addTearDown(() => cleanupTempFile(file));

    final mockClient = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/rags')) {
        return jsonResponse(errorJson('Невалидное тело'), 400);
      }
      return jsonResponse('{"error":{"message":"unexpected"}}', 500);
    });

    final useCase = makeUseCase(mockClient);

    expect(
      () => useCase.execute(name: 'Имя', files: [file]),
      throwsA(isA<RagException>()),
    );
  });

  // ============================================================
  // ТЕСТ 5: валидация — пустое имя, до сети не доходит
  // ============================================================

  test('пустое имя → ArgumentError, HTTP-запрос не идёт', () async {
    var requestCount = 0;
    final mockClient = MockClient((request) async {
      requestCount++;
      return jsonResponse('{}', 200);
    });

    final useCase = makeUseCase(mockClient);

    final file = createTempFile(filename: 'файл.pdf');
    addTearDown(() => cleanupTempFile(file));

    expect(
      () => useCase.execute(name: '', files: [file]),
      throwsA(isA<ArgumentError>()),
    );

    // До сети дело не дошло — 0 запросов.
    expect(requestCount, 0);
  });

  // ============================================================
  // ТЕСТ 6: валидация — пустой список файлов
  // ============================================================

  test('пустой список файлов → ArgumentError', () async {
    final mockClient = MockClient((request) async {
      return jsonResponse('{}', 200);
    });

    final useCase = makeUseCase(mockClient);

    expect(
      () => useCase.execute(name: 'Имя', files: const []),
      throwsA(isA<ArgumentError>()),
    );
  });

  // ============================================================
  // ТЕСТ 7: валидация — неподдерживаемый формат
  // ============================================================

  test('неподдерживаемый формат → RagException.unsupportedFormat', () async {
    final file = createTempFile(filename: 'файл.xyz');
    addTearDown(() => cleanupTempFile(file));

    final mockClient = MockClient((request) async {
      return jsonResponse('{}', 200);
    });

    final useCase = makeUseCase(mockClient);

    expect(
      () => useCase.execute(name: 'Имя', files: [file]),
      throwsA(
        isA<RagException>().having(
          (e) => e.code,
          'code',
          'RAG_UNSUPPORTED_FORMAT',
        ),
      ),
    );
  });

  // ============================================================
  // ТЕСТ 8: валидация — слишком большой файл
  // ============================================================

  test('файл больше лимита → RagException.fileTooLarge', () async {
    final file = createTempFile(
      filename: 'big.pdf',
      sizeBytes: AppConfig.ragMaxFileSizeBytes + 1,
    );
    addTearDown(() => cleanupTempFile(file));

    final mockClient = MockClient((request) async {
      return jsonResponse('{}', 200);
    });

    final useCase = makeUseCase(mockClient);

    expect(
      () => useCase.execute(name: 'Имя', files: [file]),
      throwsA(
        isA<RagException>().having((e) => e.code, 'code', 'RAG_FILE_TOO_LARGE'),
      ),
    );
  });
}
