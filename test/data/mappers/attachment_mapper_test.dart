// test/data/mappers/attachment_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/mappers/attachment_mapper.dart';
import 'package:tidi_assistant_flutter/data/models/attachment_dto.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';

void main() {
  // ============================================================
  // ХЕЛПЕРЫ
  // ============================================================

  /// Собирает AttachmentDto с валидными дефолтами.
  /// В тесте переопределяем только то, что проверяем.
  AttachmentDto makeDto({
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
    return AttachmentDto(
      id: id,
      object: object,
      bytes: bytes,
      createdAt: createdAt,
      filename: filename,
      purpose: purpose,
      status: status,
      statusDetails: statusDetails,
      processingStatus: processingStatus,
      conversationId: conversationId,
    );
  }

  /// Прогоняет DTO через маппер с дефолтными локальными данными.
  Attachment mapDto(
    AttachmentDto dto, {
    String localId = 'local-1',
    String localPath = '/tmp/накладная.pdf',
  }) {
    return AttachmentMapper.toDomain(
      dto,
      localId: localId,
      localPath: localPath,
    );
  }

  // ============================================================
  // MIME ИЗ РАСШИРЕНИЯ
  // ============================================================

  group('MIME из расширения', () {
    test('.pdf → application/pdf', () {
      final att = mapDto(makeDto(filename: 'договор.pdf'));
      expect(att.mimeType, 'application/pdf');
    });

    test('.jpg → image/jpeg', () {
      final att = mapDto(makeDto(filename: 'photo.jpg'));
      expect(att.mimeType, 'image/jpeg');
    });

    test('.jpeg → image/jpeg', () {
      final att = mapDto(makeDto(filename: 'photo.jpeg'));
      expect(att.mimeType, 'image/jpeg');
    });

    test('.png → image/png', () {
      final att = mapDto(makeDto(filename: 'screen.png'));
      expect(att.mimeType, 'image/png');
    });

    test('неизвестное расширение → application/octet-stream', () {
      final att = mapDto(makeDto(filename: 'document.docx'));
      expect(att.mimeType, 'application/octet-stream');
    });

    test('расширение в верхнем регистре тоже работает', () {
      // Пользователь мог переименовать файл в PDF.PDF
      final att = mapDto(makeDto(filename: 'ДОГОВОР.PDF'));
      expect(att.mimeType, 'application/pdf');
    });
  });

  // ============================================================
  // AttachmentKind ИЗ MIME
  // ============================================================

  group('AttachmentKind из MIME', () {
    test('PDF → AttachmentKind.pdf', () {
      final att = mapDto(makeDto(filename: 'file.pdf'));
      expect(att.kind, AttachmentKind.pdf);
    });

    test('изображение → AttachmentKind.image', () {
      final att = mapDto(makeDto(filename: 'photo.png'));
      expect(att.kind, AttachmentKind.image);
    });

    test('неизвестный MIME → AttachmentKind.other', () {
      final att = mapDto(makeDto(filename: 'file.docx'));
      expect(att.kind, AttachmentKind.other);
    });
  });

  // ============================================================
  // AttachmentStatus ИЗ processingStatus
  // ============================================================

  group('AttachmentStatus из processingStatus', () {
    test('pending → AttachmentStatus.pending', () {
      final att = mapDto(makeDto(processingStatus: 'pending'));
      expect(att.status, AttachmentStatus.pending);
    });

    test('processing → AttachmentStatus.processing', () {
      final att = mapDto(makeDto(processingStatus: 'processing'));
      expect(att.status, AttachmentStatus.processing);
    });

    test('done → AttachmentStatus.done', () {
      final att = mapDto(makeDto(processingStatus: 'done'));
      expect(att.status, AttachmentStatus.done);
    });

    test('failed → AttachmentStatus.failed', () {
      final att = mapDto(makeDto(processingStatus: 'failed'));
      expect(att.status, AttachmentStatus.failed);
    });

    test('неизвестное значение → AttachmentStatus.failed', () {
      // Безопасный дефолт: лучше явная ошибка, чем молчаливое "всё ок".
      final att = mapDto(makeDto(processingStatus: 'unknown_status'));
      expect(att.status, AttachmentStatus.failed);
    });
  });

  // ============================================================
  // errorMessage
  // ============================================================

  group('errorMessage', () {
    test('null, если статус done', () {
      final att = mapDto(makeDto(processingStatus: 'done'));
      expect(att.errorMessage, isNull);
    });

    test('null, если статус done и statusDetails передан', () {
      // Сервер может прислать "повисший" текст ошибки — игнорируем,
      // домен должен быть консистентным.
      final att = mapDto(
        makeDto(processingStatus: 'done', statusDetails: 'старая ошибка'),
      );
      expect(att.errorMessage, isNull);
    });

    test('текст из statusDetails, если статус failed', () {
      final att = mapDto(
        makeDto(processingStatus: 'failed', statusDetails: 'MinerU timeout'),
      );
      expect(att.errorMessage, 'MinerU timeout');
    });

    test('null, если статус failed, но statusDetails не передан', () {
      final att = mapDto(
        makeDto(processingStatus: 'failed', statusDetails: null),
      );
      expect(att.errorMessage, isNull);
    });
  });

  // ============================================================
  // ЛОКАЛЬНЫЕ ДАННЫЕ
  // ============================================================

  group('передача локальных данных', () {
    test('localId сохраняется как передан', () {
      final att = mapDto(makeDto(), localId: 'my-local-id-42');
      expect(att.localId, 'my-local-id-42');
    });

    test('localPath сохраняется как передан', () {
      final att = mapDto(makeDto(), localPath: '/files/накладная.pdf');
      expect(att.localPath, '/files/накладная.pdf');
    });
  });

  // ============================================================
  // uploadProgress
  // ============================================================

  group('uploadProgress', () {
    test('всегда 1.0 — файл уже загружен на сервер', () {
      final att = mapDto(makeDto());
      expect(att.uploadProgress, 1.0);
    });

    test('1.0 независимо от статуса', () {
      // Даже pending — но раз сервер ответил, файл уже принят
      final att = mapDto(makeDto(processingStatus: 'pending'));
      expect(att.uploadProgress, 1.0);
    });
  });

  // ============================================================
  // СКВОЗНОЙ МАППИНГ
  // ============================================================

  group('сквозной маппинг', () {
    test('все поля DTO корректно попадают в Attachment', () {
      final dto = makeDto(
        id: 'file-85b365de-1234-4c7d-8e9f-0a1b2c3d4e5f',
        bytes: 245678,
        filename: 'накладная.pdf',
        processingStatus: 'done',
        conversationId: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      );

      final att = mapDto(
        dto,
        localId: 'local-42',
        localPath: '/files/накладная.pdf',
      );

      // Из DTO
      expect(att.remoteId, 'file-85b365de-1234-4c7d-8e9f-0a1b2c3d4e5f');
      expect(att.fileName, 'накладная.pdf');
      expect(att.sizeBytes, 245678);
      expect(att.mimeType, 'application/pdf');
      expect(att.kind, AttachmentKind.pdf);
      expect(att.status, AttachmentStatus.done);
      expect(att.errorMessage, isNull);
      expect(att.conversationId, '3fa85f64-5717-4562-b3fc-2c963f66afa6');

      // Из параметров
      expect(att.localId, 'local-42');
      expect(att.localPath, '/files/накладная.pdf');

      // Вычислено
      expect(att.uploadProgress, 1.0);

      // Производные геттеры тоже работают
      expect(att.isUploaded, isTrue);
      expect(att.isFailed, isFalse);
      expect(att.isInProgress, isFalse);
      expect(att.isPdf, isTrue);
    });
  });
}
