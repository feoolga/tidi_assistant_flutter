// lib/core/errors/error_handler.dart

import 'dart:async';

import 'package:http/http.dart' as http;

import '../logger/app_logger.dart';
import 'app_exception.dart';
import 'file_exceptions.dart';
import 'network_exceptions.dart';
import 'rag_exceptions.dart';
import 'server_exceptions.dart';

/// Универсальный обработчик ошибок.
///
/// **Ответственность:**
/// - превращает любое исключение в [AppException];
/// - логирует ошибку с `stackTrace` и человеческим контекстом.
///
/// **Единая точка логирования.** Вызывающий код **не** должен
/// логировать ошибку **до** вызова [handle] — иначе получится дубль.
/// Вместо этого — передаём **контекст** («Не удалось загрузить агентов»)
/// и **данные контекста** (например, `{'agentId': 'epoz'}`) **в** [handle].
class ErrorHandler {
  // ============================================================
  // 1. ОБЩИЙ ОБРАБОТЧИК
  // ============================================================

  /// Обработать ошибку: преобразовать в [AppException] и **залогировать**.
  ///
  /// **Порядок действий:**
  /// 1. Если ошибка уже [AppException] — пропускаем как есть.
  /// 2. Иначе — преобразуем в подходящий тип:
  ///    - [http.ClientException] → [NetworkException.connectionError];
  ///    - [TimeoutException] → [NetworkException.timeout];
  ///    - [FormatException] → [ServerException.parseError];
  ///    - всё остальное → [UnknownException].
  /// 3. Логируем через [AppLogger.logException] — с `stackTrace`,
  ///    человеческим контекстом и данными контекста.
  ///
  /// **Параметры:**
  /// - [error] — любое исключение или ошибка;
  /// - [stackTrace] — опциональный, но **настоятельно рекомендуется**
  ///   передавать из `catch (e, stackTrace)`. Если не передан — используем
  ///   [StackTrace.current] (укажет на место вызова `handle`, не на источник
  ///   ошибки) и **предупредим в логе**;
  /// - [context] — человеческое описание операции: «Не удалось загрузить
  ///   агентов», «Ошибка в sendMessage». **Опционально**; если не передан —
  ///   используется общий fallback с типом ошибки;
  /// - [contextData] — структурированные данные операции: `{'agentId': ...,
  ///   'conversationId': ...}`. **Опционально**. Пригодится для отладки
  ///   и будущей интеграции с Sentry/Crashlytics.
  ///
  /// **Пример:**
  /// ```dart
  /// try {
  ///   final response = await _api.getModels();
  ///   ...
  /// } catch (e, stackTrace) {
  ///   throw ErrorHandler.handle(e, stackTrace, 'Не удалось загрузить агентов');
  /// }
  /// ```
  static AppException handle(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    final effectiveStackTrace = _ensureStackTrace(stackTrace);
    final appException = _convert(error);

    _log(
      error: appException,
      stackTrace: effectiveStackTrace,
      context: context,
      contextData: contextData,
    );

    return appException;
  }

  // ============================================================
  // 2. ОБРАБОТЧИК ЗАГРУЗКИ ФАЙЛОВ
  // ============================================================

  /// Обработать ошибку, возникшую при загрузке файла.
  ///
  /// Отличается от [handle] **сообщениями** для пользователя: в контексте
  /// загрузки файла он должен видеть не «сервер не отвечает», а
  /// «не удалось загрузить файл».
  ///
  /// **Логика:**
  /// - [FileException] пропускаем как есть (это уже готовый результат);
  /// - [NetworkException] переводим в [FileException.uploadFailed];
  /// - [ServerException] переводим в [FileException.uploadFailed]
  ///   (fallback — обычно `AttachmentRepository` разбирает его сам);
  /// - прочие [AppException] пропускаем;
  /// - транспортные (`http.ClientException`, `TimeoutException`,
  ///   `FormatException`) и всё остальное → [FileException.uploadFailed].
  ///
  /// **Логирует так же, как [handle].**
  static AppException handleFileUpload(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    final effectiveStackTrace = _ensureStackTrace(stackTrace);
    final appException = _convertFileUpload(error);

    _log(
      error: appException,
      stackTrace: effectiveStackTrace,
      context: context,
      contextData: contextData,
    );

    return appException;
  }

  // ============================================================
  // 3. ОБРАБОТЧИКИ RAG
  // ============================================================

