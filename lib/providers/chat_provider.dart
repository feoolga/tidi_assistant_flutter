// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../services/openai_chat_service.dart';
import '../services/service_factory.dart';

// ============================================================
// ЧАСТЬ 1: СОСТОЯНИЕ ЧАТА (ChatState)
// ============================================================

/// Состояние чата — неизменяемая (immutable) модель.
/// Все поля final, изменение только через copyWith.
class ChatState {
  // ---- Основные данные ----
  
  /// Список сообщений в текущем чате
  final List<Message> messages;
  
  /// Флаг загрузки (отправка сообщения или загрузка истории)
  final bool isLoading;
  
  /// Текущий агент (если выбран)
  final String? currentAgentId;
  
  /// Текущая сессия (если есть)
  final String? currentSessionId;
  
  /// Ошибка (если произошла)
  final String? error;

  // ---- Конструкторы ----
  
  /// Начальное состояние (пустой чат, без загрузки)
  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.currentAgentId,
    this.currentSessionId,
    this.error,
  });

  /// Фабричный метод для создания начального состояния
  factory ChatState.initial() {
    return const ChatState();
  }

  // ---- copyWith: создание копии с изменениями ----
  
  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? currentAgentId,
    String? currentSessionId,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      currentAgentId: currentAgentId ?? this.currentAgentId,
      currentSessionId: currentSessionId ?? this.currentSessionId,
      error: error ?? this.error,
    );
  }

  // ---- Вспомогательные геттеры ----
  
  bool get hasMessages => messages.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;
  bool get hasSession => currentAgentId != null && currentSessionId != null;

  @override
  String toString() {
    return 'ChatState(messages: ${messages.length}, isLoading: $isLoading, '
        'agentId: $currentAgentId, sessionId: $currentSessionId, error: $error)';
  }
}

// ============================================================
// ЧАСТЬ 2: NOTIFIER
// ============================================================

/// Управляет состоянием чата.
class ChatNotifier extends StateNotifier<ChatState> {
  final OpenAIChatService _chatService;

  // ---- Конструктор ----
  
  ChatNotifier({required OpenAIChatService chatService})
      : _chatService = chatService,
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

  void _addMessages(List<Message> newMessages) {
    state = state.copyWith(
      messages: [...state.messages, ...newMessages],
    );
  }

  void _setSession(String agentId, String sessionId) {
    state = state.copyWith(
      currentAgentId: agentId,
      currentSessionId: sessionId,
    );
  }

  void _clearSession() {
    state = state.copyWith(
      currentAgentId: null,
      currentSessionId: null,
    );
  }

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================
  
  Future<void> sendMessage(String text) async {
    print('📤 sendMessage вызван с текстом: "$text"');
    
    _clearError();
    _addMessage(Message.fromUser(text: text));
    _setLoading(true);
    
    try {
      final result = await _chatService.sendMessage(text);
      
      final aiMessage = Message.fromAI(
        text: result.text,
        agentId: result.agentId,
        sessionId: result.conversationId,
        id: result.completionId,
      );
      
      _addMessage(aiMessage);
      
      if (result.agentId != null && result.conversationId != null) {
        _setSession(result.agentId!, result.conversationId!);
      }
      
    } catch (e) {
      print('❌ Ошибка в sendMessage: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 loadChat вызван: agentId=$agentId, chatId=$chatId');
    _setLoading(true);
    
    try {
      // Временно заглушка
      await Future.delayed(const Duration(seconds: 1));
      
      final testMessages = [
        Message.fromUser(text: 'Тестовое сообщение 1'),
        Message.fromAI(
          text: 'Тестовый ответ 1',
          agentId: agentId,
          sessionId: chatId,
        ),
        Message.fromUser(text: 'Тестовое сообщение 2'),
        Message.fromAI(
          text: 'Тестовый ответ 2',
          agentId: agentId,
          sessionId: chatId,
        ),
      ];
      
      _setMessages(testMessages);
      _setSession(agentId, chatId);
      
    } catch (e) {
      print('❌ Ошибка в loadChat: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  void clearChat() {
    print('🗑️ clearChat вызван');
    _clearSession();
    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
  }

  void resetSession() {
    print('🔄 resetSession вызван');
    _chatService.resetSession();
    _clearSession();
    _clearError();
  }

  void setSession(String agentId, String sessionId) {
    print('🔵 setSession: agentId=$agentId, sessionId=$sessionId');
    _chatService.setSession(agentId, sessionId);
    _setSession(agentId, sessionId);
  }

  void clearError() {
    _clearError();
  }
}

// ============================================================
// ЧАСТЬ 3: ПРОВАЙДЕРЫ
// ============================================================

final chatServiceProvider = Provider<OpenAIChatService>((ref) {
  return ServiceFactory.getChatService() as OpenAIChatService;
});

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final service = ref.read(chatServiceProvider);
  return ChatNotifier(chatService: service);
});