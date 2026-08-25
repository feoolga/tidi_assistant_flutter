// lib/providers/session_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/logger/app_logger.dart';

/// Состояние текущей сессии чата
///
/// Это единственное место, где хранится информация о том,
/// с каким агентом и в каком чате мы сейчас работаем.
class ChatSessionState {
  final String? agentId;
  final String? sessionId; // conversation_id

  const ChatSessionState({this.agentId, this.sessionId});

  /// Есть ли активная сессия
  bool get hasSession => agentId != null && sessionId != null;

  /// Создать копию с измененными полями
  ChatSessionState copyWith({String? agentId, String? sessionId}) {
    return ChatSessionState(
      agentId: agentId ?? this.agentId,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  @override
  String toString() =>
      'ChatSessionState(agentId: $agentId, sessionId: $sessionId)';
}

/// Провайдер для управления текущей сессией чата
final sessionProvider =
    StateNotifierProvider<SessionNotifier, ChatSessionState>((ref) {
      return SessionNotifier();
    });

class SessionNotifier extends StateNotifier<ChatSessionState> {
  SessionNotifier() : super(const ChatSessionState());

  /// Установить новую сессию
  ///
  /// Используется при создании нового чата или при получении
  /// agentId и sessionId из ответа сервера
  void setSession(String agentId, String sessionId) {
    // Проверяем, изменилось ли что-то
    if (state.agentId == agentId && state.sessionId == sessionId) {
      AppLogger.debug('Сессия уже установлена: агент=$agentId, чат=$sessionId');
      return;
    }

    state = state.copyWith(agentId: agentId, sessionId: sessionId);
    AppLogger.info('Сессия установлена: агент=$agentId, чат=$sessionId');
  }

  /// Очистить сессию (начать новый диалог)
  void clearSession() {
    if (state.agentId == null && state.sessionId == null) {
      AppLogger.debug('Сессия уже пуста');
      return;
    }

    state = const ChatSessionState();
    AppLogger.info('Сессия очищена');
  }

  /// Обновить только ID агента
  ///
  /// Используется, если агент изменился, но чат остался тот же
  void updateAgent(String agentId) {
    if (state.agentId == agentId) {
      return;
    }

    state = state.copyWith(agentId: agentId);
    AppLogger.debug('Агент обновлён: $agentId');
  }

  /// Обновить только ID сессии
  ///
  /// Используется, если ID сессии изменился, но агент остался тот же
  void updateSession(String sessionId) {
    if (state.sessionId == sessionId) {
      return;
    }

    state = state.copyWith(sessionId: sessionId);
    AppLogger.debug('Сессия обновлена: $sessionId');
  }

  /// Проверить, совпадает ли переданная сессия с текущей
  bool isCurrentSession(String agentId, String sessionId) {
    return state.agentId == agentId && state.sessionId == sessionId;
  }
}

/// Вспомогательный провайдер для быстрого доступа к ID агента
final currentAgentIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).agentId;
});

/// Вспомогательный провайдер для быстрого доступа к ID сессии
final currentSessionIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).sessionId;
});

/// Вспомогательный провайдер: есть ли активная сессия
final hasSessionProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider).hasSession;
});
