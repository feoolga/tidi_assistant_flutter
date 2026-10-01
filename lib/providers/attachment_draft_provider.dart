// lib/providers/attachment_draft_provider.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_handler.dart';
import '../core/errors/file_exceptions.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';
import '../data/repositories/chat_repository.dart';
import '../domain/models/attachment.dart';
import '../domain/usecases/upload_attachment_usecase.dart';
import 'agent_provider.dart';
import 'session_provider.dart';

// ============================================================
// 1. СОСТОЯНИЕ ЧЕРНОВИКА ВЛОЖЕНИЙ
// ============================================================

/// Состояние **черновика** вложений — файлов, выбранных пользователем,
/// но ещё **не отправленных** с сообщением.
///
/// **Почему отдельно от `ChatState`.**
///
/// `pendingAttachments` (теперь — [attachments]) — это **черновик ввода**,
/// а не «состояние чата». У них **разные жизненные циклы**:
/// - `ChatState.messages` — живёт долго, растёт, это **история**;
/// - `attachments` — живёт минуты, обнуляется, это **черновик**.
///
/// Смешивать их в одном объекте — значит путать «состояние» и «черновик
/// состояния». Плюс: `MessageInput` (поле ввода) тянет **весь** `ChatState`
/// из-за вложений, хотя ему нужны **только** вложения.
///
/// **Что это даёт для RAG.** У RAG-создания — **свой** поток файлов
/// (создание набора → загрузка пачки → polling). Если бы вложения
/// жили в `ChatState`, RAG пришлось бы либо класть в `ChatState`
/// (каша), либо дублировать логику. Отдельный `AttachmentDraftNotifier`
/// развязывает руки: RAG заведёт свой `RagCreationNotifier`, они
/// **параллельны**, не мешают друг другу.
class AttachmentDraftState {
  /// Список вложений-черновиков.
  ///
  /// **Не путать с [Message.attachments].** Тут — то, что **ещё не
  /// отправлено**. Когда сообщение отправляется, `ChatNotifier`
  /// забирает этот список, кладёт в `Message.fromUser(attachments: ...)`
  /// и **очищает** этот state.
  final List<Attachment> attachments;

  /// Идёт ли сейчас загрузка вложения на сервер.
  ///
  /// Пока `true` — UI блокирует кнопку «прикрепить», чтобы пользователь
  /// не запустил параллельную загрузку. Это важно, потому что
  /// `addAttachment` **не защищён от повторного вызова** на уровне
  /// транспорта — блокировка идёт через этот флаг.
  final bool isLoading;

  /// Ошибка, связанная с прикреплением файла.
  ///
  /// **НЕ** ошибка отправки сообщения — та живёт в `ChatState.error`.
  /// Здесь — только про файл: «файл слишком большой», «формат
  /// не поддерживается», «не удалось загрузить».
  ///
  /// UI показывает `SnackBar` и очищает поле через [clearError].
  final String? error;

  /// Нейтральное информационное сообщение.
  ///
  /// В отличие от [error] — не ошибка, а подсказка: «Файл уже прикреплён».
  /// UI показывает нейтральный `SnackBar` и очищает через
  /// [clearInfoMessage].
  final String? infoMessage;

  const AttachmentDraftState({
    this.attachments = const [],
    this.isLoading = false,
    this.error,
    this.infoMessage,
  });

  /// Начальное (пустое) состояние.
  factory AttachmentDraftState.initial() {
    return const AttachmentDraftState();
  }

  AttachmentDraftState copyWith({
    List<Attachment>? attachments,
    bool? isLoading,
    Object? error = copyWithUnset,
    Object? infoMessage = copyWithUnset,
  }) {
    return AttachmentDraftState(
      attachments: attachments ?? this.attachments,
      isLoading: isLoading ?? this.isLoading,
      error: isCopyWithUnset(error) ? this.error : error as String?,
      infoMessage: isCopyWithUnset(infoMessage)
          ? this.infoMessage
          : infoMessage as String?,
    );
  }

  /// Есть ли вложения-черновики.
  bool get hasAttachments => attachments.isNotEmpty;

