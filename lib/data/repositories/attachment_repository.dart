// lib/data/repositories/attachment_repository.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// import '../../core/errors/app_exception.dart';
import '../../core/errors/error_handler.dart';
import '../../core/errors/file_exceptions.dart';
import '../../core/errors/server_exceptions.dart';
import '../../core/logger/app_logger.dart';
import '../../core/network/http_error_builder.dart';
import '../../domain/models/attachment.dart';
import '../datasources/remote/attachment_api.dart';
import '../mappers/attachment_mapper.dart';
import '../models/attachment_dto.dart';

/// Репозиторий для работы с вложениями.
///
/// Отвечает за:
/// 1. Отправку файла на сервер (через [AttachmentApi]).
/// 2. Разбор HTTP-ответа: `201` → успех, любой `>= 400` → подходящий
///    [FileException].
/// 3. Парсинг успешного ответа в [AttachmentDto] и маппинг в [Attachment].
/// 4. Обработку транспортных ошибок (нет сети, таймаут) и невалидного
///    JSON через [ErrorHandler.handleFileUpload].
///
/// **Ключевая ответственность** — классификация серверных ошибок.
/// Смотри [_classifyServerError] — там разбор статусов по бизнес-смыслу.
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
  /// **Бросает [FileException]** — в зависимости от того, что произошло:
  /// - [FileException.tooLarge] — если сервер прислал `actual_bytes`/`max_bytes`;
  /// - [FileException.tooLargeFromServer] — если сервер вернул 413 без этих полей
  ///   (например, HTML от nginx);
  /// - [FileException.processingFailed] — 502 от MinerU;
  /// - [FileException.notReady] — 400 (файл ещё обрабатывается);
  /// - [FileException.unsupportedFormat] — 415;
  /// - [FileException.uploadFailed] — все остальные случаи
  ///   (сеть, таймаут, невалидный JSON, 5xx без специфики).
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

      // Любой другой статус — превращаем в ServerException
      // (postMultipart не бросает сам) и разбираем.
      //
      // HttpErrorBuilder — единая точка создания ServerException.
      // См. lib/core/network/http_error_builder.dart.
      throw HttpErrorBuilder.fromResponse(response);
    } on FileException {
      // Уже готовый FileException — пробрасываем как есть.
      // Сюда попадают: валидация (выше по стеку), наши классификаторы.
      rethrow;
    } on ServerException catch (e, stackTrace) {
      // Серверная ошибка — классифицируем по статусу.
      // См. _classifyServerError — там разбор.
      final classified = _classifyServerError(e, stackTrace);
      throw classified;
    } catch (e, stackTrace) {
      // Транспортные ошибки (NetworkException), невалидный JSON,
      // всё остальное — в общий обработчик.
      //
      // ErrorHandler.handleFileUpload превращает NetworkException
      // в FileException.uploadFailed — потому что в контексте загрузки
      // файла «нет сети» = «не удалось загрузить файл».
      throw ErrorHandler.handleFileUpload(e, stackTrace);
    }
  }

  // ============================================================
  // 4. КЛАССИФИКАЦИЯ СЕРВЕРНЫХ ОШИБОК
  // ============================================================

  /// Превращает [ServerException] в **специфичный** [FileException]
  /// в зависимости от `statusCode`.
  ///
  /// **Зачем отдельный метод:**
  /// Разбор статусов — это **бизнес-логика** загрузки файлов.
  /// Она **не** должна жить в `upload` — иначе метод распухнет.
  /// Отдельный метод — легко читать, легко тестировать.
  ///
  /// **Логика по статусам:**
  /// - `413` → «файл слишком большой». Если есть `actual_bytes`/`max_bytes`
  ///   в теле — показываем цифры. Иначе — общее сообщение.
  /// - `502` → «MinerU не смог обработать». Текст от сервера — в технические
  ///   детали, пользователю — общее сообщение.
  /// - `400` → «файл ещё обрабатывается» (частый случай в README).
  /// - `415` → «формат не поддерживается».
  /// - всё остальное → [ErrorHandler.handleFileUpload] даст общий
  ///   `FileException.uploadFailed`.
  ///
  /// [stackTrace] нужен для логирования в fallback-ветках.
  FileException _classifyServerError(
    ServerException error,
    StackTrace? stackTrace,
  ) {
    // Логируем один раз — с контекстом операции.
    // Дальше в ветках логировать не надо.
    AppLogger.warning(
      'Файл не загружен: HTTP ${error.statusCode}, '
      'body=${error.responseBody ?? "(не JSON)"}',
    );

    switch (error.statusCode) {
      case 413:
        return _handleTooLarge(error);
      case 502:
        return _handleProcessingFailed(error);
      case 400:
        return _handleBadRequest(error);
      case 415:
        return _handleUnsupportedFormat(error);
      default:
        // Всё остальное — общий uploadFailed.
        // Пробрасываем через ErrorHandler, чтобы получить единый формат.
        return _asUploadFailed(error, stackTrace);
    }
  }

  // ============================================================
  // 5. ОБРАБОТЧИКИ КОНКРЕТНЫХ СТАТУСОВ
  // ============================================================

  /// `413 Payload Too Large` → «файл слишком большой».
  ///
  /// **Два сценария:**
  /// - **Бэкенд вернул JSON** с `actual_bytes`/`max_bytes` →
  ///   используем [FileException.tooLarge] с конкретными цифрами.
  ///   Пользователь увидит: «Файл слишком большой (35 МБ). Максимум — 25 МБ.»
  /// - **Бэкенд вернул JSON без этих полей** (или HTML от nginx) →
  ///   используем [FileException.tooLargeFromServer] с общим сообщением.
  ///   Пользователь увидит: «Файл слишком большой. Попробуйте файл меньшего размера.»
  ///
  /// **Почему `tryParse` защитный:** мы **не знаем**, присылает ли бэкенд
  /// `actual_bytes`. README **не обещает**. Значит — код **должен** работать
  /// и без них. Если присылает — используем; если нет — fallback.
  FileException _handleTooLarge(ServerException error) {
    final errorData = error.responseBody?['error'] as Map<String, dynamic>?;

    final actualBytes = errorData?['actual_bytes'] as int?;
    final maxBytes = errorData?['max_bytes'] as int?;

    // Если оба поля есть — используем их для точного сообщения.
    if (actualBytes != null && maxBytes != null) {
      return FileException.tooLarge(sizeBytes: actualBytes, maxBytes: maxBytes);
    }

    // Иначе — общее сообщение + текст от сервера в технические детали.
    final serverMessage = errorData?['message'] as String?;
    return FileException.tooLargeFromServer(serverMessage);
  }

  /// `502 Bad Gateway` → «MinerU не смог обработать документ».
  ///
  /// По README, `502` приходит, когда MinerU упал при разборе PDF.
  /// Пользователю — общее сообщение, разработчику — текст от сервера.
  FileException _handleProcessingFailed(ServerException error) {
    final errorData = error.responseBody?['error'] as Map<String, dynamic>?;
    final serverMessage = errorData?['message'] as String?;

    return FileException.processingFailed(serverMessage);
  }

  /// `400 Bad Request` → «файл ещё обрабатывается» или «слишком много файлов».
  ///
  /// По README, `400` приходит в двух случаях:
  /// - файл ещё не обработан (`processing_status != done`),
  /// - приложено больше `MAX_ATTACHED_FILES`.
  ///
  /// Различать **точно** мы не можем — бэкенд не шлёт `error.code`.
  /// Поэтому — общий [FileException.notReady]. Если когда-нибудь
  /// бэкенд начнёт шлёт `error.code = "too_many_files"` — добавим ветку.
  FileException _handleBadRequest(ServerException error) {
    return FileException.notReady();
  }

  /// `415 Unsupported Media Type` → «формат не поддерживается».
  FileException _handleUnsupportedFormat(ServerException error) {
    // MIME-тип мы не знаем — он был в запросе, а не в ответе.
    // Поэтому — общая фабрика с «unknown».
    return FileException.unsupportedFormat(mimeType: 'unknown');
  }

  /// Fallback: превращает [ServerException] в общий [FileException.uploadFailed].
  ///
  /// Использует [ErrorHandler.handleFileUpload] — единый путь для
  /// **всех** неспецифичных ошибок. Там `ServerException` превратится
  /// в `FileException.uploadFailed` с текстом от сервера в `technicalDetails`.
  FileException _asUploadFailed(ServerException error, StackTrace? stackTrace) {
    final result = ErrorHandler.handleFileUpload(error, stackTrace);
    // handleFileUpload возвращает AppException — но в контексте
    // загрузки файла это **всегда** FileException. Кастуем безопасно.
    return result as FileException;
  }

  // ============================================================
  // 6. РАЗБОР УСПЕШНОГО ОТВЕТА
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
}
