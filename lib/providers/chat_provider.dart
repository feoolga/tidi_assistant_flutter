// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../services/master_chat_service.dart';
import '../services/chat_history_service.dart';
import '../services/service_factory.dart';
import 'session_provider.dart';

// ============================================================
// ЧАСТЬ 1: СОСТОЯНИЕ ЧАТА (только сообщения и статус)
// ============================================================

class ChatState {
  /// Список сообщений в текущем чате
  final List<Message> messages;
  
  /// Флаг загрузки (отправка сообщения или загрузка истории)
  final bool isLoading;
  
  /// Текст ошибки (если есть)
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  /// Начальное состояние (пустой чат)
  factory ChatState.initial() {
    return const ChatState();
  }

  /// Создание копии с измененными полями
  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    String? error,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  /// Есть ли сообщения
  bool get hasMessages => messages.isNotEmpty;
  
  /// Есть ли ошибка
  bool get hasError => error != null && error!.isNotEmpty;

  @override
  String toString() {
    return 'ChatState(messages: ${messages.length}, isLoading: $isLoading, error: $error)';
  }
}

// ============================================================
// ЧАСТЬ 2: NOTIFIER (управляет только сообщениями)
// ============================================================

class ChatNotifier extends StateNotifier<ChatState> {
  // Сервисы для работы с чатом
  final MasterChatService _chatService;
  final ChatHistoryService _chatHistoryService;
  
  // Ссылка на провайдер сессии (через Ref)
  final Ref _ref;

  // ---- Конструктор ----
  
  ChatNotifier({
    required MasterChatService chatService,
    required ChatHistoryService chatHistoryService,
    required Ref ref,
  })  : _chatService = chatService,
        _chatHistoryService = chatHistoryService,
        _ref = ref,
        super(ChatState.initial()) {
    // Добавляем приветственное сообщение при создании
    _addWelcomeMessage();
  }

  // ============================================================
  // ПРИВАТНЫЕ МЕТОДЫ (управление состоянием)
  // ============================================================
  
  /// Добавить приветственное сообщение
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

  /// Установить флаг загрузки
  void _setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  /// Установить ошибку
  void _setError(String? error) {
    state = state.copyWith(error: error);
  }

  /// Очистить ошибку
  void _clearError() {
    state = state.copyWith(error: null);
  }

  /// Добавить одно сообщение
  void _addMessage(Message message) {
    state = state.copyWith(
      messages: [...state.messages, message],
    );
  }

  /// Добавить несколько сообщений (для загрузки истории)
  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ (используются в UI)
  // ============================================================
  
