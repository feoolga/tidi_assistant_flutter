// lib/data/repositories/attachment_repository.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/errors/error_handler.dart';
import '../../core/errors/file_exceptions.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logger/app_logger.dart';
import '../../domain/models/attachment.dart';
import '../datasources/remote/attachment_api.dart';
import '../mappers/attachment_mapper.dart';
import '../models/attachment_dto.dart';

/// Репозиторий для работы с вложениями.
///
/// Отвечает за:
/// 1. Вызов [AttachmentApi] — отправку файла на сервер.
/// 2. Разбор HTTP-ответа: `201` → успех, всё остальное → `FileException.uploadFailed`
///    с текстом от сервера в `technicalDetails`.
/// 3. Парсинг успешного ответа в [AttachmentDto] и маппинг в [Attachment].
/// 4. Обработку непредвиденных ошибок (сеть, таймаут, невалидный JSON)
///    через [ErrorHandler.handleFileUpload].
///
/// ВАЖНО: репозиторий НЕ различает типы серверных ошибок (413, 502, 400)
/// и не пытается угадать причину по тексту `error.message`. Пока бэкенд
/// не заполняет `error.code`, любой неуспешный ответ превращается в общую
/// `FileException.uploadFailed` с серверным текстом в `technicalDetails`.
///
/// Когда бэкенд начнёт возвращать осмысленный `error.code`
/// (например, `file_too_large`, `mineru_failed`, `too_many_files`),
/// здесь появится switch по `code` — и клиент сможет показывать
/// пользователю специфичные сообщения.
class AttachmentRepository {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final AttachmentApi _api;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  AttachmentRepository({AttachmentApi? api}) : _api = api ?? AttachmentApi();

  // ============================================================
  // 3. ЗАГРУЗКА ФАЙЛА
  // ============================================================

  /// Загрузить файл на сервер и получить доменную модель [Attachment].
  ///
  /// [file] — сам файл для отправки.
  /// [localId] — ID, который уже присвоен вложению в UI. Сохраняем его,
  ///   чтобы UI не потерял связь «до/после загрузки».
  /// [localPath] — путь к локальной копии (для превью). Обычно `file.path`,
  ///   но передаём явно — на случай, если вызывающий хочет другое значение.
  /// [conversationId] — опциональная привязка файла к чату.
  ///
  /// Возвращает [Attachment] со `status: done`, `remoteId` и прогрессом 1.0.
  ///
  /// Бросает [FileException]:
  /// - `uploadFailed` при любом неуспешном ответе (не 201) — с текстом
  ///   от сервера в `technicalDetails`;
  /// - `uploadFailed` при сетевых проблемах, таймаутах и невалидном JSON.
  Future<Attachment> upload({
    required File file,
    required String localId,
    required String localPath,
    String? conversationId,
  }) async {
    try {
      final response = await _api.uploadFile(
        file: file,
        conversationId: conversationId,
      );

      // Успех — парсим и маппим.
      if (response.statusCode == 201) {
        return _parseSuccessResponse(
          response,
          localId: localId,
          localPath: localPath,
        );
      }

      // Любой другой статус — общая ошибка с текстом от сервера.
      //
      // Осознанно НЕ разбираем 413/502/400 отдельно: бэкенд пока
      // не заполняет `error.code`, и угадывать по тексту `error.message`
      // — хрупко и не наша ответственность.
      // См. https://... (задача бэкендеру на осмысленный `code`)
      throw _exceptionFromResponse(response);
    } catch (e, stackTrace) {
      // Единая точка обработки:
      // - FileException от `_exceptionFromResponse` пройдёт как есть;
      // - http.ClientException, TimeoutException → uploadFailed;
      // - FormatException при парсинге невалидного JSON → uploadFailed.
      throw ErrorHandler.handleFileUpload(e, stackTrace);
    }
  }

  // ============================================================
  // 4. РАЗБОР УСПЕШНОГО ОТВЕТА
  // ============================================================

  /// Парсит JSON из успешного ответа (201) и маппит в [Attachment].
  Attachment _parseSuccessResponse(
    http.Response response, {
    required String localId,
    required String localPath,
  }) {
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final dto = AttachmentDto.fromJson(json);

    return AttachmentMapper.toDomain(
      dto,
      localId: localId,
      localPath: localPath,
    );
  }

  // ============================================================
  // 5. РАЗБОР ОШИБОЧНЫХ ОТВЕТОВ
  // ============================================================

  /// Превращает неуспешный ответ (не 201) в общую [FileException.uploadFailed].
  ///
  /// Текст от сервера (если получилось извлечь `error.message`) сохраняется
  /// в `technicalDetails` — пригодится разработчику в логах.
  /// Пользователь увидит стандартное «Не удалось загрузить файл...».
  ///
  /// Когда бэкенд начнёт отдавать осмысленный `error.code`, здесь появится
  /// разбор — какой `FileException` вернуть под конкретный случай.
  AppException _exceptionFromResponse(http.Response response) {
    // Извлекаем всё, что бэкенд прислал в error — сейчас нам реально
    // нужен только message для technicalDetails, но логируем и code, и type:
    // 1) чтобы видеть в логах, вдруг code уже не всегда null;
    // 2) чтобы накопить статистику, когда backend начнёт его заполнять.
    final errorData = _extractErrorData(response.body);
    final serverMessage = errorData.message ?? 'HTTP ${response.statusCode}';

    AppLogger.warning(
      'Файл не загружен: HTTP ${response.statusCode}, '
      'code=${errorData.code ?? "null"}, '
      'type=${errorData.type ?? "null"}, '
      'message="$serverMessage"',
    );

    return FileException.uploadFailed(serverMessage);
  }

  /// Разобранные поля объекта `error` из ответа бэкенда.
  ///
  /// Все поля опциональны: чего нет в ответе — то `null`.
  /// Никогда не бросает — это вспомогательная структура для логирования
  /// и передачи деталей в `technicalDetails`.
  ({String? message, String? code, String? type}) _extractErrorData(
    String body,
  ) {
    const empty = (message: null, code: null, type: null);
    if (body.isEmpty) return empty;

    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return empty;

      final error = decoded['error'];
      if (error is! Map<String, dynamic>) return empty;

      return (
        message: error['message'] is String ? error['message'] as String : null,
        code: error['code'] is String ? error['code'] as String : null,
        type: error['type'] is String ? error['type'] as String : null,
      );
    } catch (_) {
      // Тело не JSON или структура другая — не наша забота.
      return empty;
    }
  }
}
