// test/core/errors/error_handler_test.dart

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tidi_assistant_flutter/core/errors/error_handler.dart';
import 'package:tidi_assistant_flutter/core/errors/file_exceptions.dart';
import 'package:tidi_assistant_flutter/core/errors/network_exceptions.dart';
import 'package:tidi_assistant_flutter/core/errors/server_exceptions.dart';

void main() {
  // ============================================================
  // handleFileUpload — ОБРАБОТКА ОШИБОК ЗАГРУЗКИ ФАЙЛОВ
  // ============================================================

  group('handleFileUpload', () {
    // ----------------------------------------------------------
    // AppException ПРОХОДИТ КАК ЕСТЬ
    // ----------------------------------------------------------

    group('AppException проходит как есть', () {
      test('FileException.tooLarge НЕ оборачивается', () {
        // Валидация файла упала ДО загрузки — это уже готовый FileException.
        // handleFileUpload не должен перезаписывать его общей ошибкой.
        final original = FileException.tooLarge(
          sizeBytes: 50 * 1024 * 1024,
          maxBytes: 25 * 1024 * 1024,
        );

        final result = ErrorHandler.handleFileUpload(original);

        // Тот же самый объект, не копия
        expect(result, same(original));
        expect(result.code, 'FILE_TOO_LARGE');
      });

      test('FileException.processingFailed НЕ оборачивается', () {
        final original = FileException.processingFailed('MinerU timeout');

        final result = ErrorHandler.handleFileUpload(original);

        expect(result, same(original));
        expect(result.code, 'FILE_PROCESSING_FAILED');
      });

      test('FileException.unsupportedFormat НЕ оборачивается', () {
        final original = FileException.unsupportedFormat(
          mimeType: 'image/heic',
        );

        final result = ErrorHandler.handleFileUpload(original);

        expect(result, same(original));
        expect(result.code, 'FILE_UNSUPPORTED_FORMAT');
      });
    });

    // ----------------------------------------------------------
    // ИСКЛЮЧЕНИЯ → FileException.uploadFailed
    // ----------------------------------------------------------

    group('исключения превращаются в FileException.uploadFailed', () {
      test('TimeoutException → uploadFailed', () {
        final error = TimeoutException('Upload timeout');

        final result = ErrorHandler.handleFileUpload(error);

        expect(result, isA<FileException>());
        expect(result.code, 'FILE_UPLOAD_FAILED');
        expect(result.originalError, same(error));
      });

      test('http.ClientException → uploadFailed', () {
        final error = http.ClientException('Connection refused');

        final result = ErrorHandler.handleFileUpload(error);

        expect(result, isA<FileException>());
        expect(result.code, 'FILE_UPLOAD_FAILED');
        expect(result.originalError, same(error));
      });

      test('FormatException → uploadFailed', () {
        // Например, сервер ответил невалидным JSON
        final error = FormatException('Unexpected token');

        final result = ErrorHandler.handleFileUpload(error);

        expect(result, isA<FileException>());
        expect(result.code, 'FILE_UPLOAD_FAILED');
        expect(result.originalError, same(error));
      });

      test('произвольный Exception → uploadFailed', () {
        final error = Exception('Что-то пошло не так');

        final result = ErrorHandler.handleFileUpload(error);

        expect(result, isA<FileException>());
        expect(result.code, 'FILE_UPLOAD_FAILED');
        expect(result.originalError, same(error));
      });

      test('неизвестный тип ошибки → uploadFailed, не UnknownException', () {
        // В контексте загрузки файла любая ошибка = "не удалось загрузить".
        // UnknownException здесь неуместен.
        final error = StateError('Internal state problem');

        final result = ErrorHandler.handleFileUpload(error);

        expect(result, isA<FileException>());
        expect(result, isNot(isA<UnknownException>()));
      });
    });
  });

  // ============================================================
  // handle — ОБЫЧНЫЙ ОБРАБОТЧИК (не должен превращать в FileException)
  // ============================================================

  group('handle — обычный контекст', () {
    test('TimeoutException → NetworkException.timeout (не FileException)', () {
      final error = TimeoutException('Request timeout');

      final result = ErrorHandler.handle(error);

      expect(result, isA<NetworkException>());
      expect(result.code, 'NETWORK_TIMEOUT');
      expect(result, isNot(isA<FileException>()));
    });

    test('http.ClientException → NetworkException.connectionError', () {
      final error = http.ClientException('No internet');

      final result = ErrorHandler.handle(error);

      expect(result, isA<NetworkException>());
      expect(result.code, 'NETWORK_CONNECTION_ERROR');
    });

    test('FormatException → ServerException.parseError', () {
      final error = FormatException('Bad JSON');

      final result = ErrorHandler.handle(error);

      expect(result, isA<ServerException>());
      expect(result.code, 'PARSE_ERROR');
    });

    test('произвольный Exception → UnknownException', () {
      final error = Exception('Something');

      final result = ErrorHandler.handle(error);

      expect(result, isA<UnknownException>());
      expect(result.code, 'UNKNOWN_ERROR');
    });

    test('AppException проходит как есть', () {
      final original = FileException.tooLarge(sizeBytes: 1, maxBytes: 0);

      final result = ErrorHandler.handle(original);

      expect(result, same(original));
    });
  });

  // ============================================================
  // РАЗДЕЛЕНИЕ КОНТЕКСТОВ: ДВА МЕТОДА РАБОТАЮТ ПО-РАЗНОМУ
  // ============================================================

  group('разделение контекстов', () {
    test('одно и то же исключение даёт разные результаты', () {
      // TimeoutException — одна и та же ошибка,
      // но handle и handleFileUpload обрабатывают её по-разному.
      final error = TimeoutException('timeout');

      final generalResult = ErrorHandler.handle(error);
      final fileResult = ErrorHandler.handleFileUpload(error);

      // Обычный контекст → NetworkException
      expect(generalResult.code, 'NETWORK_TIMEOUT');

      // Контекст файла → FileException
      expect(fileResult.code, 'FILE_UPLOAD_FAILED');

      // Это два разных класса
      expect(generalResult.runtimeType, isNot(fileResult.runtimeType));
    });
  });
}
