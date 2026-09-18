// lib/core/errors/error_handler.dart

import 'dart:async';
import 'package:http/http.dart' as http;
import 'network_exceptions.dart';
import 'server_exceptions.dart';
import 'file_exceptions.dart';
import 'app_exception.dart';

/// Универсальный обработчик ошибок.
///
/// Превращает любые исключения в AppException.
/// Используется во всех слоях приложения.
///
/// Основной метод — [handle] — для обычных запросов.
/// Для специфичных контекстов (например, загрузка файлов) есть
/// отдельные методы, чтобы пользователь видел правильное сообщение.
class ErrorHandler {
  // ============================================================
  // 1. ОБЩИЙ ОБРАБОТЧИК
  // ============================================================

  /// Обработать ошибку и вернуть AppException.
  ///
  /// Используется для обычных запросов: получение агентов, чатов,
  /// отправка сообщений. Для загрузки файлов — см. [handleFileUpload].
  ///
  /// [stackTrace] не используется здесь, но принимается для единообразия
  /// API и на случай, если решим логировать прямо в обработчике.
  static AppException handle(dynamic error, [StackTrace? stackTrace]) {
    // Если это уже AppException — просто возвращаем
    if (error is AppException) {
      return error;
    }

    // Ошибка сети (http.ClientException)
    if (error is http.ClientException) {
      return NetworkException.connectionError(error);
    }

    // Timeout
    if (error is TimeoutException) {
      return NetworkException.timeout(error);
    }

    // Ошибка формата JSON
    if (error is FormatException) {
      return ServerException.parseError(error);
    }

    // Все остальные ошибки
    return UnknownException.from(error);
  }

  // ============================================================
  // 2. ОБРАБОТЧИК ЗАГРУЗКИ ФАЙЛОВ
  // ============================================================

  /// Обработать ошибку, возникшую при загрузке файла.
  ///
  /// Отличается от [handle] сообщениями для пользователя: в контексте
  /// загрузки файла он должен видеть не «сервер не отвечает», а
  /// «не удалось загрузить файл».
  ///
  /// **Что делает:**
  /// - [FileException] пропускает как есть — это уже готовый результат;
  /// - [NetworkException] переводит в [FileException.uploadFailed]
  ///   (в контексте загрузки файла «нет сети» = «не удалось загрузить»);
  /// - [ServerException] переводит в [FileException.uploadFailed]
  ///   (это fallback — обычно `AttachmentRepository` разбирает
  ///   `ServerException` сам по статусам);
  /// - прочие [AppException] (бизнес-исключения) пропускает;
  /// - `http.ClientException`, `TimeoutException`, `FormatException`
  ///   и всё остальное — переводит в [FileException.uploadFailed].
  ///
  /// **Чего не делает:**
  /// Не разбирает HTTP-статусы (413, 400, 502) — это работа
  /// `AttachmentRepository`, у которого есть контекст операции.
  static AppException handleFileUpload(
    dynamic error, [
    StackTrace? stackTrace,
  ]) {
    // 1. FileException — уже готовый результат, пропускаем.
    //    Сюда попадают: валидация до отправки, классификаторы в репозитории.
    if (error is FileException) {
      return error;
    }

    // 2. NetworkException — переводим в uploadFailed.
    //    Ключевой случай: клиент бросает NetworkException, но
    //    в контексте загрузки файла пользователь должен увидеть
    //    «не удалось загрузить файл», а не «нет соединения».
    if (error is NetworkException) {
      return FileException.uploadFailed(error);
    }

    // 3. ServerException — fallback.
    //    Репозиторий обычно разбирает ServerException сам (по статусам),
    //    но если не разобрал (неизвестный статус) — превращаем в общий.
    if (error is ServerException) {
      return FileException.uploadFailed(error);
    }

    // 4. Прочие AppException — пропускаем.
    //    Например, BusinessException — в контексте загрузки файла
    //    они не должны появляться, но если появились — не глушим.
    if (error is AppException) {
      return error;
    }

    // 5. Транспортные и парсинговые — на случай, если что-то
    //    не обёрнуто клиентом.
    if (error is http.ClientException) {
      return FileException.uploadFailed(error);
    }
    if (error is TimeoutException) {
      return FileException.uploadFailed(error);
    }
    if (error is FormatException) {
      return FileException.uploadFailed(error);
    }

    // 6. Всё остальное — общий uploadFailed.
    return FileException.uploadFailed(error);
  }
  // ============================================================
  // 3. БРОСАНИЕ
  // ============================================================

  /// Обработать и выбросить AppException.
  static void throwAppException(dynamic error, [StackTrace? stackTrace]) {
    throw handle(error, stackTrace);
  }

  /// Обработать и выбросить AppException в контексте загрузки файла.
  ///
  /// Сахар для `throw handleFileUpload(...)`.
  static void throwFileUploadException(
    dynamic error, [
    StackTrace? stackTrace,
  ]) {
    throw handleFileUpload(error, stackTrace);
  }

  // ============================================================
  // 4. ХЕЛПЕРЫ
  // ============================================================

  /// Получить сообщение для пользователя из ошибки.
  static String getUserMessage(dynamic error) {
    if (error is AppException) {
      return error.userMessage;
    }
    return 'Произошла непредвиденная ошибка. Попробуйте позже.';
  }

  /// Получить код ошибки для логирования.
  static String getErrorCode(dynamic error) {
    if (error is AppException) {
      return error.code;
    }
    return 'UNKNOWN_ERROR';
  }
}

// ============================================================
// НЕИЗВЕСТНАЯ ОШИБКА (fallback)
// ============================================================

/// Неизвестная ошибка (fallback).
///
/// Используется [ErrorHandler.handle], когда ошибка не подошла
/// ни под одну известную категорию. Живёт в этом же файле, потому что
/// тесно связан с `ErrorHandler` и используется только им.
class UnknownException extends AppException {
  const UnknownException({
    required super.code,
    required super.userMessage,
    super.technicalDetails,
    super.originalError,
  });

  factory UnknownException.from(Object error) {
    return UnknownException(
      code: 'UNKNOWN_ERROR',
      userMessage: 'Произошла непредвиденная ошибка.',
      technicalDetails: error.toString(),
      originalError: error,
    );
  }
}
