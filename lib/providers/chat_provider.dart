// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../models/agent.dart';  // 👈 ДОБАВЛЯЕМ
import '../services/master_chat_service.dart';
import '../services/chat_history_service.dart';
import '../services/service_factory.dart';
import '../domain/usecases/send_message_usecase.dart';
import 'session_provider.dart';
import 'chat_list_provider.dart';
import 'agent_provider.dart';  // 👈 ДОБАВЛЯЕМ

// ============================================================
// ЧАСТЬ 1: СОСТОЯНИЕ ЧАТА (только сообщения и статус)
// ============================================================

class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  factory ChatState.initial() {
    return const ChatState();
  }

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

  bool get hasMessages => messages.isNotEmpty;
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
  // Сервисы
  final ChatHistoryService _chatHistoryService;

  // 👇 ИСПОЛЬЗУЕМ USECASE ВМЕСТО ПРЯМОГО ВЫЗОВА СЕРВИСА
  final SendMessageUseCase _sendMessageUseCase;

  // Ссылка на провайдер сессии
  final Ref _ref;

  // ---- Конструктор ----

  ChatNotifier({
    required ChatHistoryService chatHistoryService,
    required SendMessageUseCase sendMessageUseCase,
    required Ref ref,
  })  : _chatHistoryService = chatHistoryService,
        _sendMessageUseCase = sendMessageUseCase,
        _ref = ref,
        super(ChatState.initial()) {
    _addWelcomeMessage();
    _listenToSessionChanges();
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

  void _listenToSessionChanges() {
    _ref.listen<ChatSessionState>(sessionProvider, (previous, next) {
      if (next.hasSession) {
        print('🔄 ChatNotifier: сессия изменилась: агент=${next.agentId}, conversation=${next.sessionId}');
      } else {
        print('🔄 ChatNotifier: сессия сброшена');
      }
    });
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

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Отправить сообщение
  ///
  /// Логика полностью делегирована SendMessageUseCase
  Future<void> sendMessage(String text) async {
    print('📤 ChatNotifier: sendMessage "$text"');

    _clearError();
    _addMessage(Message.fromUser(text: text));
    _setLoading(true);

    try {
      // ---- Получаем текущую сессию ----
      final currentMessages = state.messages;  // 👈 все сообщения
      final sessionState = _ref.read(sessionProvider);
      final params = SendMessageParams(
        text: text,
        history: currentMessages,  // 👈 ПЕРЕДАЕМ ВСЮ ИСТОРИЮ
        agentId: sessionState.agentId,
        sessionId: sessionState.sessionId,
      );

      // ---- Выполняем UseCase ----
      final result = await _sendMessageUseCase.execute(params);

      // ---- Обновляем UI ----
      final aiMessage = Message.fromAI(
        text: result.text,
        agentId: result.agentId,
        sessionId: result.sessionId,
      );
      _addMessage(aiMessage);

      // ---- Обновляем сессию, если она изменилась ----
      final currentSession = _ref.read(sessionProvider);
      if (currentSession.agentId != result.agentId ||
          currentSession.sessionId != result.sessionId) {
        _ref.read(sessionProvider.notifier).setSession(
              result.agentId!,
              result.sessionId!,
            );
        print('🔄 ChatNotifier: сессия обновлена из UseCase');
      }
      // 👇 НОВОЕ: Обновляем список чатов, если был создан новый чат
      if (result.chatCreated) {
        print('✅ ChatNotifier: новый чат создан, обновляем список...');
        await _refreshChatList();
      }
      if (result.chatCreated) {
        print('✅ ChatNotifier: новый чат создан через UseCase');
      }
    } catch (e) {
      print('❌ ChatNotifier: ошибка в sendMessage: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _refreshChatList() async {
    final agentsState = _ref.read(agentsProvider);
    if (agentsState is AsyncData<List<Agent>>) {
      final notifier = _ref.read(chatListNotifierProvider.notifier);
      await notifier.refresh(agents: agentsState.value);
      print('✅ ChatNotifier: список чатов обновлен');
    }
  }

  /// Загрузить чат из истории
  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 loadChat: agentId=$agentId, chatId=$chatId');

    _setLoading(true);
    _clearError();

    try {
      final messages = await _chatHistoryService.getMessages(agentId, chatId);
      _setMessages(messages);
      _ref.read(sessionProvider.notifier).setSession(agentId, chatId);
      print('✅ Загружено сообщений: ${messages.length}');
    } catch (e) {
      print('❌ Ошибка в loadChat: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Создать новый пустой чат
  ///
  /// Используется при нажатии кнопки "Новый чат"
  Future<void> createNewChat() async {
    print('🆕 createNewChat: создаем новый пустой чат...');

    // Очищаем сообщения и добавляем приветственное
    _setMessages([]);
    _addWelcomeMessage();

    // Очищаем ошибку
    _clearError();

    // 👇 СБРАСЫВАЕМ СЕССИЮ (чат создастся на сервере при первом сообщении)
    _ref.read(sessionProvider.notifier).clearSession();

    print('✅ createNewChat: сессия сброшена, ожидаем первый вопрос');
  }

  /// Очистить чат
  void clearChat() {
    print('🗑️ clearChat');
    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    _ref.read(sessionProvider.notifier).clearSession();
  }

  /// Сбросить сессию
  void resetSession() {
    print('🔄 resetSession');
    _ref.read(sessionProvider.notifier).clearSession();
    _clearError();
  }

  /// Очистить ошибку
  void clearError() {
    _clearError();
  }

  /// Получить текущий ID агента
  String? get currentAgentId {
    return _ref.read(sessionProvider).agentId;
  }

  /// Получить текущий ID сессии
  String? get currentSessionId {
    return _ref.read(sessionProvider).sessionId;
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

/// 👇 НОВЫЙ ПРОВАЙДЕР: SendMessageUseCase
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final chatService = ref.read(chatServiceProvider);
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  return SendMessageUseCase(
    chatService: chatService,
    chatHistoryService: chatHistoryService,
  );
});

/// Основной провайдер чата
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);

  return ChatNotifier(
    chatHistoryService: chatHistoryService,
    sendMessageUseCase: sendMessageUseCase,
    ref: ref,
  );
});