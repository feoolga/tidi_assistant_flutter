// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/logger/app_logger.dart';
import '../domain/models/message.dart';
import '../domain/usecases/send_message_usecase.dart';
import 'session_provider.dart';
import 'agent_provider.dart';
import '../data/repositories/chat_repository.dart';
import '../core/errors/error_handler.dart';
import '../core/errors/business_exceptions.dart';

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
    // Используем Object? вместо String?
    // По умолчанию — маркер _unset
    Object? currentAgentId = _unset,
    Object? currentConversationId = _unset,
  }) {
    return ChatState(
      // Обычные поля — как раньше (null = не передано)
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isStreaming: isStreaming ?? this.isStreaming,

      // Поля со sentinel:
      // Если параметр — маркер, оставляем старое значение
      // Иначе — используем переданное (даже если это null!)
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
  final void Function(String agentId, String sessionId)? onSessionChanged;

  ChatNotifier({
    required ChatRepository repository,
    required SendMessageUseCase sendMessageUseCase,
    this.onSessionChanged,
  }) : _repository = repository,
       _sendMessageUseCase = sendMessageUseCase,
       super(ChatState.initial()) {
    _addWelcomeMessage();
  }

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
    AppLogger.debug('🔄 Создано пустое сообщение AI (id: $tempId)');
    _addMessage(aiMessage);

    try {
      // 3. Отправляем запрос и получаем поток событий
      final params = SendMessageParams(
        text: text,
        agentId: agentId,
        sessionId: sessionId,
      );

      final eventStream = _sendMessageUseCase.execute(params);

      // 4. Переменные для сбора данных
      String fullText = '';
      String? finalAgentId;
      String? finalSessionId;
      String? messageId;
      bool isCompleted = false;

      // 5. Обрабатываем каждое событие в потоке
      await for (final event in eventStream) {
        if (event.type == 'delta') {
          // Обновляем текст
          fullText = event.data['text'] as String? ?? '';

          if (fullText.length <= 10) {
            AppLogger.debug('📝 Получен первый чанк: "$fullText"');
          }

          // Обновляем последнее сообщение (оно AI)
          final currentMessages = state.messages;
          if (currentMessages.isNotEmpty) {
            final lastIndex = currentMessages.length - 1;
            final lastMessage = currentMessages[lastIndex];

            // Проверяем, что последнее сообщение — это AI (не пользователь)
            if (!lastMessage.isFromUser) {
              final updatedMessage = lastMessage.copyWith(text: fullText);

              // Заменяем последнее сообщение на обновлённое
              final newMessages = List<Message>.from(currentMessages);
              newMessages[lastIndex] = updatedMessage;

              state = state.copyWith(messages: newMessages);
            }
          }
        } else if (event.type == 'completed') {
          // Сохраняем метаданные
          finalAgentId = event.data['agentId'] as String?;
          finalSessionId = event.data['conversationId'] as String?;
          messageId = event.data['messageId'] as String?;

          // ✅ ЛОГ: получен complete
          AppLogger.info('✅ Ответ получен полностью');
          AppLogger.debug('   📌 Агент: $finalAgentId');
          AppLogger.debug('   📌 Чат: $finalSessionId');
          AppLogger.debug('   📌 ID сообщения: $messageId');
          AppLogger.debug('   📌 Длина текста: ${fullText.length} символов');

          // Обновляем текущего агента и сессию
          if (finalAgentId != null) {
            _setCurrentAgent(finalAgentId);
          }
          if (finalSessionId != null) {
            _setCurrentConversationId(finalSessionId);
          }

          // Обновляем последнее сообщение с финальными данными
          final currentMessages = state.messages;
          if (currentMessages.isNotEmpty) {
            final lastIndex = currentMessages.length - 1;
            final lastMessage = currentMessages[lastIndex];

            if (!lastMessage.isFromUser) {
              final updatedMessage = lastMessage.copyWith(
                id: messageId ?? lastMessage.id,
                agentId: finalAgentId ?? lastMessage.agentId,
                sessionId: finalSessionId ?? lastMessage.sessionId,
              );

              final newMessages = List<Message>.from(currentMessages);
              newMessages[lastIndex] = updatedMessage;
              state = state.copyWith(messages: newMessages);
            }
          }

          // Если сессия изменилась — уведомляем
          if (finalAgentId != null && finalSessionId != null) {
            final currentAgentId = agentId;
            final currentSessionId = sessionId;

            if (currentAgentId != finalAgentId ||
                currentSessionId != finalSessionId) {
              AppLogger.info(
                'Сессия изменилась: агент=$currentAgentId→$finalAgentId, чат=$currentSessionId→$finalSessionId',
              );
              onSessionChanged?.call(finalAgentId, finalSessionId);
            }
          }

          isCompleted = true;
          AppLogger.info('Сообщение отправлено успешно');
        } else if (event.type == 'error') {
          // Обработка ошибки
          final errorMessage =
              event.data['error'] as String? ?? 'Неизвестная ошибка';

          AppLogger.error('❌ Ошибка в потоке: $errorMessage');

          // 👇 Бросаем BusinessException с понятным сообщением
          throw BusinessException.streamError(errorMessage);
        }
      }

      // Если поток завершился без completed — считаем это ошибкой
      if (!isCompleted) {
        throw BusinessException.streamError(
          'Поток завершился без финального события',
        );
      }
    } catch (e) {
      // 👇 Используем ErrorHandler для преобразования ошибки
      final appException = ErrorHandler.handle(e);
      AppLogger.logException('Ошибка в sendMessage', appException);

      // Удаляем пустое сообщение AI, если оно есть
      final currentMessages = state.messages;
      if (currentMessages.isNotEmpty) {
        final lastMessage = currentMessages.last;
        if (!lastMessage.isFromUser && lastMessage.text.isEmpty) {
          final newMessages = List<Message>.from(currentMessages);
          newMessages.removeLast();
          state = state.copyWith(messages: newMessages);
        }
      }

      // 👇 Показываем пользователю понятное сообщение
      _setError(appException.userMessage);
    } finally {
      AppLogger.debug('🏁 Завершение обработки сообщения');
      _setLoading(false);
      _setStreaming(false);
    }
  }

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
      // 👇 Используем ErrorHandler для преобразования ошибки
      final appException = ErrorHandler.handle(e);
      AppLogger.logException('Ошибка в loadChat', appException);
      // 👇 Показываем пользователю понятное сообщение
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

/// Провайдер для SendMessageUseCase
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return SendMessageUseCase(repository: repository);
});

/// Основной провайдер чата.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);

  return ChatNotifier(
    repository: repository,
    sendMessageUseCase: sendMessageUseCase,
    onSessionChanged: (agentId, sessionId) {
      ref.read(sessionProvider.notifier).setSession(agentId, sessionId);
    },
  );
});