  /// Обработать ошибку, возникшую при **создании** RAG-набора.
  ///
  /// Отличается от [handle] **сообщениями** для пользователя: в контексте
  /// создания набора он должен видеть «не удалось создать RAG-набор»,
  /// а не «сервер не отвечает».
  ///
  /// **Логика:**
  /// - [RagException] пропускаем как есть (это уже готовый результат);
  /// - [ServerException] переводим в [RagException.createFailed]
  ///   (fallback — обычно `RagRepository` разбирает его сам);
  /// - прочие [AppException] пропускаем;
  /// - транспортные (`http.ClientException`, `TimeoutException`,
  ///   `FormatException`) и всё остальное → [RagException.createFailed].
  ///
  /// **Логирует так же, как [handle].**
  static AppException handleRagCreation(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    final effectiveStackTrace = _ensureStackTrace(stackTrace);
    final appException = _convertRagCreation(error);

    _log(
      error: appException,
      stackTrace: effectiveStackTrace,
      context: context,
      contextData: contextData,
    );

    return appException;
  }

  /// Обработать ошибку, возникшую при **загрузке документов** в RAG-набор.
  ///
  /// **Важно:** загрузка документов в RAG **не атомарна**. Ошибка на
  /// одном из файлов оставляет ранее принятые файлы в наборе. Поэтому
  /// после этой ошибки вызывающий код **должен** перечитать
  /// `GET /v1/platform/rags/{id}/documents`, чтобы узнать точное
  /// состояние. Но это — задача `RagRepository` / UI, не `ErrorHandler`.
  ///
  /// **Логика:**
  /// - [RagException] пропускаем как есть;
  /// - [ServerException] переводим в [RagException.uploadFailed]
  ///   (fallback);
  /// - прочие [AppException] пропускаем;
  /// - транспортные и всё остальное → [RagException.uploadFailed].
  static AppException handleRagUpload(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    final effectiveStackTrace = _ensureStackTrace(stackTrace);
    final appException = _convertRagUpload(error);

    _log(
      error: appException,
      stackTrace: effectiveStackTrace,
      context: context,
      contextData: contextData,
    );

    return appException;
  }

  // ============================================================
  // 4. ПРЕОБРАЗОВАНИЕ (БЕЗ ЛОГИРОВАНИЯ)
  // ============================================================

  /// Преобразовать любое исключение в [AppException] — **без логирования**.
  ///
  /// **Зачем публичный метод:**
  /// В большинстве случаев используется [handle] — он конвертирует **и**
  /// логирует. Но есть ситуации, когда логирование уже произошло **выше**
  /// по стеку (например, `SendMessageUseCase` залогировал `event: error`
  /// через `AppLogger.logException`), а конвертация — нужна. Второй лог
  /// был бы дублем.
  ///
  /// **Правило:** если ошибка уже `AppException` и уже залогирована —
  /// используйте [convert]. Если это сырое исключение, которое надо
  /// и превратить, и залогировать — [handle].
  static AppException convert(Object error) {
    if (error is AppException) return error;
    if (error is http.ClientException) {
      return NetworkException.connectionError(error);
    }
    if (error is TimeoutException) {
      return NetworkException.timeout(error);
    }
    if (error is FormatException) {
      return ServerException.parseError(error);
    }
    return UnknownException.from(error);
  }

  /// Преобразовать любое исключение в [AppException] для общего контекста.
  ///
  /// **Не логирует** — логирование делает [handle].
  static AppException _convert(Object error) {
    if (error is AppException) return error;
    if (error is http.ClientException) {
      return NetworkException.connectionError(error);
    }
    if (error is TimeoutException) {
      return NetworkException.timeout(error);
    }
    if (error is FormatException) {
      return ServerException.parseError(error);
    }
    return UnknownException.from(error);
  }

  /// Преобразовать любое исключение в [AppException] для контекста
  /// загрузки файла.
  ///
  /// **Не логирует** — логирование делает [handleFileUpload].
  static AppException _convertFileUpload(Object error) {
    // FileException — уже готовый, пропускаем.
    if (error is FileException) return error;

    // NetworkException — переводим в uploadFailed.
    if (error is NetworkException) {
      return FileException.uploadFailed(error);
    }

    // ServerException — fallback (обычно репозиторий разбирает его сам).
    if (error is ServerException) {
      return FileException.uploadFailed(error);
    }

    // Прочие AppException (бизнес-исключения) — пропускаем.
    if (error is AppException) return error;

    // Транспортные и парсинговые — на случай, если что-то не обёрнуто.
    if (error is http.ClientException) {
      return FileException.uploadFailed(error);
    }
    if (error is TimeoutException) {
      return FileException.uploadFailed(error);
    }
    if (error is FormatException) {
      return FileException.uploadFailed(error);
    }

    // Всё остальное — общий uploadFailed.
    return FileException.uploadFailed(error);
  }

