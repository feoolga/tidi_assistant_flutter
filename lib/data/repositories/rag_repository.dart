// lib/data/repositories/rag_repository.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors/error_handler.dart';
import '../../core/errors/rag_exceptions.dart';
import '../../core/logger/app_logger.dart';
import '../../core/network/http_error_builder.dart';
import '../../domain/models/rag_set.dart';
import '../datasources/remote/rag_api.dart';
import '../mappers/rag_set_mapper.dart';
import '../models/rag_set_dto.dart';

/// Репозиторий для работы с RAG-наборами.
///
/// **Роль.** Прослойка между `RagApi` (транспорт) и use-case'ами
/// (домен). Отвечает за:
/// - разбор HTTP-статусов (`201`/`200`/`204`/`404`/`409`/`400`);
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
/// **Версия D3.2a — только наборы.** Методы документов и иконки —
/// в D3.2b и D3.2c.
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
  ///
  /// **Транспортные ошибки** (нет сети, таймаут) и **невалидный JSON**
  /// — тоже через `handleRagCreation`.
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
          // 4xx/5xx, не покрытые выше. `RagApi` не бросает —
          // статус здесь `>= 400`. Разбираем через ServerException.
          // `handleRagCreation` превратит его в `createFailed`.
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
  ///
  /// **Формат ответа:** `{"data": [...]}` — обёртка (не массив
  /// напрямую). См. README ingestion-сервиса, раздел «Наборы».
  ///
  /// **Пустой список** — валидный ответ, возвращаем `[]`.
  ///
  /// **Ошибочные статусы:** любые `>= 400` → `createFailed` через
  /// `handleRagCreation`. Отдельные коды **не** различаем — при
  /// загрузке **списка** они **не** критичны.
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
  ///
  /// **Ошибочные статусы:**
  /// - `404` → [RagException.notFound] — не найден или чужой.
  /// - прочие → `createFailed`.
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
  /// **Бэкендер использует `exclude_unset`** — не переданные поля
  /// **сохраняют** текущие значения.
  ///
  /// **Успех:** `200` → обновлённый [RagSet].
  ///
  /// **Ошибочные статусы:**
  /// - `404` → [RagException.notFound].
  /// - прочие → `createFailed`.
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
  /// **Успех:** `204 No Content` (тело пустое) **или** `200`.
  /// Оба варианта считаем успехом.
  ///
  /// **Ошибочные статусы:**
  /// - `404` → [RagException.notFound] — уже удалён или чужой.
  /// - прочие → `createFailed`.
  ///
  /// **Про чаты.** Они **не удаляются** автоматически (см. ответ
  /// бэкендера). UI показывает плашку «набор удалён» — задача UI.
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
  // 4. ПРИВАТНЫЕ ХЕЛПЕРЫ — ПАРСИНГ
  // ============================================================

  /// Распарсить JSON с **одним** набором и превратить в [RagSet].
  ///
  /// **`FormatException`** (невалидный JSON) и `ArgumentError`
  /// (незнакомый `status`) **не** ловим здесь — пробрасываем
  /// наружу. Вызывающий код оборачивает **всё** через
  /// `ErrorHandler`.
  RagSet _parseSingleSet(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final dto = RagSetDto.fromJson(json);
    return RagSetMapper.toDomain(dto);
  }

  /// Распарсить JSON со **списком** наборов.
  ///
  /// **Формат ответа:** `{"data": [...]}` — обёртка. **Проверяем**
  /// наличие `data` и **тип** `List`. Если что-то не так —
  /// `FormatException` — это **ошибка контракта**.
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
}
