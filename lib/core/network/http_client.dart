// lib/core/network/http_client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/network_exceptions.dart';
import '../errors/server_exceptions.dart';
import '../logger/app_logger.dart';
import 'http_error_builder.dart';

/// Единый HTTP-клиент для всех запросов к API.
///
/// Архитектурная роль: **транспорт + базовый протокол**.
/// Клиент умеет:
/// - собирать URL и заголовки;
/// - ставить таймауты;
/// - превращать транспортные ошибки (нет сети, таймаут) в NetworkException;
/// - превращать HTTP-ошибки (>= 400) в ServerException.
///
/// Клиент **не знает** про домен: ни про агентов, ни про чаты, ни про файлы.
/// Никаких бизнес-решений («404 здесь — это ок») он не принимает.
/// Это работа репозитория.
///
/// Политика по статус-кодам:
/// - `get` / `post` / `patch` / `delete` — бросают [ServerException] на `>= 400`.
/// - `postStream` — бросает [ServerException] на `>= 400`, читая тело ошибки
///   (до возврата, пока ответ ещё не отдан в парсер SSE).
/// - `postMultipart` — **не бросает**. Возвращает [http.Response] как есть,
///   потому что статусы 4xx/5xx здесь — часть бизнес-протокола загрузки файлов
///   (413 = «файл большой», 502 = «MinerU упал», 400 = «файл ещё обрабатывается»).
///   Разбор статусов — задача AttachmentRepository.
class AppHttpClient {
  // ============================================================
  // 1. ВНУТРЕННИЙ КЛИЕНТ
  // ============================================================

  /// Внутренний HTTP-клиент.
  ///
  /// Один экземпляр на всё приложение — переиспользует TCP-соединения
  /// (keep-alive), что заметно быстрее на мобильных сетях.
  final http.Client _client;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  /// Создаёт клиент.
  ///
  /// [client] — опциональный HTTP-клиент. Если не передан — создаётся
  /// реальный `http.Client()`. Параметр нужен для тестов: подменяем
  /// на `MockClient` из `package:http/testing.dart`, чтобы не ходить
  /// в реальный сервер.
  AppHttpClient({http.Client? client}) : _client = client ?? http.Client();

  // ============================================================
  // 3. ПУБЛИЧНЫЕ МЕТОДЫ — ОБЫЧНЫЕ ЗАПРОСЫ
  // ============================================================

  /// GET-запрос. Бросает [ServerException] на `>= 400`.
  Future<http.Response> get(String path, {Map<String, String>? headers}) {
    return _executeRequest(
      method: 'GET',
      path: path,
      send: () => _client.get(_buildUri(path), headers: _mergeHeaders(headers)),
    );
  }

  /// POST-запрос с JSON-телом. Бросает [ServerException] на `>= 400`.
  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    final jsonBody = body != null ? jsonEncode(body) : null;