  /// Преобразовать любое исключение в [AppException] для контекста
  /// **создания** RAG-набора.
  ///
  /// **Не логирует** — логирование делает [handleRagCreation].
  static AppException _convertRagCreation(Object error) {
    // RagException — уже готовый, пропускаем.
    if (error is RagException) return error;

    // NetworkException — переводим в createFailed.
    if (error is NetworkException) {
      return RagException.createFailed(error);
    }

    // ServerException — fallback (обычно репозиторий разбирает его сам).
    if (error is ServerException) {
      return RagException.createFailed(error);
    }

    // Прочие AppException (бизнес-исключения) — пропускаем.
    if (error is AppException) return error;

    // Транспортные и парсинговые — на случай, если что-то не обёрнуто.
    if (error is http.ClientException) {
      return RagException.createFailed(error);
    }
    if (error is TimeoutException) {
      return RagException.createFailed(error);
    }
    if (error is FormatException) {
      return RagException.createFailed(error);
    }

    // Всё остальное — общий createFailed.
    return RagException.createFailed(error);
  }

  /// Преобразовать любое исключение в [AppException] для контекста
  /// **загрузки документов** в RAG-набор.
  ///
  /// **Не логирует** — логирование делает [handleRagUpload].
  static AppException _convertRagUpload(Object error) {
    // RagException — уже готовый, пропускаем.
    if (error is RagException) return error;

    // NetworkException — переводим в uploadFailed.
    if (error is NetworkException) {
      return RagException.uploadFailed(error: error);
    }

    // ServerException — fallback (обычно репозиторий разбирает его сам).
    if (error is ServerException) {
      return RagException.uploadFailed(error: error);
    }

    // Прочие AppException — пропускаем.
    if (error is AppException) return error;

    // Транспортные и парсинговые.
    if (error is http.ClientException) {
      return RagException.uploadFailed(error: error);
    }
    if (error is TimeoutException) {
      return RagException.uploadFailed(error: error);
    }
    if (error is FormatException) {
      return RagException.uploadFailed(error: error);
    }

    // Всё остальное.
    return RagException.uploadFailed(error: error);
  }

  // ============================================================
  // 5. ЛОГИРОВАНИЕ (ОБЩЕЕ)
  // ============================================================

  /// Залогировать обработанную ошибку.
  ///
  /// Один приватный метод, потому что [handle] и [handleFileUpload]
  /// логируют одинаково. Меняем формат лога — меняем **здесь**.
  static void _log({
    required AppException error,
    required StackTrace stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  }) {
    // Если context передан — используем его как message.
    // Иначе — общий fallback с типом ошибки.
    final logMessage = context ?? 'Ошибка обработана: ${error.runtimeType}';

    AppLogger.logException(logMessage, error, stackTrace, contextData);
  }

  // ============================================================
  // 6. БРОСАНИЕ
  // ============================================================

  /// Обработать и выбросить [AppException].
  static void throwAppException(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    throw handle(error, stackTrace, context, contextData);
  }

  /// Обработать и выбросить [AppException] в контексте загрузки файла.
  static void throwFileUploadException(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    throw handleFileUpload(error, stackTrace, context, contextData);
  }

  /// Обработать и выбросить [AppException] в контексте создания RAG-набора.
  static void throwRagCreationException(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    throw handleRagCreation(error, stackTrace, context, contextData);
  }

  /// Обработать и выбросить [AppException] в контексте загрузки
  /// документов в RAG-набор.
  static void throwRagUploadException(
    Object error, [
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? contextData,
  ]) {
    throw handleRagUpload(error, stackTrace, context, contextData);
  }

  // ============================================================
  // 7. ХЕЛПЕРЫ
  // ============================================================

  /// Получить сообщение для пользователя из ошибки.
  static String getUserMessage(Object error) {
    if (error is AppException) {
      return error.userMessage;
    }
    return 'Произошла непредвиденная ошибка. Попробуйте позже.';
  }

  /// Получить код ошибки для логирования/аналитики.
  static String getErrorCode(Object error) {
    if (error is AppException) {
      return error.code;
    }
    return 'UNKNOWN_ERROR';
  }

  /// Гарантировать наличие `stackTrace`.
  ///
  /// Если `stackTrace` не передан — используем [StackTrace.current]
  /// (укажет на место вызова `handle`, не на источник ошибки)
  /// и **предупреждаем в логе**. Это помогает находить забытые
  /// `catch (e)` без `stackTrace`.
  static StackTrace _ensureStackTrace(StackTrace? stackTrace) {
    if (stackTrace != null) return stackTrace;

    AppLogger.warning(
      'ErrorHandler вызван без stackTrace. Передавайте stackTrace '
      'из catch (e, stackTrace) — иначе теряется место ошибки.',
    );
    return StackTrace.current;
  }
}

// ============================================================
// НЕИЗВЕСТНАЯ ОШИБКА (fallback)
// ============================================================

/// Неизвестная ошибка (fallback).
///
/// Используется [ErrorHandler.handle], когда ошибка не подошла
/// ни под одну известную категорию.
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
