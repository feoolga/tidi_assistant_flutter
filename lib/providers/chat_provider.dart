// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../services/master_chat_service.dart';
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
  
  /// Создаёт новое состояние на основе текущего,
  /// заменяя указанные поля.
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
  
  /// Есть ли сообщения в чате
  bool get hasMessages => messages.isNotEmpty;
  
  /// Есть ли ошибка
  bool get hasError => error != null && error!.isNotEmpty;
  
  /// Текущий агент и сессия установлены?
  bool get hasSession => currentAgentId != null && currentSessionId != null;

  // ---- Отладка ----
  
  @override
  String toString() {
    return 'ChatState(messages: ${messages.length}, isLoading: $isLoading, '
        'agentId: $currentAgentId, sessionId: $currentSessionId, error: $error)';
  }
}

// ============================================================
// ЧАСТЬ 2: NOTIFIER (пока только основа)
// ============================================================

/// Управляет состоянием чата.
/// Все изменения состояния происходят через методы этого класса.
class ChatNotifier extends StateNotifier<ChatState> {
  /// Сервис для общения с API
  final MasterChatService _chatService;

  // ---- Конструктор ----
  
  ChatNotifier({
    required MasterChatService chatService,
  })  : _chatService = chatService,
        super(ChatState.initial()) {
    // При создании добавляем приветственное сообщение
    _addWelcomeMessage();
  }

  // ---- Приватные методы для изменения состояния ----
  
  /// Добавляет приветственное сообщение (если чат пуст)
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

  /// Устанавливает флаг загрузки
  void _setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  /// Устанавливает ошибку
  void _setError(String? error) {
    state = state.copyWith(error: error);
  }

  /// Очищает ошибку
  void _clearError() {
    state = state.copyWith(error: null);
  }

  /// Добавляет одно сообщение в конец списка
  void _addMessage(Message message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  /// Добавляет несколько сообщений в конец списка
  void _addMessages(List<Message> newMessages) {
    state = state.copyWith(
      messages: [...state.messages, ...newMessages],
    );
  }

  /// Устанавливает сессию (агент + сессия)
  void _setSession(String agentId, String sessionId) {
    state = state.copyWith(
      currentAgentId: agentId,
      currentSessionId: sessionId,
    );
  }

  /// Очищает сессию
  void _clearSession() {
    state = state.copyWith(
      currentAgentId: null,
      currentSessionId: null,
    );
  }

  /// Заменяет все сообщения (для загрузки истории)
  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  // ---- Публичные методы (будем заполнять в следующем шаге) ----
  
  /// TODO: Отправить сообщение
  /// Будет реализовано в Шаге 2.2
  Future<void> sendMessage(String text) async {
    // Пока заглушка
    print('📤 sendMessage вызван с текстом: "$text"');
    _setLoading(true);
    
    // Имитация задержки
    await Future.delayed(const Duration(seconds: 1));
    
    // Добавляем тестовое сообщение
    _addMessage(
      Message.fromUser(text: text),
    );
    
    _addMessage(
      Message.fromAI(
        text: 'Это тестовый ответ на сообщение: "$text"',
        agentId: 'test_agent',
        sessionId: 'test_session',
      ),
    );
    
    _setLoading(false);
  }

  /// TODO: Загрузить чат
  /// Будет реализовано в Шаге 2.3
  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 loadChat вызван: agentId=$agentId, chatId=$chatId');
    _setLoading(true);
    
    // Имитация загрузки
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
    _setLoading(false);
  }

  /// Очистить чат
  void clearChat() {
    print('🗑️ clearChat вызван');
    _clearSession();
    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
  }

  /// Сбросить сессию (начать новый диалог)
  void resetSession() {
    print('🔄 resetSession вызван');
    _chatService.resetSession();
    _clearSession();
    _clearError();
    // Не очищаем сообщения, просто сбрасываем сессию
  }

  /// Установить сессию (для продолжения диалога)
  void setSession(String agentId, String sessionId) {
    print('🔵 setSession: agentId=$agentId, sessionId=$sessionId');
    _chatService.setSession(agentId, sessionId);
    _setSession(agentId, sessionId);
  }
}

// ============================================================
// ЧАСТЬ 3: ПРОВАЙДЕРЫ (доступ к состоянию)
// ============================================================

/// Провайдер для сервиса чата
final chatServiceProvider = Provider<MasterChatService>((ref) {
  return ServiceFactory.getChatService() as MasterChatService;
});

/// Провайдер состояния чата
/// Используй ref.watch(chatProvider) для чтения состояния
/// Используй ref.read(chatProvider.notifier) для вызова методов
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final service = ref.read(chatServiceProvider);
  return ChatNotifier(chatService: service);
});