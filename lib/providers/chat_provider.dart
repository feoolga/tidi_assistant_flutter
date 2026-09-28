// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';
import '../domain/models/attachment.dart';
import '../data/repositories/chat_repository.dart';
import '../domain/models/message.dart';
import '../domain/services/chat_stream_event.dart';
import '../domain/services/chat_stream_handler.dart';
import '../domain/usecases/send_message_usecase.dart';
import 'agent_provider.dart';
import 'attachment_draft_provider.dart';
import 'session_provider.dart';

// ============================================================
// 1. СОСТОЯНИЕ ЧАТА
// ============================================================

/// Состояние чата — сообщения, статус загрузки, стриминг.
///
/// **ВАЖНО:** здесь **нет** ни `agentId` / `sessionId`, ни состояния
/// вложений. И то, и другое живёт отдельно:
/// - сессия — в `sessionProvider` (SSOT);
/// - черновик вложений — в `attachmentDraftProvider`.
///
/// Раньше `pendingAttachments` / `isAddingAttachment` / `infoMessage`
/// лежали здесь, что смешивало «состояние диалога» и «черновик ввода».
/// После разделения у каждого объекта — **свой** жизненный цикл:
/// - `ChatState.messages` — живёт долго, растёт, это **история**;
/// - `AttachmentDraftState.attachments` — живёт минуты, обнуляется.
class ChatState {
  /// История сообщений — то, что уже **отправлено**.
  ///
  /// Вложения, отправленные с сообщением, лежат в `Message.attachments`,
  /// не здесь. Здесь — только сам диалог.
  final List<Message> messages;

  /// Идёт ли отправка сообщения или загрузка истории.
  final bool isLoading;

  /// Ошибка **чата** — отправки, загрузки, стриминга.
  ///
  /// **НЕ** путать с `AttachmentDraftState.error` — там ошибки
  /// **прикрепления файла**.
  final String? error;

  /// Идёт ли сейчас стриминг ответа AI.
  final bool isStreaming;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.isStreaming = false,
  });

  factory ChatState.initial() {
    return const ChatState();
  }

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    Object? error = copyWithUnset,
    bool? isStreaming,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: isCopyWithUnset(error) ? this.error : error as String?,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  bool get hasMessages => messages.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;
}

// ============================================================
// 2. NOTIFIER
// ============================================================

/// Нотифаер **чата**.
///
/// **Ответственность:**
/// - хранить историю сообщений;
/// - отправлять сообщения через `SendMessageUseCase`;
/// - обрабатывать события стрима (Started / Delta / Completed / Failed);
/// - загружать чат из истории (`loadChat`);
/// - очищать/создавать новый чат.
///
/// **Что НЕ делает:**
/// - не управляет вложениями-черновиками (это `AttachmentDraftNotifier`);
/// - не знает про `document_chat`-специфику загрузки файлов;
/// - не показывает SnackBar (это работа UI).
///
/// **Про вложения.** Когда пользователь отправляет сообщение,
/// `ChatNotifier` **читает** текущий черновик из `attachmentDraftProvider`
/// и кладёт вложения в `Message.fromUser(attachments: ...)`. После
/// успешной отправки — **очищает** черновик (вызывает
/// `attachmentDraftProvider.notifier.clear()`).
class ChatNotifier extends StateNotifier<ChatState> {
  /// Ссылка на Riverpod — нужна, чтобы читать и писать в другие
  /// провайдеры: `sessionProvider` (SSOT сессии) и `attachmentDraftProvider`
  /// (черновик вложений).
  final Ref _ref;

  final ChatRepository _repository;
  final SendMessageUseCase _sendMessageUseCase;
  final ChatStreamHandler _streamHandler;

  ChatNotifier({
    required Ref ref,
    required ChatRepository repository,
    required SendMessageUseCase sendMessageUseCase,
    required ChatStreamHandler streamHandler,
  }) : _ref = ref,
       _repository = repository,
       _sendMessageUseCase = sendMessageUseCase,
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

  void _addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
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
  // ОТПРАВКА СООБЩЕНИЯ
  // ============================================================

  /// Отправить сообщение в текущем чате.
  ///
  /// Логика:
  /// - Если сессия (agent_id + conversation_id) уже известна — используем её.
  /// - Если нет — определяем агента через `POST /route`, создаём чат,
  ///   сохраняем пару в `sessionProvider` и только потом отправляем.
  ///
  /// **Вложения** берём из `attachmentDraftProvider` — это текущий
  /// черновик ввода. После успешной отправки — **очищаем** черновик:
  /// вложения «переехали» в `Message.attachments` пользовательского
  /// сообщения и остаются в истории чата.
  Future<void> sendMessage({required String text}) async {
    if (state.isLoading) {
      AppLogger.warning('Отправка уже в процессе — пропускаем повторный вызов');
      return;
    }

    // Берём текущий черновик вложений.
    // **Копия** списка — потому что дальше мы можем очистить черновик,
    // и оригинальный список не должен измениться.
    final attachments = List<Attachment>.from(
      _ref.read(attachmentDraftProvider).attachments,
    );

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
            // Черновик очищаем — там уже нечего хранить.
            _ref.read(attachmentDraftProvider.notifier).clear();
            break;

          case ChatStreamFailed(:final error):
            // Логирование **уже произошло** в `SendMessageUseCase`
            // (для `event: error`) или в `ErrorHandler.handle` внутри
            // `ChatStreamHandler` (для транспортных ошибок — но мы это
            // убрали, см. правку 2). Здесь — только UI-реакция.
            //
            // **Почему не логируем:** правило `ErrorHandler` —
            // «единая точка логирования». Здесь мы не обрабатываем
            // ошибку заново, а только показываем `userMessage`.
            _removeEmptyAiMessageIfAny();
            _setError(error.userMessage);
            // Черновик вложений НЕ очищаем — пользователь может
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
  ///
  /// Черновик вложений тоже очищается — при создании нового чата
  /// старые вложения не имеют смысла.
  Future<void> createNewChat() async {
    AppLogger.info('Создание нового чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();

    // Очищаем черновик вложений (живёт в отдельном провайдере).
    _ref.read(attachmentDraftProvider.notifier).clear();

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

    // Черновик вложений тоже чистим — на экране пусто, и вложений быть
    // не должно. Сессию при этом НЕ трогаем — см. комментарий выше.
    _ref.read(attachmentDraftProvider.notifier).clear();
  }

  /// Очистить ошибку **чата** (не вложений).
  ///
  /// Для ошибок вложений — `attachmentDraftProvider.notifier.clearError()`.
  void clearError() {
    _clearError();
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

/// Основной провайдер чата.
///
/// **Зависимости:**
/// - `chatRepositoryProvider` — репозиторий для отправки/загрузки;
/// - `sendMessageUseCaseProvider` — UseCase отправки;
/// - `chatStreamHandlerProvider` — обработчик событий стрима.
///
/// **Больше не зависит** от `uploadAttachmentUseCaseProvider` —
/// управление вложениями переехало в `AttachmentDraftNotifier`.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);
  final streamHandler = ref.read(chatStreamHandlerProvider);

  return ChatNotifier(
    ref: ref,
    repository: repository,
    sendMessageUseCase: sendMessageUseCase,
    streamHandler: streamHandler,
  );
});
