// lib/data/repositories/rag_repository.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/error_handler.dart';
import '../../core/errors/rag_exceptions.dart';
import '../../core/logger/app_logger.dart';
import '../../core/network/http_error_builder.dart';
import '../../domain/models/rag_document.dart';
import '../../domain/models/rag_set.dart';
import '../datasources/remote/rag_api.dart';
import '../mappers/rag_document_mapper.dart';
import '../mappers/rag_set_mapper.dart';
import '../models/rag_document_dto.dart';
import '../models/rag_set_dto.dart';

/// Репозиторий для работы с RAG-наборами и документами.
///
/// **Роль.** Прослойка между `RagApi` (транспорт) и use-case'ами
/// (домен). Отвечает за:
/// - разбор HTTP-статусов (`201`/`200`/`202`/`204`/`4xx`/`5xx`);
/// - парсинг JSON в DTO;
/// - превращение DTO в доменные модели через мапперы;
/// - превращение транспортных ошибок в `RagException` через
///   `ErrorHandler`.
///
/// **Что НЕ делает:**
/// - не управляет состоянием (это `RagCreationNotifier`, D6);
/// - не поллит статус (это `RagStatusPoller`, D5);
/// - не кеширует (кеш — отдельный слой, позже).
///
/// **Про частичную загрузку документов.** Запрос `uploadDocuments`
/// **не атомарный**: сервер пишет файлы по очереди, каждый со своим
/// коммитом. Ошибка на середине — первые файлы **остаются принятыми**,
/// а клиент **не получает** их список. **После любой ошибки
/// загрузки** — вызывающий код **обязан** перечитать список через
/// [listDocuments], чтобы узнать **реальное** состояние.
///
/// **Роль репозитория — только сообщить об ошибке.** Логика
/// «перечитать» — в use-case / notifier (D4, D6).
class RagRepository {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final RagApi _api;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  RagRepository({RagApi? api}) : _api = api ?? RagApi();

  // ============================================================
  // 3. НАБОРЫ — CRUD
  // ============================================================

