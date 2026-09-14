// lib/domain/usecases/upload_attachment_usecase.dart

import 'dart:io';
import '../../core/logger/app_logger.dart';
import '../../data/repositories/attachment_repository.dart';
import '../models/attachment.dart';

/// UseCase для загрузки вложения на сервер.
///
/// Отвечает на вопрос: «Что делает приложение, когда пользователь
/// прикрепил файл?» — загружает его на сервер и возвращает доменную
/// модель [Attachment] с присвоенным `remoteId`.
///
/// Тонкая обёртка над [AttachmentRepository.upload], нужная для
/// соблюдения слоёв: UI работает с use-case'ами, а не с репозиториями
/// напрямую. Позже здесь может появиться дополнительная логика
/// (валидация перед загрузкой, обновление локального кэша, retry).
class UploadAttachmentUseCase {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final AttachmentRepository _repository;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  UploadAttachmentUseCase({required AttachmentRepository repository})
    : _repository = repository;

  // ============================================================
  // 3. ВЫПОЛНЕНИЕ
  // ============================================================

  /// Загрузить файл и получить доменную модель [Attachment].
  ///
  /// [file] — сам файл на диске.
  /// [localId] — ID, присвоенный вложению в UI. Должен совпадать
  ///   с тем, что уже используется в состоянии чата, — иначе UI
  ///   потеряет связь «до загрузки» и «после загрузки».
  /// [localPath] — путь к файлу для превью. Обычно `file.path`.
  /// [conversationId] — опциональная привязка к чату.
  ///
  /// Возвращает готовый [Attachment] со статусом `done`.
  /// Бросает [FileException] при любой ошибке загрузки —
  /// репозиторий уже приводит все исключения к этому типу.
  Future<Attachment> execute({
    required File file,
    required String localId,
    required String localPath,
    String? conversationId,
  }) async {
    // Логируем начало — на уровне сценария, а не транспорта.
    // Имя файла берём из пути: сам File не предоставляет fileName.
    final fileName = file.uri.pathSegments.last;
    AppLogger.info('Загрузка вложения: $fileName');

    // Вся тяжёлая работа и обработка ошибок — в репозитории.
    // UseCase не дублирует try/catch: FileException пройдёт наверх
    // как есть, UI её поймает.
    return _repository.upload(
      file: file,
      localId: localId,
      localPath: localPath,
      conversationId: conversationId,
    );
  }
}
