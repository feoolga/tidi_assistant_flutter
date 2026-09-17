// lib/providers/chat_provider.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../core/logger/app_logger.dart';
import '../core/errors/error_handler.dart';
import '../core/errors/file_exceptions.dart';
import '../domain/models/message.dart';
import '../domain/models/attachment.dart';
import '../domain/services/chat_stream_event.dart';
import '../domain/services/chat_stream_handler.dart';
import '../domain/usecases/send_message_usecase.dart';
import '../domain/usecases/upload_attachment_usecase.dart';
import 'session_provider.dart';
import 'agent_provider.dart';
import '../data/repositories/chat_repository.dart';

// ============================================================
// 1. СОСТОЯНИЕ ЧАТА
// ============================================================

/// Состояние чата - только сообщения и статус загрузки.
class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final bool isStreaming;
  final String? currentAgentId;
  final String? currentConversationId;

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
    this.currentAgentId,
    this.currentConversationId,
    this.pendingAttachments = const [],
    this.infoMessage,
    this.isAddingAttachment = false,
  });

  factory ChatState.initial() {
    return const ChatState();
  }

  // Специальный объект-маркер
  // Он означает: "это поле не было передано в copyWith"
  static const _unset = Object();

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? error,
    bool? isStreaming,
    Object? currentAgentId = _unset,
    Object? currentConversationId = _unset,
    List<Attachment>? pendingAttachments,
    Object? infoMessage = _unset,
    bool? isAddingAttachment,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isStreaming: isStreaming ?? this.isStreaming,
      currentAgentId: identical(currentAgentId, _unset)
          ? this.currentAgentId
          : currentAgentId as String?,
      currentConversationId: identical(currentConversationId, _unset)
          ? this.currentConversationId
          : currentConversationId as String?,
      pendingAttachments: pendingAttachments ?? this.pendingAttachments,
      infoMessage: identical(infoMessage, _unset)
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
  /// (например, `sessionProvider`) из методов Notifier'а.
  final Ref _ref;

  final ChatRepository _repository;
  final SendMessageUseCase _sendMessageUseCase;
  final UploadAttachmentUseCase _uploadAttachmentUseCase;
  final ChatStreamHandler _streamHandler;
  final void Function(String agentId, String sessionId)? onSessionChanged;

  ChatNotifier({
    required Ref ref,
    required ChatRepository repository,
    required SendMessageUseCase sendMessageUseCase,
    required UploadAttachmentUseCase uploadAttachmentUseCase,
    required ChatStreamHandler streamHandler,
    this.onSessionChanged,
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

  void _setCurrentAgent(String? agentId) {
    state = state.copyWith(currentAgentId: agentId);
  }

  void _setCurrentConversationId(String? conversationId) {
    state = state.copyWith(currentConversationId: conversationId);
  }

  void _setStreaming(bool isStreaming) {
    state = state.copyWith(isStreaming: isStreaming);
  }

  void _setError(String? error) {
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

  /// Обновляет текст последнего сообщения AI
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

  /// Завершает ответ — обновляет метаданные последнего сообщения AI
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

  /// Удаляет пустое AI-сообщение (если есть) — используется при ошибке
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
  /// 2. Создание `Attachment(status: pending)` и добавление в `pendingAttachments`
  ///    — чтобы UI сразу показал превью со спиннером.
  /// 3. При необходимости — создание чата у `document_chat` (файлы работают
  ///    только через этого агента; в чужом чате кнопка «прикрепить» заблокирована).
  /// 4. Загрузка файла через [UploadAttachmentUseCase].
  /// 5. Замена `pending`-вложения на `done` (или `failed` при ошибке).
  ///
  /// Защищена от race: если предыдущее прикрепление ещё в процессе —
  /// выходим без изменений. Флаг сбрасывается в `finally` в любом случае.
  Future<void> addAttachment(File file) async {
    // Защита от race condition: пока одна загрузка идёт, вторую не начинаем.
    // Проверяем через `ChatState.isAddingAttachment` — один источник правды.
    if (state.isAddingAttachment) {
      AppLogger.warning(
        'Прикрепление уже в процессе — пропускаем повторный вызов',
      );
      return;
    }

    // В чужом чате файлы сейчас не поддерживаются (решение техдира — в работе).
    // Кнопка «прикрепить» в UI тоже блокируется, здесь — вторая линия защиты.
    final sessionState = _ref.read(sessionProvider);
    if (sessionState.agentId != null &&
        sessionState.agentId != 'document_chat') {
      AppLogger.warning(
        'Прикрепление файла в чате агента ${sessionState.agentId} не поддерживается',
      );
      return;
    }

    _setAddingAttachment(true);

    // Отдельная переменная — чтобы в catch знать, какой localId поставить failed.
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

      // 3. Проверка дубликата: тот же fileName + sizeBytes уже прикреплён
      //    (включая записи со status: failed — их надо удалить вручную).
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

        // Синхронизируем sessionProvider (через callback — как при отправке).
        onSessionChanged?.call('document_chat', conversationId);

        // Обновляем локальное состояние — UI увидит смену агента в AppBar.
        _setCurrentAgent('document_chat');
        _setCurrentConversationId(conversationId);
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
      // Преобразуем в AppException.
      // FileException'ы (валидация, ошибки загрузки) уже AppException —
      // handleFileUpload вернёт их как есть.
      final appException = ErrorHandler.handleFileUpload(e, stackTrace);
      AppLogger.logException(
        'Ошибка прикрепления файла',
        appException,
        stackTrace,
      );

      // Обновляем pending-версию до failed, если она уже была добавлена.
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

  // ============================================================
  // ОТПРАВКА СООБЩЕНИЯ
  // ============================================================

  Future<void> sendMessage({
    required String text,
    String? agentId,
    String? sessionId,
  }) async {
    AppLogger.info(
      'Отправка сообщения: "$text" (агент=$agentId, чат=$sessionId)',
    );

    _clearError();

    // 1. Добавляем сообщение пользователя
    _addMessage(Message.fromUser(text: text));
    _setLoading(true);
    _setStreaming(true);

    // 2. Создаём ПУСТОЕ сообщение AI
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final aiMessage = Message(
      id: tempId,
      text: '',
      isFromUser: false,
      timestamp: DateTime.now(),
      agentId: agentId,
      sessionId: sessionId,
    );
    _addMessage(aiMessage);

    try {
      // 3. Отправляем запрос и получаем поток DTO
      final params = SendMessageParams(
        text: text,
        agentId: agentId,
        sessionId: sessionId,
      );

      // 4. Оборачиваем в хендлер — теперь работаем с событиями
      final source = _sendMessageUseCase.execute(params);
      final events = _streamHandler.handle(source);

      // 5. Обрабатываем события
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

            // Обновляем метаданные последнего сообщения
            _completeMessage(
              agentId: agentId,
              sessionId: conversationId ?? sessionId,
              messageId: messageId,
            );

            // Обновляем состояние сессии (AppBar)
            _setCurrentAgent(agentId);
            if (conversationId != null) {
              _setCurrentConversationId(conversationId);
            }

            AppLogger.info('✅ Ответ получен полностью');
            AppLogger.debug('   📌 Агент: $agentId');
            AppLogger.debug('   📌 Чат: $conversationId');
            AppLogger.debug('   📌 ID сообщения: $messageId');
            AppLogger.debug('   📌 Длина текста: ${fullText.length} символов');

            // Уведомляем о смене сессии, если она изменилась
            if (conversationId != null &&
                (agentId != sessionId || conversationId != sessionId)) {
              onSessionChanged?.call(agentId ?? '', conversationId);
            }
            break;

          case ChatStreamFailed(:final error):
            AppLogger.logException('Ошибка в стриме', error);
            _removeEmptyAiMessageIfAny();
            _setError(error.userMessage);
            break;
        }
      }
    } catch (e) {
      // На всякий случай — если что-то упадёт вне хендлера
      final appException = ErrorHandler.handle(e);
      AppLogger.logException('Ошибка в sendMessage', appException);
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

      onSessionChanged?.call(agentId, chatId);

      AppLogger.info('Загружено сообщений: ${messages.length}');
    } catch (e) {
      final appException = ErrorHandler.handle(e);
      AppLogger.logException('Ошибка в loadChat', appException);
      _setError(appException.userMessage);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createNewChat() async {
    AppLogger.info('Создание нового чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    _setCurrentAgent(null);
    _setCurrentConversationId(null);

    AppLogger.debug('Новый чат создан');
  }

  void clearChat() {
    AppLogger.info('Очистка чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    _setCurrentConversationId(null);
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

/// Провайдер для ChatStreamHandler
final chatStreamHandlerProvider = Provider<ChatStreamHandler>((ref) {
  return ChatStreamHandler();
});

/// Провайдер для SendMessageUseCase
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return SendMessageUseCase(repository: repository);
});

/// Провайдер для UploadAttachmentUseCase
///
/// Используется в ChatNotifier.addAttachment — грузит файл на сервер
/// и возвращает доменную модель Attachment.
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
    onSessionChanged: (agentId, sessionId) {
      ref.read(sessionProvider.notifier).setSession(agentId, sessionId);
    },
  );
});
