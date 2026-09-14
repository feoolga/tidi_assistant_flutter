// lib/core/network/http_client.dart

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../logger/app_logger.dart';
import '../errors/error_handler.dart';
import '../errors/network_exceptions.dart';

/// Единый HTTP клиент для всех запросов к API.
///
/// Все сервисы используют этот клиент вместо прямых вызовов http.
/// Это позволяет:
/// 1. Не дублировать заголовки и URL в каждом сервисе
/// 2. Централизованно логировать все запросы
/// 3. Единообразно обрабатывать ошибки
/// 4. Легко заменить реализацию (например, на dio)
class AppHttpClient {
  // ============================================================
  // 1. ВНУТРЕННИЙ КЛИЕНТ
  // ============================================================

  /// Внутренний HTTP клиент.
  ///
  /// Используем один экземпляр на всё приложение —
  /// это позволяет переиспользовать соединения (keep-alive).
  final http.Client _client;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  /// Создает клиент с настройками из AppConfig.
  ///
  /// [client] — опциональный HTTP-клиент. Если не передан — создаётся
  /// реальный `http.Client()`. Параметр нужен для тестов: подменяем
  /// клиент на `MockClient` из `package:http/testing.dart`, чтобы
  /// не ходить в реальный сервер.
  AppHttpClient({http.Client? client}) : _client = client ?? http.Client();

  // ============================================================
  // 3. ОСНОВНЫЕ МЕТОДЫ
  // ============================================================

