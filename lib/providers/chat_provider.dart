// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/logger/app_logger.dart';
import '../domain/models/message.dart';
import '../domain/services/chat_stream_event.dart';
import '../domain/services/chat_stream_handler.dart';
import '../domain/usecases/send_message_usecase.dart';
import 'session_provider.dart';
import 'agent_provider.dart';
import '../data/repositories/chat_repository.dart';
import '../core/errors/error_handler.dart';

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

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.isStreaming = false,
    this.currentAgentId,
    this.currentConversationId,
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
    );
  }

  bool get hasMessages => messages.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;
}

// ============================================================
// 2. NOTIFIER
// ============================================================

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repository;
  final SendMessageUseCase _sendMessageUseCase;
  final ChatStreamHandler _streamHandler;
  final void Function(String agentId, String sessionId)? onSessionChanged;

  ChatNotifier({
    required ChatRepository repository,
    required SendMessageUseCase sendMessageUseCase,
    required ChatStreamHandler streamHandler,
    this.onSessionChanged,
  }) : _repository = repository,
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

  void _addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
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

/// Основной провайдер чата.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);
  final streamHandler = ref.read(chatStreamHandlerProvider);

  return ChatNotifier(
    repository: repository,
    sendMessageUseCase: sendMessageUseCase,
    streamHandler: streamHandler,
    onSessionChanged: (agentId, sessionId) {
      ref.read(sessionProvider.notifier).setSession(agentId, sessionId);
    },
  );
});
