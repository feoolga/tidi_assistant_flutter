// test/core/errors/file_exceptions_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/errors/app_exception.dart';
import 'package:tidi_assistant_flutter/core/errors/file_exceptions.dart';

void main() {
  // ============================================================
  // ХЕЛПЕР: проверяет, что ошибка не содержит originalError
  // ============================================================
  void expectNoOriginalError(FileException e) {
    expect(e.originalError, isNull);
    expect(e.technicalDetails, isNull);
  }

  // ============================================================
  // ОБЩЕЕ ПОВЕДЕНИЕ
  // ============================================================

  group('общее поведение', () {
    test('наследуется от AppException', () {
      final e = FileException.pickFailed();
      expect(e, isA<AppException>());
    });

    test('toString содержит code и userMessage', () {
      final e = FileException.pickFailed();
      final str = e.toString();
      expect(str, contains('FILE_PICK_FAILED'));
      expect(str, contains('Не удалось открыть файл.'));
    });
  });

  // ============================================================
  // ВАЛИДАЦИЯ НА КЛИЕНТЕ
  // ============================================================

  group('валидация на клиенте', () {
    // ----------------------------------------------------------
    // tooLarge
    // ----------------------------------------------------------

    group('tooLarge', () {
      test('возвращает код FILE_TOO_LARGE', () {
        final e = FileException.tooLarge(
          sizeBytes: 5 * 1024 * 1024, // 5 МБ
          maxBytes: 25 * 1024 * 1024, // 25 МБ
        );
        expect(e.code, 'FILE_TOO_LARGE');
      });

      test('userMessage содержит отформатированные цифры', () {
        final e = FileException.tooLarge(
          sizeBytes: 5 * 1024 * 1024, // → "5.0 МБ"
          maxBytes: 25 * 1024 * 1024, // → "25 МБ"
        );
        expect(e.userMessage, contains('5.0 МБ'));
        expect(e.userMessage, contains('25 МБ'));
      });

      test('technicalDetails содержит размеры в байтах', () {
        final e = FileException.tooLarge(
          sizeBytes: 5557452,
          maxBytes: 26214400,
        );
        expect(e.technicalDetails, contains('5557452'));
        expect(e.technicalDetails, contains('26214400'));
      });

      test('originalError = null (это наша валидация)', () {
        final e = FileException.tooLarge(
          sizeBytes: 5 * 1024 * 1024,
          maxBytes: 25 * 1024 * 1024,
        );
        expect(e.originalError, isNull);
      });
    });

    // ----------------------------------------------------------
    // unsupportedFormat
    // ----------------------------------------------------------

    group('unsupportedFormat', () {
      test('возвращает код FILE_UNSUPPORTED_FORMAT', () {
        final e = FileException.unsupportedFormat(mimeType: 'image/heic');
        expect(e.code, 'FILE_UNSUPPORTED_FORMAT');
      });

      test('userMessage перечисляет разрешённые форматы', () {
        final e = FileException.unsupportedFormat(mimeType: 'image/heic');
        expect(e.userMessage, contains('PDF'));
        expect(e.userMessage, contains('JPG'));
        expect(e.userMessage, contains('PNG'));
      });

      test('technicalDetails содержит MIME-тип', () {
        final e = FileException.unsupportedFormat(mimeType: 'image/heic');
        expect(e.technicalDetails, contains('image/heic'));
      });

      test('originalError = null', () {
        final e = FileException.unsupportedFormat(mimeType: 'image/heic');
        expect(e.originalError, isNull);
      });
    });

    // ----------------------------------------------------------
    // tooManyFiles
    // ----------------------------------------------------------

    group('tooManyFiles', () {
      test('возвращает код FILE_TOO_MANY', () {
        final e = FileException.tooManyFiles(actual: 7, max: 5);
        expect(e.code, 'FILE_TOO_MANY');
      });

      test('userMessage содержит actual и max', () {
        final e = FileException.tooManyFiles(actual: 7, max: 5);
        expect(e.userMessage, contains('7'));
        expect(e.userMessage, contains('5'));
      });

      test('technicalDetails содержит оба числа', () {
        final e = FileException.tooManyFiles(actual: 7, max: 5);
        expect(e.technicalDetails, contains('7'));
        expect(e.technicalDetails, contains('5'));
      });
    });
  });

  // ============================================================
  // ЗАГРУЗКА
  // ============================================================

  group('загрузка', () {
    // ----------------------------------------------------------
    // uploadFailed
    // ----------------------------------------------------------

    group('uploadFailed', () {
      test('возвращает код FILE_UPLOAD_FAILED', () {
        final e = FileException.uploadFailed();
        expect(e.code, 'FILE_UPLOAD_FAILED');
      });

      test('userMessage не пустое', () {
        final e = FileException.uploadFailed();
        expect(e.userMessage, isNotEmpty);
      });

      test('без аргументов — originalError и technicalDetails = null', () {
        final e = FileException.uploadFailed();
        expectNoOriginalError(e);
      });

      test('сохраняет originalError — тот же самый объект', () {
        // Ключевое: именно same(), не equals() — должен быть тот же объект
        const originalError = 'Network timeout';
        final e = FileException.uploadFailed(originalError);

        expect(e.originalError, same(originalError));
        expect(e.technicalDetails, contains('Network timeout'));
      });
    });

    // ----------------------------------------------------------
    // processingFailed
    // ----------------------------------------------------------

    group('processingFailed', () {
      test('возвращает код FILE_PROCESSING_FAILED', () {
        final e = FileException.processingFailed();
        expect(e.code, 'FILE_PROCESSING_FAILED');
      });

      test('userMessage не содержит технических деталей MinerU', () {
        // Пользователь не должен видеть внутренние имена сервисов
        final e = FileException.processingFailed('MinerU timeout after 600s');
        expect(e.userMessage, isNot(contains('MinerU')));
        expect(e.userMessage, isNotEmpty);
      });

      test('technicalDetails пробрасывает детали', () {
        final e = FileException.processingFailed('MinerU timeout after 600s');
        expect(e.technicalDetails, contains('MinerU timeout'));
      });

      test('без аргументов — technicalDetails = null', () {
        final e = FileException.processingFailed();
        expect(e.technicalDetails, isNull);
      });
    });

    // ----------------------------------------------------------
    // notReady
    // ----------------------------------------------------------

    group('notReady', () {
      test('возвращает код FILE_NOT_READY', () {
        final e = FileException.notReady();
        expect(e.code, 'FILE_NOT_READY');
      });

      test('userMessage не пустое', () {
        final e = FileException.notReady();
        expect(e.userMessage, isNotEmpty);
      });
    });
  });

  // ============================================================
  // ЛОКАЛЬНЫЕ ОПЕРАЦИИ
  // ============================================================

  group('локальные операции', () {
    // ----------------------------------------------------------
    // pickFailed
    // ----------------------------------------------------------

    group('pickFailed', () {
      test('возвращает код FILE_PICK_FAILED', () {
        final e = FileException.pickFailed();
        expect(e.code, 'FILE_PICK_FAILED');
      });

      test('без аргументов — originalError = null', () {
        final e = FileException.pickFailed();
        expect(e.originalError, isNull);
      });

      test('сохраняет originalError', () {
        final originalError = Exception('Picker crashed');
        final e = FileException.pickFailed(originalError);

        expect(e.originalError, same(originalError));
      });
    });
  });
}
