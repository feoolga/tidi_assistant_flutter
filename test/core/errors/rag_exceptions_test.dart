// test/core/errors/rag_exceptions_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/errors/app_exception.dart';
import 'package:tidi_assistant_flutter/core/errors/rag_exceptions.dart';

void main() {
  // ============================================================
  // ОБЩИЕ СВОЙСТВА
  // ============================================================

  group('RagException — общие свойства', () {
    test('наследуется от AppException', () {
      final e = RagException.limitReached();
      expect(e, isA<AppException>());
    });

    test('все фабрики возвращают уникальные коды', () {
      final codes = {
        RagException.limitReached().code,
        RagException.sizeLimitReached().code,
        RagException.notReady(ragId: 'x', status: 'empty').code,
        RagException.notFound('x').code,
        RagException.createFailed().code,
        RagException.uploadFailed().code,
        RagException.fileTooLarge().code,
        RagException.unsupportedFormat(mimeType: 'x').code,
        RagException.tooManyFilesInBatch(actual: 1, max: 1).code,
        RagException.iconTooLarge(sizeBytes: 1, maxBytes: 1).code,
        RagException.iconUnsupportedFormat(mimeType: 'x').code,
      };
      expect(codes.length, 11, reason: 'Все коды должны быть разными');
    });
  });

  // ============================================================
  // ЛИМИТЫ
  // ============================================================

  group('limitReached', () {
    test('без параметра max — общее сообщение', () {
      final e = RagException.limitReached();
      expect(e.code, 'RAG_LIMIT_REACHED');
      expect(e.userMessage, contains('лимит RAG-наборов'));
      expect(e.userMessage, isNot(contains('(')));
    });

    test('с параметром max — показывает число', () {
      final e = RagException.limitReached(max: 50);
      expect(e.userMessage, contains('(50)'));
    });
  });

  group('sizeLimitReached', () {
    test('без параметров — общее сообщение', () {
      final e = RagException.sizeLimitReached();
      expect(e.code, 'RAG_SIZE_LIMIT_REACHED');
      expect(e.userMessage, contains('общий размер набора'));
    });

    test('с обоими параметрами — точные ГБ', () {
      final e = RagException.sizeLimitReached(
        currentBytes: 21 * 1024 * 1024 * 1024, // 21 ГБ
        maxBytes: 20 * 1024 * 1024 * 1024, // 20 ГБ
      );
      expect(e.userMessage, contains('21.0 ГБ'));
      expect(e.userMessage, contains('20.0 ГБ'));
    });
  });

  group('notReady', () {
    test('empty — про отсутствие документов', () {
      final e = RagException.notReady(ragId: 'rag-1', status: 'empty');
      expect(e.code, 'RAG_NOT_READY');
      expect(e.userMessage, contains('нет документов'));
    });

    test('ingesting — про обработку', () {
      final e = RagException.notReady(ragId: 'rag-1', status: 'ingesting');
      expect(e.userMessage, contains('обрабатывается'));
    });

    test('failed — про ошибку обработки', () {
      final e = RagException.notReady(ragId: 'rag-1', status: 'failed');
      expect(e.userMessage, contains('не удалось обработать'));
    });

    test('неизвестный статус — общее сообщение', () {
      final e = RagException.notReady(ragId: 'rag-1', status: 'wat');
      expect(e.userMessage, contains('не готов'));
    });

    test('technicalDetails содержит ragId и status', () {
      final e = RagException.notReady(ragId: 'rag-1', status: 'empty');
      expect(e.technicalDetails, contains('rag-1'));
      expect(e.technicalDetails, contains('empty'));
    });
  });

  group('notFound', () {
    test('содержит ragId в technicalDetails', () {
      final e = RagException.notFound('rag-42');
      expect(e.code, 'RAG_NOT_FOUND');
      expect(e.userMessage, contains('не найден'));
      expect(e.technicalDetails, contains('rag-42'));
    });
  });

  // ============================================================
  // СОЗДАНИЕ / ЗАГРУЗКА
  // ============================================================

  group('createFailed', () {
    test('без error — общее сообщение', () {
      final e = RagException.createFailed();
      expect(e.code, 'RAG_CREATE_FAILED');
      expect(e.userMessage, contains('Не удалось создать'));
    });

    test('с error — сохраняет originalError', () {
      final original = Exception('boom');
      final e = RagException.createFailed(original);
      expect(e.originalError, same(original));
      expect(e.technicalDetails, contains('boom'));
    });
  });

  group('uploadFailed', () {
    test('без параметров — общее сообщение', () {
      final e = RagException.uploadFailed();
      expect(e.code, 'RAG_UPLOAD_FAILED');
      expect(e.userMessage, contains('Не удалось загрузить документы'));
    });

    test('с accepted и failed — показывает оба числа', () {
      final e = RagException.uploadFailed(accepted: 4, failed: 6);
      expect(e.userMessage, contains('Принято: 4'));
      expect(e.userMessage, contains('отклонено: 6'));
    });

    test('только с accepted — предупреждает про список файлов', () {
      final e = RagException.uploadFailed(accepted: 4);
      expect(e.userMessage, contains('Принято: 4'));
      expect(e.userMessage, contains('Проверьте список'));
    });

    test('accepted = 0 без failed — общее сообщение', () {
      final e = RagException.uploadFailed(accepted: 0);
      expect(e.userMessage, contains('Не удалось загрузить документы'));
    });
  });

  group('fileTooLarge', () {
    test('без параметров — общее сообщение', () {
      final e = RagException.fileTooLarge();
      expect(e.code, 'RAG_FILE_TOO_LARGE');
      expect(e.userMessage, contains('слишком большой'));
      expect(e.userMessage, isNot(contains('МБ')));
    });

    test('с maxBytes — показывает лимит в МБ', () {
      final e = RagException.fileTooLarge(maxBytes: 200 * 1024 * 1024);
      expect(e.userMessage, contains('200 МБ'));
    });

    test('с serverMessage — сохраняет в technicalDetails', () {
      final e = RagException.fileTooLarge(serverMessage: 'File exceeds 200 MB');
      expect(e.technicalDetails, contains('File exceeds'));
    });
  });

  group('unsupportedFormat', () {
    test('содержит mimeType в technicalDetails', () {
      final e = RagException.unsupportedFormat(mimeType: 'image/svg+xml');
      expect(e.code, 'RAG_UNSUPPORTED_FORMAT');
      expect(e.technicalDetails, contains('image/svg+xml'));
    });
  });

  group('tooManyFilesInBatch', () {
    test('показывает лимит и факт', () {
      final e = RagException.tooManyFilesInBatch(actual: 15, max: 10);
      expect(e.userMessage, contains('не более 10'));
      expect(e.userMessage, contains('Выбрано: 15'));
    });
  });

  // ============================================================
  // ИКОНКА
  // ============================================================

  group('iconTooLarge', () {
    test('показывает размер и лимит в КБ', () {
      final e = RagException.iconTooLarge(
        sizeBytes: 800 * 1024,
        maxBytes: 512 * 1024,
      );
      expect(e.code, 'RAG_ICON_TOO_LARGE');
      expect(e.userMessage, contains('800 КБ'));
      expect(e.userMessage, contains('512 КБ'));
    });
  });

  group('iconUnsupportedFormat', () {
    test('содержит mimeType в technicalDetails', () {
      final e = RagException.iconUnsupportedFormat(mimeType: 'image/svg+xml');
      expect(e.code, 'RAG_ICON_UNSUPPORTED_FORMAT');
      expect(e.technicalDetails, contains('image/svg+xml'));
    });
  });
}
