// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/message.dart';
import '../domain/usecases/send_message_usecase.dart';
import '../services/chat_history_service.dart';
import 'session_provider.dart';
import 'agent_provider.dart';

// ============================================================
// 1. СОСТОЯНИЕ ЧАТА
// ============================================================

/// Состояние чата - только сообщения и статус загрузки.
class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final String? error;
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
}

// ============================================================
// 2. NOTIFIER
// ============================================================

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatHistoryService _chatHistoryService;
  final SendMessageUseCase _sendMessageUseCase;
  final void Function(String agentId, String sessionId)? onSessionChanged;

  ChatNotifier({
    required ChatHistoryService chatHistoryService,
    required SendMessageUseCase sendMessageUseCase,
    this.onSessionChanged,
  }) : _chatHistoryService = chatHistoryService,
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
    print('📤 ChatNotifier: sendMessage "$text"');
    print('📤 ChatNotifier: agentId=$agentId, sessionId=$sessionId');

    _clearError();
    _addMessage(Message.fromUser(text: text));
    _setLoading(true);
    _setStreaming(true);

    try {
      final currentMessages = state.messages;

      final params = SendMessageParams(
        text: text,
        history: currentMessages,
        agentId: agentId,
        sessionId: sessionId,
      );

      final result = await _sendMessageUseCase.execute(params);

      final aiMessage = Message.fromAI(
        text: result.text,
        agentId: result.agentId,
        sessionId: result.sessionId,
      );
      _addMessage(aiMessage);

      if (result.agentId != null && result.sessionId != null) {
        final currentAgentId = agentId;
        final currentSessionId = sessionId;

        if (currentAgentId != result.agentId ||
            currentSessionId != result.sessionId) {
          print('🔄 ChatNotifier: сессия изменилась!');
          print('   Было: агент=$currentAgentId, чат=$currentSessionId');
          print('   Стало: агент=${result.agentId}, чат=${result.sessionId}');

          onSessionChanged?.call(result.agentId!, result.sessionId!);
        }
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

  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 ChatNotifier: loadChat агент=$agentId, чат=$chatId');

    _setLoading(true);
    _clearError();

    try {
      final messages = await _chatHistoryService.getMessages(agentId, chatId);
      _setMessages(messages);

      onSessionChanged?.call(agentId, chatId);

      print('✅ ChatNotifier: загружено ${messages.length} сообщений');
    } catch (e) {
      print('❌ ChatNotifier: ошибка в loadChat: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createNewChat() async {
    print('🆕 ChatNotifier: createNewChat');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
    print('✅ ChatNotifier: новый чат создан');
  }

  void clearChat() {
    print('🗑️ ChatNotifier: clearChat');
    _setMessages([]);
    _addWelcomeMessage();
    _clearError();
  }

  void clearError() {
    _clearError();
  }
}

// ============================================================
// 3. ПРОВАЙДЕРЫ
// ============================================================

/// Провайдер для сервиса истории
final chatHistoryServiceProvider = Provider<ChatHistoryService>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return ChatHistoryService(repository: repository);
});

/// Провайдер для SendMessageUseCase
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return SendMessageUseCase(repository: repository);
});

/// Основной провайдер чата.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);

  return ChatNotifier(
    chatHistoryService: chatHistoryService,
    sendMessageUseCase: sendMessageUseCase,
    onSessionChanged: (agentId, sessionId) {
      ref.read(sessionProvider.notifier).setSession(agentId, sessionId);
    },
  );
});
