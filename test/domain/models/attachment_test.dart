// test/domain/models/attachment_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';

void main() {
  // ============================================================
  // ХЕЛПЕР: создаёт Attachment с дефолтными значениями
  // ============================================================

  /// Собирает Attachment для тестов.
  ///
  /// Все параметры имеют значения по умолчанию — в тесте нужно
  /// переопределять только то, что реально проверяется.
  Attachment makeAttachment({
    String localId = 'local-1',
    String? remoteId,
    String fileName = 'test.pdf',
    String mimeType = 'application/pdf',
    int sizeBytes = 1024,
    String localPath = '/tmp/test.pdf',
    AttachmentKind kind = AttachmentKind.pdf,
    AttachmentStatus status = AttachmentStatus.pending,
    String? errorMessage,
    double uploadProgress = 0.0,
    String? conversationId,
  }) {
    return Attachment(
      localId: localId,
      remoteId: remoteId,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      localPath: localPath,
      kind: kind,
      status: status,
      errorMessage: errorMessage,
      uploadProgress: uploadProgress,
      conversationId: conversationId,
    );
  }

  // ============================================================
  // КОНСТРУКТОР
  // ============================================================

  group('конструктор', () {
    test('дефолтные значения status, uploadProgress', () {
      final att = makeAttachment();

      expect(att.status, AttachmentStatus.pending);
      expect(att.uploadProgress, 0.0);
    });

    test('nullable-поля по умолчанию = null', () {
      final att = makeAttachment();

      expect(att.remoteId, isNull);
      expect(att.errorMessage, isNull);
      expect(att.conversationId, isNull);
    });

    test('все обязательные поля сохранены', () {
      final att = makeAttachment(
        localId: 'id-42',
        fileName: 'договор.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 4096,
        localPath: '/files/договор.pdf',
        kind: AttachmentKind.pdf,
      );

      expect(att.localId, 'id-42');
      expect(att.fileName, 'договор.pdf');
      expect(att.mimeType, 'application/pdf');
      expect(att.sizeBytes, 4096);
      expect(att.localPath, '/files/договор.pdf');
      expect(att.kind, AttachmentKind.pdf);
    });
  });

  // ============================================================
  // fromLocalFile
  // ============================================================

  group('fromLocalFile', () {
    test('определяет image по MIME image/jpeg', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        localPath: '/tmp/photo.jpg',
      );

      expect(att.kind, AttachmentKind.image);
    });

    test('определяет image по MIME image/png', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'screen.png',
        mimeType: 'image/png',
        sizeBytes: 1024,
        localPath: '/tmp/screen.png',
      );

      expect(att.kind, AttachmentKind.image);
    });

    test('определяет image по MIME image/webp', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'image.webp',
        mimeType: 'image/webp',
        sizeBytes: 1024,
        localPath: '/tmp/image.webp',
      );

      expect(att.kind, AttachmentKind.image);
    });

    test('определяет pdf по MIME application/pdf', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'накладная.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 1024,
        localPath: '/tmp/накладная.pdf',
      );

      expect(att.kind, AttachmentKind.pdf);
    });

    test('неизвестный MIME → other', () {
      // Например, бэкенд когда-нибудь разрешит DOCX
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'document.docx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        sizeBytes: 1024,
        localPath: '/tmp/document.docx',
      );

      expect(att.kind, AttachmentKind.other);
    });

    test('статус по умолчанию — pending', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        localPath: '/tmp/photo.jpg',
      );

      expect(att.status, AttachmentStatus.pending);
    });

    test('remoteId по умолчанию = null', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        localPath: '/tmp/photo.jpg',
      );

      expect(att.remoteId, isNull);
    });

    test('сохраняет conversationId, если передан', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-1',
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
        localPath: '/tmp/photo.jpg',
        conversationId: 'conv-42',
      );

      expect(att.conversationId, 'conv-42');
    });

    test('все переданные поля сохранены', () {
      final att = Attachment.fromLocalFile(
        localId: 'local-42',
        fileName: 'договор.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 8192,
        localPath: '/files/договор.pdf',
      );

      expect(att.localId, 'local-42');
      expect(att.fileName, 'договор.pdf');
      expect(att.mimeType, 'application/pdf');
      expect(att.sizeBytes, 8192);
      expect(att.localPath, '/files/договор.pdf');
    });
  });

  // ============================================================
  // ГЕТТЕРЫ
  // ============================================================

  group('геттеры', () {
    // ----------------------------------------------------------
    // isUploaded
    // ----------------------------------------------------------

    group('isUploaded', () {
      test('true, когда done и есть remoteId', () {
        final att = makeAttachment(
          status: AttachmentStatus.done,
          remoteId: 'file-123',
        );

        expect(att.isUploaded, isTrue);
      });

      test('false, когда done, но remoteId = null', () {
        // Теоретически не должно случаться, но защита нужна
        final att = makeAttachment(status: AttachmentStatus.done);

        expect(att.isUploaded, isFalse);
      });

      test('false, когда есть remoteId, но status != done', () {
        // Например, processing: id уже присвоен, но файл ещё не готов
        final att = makeAttachment(
          status: AttachmentStatus.processing,
          remoteId: 'file-123',
        );

        expect(att.isUploaded, isFalse);
      });

      test('false для pending, uploading, failed', () {
        for (final status in [
          AttachmentStatus.pending,
          AttachmentStatus.uploading,
          AttachmentStatus.failed,
        ]) {
          final att = makeAttachment(status: status, remoteId: 'file-123');
          expect(att.isUploaded, isFalse, reason: 'status: $status');
        }
      });
    });

    // ----------------------------------------------------------
    // isFailed
    // ----------------------------------------------------------

    group('isFailed', () {
      test('true только для failed', () {
        final att = makeAttachment(status: AttachmentStatus.failed);
        expect(att.isFailed, isTrue);
      });

      test('false для остальных статусов', () {
        for (final status in [
          AttachmentStatus.pending,
          AttachmentStatus.uploading,
          AttachmentStatus.processing,
          AttachmentStatus.done,
        ]) {
          final att = makeAttachment(status: status);
          expect(att.isFailed, isFalse, reason: 'status: $status');
        }
      });
    });

    // ----------------------------------------------------------
    // isInProgress
    // ----------------------------------------------------------

    group('isInProgress', () {
      test('true для pending, uploading, processing', () {
        for (final status in [
          AttachmentStatus.pending,
          AttachmentStatus.uploading,
          AttachmentStatus.processing,
        ]) {
          final att = makeAttachment(status: status);
          expect(att.isInProgress, isTrue, reason: 'status: $status');
        }
      });

      test('false для done и failed', () {
        for (final status in [AttachmentStatus.done, AttachmentStatus.failed]) {
          final att = makeAttachment(status: status);
          expect(att.isInProgress, isFalse, reason: 'status: $status');
        }
      });
    });

    // ----------------------------------------------------------
    // isImage / isPdf
    // ----------------------------------------------------------

    group('isImage и isPdf', () {
      test('isImage true только для kind image', () {
        final image = makeAttachment(kind: AttachmentKind.image);
        final pdf = makeAttachment(kind: AttachmentKind.pdf);
        final other = makeAttachment(kind: AttachmentKind.other);

        expect(image.isImage, isTrue);
        expect(pdf.isImage, isFalse);
        expect(other.isImage, isFalse);
      });

      test('isPdf true только для kind pdf', () {
        final image = makeAttachment(kind: AttachmentKind.image);
        final pdf = makeAttachment(kind: AttachmentKind.pdf);
        final other = makeAttachment(kind: AttachmentKind.other);

        expect(image.isPdf, isFalse);
        expect(pdf.isPdf, isTrue);
        expect(other.isPdf, isFalse);
      });
    });
  });

  // ============================================================
  // copyWith — обычные поля
  // ============================================================

  group('copyWith — обычные поля', () {
    test('меняет status', () {
      final att = makeAttachment(status: AttachmentStatus.pending);
      final copy = att.copyWith(status: AttachmentStatus.uploading);

      expect(copy.status, AttachmentStatus.uploading);
      // Оригинал НЕ изменился (immutability)
      expect(att.status, AttachmentStatus.pending);
    });

    test('меняет fileName', () {
      final att = makeAttachment(fileName: 'old.pdf');
      final copy = att.copyWith(fileName: 'new.pdf');

      expect(copy.fileName, 'new.pdf');
      expect(att.fileName, 'old.pdf');
    });

    test('меняет uploadProgress', () {
      final att = makeAttachment(uploadProgress: 0.0);
      final copy = att.copyWith(uploadProgress: 0.5);

      expect(copy.uploadProgress, 0.5);
      expect(att.uploadProgress, 0.0);
    });

    test('без аргументов — все поля сохранены', () {
      final att = makeAttachment(
        localId: 'id-1',
        fileName: 'file.pdf',
        sizeBytes: 4096,
        status: AttachmentStatus.done,
        remoteId: 'file-123',
      );
      final copy = att.copyWith();

      expect(copy.localId, 'id-1');
      expect(copy.fileName, 'file.pdf');
      expect(copy.sizeBytes, 4096);
      expect(copy.status, AttachmentStatus.done);
      expect(copy.remoteId, 'file-123');
    });
  });

  // ============================================================
  // copyWith — nullable-поля (remoteId, errorMessage, conversationId)
  // ============================================================

  group('copyWith — nullable-поля', () {
    // ----------------------------------------------------------
    // remoteId
    // ----------------------------------------------------------

    group('remoteId', () {
      test('не передан — сохраняется старое значение', () {
        final att = makeAttachment(remoteId: 'file-old');
        final copy = att.copyWith(status: AttachmentStatus.done);

        expect(copy.remoteId, 'file-old');
      });

      test('передан null — обнуляется', () {
        final att = makeAttachment(remoteId: 'file-old');
        final copy = att.copyWith(remoteId: null);

        expect(copy.remoteId, isNull);
      });

      test('передано новое значение — меняется', () {
        final att = makeAttachment(remoteId: 'file-old');
        final copy = att.copyWith(remoteId: 'file-new');

        expect(copy.remoteId, 'file-new');
      });

      test('было null, передали значение — меняется', () {
        final att = makeAttachment(); // remoteId = null
        final copy = att.copyWith(remoteId: 'file-123');

        expect(copy.remoteId, 'file-123');
      });
    });

    // ----------------------------------------------------------
    // errorMessage
    // ----------------------------------------------------------

    group('errorMessage', () {
      test('не передан — сохраняется', () {
        final att = makeAttachment(errorMessage: 'старая ошибка');
        final copy = att.copyWith(status: AttachmentStatus.uploading);

        expect(copy.errorMessage, 'старая ошибка');
      });

      test('передан null — обнуляется', () {
        final att = makeAttachment(errorMessage: 'старая ошибка');
        final copy = att.copyWith(errorMessage: null);

        expect(copy.errorMessage, isNull);
      });

      test('передано новое значение — меняется', () {
        final att = makeAttachment();
        final copy = att.copyWith(errorMessage: 'новая ошибка');

        expect(copy.errorMessage, 'новая ошибка');
      });
    });

    // ----------------------------------------------------------
    // conversationId
    // ----------------------------------------------------------

    group('conversationId', () {
      test('не передан — сохраняется', () {
        final att = makeAttachment(conversationId: 'conv-1');
        final copy = att.copyWith(status: AttachmentStatus.done);

        expect(copy.conversationId, 'conv-1');
      });

      test('передан null — обнуляется', () {
        final att = makeAttachment(conversationId: 'conv-1');
        final copy = att.copyWith(conversationId: null);

        expect(copy.conversationId, isNull);
      });

      test('передано новое значение — меняется', () {
        final att = makeAttachment();
        final copy = att.copyWith(conversationId: 'conv-42');

        expect(copy.conversationId, 'conv-42');
      });
    });
  });

  // ============================================================
  // toString
  // ============================================================

  group('toString', () {
    test('содержит localId, kind, status, sizeBytes, fileName', () {
      final att = makeAttachment(
        localId: 'id-42',
        fileName: 'накладная.pdf',
        sizeBytes: 245678,
        kind: AttachmentKind.pdf,
        status: AttachmentStatus.done,
      );

      final str = att.toString();

      expect(str, contains('id-42'));
      expect(str, contains('pdf'));
      expect(str, contains('done'));
      expect(str, contains('245678'));
      expect(str, contains('накладная.pdf'));
    });
  });
}
