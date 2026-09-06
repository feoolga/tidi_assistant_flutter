// lib/core/errors/error_handler.dart

import 'dart:async';
import 'package:http/http.dart' as http;
import 'network_exceptions.dart';
import 'server_exceptions.dart';
import 'app_exception.dart';

/// Универсальный обработчик ошибок.
///
/// Превращает любые исключения в AppException.
/// Используется во всех слоях приложения.
class ErrorHandler {
  /// Обработать ошибку и вернуть AppException
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

  /// Обработать и выбросить AppException
  static void throwAppException(dynamic error, [StackTrace? stackTrace]) {
    throw handle(error, stackTrace);
  }

  /// Получить сообщение для пользователя из ошибки
  static String getUserMessage(dynamic error) {
    if (error is AppException) {
      return error.userMessage;
    }
    return 'Произошла непредвиденная ошибка. Попробуйте позже.';
  }

  /// Получить код ошибки для логирования
  static String getErrorCode(dynamic error) {
    if (error is AppException) {
      return error.code;
    }
    return 'UNKNOWN_ERROR';
  }
}

/// Неизвестная ошибка (fallback)
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
