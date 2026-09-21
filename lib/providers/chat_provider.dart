// lib/providers/chat_provider.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors/error_handler.dart';
import '../core/errors/file_exceptions.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';
import '../data/repositories/chat_repository.dart';
import '../domain/models/attachment.dart';
import '../domain/models/message.dart';
import '../domain/services/chat_stream_event.dart';
import '../domain/services/chat_stream_handler.dart';
import '../domain/usecases/send_message_usecase.dart';
import '../domain/usecases/upload_attachment_usecase.dart';
import 'agent_provider.dart';
import 'session_provider.dart';

// ============================================================
// 1. СОСТОЯНИЕ ЧАТА
// ============================================================

/// Состояние чата — сообщения, статус загрузки, стриминг, вложения.
///
/// **ВАЖНО:** здесь **нет** `agentId` / `sessionId`. Сессия хранится
/// **только** в `sessionProvider` — единый источник правды (SSOT).
/// См. `lib/providers/session_provider.dart`.
///
/// Раньше эти поля дублировались в `ChatState`, что приводило
/// к рассинхронизации: `loadChat` обновлял `sessionProvider`,
/// но не `ChatState` — AppBar показывал старое имя агента.
class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final bool isStreaming;

  /// Вложения, уже загруженные на сервер, но ещё не отправленные
  /// с сообщением. Появляются, когда пользователь нажимает «прикрепить»
  /// и файл успешно загружается. Очищаются после отправки сообщения
  /// (или при создании нового чата / очистке).
  final List<Attachment> pendingAttachments;

  /// Нейтральное информационное сообщение для пользователя.
  ///
  /// В отличие от [error] — не ошибка, а подсказка или уведомление:
  /// «Файл уже прикреплён», «Чат создан». UI показывает зелёный/нейтральный
  /// SnackBar и очищает поле через `clearInfoMessage()`.
  final String? infoMessage;

  /// Идёт ли сейчас загрузка прикреплённого файла на сервер.
  ///
  /// Пока `true` — UI блокирует кнопку «прикрепить» (иначе пользователь
  /// может запустить вторую загрузку параллельно, что приведёт к гонке
  /// при создании чата и записи `pendingAttachments`).
  final bool isAddingAttachment;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.isStreaming = false,
    this.pendingAttachments = const [],
    this.infoMessage,
    this.isAddingAttachment = false,
  });

  factory ChatState.initial() {
    return const ChatState();
  }

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    Object? error = copyWithUnset,
    bool? isStreaming,
    List<Attachment>? pendingAttachments,
    Object? infoMessage = copyWithUnset,
    bool? isAddingAttachment,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: isCopyWithUnset(error) ? this.error : error as String?,
      isStreaming: isStreaming ?? this.isStreaming,
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      infoMessage: isCopyWithUnset(infoMessage)
          ? this.infoMessage
          : infoMessage as String?,
      isAddingAttachment: isAddingAttachment ?? this.isAddingAttachment,
    );
  }

  bool get hasMessages => messages.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;

  /// Есть ли прикреплённые, но ещё не отправленные вложения.
  bool get hasPendingAttachments => pendingAttachments.isNotEmpty;

  /// Есть ли информационное сообщение для показа пользователю.
  bool get hasInfoMessage => infoMessage != null && infoMessage!.isNotEmpty;
}

// ============================================================
// 2. NOTIFIER
// ============================================================

class ChatNotifier extends StateNotifier<ChatState> {
  /// Ссылка на Riverpod — нужна, чтобы читать другие провайдеры
  /// (в частности, `sessionProvider` — SSOT сессии).
  final Ref _ref;

  final ChatRepository _repository;
  final SendMessageUseCase _sendMessageUseCase;
  final UploadAttachmentUseCase _uploadAttachmentUseCase;
  final ChatStreamHandler _streamHandler;