    return _executeRequest(
      method: 'POST',
      path: path,
      bodyForLog: jsonBody,
      send: () => _client.post(
        _buildUri(path),
        headers: _mergeHeaders(headers),
        body: jsonBody,
      ),
    );
  }

  /// PATCH-запрос с JSON-телом. Бросает [ServerException] на `>= 400`.
  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    final jsonBody = body != null ? jsonEncode(body) : null;

    return _executeRequest(
      method: 'PATCH',
      path: path,
      bodyForLog: jsonBody,
      send: () => _client.patch(
        _buildUri(path),
        headers: _mergeHeaders(headers),
        body: jsonBody,
      ),
    );
  }

  /// DELETE-запрос. Бросает [ServerException] на `>= 400`.
  Future<http.Response> delete(String path, {Map<String, String>? headers}) {
    return _executeRequest(
      method: 'DELETE',
      path: path,
      send: () =>
          _client.delete(_buildUri(path), headers: _mergeHeaders(headers)),
    );
  }

  // ============================================================
  // 4. СТРИМ (SSE)
  // ============================================================

  /// POST-запрос со стрим-ответом (SSE). Бросает [ServerException] на `>= 400`.
  ///
  /// **Почему отдельно от _executeRequest:**
  /// при ошибке надо прочитать тело (это JSON, а не SSE-поток),
  /// чтобы положить его в `ServerException.responseBody`. Если отдать
  /// стрим в SseParser, тот не сможет прочитать тело — он ожидает
  /// SSE-события, а не JSON ошибки.
  ///
  /// Успех (`200 OK`) — возвращаем `StreamedResponse` как есть,
  /// парсер SSE прочитает тело по кусочкам.
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

      // Проверяем статус ДО возврата. На ошибке читаем тело целиком —
      // это уже не стрим, а обычный JSON с деталями.
      if (response.statusCode >= 400) {
        final bodyString = await response.stream.bytesToString();
        _logHttpError(response.statusCode, bodyString);

        throw _buildServerExceptionFromBody(
          statusCode: response.statusCode,
          bodyString: bodyString,
        );
      }

      return response;
    } on TimeoutException {
      AppLogger.error('Таймаут при выполнении POST-запроса (stream): $path');
      throw NetworkException.timeout();
    } on http.ClientException catch (e, stackTrace) {
      AppLogger.error(
        'Ошибка сети при POST-запросе (stream): $path',
        e,
        stackTrace,
      );
      throw NetworkException.connectionError(e);
    } on ServerException {
      // Уже наше — пробрасываем как есть, чтобы не обернуть в общий.
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.error('Ошибка при POST-запросе (stream): $path', e, stackTrace);
      throw NetworkException.connectionError(e);
    }
  }

  // ============================================================
  // 5. MULTIPART (ЗАГРУЗКА ФАЙЛОВ)
  // ============================================================

  /// POST-запрос с multipart/form-data. **Не бросает на `>= 400`.**
  ///
  /// Особенности:
  /// - **Отдельный таймаут** [timeout] — по умолчанию [AppConfig.uploadTimeout]
  ///   (10 минут), потому что сервер синхронно прогоняет файл через MinerU.
  /// - **Не бросает на `>= 400`** — каждый статус здесь несёт бизнес-смысл:
  ///   201 = успех, 400 = проблема с запросом, 413 = файл большой,
  ///   502 = MinerU упал, 503 = перегрузка. Разбор — задача репозитория.
  /// - **Транспортные ошибки бросает** как обычно: нет сети → NetworkException,
  ///   таймаут → NetworkException.
  ///
  /// Пример:
  /// ```dart
  /// final response = await client.postMultipart(
  ///   '/agents/document_chat/v1/files',
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

    AppLogger.info('POST (multipart) $uri');
    AppLogger.debug(
      'Загружаем файл: ${file.path.split('/').last} '
      '(${await file.length()} байт)',
    );

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(allHeaders);

      if (fields != null && fields.isNotEmpty) {
        request.fields.addAll(fields);
      }

      // fromPath — предпочтительнее fromBytes: файл читается по кускам
      // по мере отправки, а не грузится целиком в память.
      final multipartFile = await http.MultipartFile.fromPath(
        fileField,
        file.path,
      );
      request.files.add(multipartFile);

      final streamedResponse = await _client
          .send(request)
          .timeout(effectiveTimeout);

      final response = await http.Response.fromStream(streamedResponse);

      AppLogger.debug('POST (multipart) ${response.statusCode}');
      _logResponse(response);

      // НЕ бросаем на >= 400 — разбор статуса на стороне репозитория.
      return response;
    } on TimeoutException catch (e, stackTrace) {
      AppLogger.error(
        'Таймаут при загрузке файла: $path '
        '(лимит: ${effectiveTimeout.inMinutes} мин)',
        e,
        stackTrace,
      );
      throw NetworkException.timeout(e);
    } on http.ClientException catch (e, stackTrace) {
      AppLogger.error('Ошибка сети при загрузке файла: $path', e, stackTrace);
      throw NetworkException.connectionError(e);
    } catch (e, stackTrace) {
      AppLogger.error('Ошибка при загрузке файла: $path', e, stackTrace);
      throw NetworkException.connectionError(e);
    }
  }

  // ============================================================
  // 6. ЗАКРЫТИЕ
  // ============================================================

  /// Закрывает HTTP-клиент. Обычно вызывается при завершении приложения.
  void close() {
    AppLogger.debug('Закрытие HTTP клиента');
    _client.close();
  }

  // ============================================================
  // 7. ПРИВАТНЫЕ МЕТОДЫ — ОБЩИЙ КОНВЕЙЕР
  // ============================================================

  /// Общий конвейер для обычных запросов (`get`/`post`/`patch`/`delete`).
  ///
  /// Делает всё в одном месте:
  /// - ставит таймаут;
  /// - логирует запрос и ответ;
  /// - ловит транспортные ошибки → [NetworkException];
  /// - проверяет статус → [ServerException] на `>= 400`.
  ///
  /// [send] — лямбда, которая выполняет конкретный запрос. Например,
  /// для `get` это `() => _client.get(...)`. Так один хелпер обслуживает
  /// четыре метода без дублирования.
  Future<http.Response> _executeRequest({
    required String method,
    required String path,
    required Future<http.Response> Function() send,
    String? bodyForLog,
  }) async {
    AppLogger.info('$method ${_buildUri(path)}');
    if (bodyForLog != null) {
      AppLogger.debug('Тело запроса: ${bodyForLog.length} символов');
    }

    try {
      final response = await send().timeout(AppConfig.timeout);

      AppLogger.debug('$method ${response.statusCode}');

      // Единая проверка статуса для всех обычных методов.
      _throwIfError(response);

      return response;
    } on TimeoutException catch (e, stackTrace) {
      AppLogger.error('Таймаут $method-запроса: $path', e, stackTrace);
      throw NetworkException.timeout(e);
    } on http.ClientException catch (e, stackTrace) {
      AppLogger.error('Ошибка сети $method-запроса: $path', e, stackTrace);
      throw NetworkException.connectionError(e);
    } on ServerException {
      // Уже наше — пробрасываем как есть.
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.error('Ошибка $method-запроса: $path', e, stackTrace);
      throw NetworkException.connectionError(e);
    }
  }

  /// Проверяет статус ответа и бросает [ServerException] при `>= 400`.
  ///
  /// Делегирует создание исключения в [HttpErrorBuilder] —
  /// единую точку создания `ServerException` в приложении.
  void _throwIfError(http.Response response) {
    if (response.statusCode < 400) return;

    _logHttpError(response.statusCode, response.body);

    throw HttpErrorBuilder.fromResponse(response);
  }

  /// Создаёт [ServerException] из статуса и **строки** тела.
  ///
  /// Нужен **только** для `postStream`: там тело ошибки читается
  /// через `response.stream.bytesToString()` — это **строка**, а не
  /// готовый `http.Response`. `HttpErrorBuilder.fromResponse` требует
  /// `http.Response`, которого у нас нет. Поэтому — строим `Response`
  /// вручную и передаём в билдер.
  ///
  /// **Почему не отдельный метод билдера:** это **тонкий** случай,
  /// он нужен **только** в `postStream`. Держать его локально —
  /// правильнее, чем раздувать публичный API `HttpErrorBuilder`.
  ServerException _buildServerExceptionFromBody({
    required int statusCode,
    required String bodyString,
  }) {
    // Собираем искусственный http.Response, чтобы переиспользовать
    // логику HttpErrorBuilder.fromResponse.
    final fakeResponse = http.Response(
      bodyString,
      statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

    return HttpErrorBuilder.fromResponse(fakeResponse);
  }

  /// Логирует HTTP-ошибку с телом (обрезанным до 200 символов).
  void _logHttpError(int statusCode, String body) {
    final preview = body.length > 200 ? '${body.substring(0, 200)}...' : body;
    AppLogger.warning('HTTP $statusCode: $preview');
  }

  /// Логирует ответ, если он содержит ошибку.
  ///
  /// Используется в `postMultipart`, где мы не бросаем на `>= 400`,
  /// но хотим видеть ошибку в логах.
  void _logResponse(http.Response response) {
    if (response.statusCode >= 400) {
      _logHttpError(response.statusCode, response.body);
    }
  }

  // ============================================================
  // 8. ПРИВАТНЫЕ МЕТОДЫ — URL И ЗАГОЛОВКИ
  // ============================================================

  /// Строит полный URI из базового URL и пути.
  Uri _buildUri(String path) {
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;

    final cleanPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$base$cleanPath');
  }

  /// Объединяет заголовки по умолчанию с переданными.
  ///
  /// Всегда добавляет `X-User-Id` — сейчас это единственный способ
  /// аутентификации. Когда появится настоящая авторизация (JWT),
  /// здесь же добавится `Authorization: Bearer ...`.
  Map<String, String> _mergeHeaders(
    Map<String, String>? customHeaders, {
    bool isStream = false,
  }) {
    final defaultHeaders = isStream
        ? AppConfig.streamHeaders
        : AppConfig.defaultHeaders;

    final headers = Map<String, String>.from(defaultHeaders)
      ..['X-User-Id'] = AppConfig.userId;

    if (customHeaders != null) {
      headers.addAll(customHeaders);
    }

    return headers;
  }
}
