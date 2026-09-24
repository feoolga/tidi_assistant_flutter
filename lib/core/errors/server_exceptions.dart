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

  /// Ошибка 4xx (ошибка клиента).
  ///
  /// **Почему `switch`, а не `if`-цепочка:**
  /// - читается как таблица соответствий «код → сообщение»;
  /// - видно, какие коды **осознанно** обработаны, а какие падают
  ///   в дефолт;
  /// - при добавлении нового кода легко добавить `case`.
  ///
  /// **Покрытые коды:**
  /// - `400` — невалидное тело запроса (README Master Router: ответ
  ///   на такие запросы — именно `400`, не `422`, для совместимости
  ///   с OpenAI SDK);
  /// - `401` — не авторизован (пока `X-User-Id`, позже — JWT);
  /// - `403` — доступ запрещён (роль не позволяет);
  /// - `404` — ресурс не найден (у нас — «чужой ресурс», README
  ///   сознательно возвращает 404, не 403);
  /// - `409` — конфликт (например, дубль при создании);
  /// - `422` — валидация не пройдена (Responses API: «input с историей
  ///   при conversation_id»);
  /// - `429` — слишком много запросов (лимиты Ollama).
  ///
  /// **Дефолт** (`'Ошибка запроса.'`) — для **незнакомых** 4xx. Если
  /// увидишь его в логах — значит, бэкенд вернул код, который мы
  /// ещё не обработали. Добавь `case`.
  factory ServerException.clientError({
    required int statusCode,
    Map<String, dynamic>? body,
    Object? error,
  }) {
    final String userMessage = switch (statusCode) {
      400 => 'Некорректный запрос. Проверьте введенные данные.',
      401 => 'Не авторизован. Пожалуйста, войдите заново.',
      403 => 'Доступ запрещен.',
      404 => 'Запрашиваемый ресурс не найден.',
      409 => 'Конфликт. Возможно, такой объект уже существует.',
      422 => 'Не удалось обработать запрос. Проверьте данные.',
      429 => 'Слишком много запросов. Подождите немного и попробуйте снова.',
      _ => 'Ошибка запроса.',
    };

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
