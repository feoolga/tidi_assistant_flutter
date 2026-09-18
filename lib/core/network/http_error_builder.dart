// lib/core/network/http_error_builder.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/server_exceptions.dart';

/// Строитель [ServerException] из [http.Response].
///
/// **Зачем нужен отдельный класс:**
///
/// Создание [ServerException] нужно в **двух** местах:
/// 1. `AppHttpClient` — после обычного запроса (`get`/`post`/…),
///    где клиент **сам** решает, что `>= 400` — это ошибка.
/// 2. `AttachmentRepository` — после `postMultipart`, который **не бросает**
///    на `>= 400` (потому что статусы там несут бизнес-смысл).
///
/// Чтобы **не дублировать** логику (парсинг тела, разделение 4xx/5xx),
/// она вынесена сюда. Оба места вызывают [fromResponse] — единый источник правды.
///
/// **Что класс НЕ делает:**
/// - не бросает исключение сам — только создаёт;
/// - не логирует — логирование требует контекста, он есть у вызывающего;
/// - не знает про домен (чаты, агенты, файлы) — только про HTTP.
class HttpErrorBuilder {
  /// Приватный конструктор — класс используется только статически.
  const HttpErrorBuilder._();

  // ============================================================
  // 1. ПУБЛИЧНЫЙ API
  // ============================================================

  /// Создаёт [ServerException] из [http.Response].
  ///
  /// **Разделение по классу статуса:**
  /// - `4xx` → [ServerException.clientError] — ошибка клиента
  ///   (неправильный запрос, нет доступа, не найдено);
  /// - `5xx` → [ServerException.serverError] — ошибка сервера
  ///   (сломалось, перегрузка, MinerU упал).
  ///
  /// Разные фабрики дают **разные** `userMessage`. Это важно для UI:
  /// «Некорректный запрос» vs «На сервере произошла ошибка».
  ///
  /// **Парсинг тела:**
  /// Пытается распарсить тело как JSON-объект. Если получится —
  /// кладёт результат в `responseBody` (там будет `error.message`,
  /// `error.code`, `error.type` от бэкенда). Если нет (HTML от nginx,
  /// пустое тело) — `responseBody` будет `null`.
  ///
  /// **Никогда не бросает.** Даже если тело — не JSON, даже если
  /// оно пустое. Просто создаёт [ServerException] с тем, что есть.
  static ServerException fromResponse(http.Response response) {
    final parsedBody = tryParseJson(response.body);

    if (response.statusCode >= 500) {
      return ServerException.serverError(
        statusCode: response.statusCode,
        body: parsedBody,
      );
    }
    return ServerException.clientError(
      statusCode: response.statusCode,
      body: parsedBody,
    );
  }

  /// Пытается распарсить тело как JSON-объект.
  ///
  /// Возвращает `null`, если:
  /// - тело пустое;
  /// - тело — не валидный JSON;
  /// - тело — валидный JSON, но не объект (например, массив или число).
  ///
  /// **Никогда не бросает.** Используется для **диагностики**, а не логики.
  ///
  /// **Публичный**, потому что нужен ещё в `AppHttpClient._executeRequest`
  /// (для `postStream` — там тело читается отдельно).
  static Map<String, dynamic>? tryParseJson(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