  /// Есть ли ошибка для показа.
  bool get hasError => error != null && error!.isNotEmpty;

  /// Есть ли информационное сообщение для показа.
  bool get hasInfoMessage => infoMessage != null && infoMessage!.isNotEmpty;

  /// Все ли вложения **готовы к отправке**?
  ///
  /// `true`, если:
  /// - вложений нет вообще;
  /// - все вложения в статусе [AttachmentStatus.done].
  ///
  /// Используется `MessageInput`, чтобы решить, доступна ли кнопка
  /// «отправить». Если хоть одно вложение в `pending`/`uploading`/
  /// `processing`/`failed` — отправка запрещена.
  bool get allAttachmentsReady =>
      attachments.every((a) => a.status == AttachmentStatus.done);
}

// ============================================================
// 2. NOTIFIER
// ============================================================

/// Notifier для управления **черновиком** вложений.
///
/// **Ответственность:**
/// - валидация файла (размер, MIME, количество, дубликат);
/// - создание чата `document_chat`, если его ещё нет (см. ниже);
/// - загрузка файла на сервер через [UploadAttachmentUseCase];
/// - замена «pending»-версии на «done» (или «failed» при ошибке);
/// - удаление вложения до отправки;
/// - очистка списка после успешной отправки (вызывает `ChatNotifier`).
///
/// **Что НЕ делает:**
/// - **не отправляет** сообщения — это `ChatNotifier`;
/// - **не знает** про `messages` — только про сессию (agentId, sessionId);
/// - **не показывает** SnackBar — это работа UI.
///
/// **Про создание чата `document_chat`.** Логика «если сессии нет — создать
/// чат `document_chat`» переехала сюда из `ChatNotifier` **как есть**.
/// Она нужна, потому что пользователь может прикрепить файл **до** того,
/// как напишет первое сообщение: файл должен куда-то привязаться.
///
/// **Хардкод `'document_chat'`** здесь сохранён сознательно: реестр
/// агентов с флагами `canUploadFiles` — отдельная задача (этап C).
/// Сейчас — 1-в-1 поведение как было.
class AttachmentDraftNotifier extends StateNotifier<AttachmentDraftState> {
  /// Ссылка на Riverpod — для чтения `sessionProvider`, `chatRepositoryProvider`
  /// и обновления `sessionProvider` после создания чата.
  final Ref _ref;

  final ChatRepository _repository;
  final UploadAttachmentUseCase _uploadAttachmentUseCase;

  AttachmentDraftNotifier({
    required Ref ref,
    required ChatRepository repository,
    required UploadAttachmentUseCase uploadAttachmentUseCase,
  }) : _ref = ref,
       _repository = repository,
       _uploadAttachmentUseCase = uploadAttachmentUseCase,
       super(AttachmentDraftState.initial());

  // ============================================================
  // 2.1. ПРИКРЕПЛЕНИЕ ФАЙЛА
  // ============================================================