  /// Создать новый RAG-набор.
  ///
  /// **Успех:** `201` → распарсенный [RagSet].
  ///
  /// **Ошибочные статусы:**
  /// - `409` → [RagException.limitReached] — превышен лимит наборов.
  /// - прочие `4xx`/`5xx` → `RagException.createFailed`
  ///   (через `handleRagCreation`).
  Future<RagSet> create({
    required String name,
    String? description,
    Map<String, dynamic>? config,
  }) async {
    AppLogger.info('Создание RAG-набора: "$name"');

    try {
      final response = await _api.createRag(
        name: name,
        description: description,
        config: config,
      );

      switch (response.statusCode) {
        case 201:
          final set = _parseSingleSet(response.body);
          AppLogger.info('RAG-набор создан: ${set.id}');
          return set;
        case 409:
          AppLogger.warning('Превышен лимит RAG-наборов (409)');
          throw RagException.limitReached();
        default:
          throw HttpErrorBuilder.fromResponse(response);
      }
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось создать RAG-набор',
        {'name': name, 'hasDescription': description != null},
      );
    }
  }

  /// Получить список **своих** RAG-наборов.
  ///
  /// **Успех:** `200` → список [RagSet].
  /// **Формат ответа:** `{"data": [...]}` — обёртка.
  Future<List<RagSet>> list() async {
    AppLogger.debug('Загрузка списка RAG-наборов');

    try {
      final response = await _api.listRags();

      if (response.statusCode != 200) {
        throw HttpErrorBuilder.fromResponse(response);
      }

      final sets = _parseSetList(response.body);
      AppLogger.debug('Загружено RAG-наборов: ${sets.length}');
      return sets;
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось загрузить список RAG-наборов',
      );
    }
  }

  /// Получить один RAG-набор по id.
  ///
  /// **Успех:** `200` → [RagSet].
  /// **Ошибочные статусы:** `404` → [RagException.notFound].
  Future<RagSet> get(String ragId) async {
    AppLogger.debug('Загрузка RAG-набора: $ragId');

    try {
      final response = await _api.getRag(ragId: ragId);

      switch (response.statusCode) {
        case 200:
          return _parseSingleSet(response.body);
        case 404:
          AppLogger.info('RAG-набор не найден: $ragId (404)');
          throw RagException.notFound(ragId);
        default:
          throw HttpErrorBuilder.fromResponse(response);
      }
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось загрузить RAG-набор',
        {'ragId': ragId},
      );
    }
  }

  /// Частично обновить RAG-набор.
  ///
  /// **Успех:** `200` → обновлённый [RagSet].
  /// **Ошибочные статусы:** `404` → [RagException.notFound].
  Future<RagSet> update({
    required String ragId,
    String? name,
    String? description,
    Map<String, dynamic>? config,
  }) async {
    AppLogger.info('Обновление RAG-набора: $ragId');

    try {
      final response = await _api.updateRag(
        ragId: ragId,
        name: name,
        description: description,
        config: config,
      );

      switch (response.statusCode) {
        case 200:
          final set = _parseSingleSet(response.body);
          AppLogger.info('RAG-набор обновлён: ${set.id}');
          return set;
        case 404:
          throw RagException.notFound(ragId);
        default:
          throw HttpErrorBuilder.fromResponse(response);
      }
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось обновить RAG-набор',
        {'ragId': ragId},
      );
    }
  }

  /// Удалить RAG-набор (soft-delete + фоновая уборка).
  ///
  /// **Успех:** `204 No Content` **или** `200`.
  /// **Ошибочные статусы:** `404` → [RagException.notFound].
  Future<void> delete(String ragId) async {
    AppLogger.info('Удаление RAG-набора: $ragId');

    try {
      final response = await _api.deleteRag(ragId: ragId);

      switch (response.statusCode) {
        case 200:
        case 204:
          AppLogger.info('RAG-набор удалён: $ragId');
          return;
        case 404:
          throw RagException.notFound(ragId);
        default:
          throw HttpErrorBuilder.fromResponse(response);
      }
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось удалить RAG-набор',
        {'ragId': ragId},
      );
    }
  }

  // ============================================================
  // 4. ДОКУМЕНТЫ
  // ============================================================

  /// Загрузить **пачку** файлов в RAG-набор.
  ///
  /// **Успех:** `202` → список [RagDocument] (принятые + дубликаты).
  ///
  /// **Ошибочные статусы:**
  /// - `413` → [RagException.fileTooLarge] — файл слишком большой
  ///   **или** превышен общий размер набора.
  /// - `415` → [RagException.unsupportedFormat] — неподдерживаемый
  ///   формат.
  /// - прочие → `RagException.uploadFailed` (через `handleRagUpload`).
  ///
  /// **Клиентский лимит.** [AppConfig.ragMaxFilesPerBatch] файлов
  /// в одном вызове (по умолчанию 10). Бэкенд лимит **не**
  /// устанавливает, но **рекомендует** пачки 5–10 — из-за
  /// **не атомарности** (см. ниже).
  ///
  /// **КРИТИЧНО: загрузка не атомарная.** Файлы пишутся по очереди.
  /// Ошибка на середине → **первые файлы приняты**, клиент **не
  /// получает** их список. **После любой ошибки** вызывающий код
  /// **обязан** вызвать [listDocuments], чтобы узнать реальное
  /// состояние набора.
  Future<List<RagDocument>> uploadDocuments({
    required String ragId,
    required List<File> files,
  }) async {
    AppLogger.info(
      'Загрузка документов в набор $ragId: '
      '${files.length} файл(ов)',
    );

    // Клиентский лимит — рекомендация бэкендера «пачки 5–10».
    if (files.length > AppConfig.ragMaxFilesPerBatch) {
      throw RagException.tooManyFilesInBatch(
        actual: files.length,
        max: AppConfig.ragMaxFilesPerBatch,
      );
    }

    // Пустой список — ошибка программиста. Падаем до HTTP-запроса.
    if (files.isEmpty) {
      throw ArgumentError.value(
        files,
        'files',
        'Список файлов не может быть пустым',
      );
    }

    try {
      final response = await _api.uploadDocuments(ragId: ragId, files: files);

      switch (response.statusCode) {
        case 202:
          final documents = _parseDocumentUploadResponse(response.body);
          AppLogger.info('Загружено документов: ${documents.length}');
          return documents;

        case 413:
          AppLogger.warning(
            'Файл или набор превышают лимит (413). '
            'ВАЖНО: загрузка не атомарная — часть файлов могла '
            'быть принята. Перечитайте список через listDocuments.',
          );
          throw RagException.fileTooLarge(
            serverMessage: _extractErrorMessage(response.body),
            maxBytes: AppConfig.ragMaxFileSizeBytes,
          );
        case 415:
          AppLogger.warning(
            'Неподдерживаемый формат (415). '
            'ВАЖНО: загрузка не атомарная — часть файлов могла '
            'быть принята.',
          );
          // Какой именно MIME отвергнут — из тела ответа неясно.
          throw RagException.unsupportedFormat(mimeType: 'unknown');

        default:
          // Прочие 4xx/5xx. Частичная загрузка тоже возможна —
          // логируем предупреждение.
          AppLogger.warning(
            'Ошибка загрузки (${response.statusCode}). '
            'ВАЖНО: загрузка не атомарная — часть файлов могла '
            'быть принята.',
          );
          throw HttpErrorBuilder.fromResponse(response);
      }
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagUpload(
        e,
        stackTrace,
        'Не удалось загрузить документы в RAG-набор',
        {'ragId': ragId, 'filesCount': files.length},
      );
    }
  }

  /// Получить список документов набора.
  ///
  /// **Успех:** `200` → список [RagDocument].
  ///
  /// **Формат ответа — устойчив к двум вариантам:**
  /// - массив напрямую: `[...]`;
  /// - обёртка: `{"data": [...]}`.
  ///
  /// README ingestion-сервиса **не даёт** примера для этого эндпойнта,
  /// поэтому **принимаем оба** формата. Это **дёшево** и **безопасно**.
  Future<List<RagDocument>> listDocuments({required String ragId}) async {
    AppLogger.debug('Загрузка документов набора: $ragId');

    try {
      final response = await _api.listDocuments(ragId: ragId);

      if (response.statusCode != 200) {
        throw HttpErrorBuilder.fromResponse(response);
      }

      final documents = _parseDocumentList(response.body);
      AppLogger.debug(
        'Загружено документов набора $ragId: ${documents.length}',
      );
      return documents;
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось загрузить список документов набора',
        {'ragId': ragId},
      );
    }
  }

  /// Удалить документ из набора.
  ///
  /// **Успех:** `204 No Content` **или** `200`.
  /// **Ошибочные статусы:** `404` → [RagException.notFound].
  Future<void> deleteDocument({
    required String ragId,
    required String documentId,
  }) async {
    AppLogger.info('Удаление документа $documentId из набора $ragId');

    try {
      final response = await _api.deleteDocument(
        ragId: ragId,
        documentId: documentId,
      );

      switch (response.statusCode) {
        case 200:
        case 204:
          AppLogger.info('Документ удалён: $documentId');
          return;
        case 404:
          throw RagException.notFound(ragId);
        default:
          throw HttpErrorBuilder.fromResponse(response);
      }
    } on RagException {
      rethrow;
    } catch (e, stackTrace) {
      throw ErrorHandler.handleRagCreation(
        e,
        stackTrace,
        'Не удалось удалить документ',
        {'ragId': ragId, 'documentId': documentId},
      );
    }
  }

  // ============================================================
  // 5. ПРИВАТНЫЕ ХЕЛПЕРЫ — ПАРСИНГ
  // ============================================================

  RagSet _parseSingleSet(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final dto = RagSetDto.fromJson(json);
    return RagSetMapper.toDomain(dto);
  }

  List<RagSet> _parseSetList(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'];

    if (data is! List) {
      throw FormatException(
        'Ожидался объект {"data": [...]}, получено: '
        '${data.runtimeType}',
      );
    }

    return data
        .cast<Map<String, dynamic>>()
        .map(RagSetDto.fromJson)
        .map(RagSetMapper.toDomain)
        .toList();
  }

  /// Распарсить ответ `POST .../documents` (успех `202`).
  ///
  /// **Формат ответа:** `{"documents": [...]}` — обёртка.
  /// См. README ingestion-сервиса.
  List<RagDocument> _parseDocumentUploadResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final documents = json['documents'];

    if (documents is! List) {
      throw FormatException(
        'Ожидался объект {"documents": [...]}, получено: '
        '${documents.runtimeType}',
      );
    }

    return documents
        .cast<Map<String, dynamic>>()
        .map(RagDocumentDto.fromJson)
        .map(RagDocumentMapper.toDomain)
        .toList();
  }

  /// Распарсить список документов (`GET .../documents`).
  ///
  /// **Устойчив к двум форматам:**
  /// - массив напрямую: `[...]`;
  /// - обёртка: `{"data": [...]}`.
  ///
  /// README **не даёт** примера для этого эндпойнта, поэтому
  /// принимаем **оба**. Это **дёшево** и **безопасно**.
  List<RagDocument> _parseDocumentList(String body) {
    final decoded = jsonDecode(body);

    final dynamic data;
    if (decoded is List) {
      // Массив напрямую.
      data = decoded;
    } else if (decoded is Map<String, dynamic>) {
      // Обёртка {"data": [...]}.
      data = decoded['data'];
    } else {
      throw FormatException(
        'Ожидался массив или {"data": [...]}, получено: '
        '${decoded.runtimeType}',
      );
    }

    if (data is! List) {
      throw FormatException(
        'Поле "data" не является массивом: ${data.runtimeType}',
      );
    }

    return data
        .cast<Map<String, dynamic>>()
        .map(RagDocumentDto.fromJson)
        .map(RagDocumentMapper.toDomain)
        .toList();
  }

  /// Попытаться извлечь `error.message` из тела ошибки.
  ///
  /// Возвращает строку или `null`, если не получилось.
  /// **Не бросает** — это **best effort** для `technicalDetails`.
  String? _extractErrorMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) {
            return message;
          }
        }
      }
    } catch (_) {
      // Игнорируем — это best effort.
    }
    return null;
  }
}