  /// GET-запрос.
  ///
  /// Пример использования:
  /// ```dart
  /// final response = await client.get('/v1/models');
  /// ```
  Future<http.Response> get(String path, {Map<String, String>? headers}) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);

    AppLogger.info('GET $uri');

    try {
      final response = await _client
          .get(uri, headers: allHeaders)
          .timeout(AppConfig.timeout);

      AppLogger.debug('GET ${response.statusCode}');
      _logResponse(response);

      return response;
    } on TimeoutException {
      AppLogger.error('Таймаут при выполнении GET-запроса: $path');
      throw NetworkException.timeout();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Ошибка при выполнении GET-запроса: $path',
        e,
        stackTrace,
      );
      throw ErrorHandler.handle(e);
    }
  }

  /// POST-запрос с JSON-телом.
  ///
  /// Пример использования:
  /// ```dart
  /// final body = {'model': 'auto', 'messages': [...]};
  /// final response = await client.post('/v1/chat/completions', body: body);
  /// ```
  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    final jsonBody = body != null ? jsonEncode(body) : null;

    AppLogger.info('POST $uri');
    if (body != null) {
      AppLogger.debug('Тело запроса: ${jsonBody?.length ?? 0} символов');
    }

    try {
      final response = await _client
          .post(uri, headers: allHeaders, body: jsonBody)
          .timeout(AppConfig.timeout);

      AppLogger.debug('POST ${response.statusCode}');
      _logResponse(response);

      return response;
    } on TimeoutException {
      AppLogger.error('Таймаут при выполнении POST-запроса: $path');
      throw NetworkException.timeout();
    } catch (e) {
      AppLogger.error('Ошибка при выполнении POST-запроса: $path', e);
      throw ErrorHandler.handle(e);
    }
  }

  /// POST-запрос со стрим-ответом (для SSE).
  ///
  /// Отличается от обычного POST тем, что возвращает StreamedResponse.
  /// Это позволяет читать ответ по частям (токен за токеном).
  ///
  /// Пример использования:
  /// ```dart
  /// final body = {'model': 'auto', 'messages': [...]};
  /// final response = await client.postStream('/v1/chat/completions', body: body);
  /// ```
  Future<http.StreamedResponse> postStream(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers, isStream: true);
    final jsonBody = body != null ? jsonEncode(body) : null;

    AppLogger.info('POST (stream) $uri');

    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(allHeaders)
        ..body = jsonBody ?? '';

      final response = await _client
          .send(request)
          .timeout(AppConfig.streamTimeout);

      AppLogger.debug('POST (stream) ${response.statusCode}');

      return response;
    } on TimeoutException {
      AppLogger.error('Таймаут при выполнении POST-запроса (stream): $path');
      throw NetworkException.timeout();
    } catch (e) {
      AppLogger.error('Ошибка при выполнении POST-запроса (stream): $path', e);
      throw ErrorHandler.handle(e);
    }
  }

  /// POST-запрос с multipart/form-data — используется для загрузки файлов.
  ///
  /// Отличается от [post] тем, что тело — не JSON, а multipart-форма:
  /// файл + опциональные текстовые поля. Такой формат требует бэкенд
  /// для `POST /v1/files` (см. README `document_chat`).
  ///
  /// Особенности:
  /// - **Отдельный таймаут** [timeout] — по умолчанию [AppConfig.uploadTimeout]
  ///   (10 минут), потому что сервер синхронно прогоняет файл через MinerU.
  ///   Если не передан — берём дефолт; при желании можно переопределить.
  /// - **Обработчик ошибок** — [ErrorHandler.handleFileUpload], а не [ErrorHandler.handle]:
  ///   в контексте загрузки файла для пользователя сообщение должно быть
  ///   «не удалось загрузить файл», а не «сервер не отвечает».
  /// - **Возвращает** `http.Response` как есть — статусы (`413`, `400`, `502`)
  ///   разбирает вызывающий код (`AttachmentRepository`), не этот метод.
  ///
  /// Пример использования:
  /// ```dart
  /// final response = await client.postMultipart(
  ///   '/v1/files',
  ///   file: File('/path/to/накладная.pdf'),
  ///   fields: {'conversation_id': 'cid-42'},
  /// );
  /// ```
  Future<http.Response> postMultipart(
    String path, {
    required File file,
    String fileField = 'file',
    Map<String, String>? fields,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    final effectiveTimeout = timeout ?? AppConfig.uploadTimeout;

    // Логируем начало загрузки. Размер файла читаем отдельно — это
    // может быть полезно в отладке и стоит один системный вызов.
    AppLogger.info('POST (multipart) $uri');
    AppLogger.debug(
      'Загружаем файл: ${file.path.split('/').last} '
      '(${await file.length()} байт)',
    );

    try {
      // 1. Собираем multipart-запрос.
      //
      // MultipartRequest — специальный тип из package:http, который
      // автоматически формирует тело с границами (boundary) и ставит
      // правильный Content-Type: multipart/form-data.
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(allHeaders);

      // 2. Добавляем текстовые поля (если есть).
      //    Например, conversation_id — привязка файла к чату.
      if (fields != null && fields.isNotEmpty) {
        request.fields.addAll(fields);
      }

      // 3. Добавляем сам файл.
      //
      // fromPath — предпочтительнее fromBytes: файл читается по кускам
      // по мере отправки, а не грузится целиком в память. Для 25 МБ разница
      // заметна. Имя поля формы — fileField (по умолчанию 'file', как ждёт
      // бэкенд).
      final multipartFile = await http.MultipartFile.fromPath(
        fileField,
        file.path,
      );
      request.files.add(multipartFile);

      // 4. Отправляем.
      //
      // client.send() — единственный способ отправить MultipartRequest.
      // Возвращает StreamedResponse — то есть тело доступно потоково.
      // Мы читаем его целиком через Response.fromStream(), чтобы получить
      // обычный Response с .body/.statusCode.
      final streamedResponse = await _client
          .send(request)
          .timeout(effectiveTimeout);

      final response = await http.Response.fromStream(streamedResponse);

      AppLogger.debug('POST (multipart) ${response.statusCode}');
      _logResponse(response);

      return response;
    } on TimeoutException catch (e, stackTrace) {
      AppLogger.error(
        'Таймаут при загрузке файла: $path '
        '(лимит: ${effectiveTimeout.inMinutes} мин)',
      );
      throw ErrorHandler.handleFileUpload(e, stackTrace);
    } catch (e, stackTrace) {
      AppLogger.error('Ошибка при загрузке файла: $path', e, stackTrace);
      throw ErrorHandler.handleFileUpload(e, stackTrace);
    }
  }

  /// PATCH-запрос с JSON-телом.
  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    final jsonBody = body != null ? jsonEncode(body) : null;

    AppLogger.info('PATCH $uri');

    try {
      final response = await _client
          .patch(uri, headers: allHeaders, body: jsonBody)
          .timeout(AppConfig.timeout);

      AppLogger.debug('PATCH ${response.statusCode}');
      _logResponse(response);

      return response;
    } on TimeoutException {
      AppLogger.error('Таймаут при выполнении PATCH-запроса: $path');
      throw NetworkException.timeout();
    } catch (e) {
      AppLogger.error('Ошибка при выполнении PATCH-запроса: $path', e);
      throw ErrorHandler.handle(e);
    }
  }

  /// DELETE-запрос.
  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);

    AppLogger.info('DELETE $uri');

    try {
      final response = await _client
          .delete(uri, headers: allHeaders)
          .timeout(AppConfig.timeout);

      AppLogger.debug('DELETE ${response.statusCode}');
      _logResponse(response);

      return response;
    } on TimeoutException {
      AppLogger.error('Таймаут при выполнении DELETE-запроса: $path');
      throw NetworkException.timeout();
    } catch (e) {
      AppLogger.error('Ошибка при выполнении DELETE-запроса: $path', e);
      throw ErrorHandler.handle(e);
    }
  }

  // ============================================================
  // 4. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Строит полный URI из базового URL и пути.
  Uri _buildUri(String path) {
    // Убираем лишние слэши
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;

    final cleanPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$base$cleanPath');
  }

  /// Объединяет заголовки по умолчанию с переданными.
  Map<String, String> _mergeHeaders(
    Map<String, String>? customHeaders, {
    bool isStream = false,
  }) {
    // Берем заголовки по умолчанию
    final defaultHeaders = isStream
        ? AppConfig.streamHeaders
        : AppConfig.defaultHeaders;

    // Добавляем X-User-Id
    final headers = Map<String, String>.from(defaultHeaders)
      ..['X-User-Id'] = AppConfig.userId;

    // Добавляем кастомные заголовки (они переопределяют дефолтные)
    if (customHeaders != null) {
      headers.addAll(customHeaders);
    }

    return headers;
  }

  /// Логирует ответ, если он содержит ошибку.
  void _logResponse(http.Response response) {
    if (response.statusCode >= 400) {
      // Обрезаем длинное тело ответа для читаемости
      final body = response.body.length > 200
          ? '${response.body.substring(0, 200)}...'
          : response.body;
      AppLogger.warning('HTTP ${response.statusCode}: $body');
    }
  }

  // ============================================================
  // 5. ЗАКРЫТИЕ КЛИЕНТА
  // ============================================================

  /// Закрывает HTTP клиент.
  ///
  /// Нужно вызывать при завершении приложения,
  /// но обычно Flutter сам управляет жизненным циклом.
  void close() {
    AppLogger.debug('Закрытие HTTP клиента');
    _client.close();
  }
}