  /// Прикрепить файл: провалидировать, загрузить на сервер,
  /// добавить в черновик.
  ///
  /// **Полный флоу:**
  /// 1. Защита от race: если уже идёт загрузка — выходим.
  /// 2. Проверка, что мы в правильном чате (`document_chat` или новый).
  /// 3. Валидация: количество, размер, MIME, дубликат.
  /// 4. Создание `Attachment(status: pending)` и добавление в state —
  ///    чтобы UI сразу показал превью.
  /// 5. Создание чата `document_chat`, если сессии ещё нет.
  /// 6. Загрузка файла через [UploadAttachmentUseCase].
  /// 7. Замена `pending`-версии на `done` (или `failed` при ошибке).
  ///
  /// **Бросает** только в исключительных случаях — во всех «ожидаемых»
  /// ошибках (валидация, загрузка) ставит `state.error` и выходит.
  Future<void> addAttachment(File file) async {
    if (state.isLoading) {
      AppLogger.warning(
        'Прикрепление уже в процессе — пропускаем повторный вызов',
      );
      return;
    }

    // В чужом чате файлы сейчас не поддерживаются.
    final sessionState = _ref.read(sessionProvider);
    if (sessionState.agentId != null &&
        sessionState.agentId != 'document_chat') {
      AppLogger.warning(
        'Прикрепление файла в чате агента ${sessionState.agentId} '
        'не поддерживается',
      );
      return;
    }

    _setLoading(true);

    String? localId;

    try {
      // 1. Валидация количества.
      final currentCount = state.attachments.length;
      if (currentCount >= AppConfig.documentChatMaxAttachedFiles) {
        throw FileException.tooManyFiles(
          actual: currentCount + 1,
          max: AppConfig.documentChatMaxAttachedFiles,
        );
      }

      // 2. Имя, размер, MIME.
      final fileName = file.uri.pathSegments.last;
      final sizeBytes = await file.length();

      if (sizeBytes > AppConfig.documentChatMaxFileSizeBytes) {
        throw FileException.tooLarge(
          sizeBytes: sizeBytes,
          maxBytes: AppConfig.documentChatMaxFileSizeBytes,
        );
      }

      final mimeType = attachmentMimeTypeFromFilename(fileName);
      if (!AppConfig.documentChatAllowedMimeTypes.contains(mimeType)) {
        throw FileException.unsupportedFormat(mimeType: mimeType);
      }

      // 3. Проверка дубликата.
      final isDuplicate = state.attachments.any(
        (a) => a.fileName == fileName && a.sizeBytes == sizeBytes,
      );
      if (isDuplicate) {
        _setInfoMessage('Файл уже прикреплён');
        return;
      }

      // 4. Создаём локальный Attachment и сразу показываем в UI.
      localId = DateTime.now().millisecondsSinceEpoch.toString();
      final pending = Attachment.fromLocalFile(
        localId: localId,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        localPath: file.path,
      );
      _addAttachment(pending);

      // 5. Обеспечиваем чат у document_chat.
      var conversationId = sessionState.sessionId;
      if (conversationId == null) {
        AppLogger.info('Создаём чат document_chat для работы с файлом');
        final session = await _repository.createConversation(
          agentId: 'document_chat',
          title: fileName,
        );
        conversationId = session.id;

        // Обновляем SSOT — sessionProvider.
        //
        // `agentDisplayName` — хардкод «Документы». Почему не через
        // `agentsByIdProvider`: это внутренний вызов, `document_chat`
        // известная константа. Достаточно литерала. Позже, когда
        // появится реестр агентов с флагами — перепишем на lookup.
        _ref
            .read(sessionProvider.notifier)
            .setSession(
              'document_chat',
              conversationId,
              agentDisplayName: 'Документы',
            );
      }

      // 6. Загружаем файл.
      AppLogger.info('Загрузка вложения: $fileName');
      final uploaded = await _uploadAttachmentUseCase.execute(
        file: file,
        localId: localId,
        localPath: file.path,
        conversationId: conversationId,
      );

      // 7. Заменяем pending-версию на done-версию.
      _replaceAttachment(localId, uploaded);
      AppLogger.info('Вложение загружено: ${uploaded.remoteId}');
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handleFileUpload(
        e,
        stackTrace,
        'Ошибка прикрепления файла',
        {'fileName': file.uri.pathSegments.last, 'localId': localId},
      );

      if (localId != null) {
        final failed = state.attachments
            .firstWhere(
              (a) => a.localId == localId,
              orElse: () =>
                  throw StateError('pending-вложение исчезло из состояния'),
            )
            .copyWith(
              status: AttachmentStatus.failed,
              errorMessage: appException.userMessage,
            );
        _replaceAttachment(localId, failed);
      }

      _setError(appException.userMessage);
    } finally {
      _setLoading(false);
    }
  }

  /// Удалить вложение из черновика по `localId`.
  ///
  /// Вызывается, когда пользователь нажимает крестик на превью.
  /// **Не** ходит на сервер — файл уже загружен, но не отправлен,
  /// сервер сам подчистит «осиротевший» объект.
  void removeAttachment(String localId) {
    AppLogger.info('Удаление вложения из черновика: $localId');
    _removeAttachment(localId);
  }

  // ============================================================
  // 2.2. ОЧИСТКА
  // ============================================================

