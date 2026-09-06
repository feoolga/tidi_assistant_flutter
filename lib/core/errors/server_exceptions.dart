// lib/core/errors/server_exceptions.dart

import 'app_exception.dart';

/// Ошибки, возвращаемые сервером (HTTP статусы).
class ServerException extends AppException {
  final int statusCode;
  final Map<String, dynamic>? responseBody;

  const ServerException({
    required super.code,
    required super.userMessage,
    required this.statusCode,
    this.responseBody,
    super.technicalDetails,
    super.originalError,
  });

  /// Ошибка 4xx (ошибка клиента)
  factory ServerException.clientError({
    required int statusCode,
    Map<String, dynamic>? body,
    Object? error,
  }) {
    String userMessage = 'Ошибка запроса.';
    if (statusCode == 400)
      userMessage = 'Некорректный запрос. Проверьте введенные данные.';
    if (statusCode == 401)
      userMessage = 'Не авторизован. Пожалуйста, войдите заново.';
    if (statusCode == 403) userMessage = 'Доступ запрещен.';
    if (statusCode == 404) userMessage = 'Запрашиваемый ресурс не найден.';

    return ServerException(
      code: 'HTTP_$statusCode',
      userMessage: userMessage,
      statusCode: statusCode,
      responseBody: body,
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  /// Ошибка 5xx (ошибка сервера)
  factory ServerException.serverError({
    required int statusCode,
    Map<String, dynamic>? body,
    Object? error,
  }) {
    return ServerException(
      code: 'HTTP_$statusCode',
      userMessage: 'На сервере произошла ошибка. Мы уже работаем над этим.',
      statusCode: statusCode,
      responseBody: body,
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  /// Ошибка парсинга JSON
  factory ServerException.parseError(Object error) {
    return ServerException(
      code: 'PARSE_ERROR',
      userMessage: 'Не удалось обработать ответ от сервера.',
      statusCode: 0,
      technicalDetails: error.toString(),
      originalError: error,
    );
  }
}
