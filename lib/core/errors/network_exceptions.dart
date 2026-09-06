//lib/core/errors/network_exceptions.dart

import 'app_exception.dart';

/// Ошибки, связанные с сетью.
///
/// Например: нет интернета, таймаут, сервер недоступен.
class NetworkException extends AppException {
  const NetworkException({
    required super.code,
    required super.userMessage,
    super.technicalDetails,
    super.originalError,
  });

  /// Ошибка при подключении к серверу
  factory NetworkException.connectionError([Object? error]) {
    return NetworkException(
      code: 'NETWORK_CONNECTION_ERROR',
      userMessage:
          'Не удается подключиться к серверу. Проверьте интернет-соединение.',
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  /// Таймаут запроса
  factory NetworkException.timeout([Object? error]) {
    return NetworkException(
      code: 'NETWORK_TIMEOUT',
      userMessage: 'Сервер долго не отвечает. Попробуйте позже.',
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  /// Ошибка парсинга SSE
  factory NetworkException.sseParseError([Object? error]) {
    return NetworkException(
      code: 'SSE_PARSE_ERROR',
      userMessage: 'Ошибка при получении ответа от сервера.',
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }
}
