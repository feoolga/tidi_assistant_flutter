// test/data/models/attachment_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/attachment_dto.dart';

void main() {
  // ============================================================
  // ХЕЛПЕР: создаёт валидный JSON ответа POST /v1/files
  // ============================================================

  /// Собирает JSON, который отдаёт бэкенд.
  ///
  /// Все параметры имеют валидные значения по умолчанию — в тесте
  /// переопределяем только то, что реально проверяем.
  Map<String, dynamic> validJson({
    String id = 'file-123',
    String object = 'file',
    int bytes = 245678,
    int createdAt = 1735900000,
    String filename = 'накладная.pdf',
    String purpose = 'assistants',
    String status = 'processed',
    String? statusDetails,
    String processingStatus = 'done',
    String? conversationId,
  }) {
    return {
      'id': id,
      'object': object,
      'bytes': bytes,
      'created_at': createdAt,
      'filename': filename,
      'purpose': purpose,
      'status': status,
      'status_details': statusDetails,
      'processing_status': processingStatus,
      'conversation_id': conversationId,
    };
  }

  // ============================================================
  // ПАРСИНГ ОБЯЗАТЕЛЬНЫХ ПОЛЕЙ
  // ============================================================

  group('парсинг обязательных полей', () {
    test('id', () {
      final dto = AttachmentDto.fromJson(validJson(id: 'file-abc'));
      expect(dto.id, 'file-abc');
    });

    test('object', () {
      final dto = AttachmentDto.fromJson(validJson(object: 'file'));
      expect(dto.object, 'file');
    });

    test('bytes', () {
      final dto = AttachmentDto.fromJson(validJson(bytes: 12345));
      expect(dto.bytes, 12345);
    });

    test('createdAt (Unix-время в секундах)', () {
      final dto = AttachmentDto.fromJson(validJson(createdAt: 1735900000));
      expect(dto.createdAt, 1735900000);
    });

    test('filename', () {
      final dto = AttachmentDto.fromJson(validJson(filename: 'договор.pdf'));
      expect(dto.filename, 'договор.pdf');
    });

    test('purpose', () {
      final dto = AttachmentDto.fromJson(validJson(purpose: 'assistants'));
      expect(dto.purpose, 'assistants');
    });

    test('status', () {
      final dto = AttachmentDto.fromJson(validJson(status: 'processed'));
      expect(dto.status, 'processed');
    });

    test('processingStatus', () {
      final dto = AttachmentDto.fromJson(validJson(processingStatus: 'done'));
      expect(dto.processingStatus, 'done');
    });

    test('все обязательные поля из полного JSON', () {
      final dto = AttachmentDto.fromJson(
        validJson(
          id: 'file-85b365de',
          object: 'file',
          bytes: 245678,
          createdAt: 1735900000,
          filename: 'накладная.pdf',
          purpose: 'assistants',
          status: 'processed',
          processingStatus: 'done',
        ),
      );

      expect(dto.id, 'file-85b365de');
      expect(dto.object, 'file');
      expect(dto.bytes, 245678);
      expect(dto.createdAt, 1735900000);
      expect(dto.filename, 'накладная.pdf');
      expect(dto.purpose, 'assistants');
      expect(dto.status, 'processed');
      expect(dto.processingStatus, 'done');
    });
  });

  // ============================================================
  // NULLABLE ПОЛЯ
  // ============================================================

  group('nullable поля', () {
    group('statusDetails', () {
      test('null, если отсутствует', () {
        final dto = AttachmentDto.fromJson(validJson());
        expect(dto.statusDetails, isNull);
      });

      test('null, если явно null', () {
        final dto = AttachmentDto.fromJson(validJson(statusDetails: null));
        expect(dto.statusDetails, isNull);
      });

      test('текст, если передан', () {
        final dto = AttachmentDto.fromJson(
          validJson(statusDetails: 'MinerU timeout'),
        );
        expect(dto.statusDetails, 'MinerU timeout');
      });
    });

    group('conversationId', () {
      test('null, если отсутствует', () {
        final dto = AttachmentDto.fromJson(validJson());
        expect(dto.conversationId, isNull);
      });

      test('null, если явно null', () {
        final dto = AttachmentDto.fromJson(validJson(conversationId: null));
        expect(dto.conversationId, isNull);
      });

      test('UUID, если передан', () {
        final dto = AttachmentDto.fromJson(
          validJson(conversationId: '3fa85f64-5717-4562-b3fc-2c963f66afa6'),
        );
        expect(dto.conversationId, '3fa85f64-5717-4562-b3fc-2c963f66afa6');
      });
    });
  });

  // ============================================================
  // УСТОЙЧИВОСТЬ К НЕОЖИДАННОМУ JSON
  // ============================================================

  group('устойчивость', () {
    test('неизвестные поля игнорируются', () {
      // Бэкенд может добавить новые поля — мы не должны падать
      final json = validJson()
        ..['md5'] =
            'abc123def456' // новое поле
        ..['download_url'] =
            'https://...' // ещё одно
        ..['expires_at'] = 1735999999; // и ещё

      // Не должно бросить исключение
      final dto = AttachmentDto.fromJson(json);

      // Известные поля всё равно читаются
      expect(dto.id, 'file-123');
      expect(dto.filename, 'накладная.pdf');
    });

    test('невалидный тип id (int) → TypeError', () {
      final json = validJson();
      json['id'] = 123; // должно быть String

      expect(() => AttachmentDto.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('невалидный тип bytes (String) → TypeError', () {
      final json = validJson();
      json['bytes'] = '245678'; // должно быть int

      expect(() => AttachmentDto.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('отсутствие обязательного поля → TypeError', () {
      final json = validJson();
      json.remove('filename'); // обязательное поле

      expect(() => AttachmentDto.fromJson(json), throwsA(isA<TypeError>()));
    });
  });

  // ============================================================
  // toString
  // ============================================================

  group('toString', () {
    test('содержит id, filename, bytes, status, processingStatus', () {
      final dto = AttachmentDto.fromJson(
        validJson(
          id: 'file-42',
          filename: 'договор.pdf',
          bytes: 4096,
          status: 'processed',
          processingStatus: 'done',
        ),
      );

      final str = dto.toString();

      expect(str, contains('file-42'));
      expect(str, contains('договор.pdf'));
      expect(str, contains('4096'));
      expect(str, contains('processed'));
      expect(str, contains('done'));
    });
  });
}
