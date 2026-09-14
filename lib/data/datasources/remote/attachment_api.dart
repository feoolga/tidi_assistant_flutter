// lib/data/datasources/remote/attachment_api.dart

import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../core/network/http_client.dart';

/// API-слой для работы с файлами.
///
/// Обёртка над `AppHttpClient`, знающая конкретные эндпоинты бэкенда.
/// Задача — держать URL и параметры multipart-формы в одном месте,
/// чтобы `AttachmentRepository` работал с методами, а не с путями.
///
/// ВАЖНО: этот класс НЕ парсит ответ и НЕ обрабатывает статусы —
/// только возвращает сырой `http.Response`. Разбор `201`/`413`/`400`/`502`
/// и превращение в `Attachment` — работа `AttachmentRepository`.
class AttachmentApi {
  final AppHttpClient _httpClient;

  AttachmentApi({AppHttpClient? httpClient})
    : _httpClient = httpClient ?? AppHttpClient();

  // ============================================================
  // 1. ЗАГРУЗКА ФАЙЛА
  // ============================================================

  /// POST /v1/files — загрузить документ.
  ///
  /// Бэкенд (`document_chat`) синхронно прогоняет файл через MinerU
  /// (OCR + разбор в markdown) прямо в этом вызове. Поэтому таймаут —
  /// до 10 минут (см. `AppConfig.uploadTimeout`, применяется внутри
  /// `postMultipart`).
  ///
  /// [conversationId] — опциональная привязка файла к чату.
  /// Если задан, файл в форме Responses будет автоматически
  /// подтягиваться в последующие вопросы этого чата
  /// (см. README `document_chat`).
  ///
  /// Возвращает сырой ответ — вызывающий код сам смотрит статус.
  Future<http.Response> uploadFile({
    required File file,
    String? conversationId,
  }) async {
    // Имя поля формы — 'file': именно это ждёт бэкенд (`-F "file=@..."`).
    // Оставляем дефолт `fileField` из `postMultipart` — не передаём явно,
    // чтобы не дублировать константу.
    final fields = conversationId != null
        ? <String, String>{'conversation_id': conversationId}
        : null;

    return _httpClient.postMultipart('/v1/files', file: file, fields: fields);
  }
}