  ChatNotifier({
    required Ref ref,
    required ChatRepository repository,
    required SendMessageUseCase sendMessageUseCase,
    required UploadAttachmentUseCase uploadAttachmentUseCase,
    required ChatStreamHandler streamHandler,
  }) : _ref = ref,
       _repository = repository,
       _sendMessageUseCase = sendMessageUseCase,
       _uploadAttachmentUseCase = uploadAttachmentUseCase,
       _streamHandler = streamHandler,
       super(ChatState.initial()) {
    _addWelcomeMessage();
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ СОСТОЯНИЯ
  // ============================================================

  void _addWelcomeMessage() {
    if (state.messages.isEmpty) {
      final welcomeMessage = Message(
        id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Здравствуйте! Я AI-ассистент. Задайте мне вопрос.',
        isFromUser: false,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(messages: [welcomeMessage]);
    }
  }

  void _setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void _setAddingAttachment(bool value) {
    state = state.copyWith(isAddingAttachment: value);
  }

  void _setStreaming(bool isStreaming) {
    state = state.copyWith(isStreaming: isStreaming);
  }

  void _setError(String? error) {
    if (error != null) {
      AppLogger.debug('🔴 ChatNotifier._setError("$error")');
    }
    state = state.copyWith(error: error);
  }

  void _clearError() {
    state = state.copyWith(error: null);
  }

  void _setInfoMessage(String? message) {
    state = state.copyWith(infoMessage: message);
  }

  void _addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  /// Добавить вложение в конец списка `pendingAttachments`.
  void _addPendingAttachment(Attachment attachment) {
    state = state.copyWith(
      pendingAttachments: [...state.pendingAttachments, attachment],
    );
  }

  /// Заменить вложение по `localId` на обновлённую версию.
  ///
  /// Используется после завершения загрузки: локальная запись
  /// `status: pending` заменяется на `status: done` (или `failed`).
  void _replacePendingAttachment(String localId, Attachment updated) {
    final newList = state.pendingAttachments
        .map((a) => a.localId == localId ? updated : a)
        .toList();
    state = state.copyWith(pendingAttachments: newList);
  }

  /// Удалить вложение из `pendingAttachments` по `localId`.
  void _removePendingAttachment(String localId) {
    final current = state.pendingAttachments;
    final newList = current.where((a) => a.localId != localId).toList();

    if (newList.length == current.length) return;

    state = state.copyWith(pendingAttachments: newList);
  }

  /// Обновляет текст последнего сообщения AI.
  void _updateMessageText(String text) {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastIndex = currentMessages.length - 1;
    final lastMessage = currentMessages[lastIndex];

    if (!lastMessage.isFromUser) {
      final updatedMessage = lastMessage.copyWith(text: text);
      final newMessages = List<Message>.from(currentMessages);
      newMessages[lastIndex] = updatedMessage;
      state = state.copyWith(messages: newMessages);
    }
  }

  /// Завершает ответ — обновляет метаданные последнего сообщения AI.
  void _completeMessage({
    required String? agentId,
    required String? sessionId,
    required String? messageId,
  }) {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastIndex = currentMessages.length - 1;
    final lastMessage = currentMessages[lastIndex];

    if (!lastMessage.isFromUser) {
      final updatedMessage = lastMessage.copyWith(
        id: messageId ?? lastMessage.id,
        agentId: agentId ?? lastMessage.agentId,
        sessionId: sessionId ?? lastMessage.sessionId,
      );

      final newMessages = List<Message>.from(currentMessages);
      newMessages[lastIndex] = updatedMessage;
      state = state.copyWith(messages: newMessages);
    }
  }

  /// Удаляет пустое AI-сообщение (если есть) — используется при ошибке.
  void _removeEmptyAiMessageIfAny() {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastMessage = currentMessages.last;
    if (!lastMessage.isFromUser && lastMessage.text.isEmpty) {
      final newMessages = List<Message>.from(currentMessages)..removeLast();
      state = state.copyWith(messages: newMessages);
    }
  }

  // ============================================================
  // ПРИКРЕПЛЕНИЕ ФАЙЛОВ
  // ============================================================

  /// Прикрепить файл: загрузить на сервер и добавить в `pendingAttachments`.
  ///
  /// Полный флоу:
  /// 1. Валидация: количество, размер, MIME, дубликат.
  /// 2. Создание `Attachment(status: pending)` и добавление в `pendingAttachments`.
  /// 3. При необходимости — создание чата у `document_chat`.
  /// 4. Загрузка файла через [UploadAttachmentUseCase].
  /// 5. Замена `pending`-вложения на `done` (или `failed` при ошибке).
  ///
  /// Защищена от race: если предыдущее прикрепление ещё в процессе —
  /// выходим без изменений. Флаг сбрасывается в `finally`.
  Future<void> addAttachment(File file) async {
    if (state.isAddingAttachment) {
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

    _setAddingAttachment(true);

    String? localId;

    try {
      // 1. Валидация количества.
      final currentCount = state.pendingAttachments.length;
      if (currentCount >= AppConfig.maxAttachedFiles) {
        throw FileException.tooManyFiles(
          actual: currentCount + 1,
          max: AppConfig.maxAttachedFiles,
        );
      }

      // 2. Имя, размер, MIME.
      final fileName = file.uri.pathSegments.last;
      final sizeBytes = await file.length();

      if (sizeBytes > AppConfig.maxFileSizeBytes) {
        throw FileException.tooLarge(
          sizeBytes: sizeBytes,
          maxBytes: AppConfig.maxFileSizeBytes,
        );
      }

      final mimeType = attachmentMimeTypeFromFilename(fileName);
      if (!AppConfig.allowedMimeTypes.contains(mimeType)) {
        throw FileException.unsupportedFormat(mimeType: mimeType);
      }

      // 3. Проверка дубликата.
      final isDuplicate = state.pendingAttachments.any(
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
      _addPendingAttachment(pending);

      // 5. Обеспечиваем чат у document_chat.
      var conversationId = sessionState.sessionId;
      if (conversationId == null) {
        AppLogger.info('Создаём чат document_chat для работы с файлом');
        final session = await _repository.createConversation(
          agentId: 'document_chat',
          title: fileName,
        );
        conversationId = session.id;

        // Обновляем SSOT — sessionProvider. UI читает agentId
        // напрямую из sessionProvider, поэтому сразу увидит смену агента.
        _ref
            .read(sessionProvider.notifier)
            .setSession('document_chat', conversationId);
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
      _replacePendingAttachment(localId, uploaded);
      AppLogger.info('Вложение загружено: ${uploaded.remoteId}');
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handleFileUpload(
        e,
        stackTrace,
        'Ошибка прикрепления файла',
        {'fileName': file.uri.pathSegments.last, 'localId': localId},
      );

      if (localId != null) {
        final failed = state.pendingAttachments
            .firstWhere(
              (a) => a.localId == localId,
              orElse: () =>
                  throw StateError('pending-вложение исчезло из состояния'),
            )
            .copyWith(
              status: AttachmentStatus.failed,
              errorMessage: appException.userMessage,
            );
        _replacePendingAttachment(localId, failed);
      }

      _setError(appException.userMessage);
    } finally {
      _setAddingAttachment(false);
    }
  }

  /// Удалить прикреплённый файл из `pendingAttachments` по `localId`.
  void removeAttachment(String localId) {
    AppLogger.info('Удаление вложения: $localId');
    _removePendingAttachment(localId);
  }

  /// Полностью очистить список прикреплённых файлов.
  void _clearPendingAttachments() {
    if (state.pendingAttachments.isEmpty) return;
    state = state.copyWith(pendingAttachments: const []);
  }

  // ============================================================
  // ОТПРАВКА СООБЩЕНИЯ
  // ============================================================

  /// Отправить сообщение в текущем чате.
  ///
  /// Логика:
  /// - Если сессия (agent_id + conversation_id) уже известна — используем её.
  /// - Если нет — определяем агента через `POST /route`, создаём чат,
  ///   сохраняем пару в `sessionProvider` и только потом отправляем.
  ///
  /// Вложения из `pendingAttachments` передаются в сообщение и в запрос;
  /// после успешной отправки список очищается.
  Future<void> sendMessage({required String text}) async {
    if (state.isLoading) {
      AppLogger.warning('Отправка уже в процессе — пропускаем повторный вызов');
      return;
    }

    final attachments = List<Attachment>.from(state.pendingAttachments);

    AppLogger.info(
      'Отправка сообщения: "$text" '
      '(вложений: ${attachments.length})',
    );

    _clearError();

    // 1. Сообщение пользователя — сразу с вложениями, чтобы UI показал превью.
    _addMessage(Message.fromUser(text: text, attachments: attachments));
    _setLoading(true);
    _setStreaming(true);

    // 2. Пустое AI-сообщение — заполнится по мере стрима.
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final aiMessage = Message(
      id: tempId,
      text: '',
      isFromUser: false,
      timestamp: DateTime.now(),
    );
    _addMessage(aiMessage);

    try {
      // 3. Определяем сессию: либо уже есть, либо создаём на лету.
      var currentAgentId = _ref.read(sessionProvider).agentId;
      var currentSessionId = _ref.read(sessionProvider).sessionId;

      if (currentSessionId == null) {
        if (attachments.isNotEmpty) {
          AppLogger.warning(
            'Есть вложения, но нет сессии — пропускаем отправку. '
            'Ожидалось, что чат создан в addAttachment.',
          );
          _removeEmptyAiMessageIfAny();
          return;
        }

        // Обычный новый чат: определяем агента и создаём чат.
        AppLogger.info('Новый чат — определяем агента через /route');
        currentAgentId = await _repository.getRoute(text);

        AppLogger.info('Создаём чат у агента $currentAgentId');
        final session = await _repository.createConversation(
          agentId: currentAgentId,
          title: text,
        );
        currentSessionId = session.id;

        // Обновляем SSOT — sessionProvider.
        // UI читает agentId/sessionId напрямую оттуда, поэтому
        // agentId и sessionId здесь гарантированно non-null:
        // getRoute возвращает String, ChatSession.id — String.
        _ref
            .read(sessionProvider.notifier)
            .setSession(currentAgentId, currentSessionId);

        AppLogger.info(
          'Чат создан: agent=$currentAgentId, session=$currentSessionId',
        );
      }

      // 4. Отправляем сообщение.
      final params = SendMessageParams(
        text: text,
        agentId: currentAgentId,
        sessionId: currentSessionId,
        attachments: attachments,
      );

      final source = _sendMessageUseCase.execute(params);
      final events = _streamHandler.handle(source);

      // 5. Обрабатываем события стрима.
      await for (final event in events) {
        switch (event) {
          case ChatStreamStarted():
            AppLogger.debug('🟢 Стрим начался');
            break;

          case ChatStreamDelta(:final fullText):
            _updateMessageText(fullText);
            break;

          case ChatStreamCompleted(
            :final fullText,
            :final messageId,
            :final agentId,
            :final conversationId,
          ):
            _updateMessageText(fullText);
            _setStreaming(false);

            _completeMessage(
              agentId: agentId,
              sessionId: conversationId ?? currentSessionId,
              messageId: messageId,
            );

            // Обновляем SSOT, только если сервер прислал **полную** пару.
            // Иначе оставляем как есть — sessionProvider уже правильный
            // (обновили при создании чата).
            if (agentId != null && conversationId != null) {
              _ref
                  .read(sessionProvider.notifier)
                  .setSession(agentId, conversationId);
            }

            AppLogger.info('✅ Ответ получен полностью');
            AppLogger.debug('   📌 Агент: $agentId');
            AppLogger.debug('   📌 Чат: $conversationId');
            AppLogger.debug('   📌 ID сообщения: $messageId');
            AppLogger.debug('   📌 Длина текста: ${fullText.length} символов');

            // Отправка прошла — вложения «переехали» в историю сообщений.
            _clearPendingAttachments();
            break;

          case ChatStreamFailed(:final error):
            AppLogger.logException('Ошибка в стриме', error);
            _removeEmptyAiMessageIfAny();
            _setError(error.userMessage);
            // pendingAttachments НЕ очищаем — пользователь может
            // попробовать снова.
            break;
        }
      }
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка в sendMessage',
        {'text_length': text.length, 'attachments_count': attachments.length},
      );
      _removeEmptyAiMessageIfAny();
      _setError(appException.userMessage);
    } finally {
      AppLogger.debug('🏁 Завершение обработки сообщения');
      _setLoading(false);
      _setStreaming(false);
    }
  }

  // ============================================================
  // ЗАГРУЗКА И УПРАВЛЕНИЕ ЧАТОМ
  // ============================================================

  /// Загрузить чат из истории.
  ///
  /// Загружает сообщения чата и обновляет SSOT-сессию.
  ///
  /// Обновление `sessionProvider` — критично: без него AppBar
  /// показывал бы старое имя агента при открытии чата из истории.
  /// Раньше сессия дублировалась в `ChatState` и могла рассинхронизироваться;
  /// теперь такого класса проблем нет — сессия живёт в одном месте.
  Future<void> loadChat(String agentId, String chatId) async {
    AppLogger.info('Загрузка чата: агент=$agentId, чат=$chatId');

    _setLoading(true);
    _clearError();

    try {
      final messages = await _repository.getMessages(
        agentId: agentId,
        conversationId: chatId,
      );
      _setMessages(messages);

      // Обновляем SSOT — AppBar сразу покажет нужного агента.
      _ref.read(sessionProvider.notifier).setSession(agentId, chatId);

      AppLogger.info('Загружено сообщений: ${messages.length}');
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка в loadChat',
        {'agentId': agentId, 'chatId': chatId},
      );
      _setError(appException.userMessage);
    } finally {
      _setLoading(false);
    }
  }

  /// Создать новый чат (визуально очистить поле).
  ///
  /// Сессия сбрасывается в `sessionProvider` — значит, `AppBar`
  /// сразу покажет «AI Ассистент» (агент не выбран).
  Future<void> createNewChat() async {
    AppLogger.info('Создание нового чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    _clearPendingAttachments();

    _ref.read(sessionProvider.notifier).clearSession();

    AppLogger.debug('Новый чат создан');
  }

  /// Очистить текущий чат.
  ///
  /// **Осознанное отличие от [createNewChat]:** `clearChat` НЕ сбрасывает
  /// сессию — пользователь остаётся в том же агенте и чате, но история
  /// сообщений на экране очищается. Если надо начать полностью новый чат —
  /// используйте [createNewChat].
  void clearChat() {
    AppLogger.info('Очистка чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    _clearPendingAttachments();
  }

  void clearError() {
    _clearError();
  }

  void clearInfoMessage() {
    _setInfoMessage(null);
  }
}

// ============================================================
// 3. ПРОВАЙДЕРЫ
// ============================================================

/// Провайдер для ChatStreamHandler.
final chatStreamHandlerProvider = Provider<ChatStreamHandler>((ref) {
  return ChatStreamHandler();
});

/// Провайдер для SendMessageUseCase.
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return SendMessageUseCase(repository: repository);
});

/// Провайдер для UploadAttachmentUseCase.
final uploadAttachmentUseCaseProvider = Provider<UploadAttachmentUseCase>((
  ref,
) {
  final repository = ref.read(attachmentRepositoryProvider);
  return UploadAttachmentUseCase(repository: repository);
});

/// Основной провайдер чата.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);
  final uploadAttachmentUseCase = ref.read(uploadAttachmentUseCaseProvider);
  final streamHandler = ref.read(chatStreamHandlerProvider);

  return ChatNotifier(
    ref: ref,
    repository: repository,
    sendMessageUseCase: sendMessageUseCase,
    uploadAttachmentUseCase: uploadAttachmentUseCase,
    streamHandler: streamHandler,
  );
});