  /// Очистить черновик — все вложения, ошибки и подсказки.
  ///
  /// Вызывается:
  /// - **`ChatNotifier`** — после успешной отправки сообщения;
  ///   вложения «переехали» в историю (`Message.attachments`);
  /// - **`ChatNotifier`** — при создании нового чата / очистке чата;
  /// - **UI** — если понадобится сбросить (например, кнопка «отменить»).
  void clear() {
    if (state.attachments.isEmpty &&
        state.error == null &&
        state.infoMessage == null) {
      return;
    }
    AppLogger.debug('Очистка черновика вложений');
    state = AttachmentDraftState.initial();
  }

  /// Очистить ошибку (после показа `SnackBar`).
  void clearError() {
    _setError(null);
  }

  /// Очистить информационное сообщение (после показа `SnackBar`).
  void clearInfoMessage() {
    _setInfoMessage(null);
  }

  // ============================================================
  // 2.3. ПРИВАТНЫЕ ХЕЛПЕРЫ СОСТОЯНИЯ
  // ============================================================

  void _setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void _setError(String? error) {
    if (error != null) {
      AppLogger.debug('🔴 AttachmentDraftNotifier._setError("$error")');
    }
    state = state.copyWith(error: error);
  }

  void _setInfoMessage(String? message) {
    state = state.copyWith(infoMessage: message);
  }

  /// Добавить вложение в конец списка.
  void _addAttachment(Attachment attachment) {
    state = state.copyWith(attachments: [...state.attachments, attachment]);
  }

  /// Заменить вложение по `localId` на обновлённую версию.
  void _replaceAttachment(String localId, Attachment updated) {
    final newList = state.attachments
        .map((a) => a.localId == localId ? updated : a)
        .toList();
    state = state.copyWith(attachments: newList);
  }

  /// Удалить вложение по `localId`.
  void _removeAttachment(String localId) {
    final current = state.attachments;
    final newList = current.where((a) => a.localId != localId).toList();

    if (newList.length == current.length) return;

    state = state.copyWith(attachments: newList);
  }
}

// ============================================================
// 3. ПРОВАЙДЕР
// ============================================================

/// Провайдер для черновика вложений.
///
/// Читается:
/// - `MessageInput` — для отображения превью и кнопки «прикрепить»;
/// - `ChatNotifier` — для взятия вложений при отправке сообщения;
/// - `ChatScreen` — для показа ошибок/подсказок через SnackBar.
/// Провайдер для `UploadAttachmentUseCase`.
///
/// **Живёт здесь, а не в `chat_provider.dart`.** Причина: этот UseCase
/// относится к **вложениям**, а не к чату. После разделения состояния
/// (ChatState vs AttachmentDraftState) логика вложений переехала сюда —
/// и провайдеры тоже.
///
/// **Пока** (шаг B1) в `chat_provider.dart` **всё ещё** объявлен
/// такой же провайдер. Это **временное** состояние: между B1 и B2
/// оба файла имеют свои `uploadAttachmentUseCaseProvider`. Конфликта
/// нет, потому что никто не импортирует оба файла одновременно.
/// В шаге B2 из `chat_provider.dart` провайдер будет удалён.
final uploadAttachmentUseCaseProvider = Provider<UploadAttachmentUseCase>((
  ref,
) {
  final repository = ref.read(attachmentRepositoryProvider);
  return UploadAttachmentUseCase(repository: repository);
});

/// Провайдер для черновика вложений.
///
/// Читается:
/// - `MessageInput` — для отображения превью и кнопки «прикрепить»;
/// - `ChatNotifier` — для взятия вложений при отправке сообщения;
/// - `ChatScreen` — для показа ошибок/подсказок через SnackBar.
final attachmentDraftProvider =
    StateNotifierProvider<AttachmentDraftNotifier, AttachmentDraftState>((ref) {
      final repository = ref.read(chatRepositoryProvider);
      final uploadAttachmentUseCase = ref.read(uploadAttachmentUseCaseProvider);

      return AttachmentDraftNotifier(
        ref: ref,
        repository: repository,
        uploadAttachmentUseCase: uploadAttachmentUseCase,
      );
    });
