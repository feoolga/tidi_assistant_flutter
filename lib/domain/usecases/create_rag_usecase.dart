// lib/domain/usecases/create_rag_usecase.dart

import 'dart:io';

import '../../core/config/app_config.dart';
import '../../core/errors/rag_exceptions.dart';
import '../../core/logger/app_logger.dart';
import '../../data/repositories/rag_repository.dart';
import '../models/rag_set.dart';
import '../utils/rag_file_utils.dart';

/// UseCase создания RAG-набора с загрузкой файлов.
///
/// **MVP-сценарий «RAG по кнопке»:**
/// 1. Валидация: имя, файлы (количество, размер, MIME).
/// 2. Создать набор (`RagRepository.create`).
/// 3. Загрузить файлы (`RagRepository.uploadDocuments`).
/// 4. Перечитать набор (`RagRepository.get`) — для актуального
///    статуса и счётчиков.
/// 5. Вернуть [RagSet].
///
/// **Что возвращаем и почему.** Возвращаем **`RagSet`**, а не
/// `CreateRagResult` с документами. Обоснование: для прогресс-экрана
/// достаточно **счётчиков** (`documentsCounts.total/ready/failed/pending`)
/// и статуса. Имена файлов не критичны — если понадобятся, добавим
/// `listDocuments` в следующей итерации.
///
/// **Что НЕ делает:**
/// - не поллит — это `WatchRagReadinessUseCase` (D4.2);
/// - не создаёт чат — это `StartRagChatUseCase` (D4.3);
/// - не показывает ошибок — только **кидает**.
///
/// **Обработка ошибок:**
/// - **валидация** → сразу падаем;
/// - **create** упал → падаем (набора нет);
/// - **upload** упал → падаем (набор **создан**, файлы **частично**);
/// - **get** упал → **не** падаем, возвращаем `RagSet` от `create`.
class CreateRagUseCase {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final RagRepository _repository;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  CreateRagUseCase({required RagRepository repository})
    : _repository = repository;

  // ============================================================
  // 3. ВЫПОЛНЕНИЕ
  // ============================================================

  /// Создать RAG-набор и загрузить файлы.
  ///
  /// Возвращает **актуальный** `RagSet` (со статусом `ingesting`
  /// и счётчиками). Если `get` после upload **упал** — вернёт
  /// `RagSet` от `create` со статусом `empty`.
  Future<RagSet> execute({
    required String name,
    String? description,
    required List<File> files,
    Map<String, dynamic>? config,
  }) async {
    AppLogger.info('Создание RAG-набора: name="$name", files=${files.length}');

    // -------- ВАЛИДАЦИЯ --------
    await _validate(name: name, files: files);

    // -------- СОЗДАНИЕ НАБОРА --------
    final createdSet = await _repository.create(
      name: name,
      description: description,
      config: config,
    );
    AppLogger.info('Набор создан: ${createdSet.id}');

    // -------- ЗАГРУЗКА ФАЙЛОВ --------
    await _repository.uploadDocuments(ragId: createdSet.id, files: files);
    AppLogger.info('Файлы загружены для набора ${createdSet.id}');

    // -------- ПЕРЕЧИТЫВАЕМ НАБОР --------
    // Актуализируем статус и счётчики.
    // Если упадёт — НЕ падаем, возвращаем набор от create.
    try {
      final updatedSet = await _repository.get(createdSet.id);
      AppLogger.info(
        'RAG-набор: ${updatedSet.id}, status=${updatedSet.status.name}, '
        'documents: ${updatedSet.documentsCounts}',
      );
      return updatedSet;
    } catch (e) {
      AppLogger.warning(
        'Не удалось перечитать набор ${createdSet.id} после upload: $e. '
        'Возвращаем набор от create — статус актуализируется через polling.',
      );
      return createdSet;
    }
  }

  // ============================================================
  // 4. ВАЛИДАЦИЯ
  // ============================================================

  Future<void> _validate({
    required String name,
    required List<File> files,
  }) async {
    // 1. Имя.
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Имя RAG-набора не может быть пустым',
      );
    }
    if (trimmedName.length > AppConfig.ragMaxNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'Имя RAG-набора не должно превышать '
            '${AppConfig.ragMaxNameLength} символов',
      );
    }

    // 2. Количество файлов.
    if (files.isEmpty) {
      throw ArgumentError.value(
        files,
        'files',
        'Нужен хотя бы один файл для RAG-набора',
      );
    }
    if (files.length > AppConfig.ragMaxFilesPerBatch) {
      throw RagException.tooManyFilesInBatch(
        actual: files.length,
        max: AppConfig.ragMaxFilesPerBatch,
      );
    }

    // 3. Каждый файл — размер + MIME.
    for (final file in files) {
      await _validateFile(file);
    }
  }

  Future<void> _validateFile(File file) async {
    final fileName = file.uri.pathSegments.last;

    // Размер.
    final sizeBytes = await file.length();
    if (sizeBytes > AppConfig.ragMaxFileSizeBytes) {
      throw RagException.fileTooLarge(maxBytes: AppConfig.ragMaxFileSizeBytes);
    }

    // MIME.
    final mimeType = ragMimeTypeFromFilename(fileName);
    if (!isRagAllowedMimeType(mimeType)) {
      throw RagException.unsupportedFormat(mimeType: mimeType);
    }
  }
}
