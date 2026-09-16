// test/data/repositories/chat_repository_input_test.dart

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tidi_assistant_flutter/core/network/http_client.dart';
import 'package:tidi_assistant_flutter/data/datasources/remote/chat_api.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';

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
  // ХЕЛПЕР: DTO вложения с готовыми дефолтами
  // ------------------------------------------------------------
  Attachment makeAttachment({
    String localId = 'local-1',
    String? remoteId = 'file-123',
    String fileName = 'накладная.pdf',
    String mimeType = 'application/pdf',
    AttachmentKind kind = AttachmentKind.pdf,
    AttachmentStatus status = AttachmentStatus.done,
  }) {
    return Attachment(
      localId: localId,
      remoteId: remoteId,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: 1024,
      localPath: '/tmp/$fileName',
      kind: kind,
      status: status,
    );
  }

  // ------------------------------------------------------------
  // ХЕЛПЕР: вызывает sendMessageStream и перехватывает тело запроса
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> captureRequestBody({
    required String text,
    required List<Attachment> attachments,
  }) async {
    late http.Request capturedRequest;

    final mockClient = MockClient((request) async {
      capturedRequest = request;
      // Пустой ответ: мы проверяем только то, что ушло НА сервер,
      // а не то, что от него пришло. 200 — чтобы не упало на проверке статуса.
      return http.Response('', 200);
    });

    final repo = makeRepository(mockClient);

    await repo.sendMessageStream(text: text, attachments: attachments);

    return jsonDecode(capturedRequest.body) as Map<String, dynamic>;
  }

  // ============================================================
  // БЕЗ ВЛОЖЕНИЙ — input = строка
  // ============================================================

  group('без вложений', () {
    test('input — строка с текстом', () async {
      final body = await captureRequestBody(
        text: 'Привет',
        attachments: const [],
      );

      expect(body['input'], 'Привет');
      expect(body['input'], isA<String>());
    });

    test('model, stream на месте', () async {
      final body = await captureRequestBody(
        text: 'Привет',
        attachments: const [],
      );

      expect(body['model'], 'auto');
      expect(body['stream'], true);
    });
  });

  // ============================================================
  // С ВЛОЖЕНИЯМИ — input = массив items
  // ============================================================

  group('с вложениями', () {
    test('input — массив items с правильной структурой', () async {
      final body = await captureRequestBody(
        text: 'Какая сумма в накладной?',
        attachments: [makeAttachment(remoteId: 'file-abc')],
      );

      final input = body['input'];
      expect(input, isA<List>());
      expect((input as List).length, 1);

      final item = input[0] as Map<String, dynamic>;
      expect(item['role'], 'user');

      final content = item['content'] as List;
      expect(content.length, 2);

      // 1-я часть — текст
      final textPart = content[0] as Map<String, dynamic>;
      expect(textPart['type'], 'input_text');
      expect(textPart['text'], 'Какая сумма в накладной?');

      // 2-я часть — файл, file_id ПЛОСКИЙ (не вложенный под "file")
      final filePart = content[1] as Map<String, dynamic>;
      expect(filePart['type'], 'input_file');
      expect(filePart['file_id'], 'file-abc');
    });

    test('два вложения — оба в content', () async {
      final body = await captureRequestBody(
        text: 'Сравни документы',
        attachments: [
          makeAttachment(localId: 'l1', remoteId: 'file-1'),
          makeAttachment(localId: 'l2', remoteId: 'file-2'),
        ],
      );

      final input = body['input'] as List;
      final content = (input[0] as Map<String, dynamic>)['content'] as List;

      // 1 текст + 2 файла = 3 части
      expect(content.length, 3);

      final fileIds = content
          .where((c) => (c as Map)['type'] == 'input_file')
          .map((c) => (c as Map)['file_id'])
          .toList();

      expect(fileIds, ['file-1', 'file-2']);
    });

    test('пустой текст + вложение — валидный массив', () async {
      // Пользователь прикрепил файл и не ввёл текст.
      // Мы не блокируем такое на этом уровне — отправим пустую input_text.
      final body = await captureRequestBody(
        text: '',
        attachments: [makeAttachment(remoteId: 'file-xyz')],
      );

      final input = body['input'] as List;
      final content = (input[0] as Map<String, dynamic>)['content'] as List;

      expect(content[0]['type'], 'input_text');
      expect(content[0]['text'], '');
      expect(content[1]['type'], 'input_file');
      expect(content[1]['file_id'], 'file-xyz');
    });
  });

  // ============================================================
  // ВЛОЖЕНИЯ БЕЗ remoteId — отбрасываются
  // ============================================================

  group('незагруженные вложения', () {
    test('вложение без remoteId — пропускается', () async {
      final body = await captureRequestBody(
        text: 'Вопрос',
        attachments: [
          makeAttachment(localId: 'l1', remoteId: 'file-ok'),
          makeAttachment(localId: 'l2', remoteId: null), // не загружено
        ],
      );

      final input = body['input'] as List;
      final content = (input[0] as Map<String, dynamic>)['content'] as List;

      // 1 текст + 1 файл (второй отфильтрован)
      expect(content.length, 2);
      expect(content[1]['file_id'], 'file-ok');
    });

    test('все вложения без remoteId — input снова строка', () async {
      final body = await captureRequestBody(
        text: 'Просто вопрос',
        attachments: [
          makeAttachment(localId: 'l1', remoteId: null),
          makeAttachment(localId: 'l2', remoteId: null),
        ],
      );

      // Ни одно вложение не годится — fallback на строку
      expect(body['input'], 'Просто вопрос');
      expect(body['input'], isA<String>());
    });
  });
}