  /// Отправить сообщение
  /// 
  /// Логика:
  /// 1. Проверяем, есть ли активная сессия (из sessionProvider)
  /// 2. Если нет — создаем новый чат
  /// 3. Отправляем сообщение через MasterChatService
  /// 4. Добавляем ответ AI в список сообщений
  /// 5. Обновляем сессию (если пришли новые agentId/sessionId)
  Future<void> sendMessage(String text) async {
    print('📤 sendMessage: "$text"');
    
    // Очищаем ошибку
    _clearError();
    
    // Добавляем сообщение пользователя
    _addMessage(Message.fromUser(text: text));
    
    // Показываем загрузку
    _setLoading(true);
    
    try {
      // Получаем текущую сессию из sessionProvider
      final sessionState = _ref.read(sessionProvider);
      
      String? agentId = sessionState.agentId;
      String? sessionId = sessionState.sessionId;
      
      // Если нет сессии — создаем новый чат
      if (agentId == null || sessionId == null) {
        print('🆕 Нет сессии, создаем чат...');
        
        // Используем 'chat' как агента по умолчанию для создания
        const defaultAgentId = 'chat';
        
        // Создаем чат через ChatHistoryService
        final newChat = await _chatHistoryService.createChat(defaultAgentId);
        
        agentId = newChat.agentId;
        sessionId = newChat.id;
        
        // Сохраняем сессию в sessionProvider
        _ref.read(sessionProvider.notifier).setSession(agentId, sessionId);
        
        // Устанавливаем сессию в сервисе
        _chatService.setSession(agentId, sessionId);
        
        print('✅ Создан чат: agentId=$agentId, sessionId=$sessionId');
      }
      
      // Убеждаемся, что у нас есть agentId и sessionId
      final String finalAgentId = agentId!;
      final String finalSessionId = sessionId!;
      
      // Отправляем сообщение через MasterChatService
      final result = await _chatService.sendMessage(text);
      
      // Создаем сообщение от AI
      final aiMessage = Message.fromAI(
        text: result.text,
        agentId: result.agentId ?? finalAgentId,
        sessionId: result.sessionId ?? finalSessionId,
      );
      
      // Добавляем сообщение AI
      _addMessage(aiMessage);
      
      // Обновляем сессию, если пришли новые данные
      if (result.agentId != null && result.sessionId != null) {
        // Проверяем, изменились ли agentId или sessionId
        final currentSession = _ref.read(sessionProvider);
        if (currentSession.agentId != result.agentId ||
            currentSession.sessionId != result.sessionId) {
          _ref.read(sessionProvider.notifier).setSession(
            result.agentId!,
            result.sessionId!,
          );
          _chatService.setSession(result.agentId!, result.sessionId!);
          print('🔄 Сессия обновлена: agentId=${result.agentId}, sessionId=${result.sessionId}');
        }
      }
      
    } catch (e) {
      print('❌ Ошибка в sendMessage: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Загрузить чат из истории
  /// 
  /// Используется при выборе чата из списка истории
  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 loadChat: agentId=$agentId, chatId=$chatId');
    
    _setLoading(true);
    _clearError();
    
    try {
      // Загружаем сообщения
      final messages = await _chatHistoryService.getMessages(agentId, chatId);
      
      // Устанавливаем сообщения в состояние
      _setMessages(messages);
      
      // Обновляем сессию в sessionProvider
      _ref.read(sessionProvider.notifier).setSession(agentId, chatId);
      
      // Обновляем сессию в сервисе
      _chatService.setSession(agentId, chatId);
      
      print('✅ Загружено сообщений: ${messages.length}');
      
    } catch (e) {
      print('❌ Ошибка в loadChat: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Очистить чат (удалить все сообщения)
  void clearChat() {
    print('🗑️ clearChat');
    
    // Очищаем сообщения
    _setMessages([]);
    
    // Добавляем приветственное
    _addWelcomeMessage();
    
    // Очищаем ошибку
    _clearError();
    
    // Очищаем сессию в sessionProvider
    _ref.read(sessionProvider.notifier).clearSession();
    
    // Сбрасываем сессию в сервисе
    _chatService.resetSession();
  }

  /// Сбросить сессию (начать новый чат без очистки сообщений)
  void resetSession() {
    print('🔄 resetSession');
    
    // Очищаем сессию в sessionProvider
    _ref.read(sessionProvider.notifier).clearSession();
    
    // Сбрасываем сессию в сервисе
    _chatService.resetSession();
    
    // Очищаем ошибку
    _clearError();
  }

  /// Очистить ошибку (вызывается после показа SnackBar)
  void clearError() {
    _clearError();
  }

  /// Получить текущий ID агента (из sessionProvider)
  String? get currentAgentId {
    return _ref.read(sessionProvider).agentId;
  }

  /// Получить текущий ID сессии (из sessionProvider)
  String? get currentSessionId {
    return _ref.read(sessionProvider).sessionId;
  }
}

// ============================================================
// ЧАСТЬ 3: ПРОВАЙДЕРЫ
// ============================================================

/// Провайдер для сервиса чата
final chatServiceProvider = Provider<MasterChatService>((ref) {
  // Используем ServiceFactory для получения сервиса
  return ServiceFactory.getChatService() as MasterChatService;
});

/// Провайдер для сервиса истории
final chatHistoryServiceProvider = Provider<ChatHistoryService>((ref) {
  return ServiceFactory.getChatHistoryService();
});

/// Основной провайдер чата
/// 
/// Использует sessionProvider для управления сессией
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final chatService = ref.read(chatServiceProvider);
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  
  return ChatNotifier(
    chatService: chatService,
    chatHistoryService: chatHistoryService,
    ref: ref,
  );
});