// test/data/repositories/attachment_repository_test.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tidi_assistant_flutter/core/errors/file_exceptions.dart';
import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/attachment_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/attachment_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';

void main() {
  // ============================================================
  // ОБЩАЯ ИНФРАСТРУКТУРА
  // ============================================================

  late Directory tempDir;
  late File testFile;

  setUp(() async {
    // dotenv в тестах не загружен автоматически — заполняем вручную.
    // AppConfig.baseUrl требует эти ключи, иначе упадёт с Exception.
    dotenv.testLoad(fileInput: 'API_URL=http://test.local\nUSER_ID=test-user');

    tempDir = Directory.systemTemp.createTempSync('attachment_repo_test_');
    testFile = File('${tempDir.path}/накладная.pdf');
    await testFile.writeAsBytes([0x25, 0x50, 0x44, 0x46]); // "%PDF"
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ------------------------------------------------------------
  // ХЕЛПЕР: собирает репозиторий с подменённым http.Client
  // ------------------------------------------------------------
  AttachmentRepository makeRepository(MockClient mockClient) {
    return AttachmentRepository(
      api: AttachmentApi(httpClient: AppHttpClient(client: mockClient)),
    );
  }

  // ------------------------------------------------------------
  // ХЕЛПЕР: валидный JSON ответа POST /v1/files (201)
  // ------------------------------------------------------------
  String validResponseJson({
    String id = 'file-test-123',
    String filename = 'накладная.pdf',
    int bytes = 245678,
    String processingStatus = 'done',
    String status = 'processed',
    String? conversationId,
  }) {
    return jsonEncode({
      'id': id,
      'object': 'file',
      'bytes': bytes,
      'created_at': 1735900000,
      'filename': filename,
      'purpose': 'assistants',
      'status': status,
      'status_details': null,
      'processing_status': processingStatus,
      'conversation_id': conversationId,
    });
  }

  // ------------------------------------------------------------
  // ХЕЛПЕР: JSON ошибки в формате бэкенда
  // ------------------------------------------------------------
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

  /// Создаёт http.Response с UTF-8 — для русских текстов в теле.
  /// Без `charset=utf-8` в content-type `http.Response` использует Latin-1,
  /// и любая кириллица падает с "Invalid argument (string): Contains invalid characters".
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

  group('успешная загрузка', () {
    test('возвращает Attachment со всеми полями из ответа', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(validResponseJson(), 201);
      });

      final repo = makeRepository(mockClient);

      final attachment = await repo.upload(
        file: testFile,
        localId: 'local-42',
        localPath: testFile.path,
      );

      // Из ответа сервера
      expect(attachment.remoteId, 'file-test-123');
      expect(attachment.fileName, 'накладная.pdf');
      expect(attachment.sizeBytes, 245678);
      expect(attachment.status, AttachmentStatus.done);
      expect(attachment.mimeType, 'application/pdf');
      expect(attachment.kind, AttachmentKind.pdf);
      expect(attachment.errorMessage, isNull);

      // Из параметров запроса
      expect(attachment.localId, 'local-42');
      expect(attachment.localPath, testFile.path);

      // Вычислено маппером
      expect(attachment.uploadProgress, 1.0);
      expect(attachment.isUploaded, isTrue);
    });

    test('сохраняет conversationId, если сервер его вернул', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(validResponseJson(conversationId: 'conv-abc'), 201);
      });

      final repo = makeRepository(mockClient);

      final attachment = await repo.upload(
        file: testFile,
        localId: 'local-1',
        localPath: testFile.path,
        conversationId: 'conv-abc',
      );

      expect(attachment.conversationId, 'conv-abc');
    });
  });

  // ============================================================
  // ПРОВЕРКА ЗАПРОСА
  // ============================================================

  group('отправляемый запрос', () {
    test('POST на /v1/files с X-User-Id и multipart', () async {
      late http.BaseRequest capturedRequest;

      final mockClient = MockClient((request) async {
        capturedRequest = request;
        return jsonResponse(validResponseJson(), 201);
      });

      final repo = makeRepository(mockClient);

      await repo.upload(
        file: testFile,
        localId: 'local-1',
        localPath: testFile.path,
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.url.path,
        endsWith('/agents/document_chat/v1/files'),
      );
      expect(capturedRequest.headers['X-User-Id'], isNotNull);

      final contentType = capturedRequest.headers['content-type'] ?? '';
      expect(contentType, startsWith('multipart/form-data'));
    });
  });

  // ============================================================
  // ОШИБКИ СЕРВЕРА
  // ============================================================

  group('ошибки сервера', () {
    test(
      '413 → FileException с текстом от сервера в технических деталях',
      () async {
        final mockClient = MockClient((request) async {
          return jsonResponse(errorJson('Файл слишком большой'), 413);
        });

        final repo = makeRepository(mockClient);

        expect(
          () => repo.upload(
            file: testFile,
            localId: 'local-1',
            localPath: testFile.path,
          ),
          throwsA(
            isA<FileException>()
                .having((e) => e.code, 'code', 'FILE_UPLOAD_FAILED')
                .having(
                  (e) => e.technicalDetails,
                  'technicalDetails',
                  contains('Файл слишком большой'),
                ),
          ),
        );
      },
    );

    test('502 → FileException с текстом от MinerU', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(
          errorJson('Не удалось обработать документ: timeout'),
          502,
        );
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.upload(
          file: testFile,
          localId: 'local-1',
          localPath: testFile.path,
        ),
        throwsA(
          isA<FileException>()
              .having((e) => e.code, 'code', 'FILE_UPLOAD_FAILED')
              .having(
                (e) => e.technicalDetails,
                'technicalDetails',
                contains('Не удалось обработать'),
              ),
        ),
      );
    });

    test('400 → FileException', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse(errorJson('Bad request'), 400);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.upload(
          file: testFile,
          localId: 'local-1',
          localPath: testFile.path,
        ),
        throwsA(
          isA<FileException>().having(
            (e) => e.code,
            'code',
            'FILE_UPLOAD_FAILED',
          ),
        ),
      );
    });

    test('ошибка без JSON в теле — тоже FileException', () async {
      // Например, nginx вернул HTML на 502
      final mockClient = MockClient((request) async {
        return jsonResponse('<html>502 Bad Gateway</html>', 502);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.upload(
          file: testFile,
          localId: 'local-1',
          localPath: testFile.path,
        ),
        throwsA(
          isA<FileException>().having(
            (e) => e.code,
            'code',
            'FILE_UPLOAD_FAILED',
          ),
        ),
      );
    });
  });

  // ============================================================
  // СЕТЕВЫЕ ОШИБКИ
  // ============================================================

  group('сетевые ошибки', () {
    test('ClientException → FileException.uploadFailed', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Connection refused');
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.upload(
          file: testFile,
          localId: 'local-1',
          localPath: testFile.path,
        ),
        throwsA(
          isA<FileException>().having(
            (e) => e.code,
            'code',
            'FILE_UPLOAD_FAILED',
          ),
        ),
      );
    });
  });

  // ============================================================
  // НЕВАЛИДНЫЙ ОТВЕТ
  // ============================================================

  group('невалидный ответ', () {
    test('201 с невалидным JSON → FileException.uploadFailed', () async {
      final mockClient = MockClient((request) async {
        return jsonResponse('это не JSON', 201);
      });

      final repo = makeRepository(mockClient);

      expect(
        () => repo.upload(
          file: testFile,
          localId: 'local-1',
          localPath: testFile.path,
        ),
        throwsA(
          isA<FileException>().having(
            (e) => e.code,
            'code',
            'FILE_UPLOAD_FAILED',
          ),
        ),
      );
    });
  });
}
