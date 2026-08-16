// lib/providers/session_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Состояние текущей сессии чата
/// 
/// В терминах бэкенда:
/// - [agentId] — это ID агента (значение поля "model" в ответе)
/// - [sessionId] — это conversation_id (приходит в ответе на генерацию)
class ChatSessionState {
  final String? agentId;
  final String? sessionId; // conversation_id

  const ChatSessionState({
    this.agentId,
    this.sessionId,
  });

  bool get hasSession => agentId != null && sessionId != null;

  ChatSessionState copyWith({
    String? agentId,
    String? sessionId,
  }) {
    return ChatSessionState(
      agentId: agentId ?? this.agentId,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  @override
  String toString() => 'ChatSessionState(agentId: $agentId, sessionId: $sessionId)';
}

/// Провайдер для управления текущей сессией чата
final sessionProvider = StateNotifierProvider<SessionNotifier, ChatSessionState>((ref) {
  return SessionNotifier();
});

class SessionNotifier extends StateNotifier<ChatSessionState> {
  SessionNotifier() : super(const ChatSessionState());

  void setSession(String agentId, String sessionId) {
    state = state.copyWith(
      agentId: agentId,
      sessionId: sessionId,
    );
    print('🔵 Сессия установлена: агент=$agentId, conversation=$sessionId');
  }

  void clearSession() {
    state = const ChatSessionState();
    print('🔄 Сессия очищена');
  }

  void updateAgent(String agentId) {
    state = state.copyWith(agentId: agentId);
    print('🔄 Агент обновлен: $agentId');
  }

  void updateSession(String sessionId) {
    state = state.copyWith(sessionId: sessionId);
    print('🔄 Conversation обновлен: $sessionId');
  }
}