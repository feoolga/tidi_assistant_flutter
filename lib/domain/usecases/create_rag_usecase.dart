// lib/domain/usecases/create_rag_usecase.dart

import 'dart:io';

import '../../core/config/app_config.dart';
import '../../core/errors/rag_exceptions.dart';
import '../../core/logger/app_logger.dart';
import '../../data/repositories/rag_repository.dart';
import '../models/attachment.dart';
import '../models/rag_document.dart';
import '../models/rag_set.dart';

/// Результат создания RAG-набора.
///
/// **Зачем отдельный класс.** До этого `CreateRagUseCase` возвращал
/// `RagSet` и **бросал исключение** при ошибке upload. Но upload —
/// **не** атомарный (по README RAG Ingest): ошибка на середине
/// **оставляет** ранее принятые файлы в наборе. Значит, «ошибка
/// upload» — это **не** «use-case упал», а «use-case завершился
/// **частично**». Мы должны вернуть пользователю:
/// - сам набор (со счётчиками);
/// - список принятых файлов;
/// - ошибку upload (если была) — чтобы UI показал «что пошло не так».
///
/// `isPartial == true` — сама ошибка upload уже произошла; UI
/// показывает частичный результат и даёт кнопки «Открыть чат» /
/// «Удалить набор».
class CreateRagResult {
  /// Актуальный набор. Если `create` успел — здесь непустой `RagSet`.
  final RagSet set;

  /// Список документов набора — что реально **принято**.
  ///
  /// - при полном успехе — то, что вернул `uploadDocuments`;
  /// - при частичной загрузке — перечитано через `listDocuments`;
  /// - если перечитать не удалось — пустой список.
  final List<RagDocument> documents;

  /// Ошибка upload, если была. `null` — полный успех.
  final RagException? uploadError;

  /// `true`, если upload упал (хотя бы один файл не принят).
  final bool isPartial;

  const CreateRagResult({
    required this.set,
    required this.documents,
    required this.uploadError,
    required this.isPartial,
  });

  /// Полный успех — все файлы приняты.
  factory CreateRagResult.success({
    required RagSet set,
    required List<RagDocument> documents,
  }) {
    return CreateRagResult(
      set: set,
      documents: documents,
      uploadError: null,
      isPartial: false,
    );
  }

  /// Частичная загрузка — набор есть, но часть файлов не принята.
  factory CreateRagResult.partial({
    required RagSet set,
    required List<RagDocument> documents,
    required RagException uploadError,
  }) {
    return CreateRagResult(
      set: set,
      documents: documents,
      uploadError: uploadError,
      isPartial: true,
    );
  }
}

