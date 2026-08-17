// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../models/agent.dart';
import '../services/master_chat_service.dart';
import '../services/chat_history_service.dart';
import '../services/service_factory.dart';
import '../domain/usecases/send_message_usecase.dart';
import 'session_provider.dart';
import 'chat_list_provider.dart';
import 'agent_provider.dart';

// ============================================================
// ЧАСТЬ 1: СОСТОЯНИЕ ЧАТА (только сообщения и статус)
// ============================================================

/// Состояние чата - только сообщения и статус загрузки.
/// 
/// Важно: здесь НЕТ agentId и sessionId!
/// Они хранятся в отдельном провайдере - sessionProvider.
class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
  final bool isStreaming; // 👈 НОВОЕ: идет ли сейчас стрим

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
    String? error,
    bool? isStreaming,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  bool get hasMessages => messages.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;

  @override
  String toString() {
    return 'ChatState(messages: ${messages.length}, isLoading: $isLoading, isStreaming: $isStreaming, error: $error)';
  }
}

// ============================================================
// ЧАСТЬ 2: NOTIFIER (управляет только сообщениями)
// ============================================================

class ChatNotifier extends StateNotifier<ChatState> {
  // ---- Сервисы ----
  final ChatHistoryService _chatHistoryService;
  final SendMessageUseCase _sendMessageUseCase;
  
  // ---- Callback для обновления сессии ----
  final void Function(String agentId, String sessionId)? onSessionChanged;

  // ---- Конструктор ----
  ChatNotifier({
    required ChatHistoryService chatHistoryService,
    required SendMessageUseCase sendMessageUseCase,
    this.onSessionChanged,
  })  : _chatHistoryService = chatHistoryService,
        _sendMessageUseCase = sendMessageUseCase,
        super(ChatState.initial()) {
    _addWelcomeMessage();
  }

  // ============================================================
  // ПРИВАТНЫЕ МЕТОДЫ
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
    state = state.copyWith(error: error);
  }

  void _clearError() {
    state = state.copyWith(error: null);
  }

  void _addMessage(Message message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Отправить сообщение.
  /// 
  /// [agentId] - ID агента (если есть)
  /// [sessionId] - ID сессии (если есть)
  Future<void> sendMessage({
    required String text,
    String? agentId,
    String? sessionId,
  }) async {
    print('📤 ChatNotifier: sendMessage "$text"');
    print('📤 ChatNotifier: agentId=$agentId, sessionId=$sessionId');

    _clearError();
    _addMessage(Message.fromUser(text: text));
    _setLoading(true);
    _setStreaming(true);

    try {
      // ---- 1. Получаем текущие сообщения (историю) ----
      final currentMessages = state.messages;

      // ---- 2. Строим параметры для UseCase ----
      final params = SendMessageParams(
        text: text,
        history: currentMessages,
        agentId: agentId,
        sessionId: sessionId,
      );

      // ---- 3. Выполняем UseCase ----
      final result = await _sendMessageUseCase.execute(params);

      // ---- 4. Обновляем UI ----
      final aiMessage = Message.fromAI(
        text: result.text,
        agentId: result.agentId,
        sessionId: result.sessionId,
      );
      _addMessage(aiMessage);

      // ---- 5. Сообщаем об изменении сессии (если она изменилась) ----
      if (result.agentId != null && result.sessionId != null) {
        // Проверяем, изменилась ли сессия
        final currentAgentId = agentId;
        final currentSessionId = sessionId;
        
        if (currentAgentId != result.agentId || 
            currentSessionId != result.sessionId) {
          print('🔄 ChatNotifier: сессия изменилась!');
          print('   Было: агент=$currentAgentId, чат=$currentSessionId');
          print('   Стало: агент=${result.agentId}, чат=${result.sessionId}');
          
          // Вызываем callback, чтобы обновить sessionProvider
          onSessionChanged?.call(result.agentId!, result.sessionId!);
        }
      }

      // ---- 6. Если создан новый чат - обновляем список ----
      if (result.chatCreated) {
        print('✅ ChatNotifier: новый чат создан, обновляем список...');
        // TODO: обновить список чатов через callback
        // Пока просто логируем
      }

      print('✅ ChatNotifier: сообщение отправлено успешно');
      
    } catch (e) {
      print('❌ ChatNotifier: ошибка в sendMessage: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
      _setStreaming(false);
    }
  }

  /// Загрузить чат из истории.
  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 ChatNotifier: loadChat агент=$agentId, чат=$chatId');

    _setLoading(true);
    _clearError();

    try {
      final messages = await _chatHistoryService.getMessages(agentId, chatId);
      _setMessages(messages);
      
      // Сообщаем об изменении сессии
      onSessionChanged?.call(agentId, chatId);
      
      print('✅ ChatNotifier: загружено ${messages.length} сообщений');
    } catch (e) {
      print('❌ ChatNotifier: ошибка в loadChat: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Создать новый пустой чат.
  Future<void> createNewChat() async {
    print('🆕 ChatNotifier: createNewChat');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    
    // Сообщаем, что сессия сброшена
    // onSessionChanged?.call(null, null); // 👈 пока не используем
    print('✅ ChatNotifier: новый чат создан');
  }

  /// Очистить чат.
  void clearChat() {
    print('🗑️ ChatNotifier: clearChat');
    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
  }

  /// Очистить ошибку.
  void clearError() {
    _clearError();
  }
}

// ============================================================
// ЧАСТЬ 3: ПРОВАЙДЕРЫ
// ============================================================

/// Провайдер для сервиса чата
final chatServiceProvider = Provider<MasterChatService>((ref) {
  return ServiceFactory.getChatService();
});

/// Провайдер для сервиса истории
final chatHistoryServiceProvider = Provider<ChatHistoryService>((ref) {
  return ServiceFactory.getChatHistoryService();
});

/// Провайдер для SendMessageUseCase
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final chatService = ref.read(chatServiceProvider);
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  return SendMessageUseCase(
    chatService: chatService,
    chatHistoryService: chatHistoryService,
  );
});

/// Основной провайдер чата.
/// 
/// Теперь он принимает callback для обновления сессии.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);

  return ChatNotifier(
    chatHistoryService: chatHistoryService,
    sendMessageUseCase: sendMessageUseCase,
    onSessionChanged: (agentId, sessionId) {
      // 👈 Обновляем sessionProvider через callback
      ref.read(sessionProvider.notifier).setSession(agentId, sessionId);
    },
  );
});