/// UseCase создания RAG-набора с загрузкой файлов.
///
/// **Сценарий «RAG по кнопке»:**
/// 1. Валидация: имя, файлы (количество, размер, MIME).
/// 2. Создать набор (`RagRepository.create`).
/// 3. Загрузить файлы (`RagRepository.uploadDocuments`).
/// 4. Перечитать набор (`RagRepository.get`) — для актуального
///    статуса и счётчиков.
/// 5. Вернуть [CreateRagResult].
///
/// **Что НЕ делает:**
/// - не поллит — это `WatchRagReadinessUseCase` (D4.2);
/// - не создаёт чат — это `StartRagChatUseCase` (D4.3);
/// - не показывает ошибок — только возвращает результат.
///
/// **Обработка ошибок:**
/// - **валидация** → падаем (это программная ошибка, не бизнес);
/// - **create** упал → падаем (набора нет — возвращать нечего);
/// - **upload** упал → **не** падаем, возвращаем
///   `CreateRagResult.partial` — с перечитанными состояниями;
/// - **get**/**listDocuments** после upload упали → **не** падаем,
///   возвращаем то, что успели получить.
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
  /// Возвращает [CreateRagResult]. **Не** бросает исключение при
  /// ошибке upload — возвращает `isPartial: true` + `uploadError`.
  Future<CreateRagResult> execute({
    required String name,
    String? description,
    required List<File> files,
    Map<String, dynamic>? config,
  }) async {
    AppLogger.info('Создание RAG-набора: name="$name", files=${files.length}');

    // -------- ВАЛИДАЦИЯ --------
    await _validate(name: name, files: files);

    // -------- СОЗДАНИЕ НАБОРА --------
    // Если `create` упадёт — исключение летит наружу, это нормально:
    // набора нет, возвращать нечего.
    final createdSet = await _repository.create(
      name: name,
      description: description,
      config: config,
    );
    AppLogger.info('Набор создан: ${createdSet.id}');

    // -------- ЗАГРУЗКА ФАЙЛОВ --------
    // Здесь **ловим** ошибку: upload не атомарный, часть файлов
    // может быть уже принята. Возвращаем частичный результат.
    List<RagDocument> uploadedDocuments;
    try {
      uploadedDocuments = await _repository.uploadDocuments(
        ragId: createdSet.id,
        files: files,
      );
      AppLogger.info('Файлы загружены для набора ${createdSet.id}');
    } on RagException catch (e, stackTrace) {
      AppLogger.logException(
        'Upload частично упал для набора ${createdSet.id}',
        e,
        stackTrace,
        {'ragId': createdSet.id, 'filesCount': files.length},
      );
      return _buildPartialResult(
        ragId: createdSet.id,
        fallbackSet: createdSet,
        uploadError: e,
      );
    } catch (e, stackTrace) {
      // Не-RagException (маловероятно — репозиторий всё оборачивает).
      // Всё равно не роняем: оборачиваем в RagException и возвращаем
      // как частичный результат.
      AppLogger.logException(
        'Upload упал с неожиданной ошибкой для набора ${createdSet.id}',
        e,
        stackTrace,
        {'ragId': createdSet.id, 'filesCount': files.length},
      );
      final wrapped = RagException.uploadFailed(error: e);
      return _buildPartialResult(
        ragId: createdSet.id,
        fallbackSet: createdSet,
        uploadError: wrapped,
      );
    }

    // -------- ПЕРЕЧИТЫВАЕМ НАБОР --------
    // Актуализируем статус и счётчики.
    // Если упадёт — не падаем, возвращаем набор от create.
    final updatedSet = await _refreshSetOrFallback(
      ragId: createdSet.id,
      fallbackSet: createdSet,
    );

    return CreateRagResult.success(
      set: updatedSet,
      documents: uploadedDocuments,
    );
  }

  // ============================================================
  // 4. ЧАСТИЧНЫЙ РЕЗУЛЬТАТ
  // ============================================================

  /// Собрать частичный результат: перечитать набор и документы.
  ///
  /// **Порядок**: сначала `get` (счётчики), потом `listDocuments`
  /// (список файлов). Оба — **не** обязательные: если упадут,
  /// вернём что есть (fallback на `createdSet`, пустой список).
  Future<CreateRagResult> _buildPartialResult({
    required String ragId,
    required RagSet fallbackSet,
    required RagException uploadError,
  }) async {
    final refreshedSet = await _refreshSetOrFallback(
      ragId: ragId,
      fallbackSet: fallbackSet,
    );

    final documents = await _tryListDocuments(ragId: ragId);

    AppLogger.info(
      'Частичная загрузка набора $ragId: '
      'принято ${documents.length}, ошибка: ${uploadError.code}',
    );

    return CreateRagResult.partial(
      set: refreshedSet,
      documents: documents,
      uploadError: uploadError,
    );
  }

  /// Перечитать `RagSet` или вернуть fallback.
  ///
  /// Вспомогательный метод — используется и на успешном пути,
  /// и на частичном.
  Future<RagSet> _refreshSetOrFallback({
    required String ragId,
    required RagSet fallbackSet,
  }) async {
    try {
      final set = await _repository.get(ragId);
      AppLogger.debug(
        'Перечитан набор $ragId: status=${set.status.name}, '
        'documents: ${set.documentsCounts}',
      );
      return set;
    } catch (e) {
      AppLogger.warning(
        'Не удалось перечитать набор $ragId: $e. '
        'Возвращаем предыдущий слепок.',
      );
      return fallbackSet;
    }
  }

  /// Попробовать получить список документов. При ошибке — пустой список.
  Future<List<RagDocument>> _tryListDocuments({required String ragId}) async {
    try {
      return await _repository.listDocuments(ragId: ragId);
    } catch (e) {
      AppLogger.warning(
        'Не удалось получить список документов набора $ragId: $e. '
        'Возвращаем пустой список.',
      );
      return const [];
    }
  }

  // ============================================================
  // 5. ВАЛИДАЦИЯ
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
    final mimeType = mimeTypeFromFilename(fileName);
    if (!AppConfig.allowedMimeTypes.contains(mimeType)) {
      throw RagException.unsupportedFormat(mimeType: mimeType);
    }
  }
}
