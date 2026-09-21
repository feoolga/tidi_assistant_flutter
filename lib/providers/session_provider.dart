// lib/providers/session_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';

/// Состояние текущей сессии чата.
///
/// **Это единственный источник правды (SSOT) о том, с каким агентом
/// и в каком чате мы сейчас работаем.** Все остальные места
/// (`ChatState`, UI, use-case) читают сессию **отсюда**, а не хранят
/// свою копию.
///
/// Почему именно `sessionProvider` — SSOT:
/// - `agentId` и `sessionId` — это **сессия** пользователя с агентом,
///   а не «состояние чата». Логически они отдельны от списка сообщений.
/// - Сессия живёт **глобально**, а чат — только когда открыт `ChatScreen`.
/// - Дублирование в `ChatState` приводило к рассинхронизации:
///   `loadChat` обновлял `sessionProvider`, но не `ChatState`.
class ChatSessionState {
  /// ID агента, с которым идёт диалог.
  ///
  /// `null` — сессия ещё не начата (новый чат, до первого сообщения
  /// или первого файла).
  final String? agentId;

  /// ID чата (`conversation_id`).
  ///
  /// `null` — сессия ещё не начата. Появляется после `POST /platform/conversations`
  /// (обычный чат) или после загрузки файла (чат `document_chat`).
  final String? sessionId;

  const ChatSessionState({this.agentId, this.sessionId});

  /// Есть ли активная сессия (и агент, и чат известны).
  bool get hasSession => agentId != null && sessionId != null;

  // ------------------------------------------------------------
  // copyWith с маркером _unset
  // ------------------------------------------------------------

  /// Создать копию с изменёнными полями.
  ///
  /// Примеры:
  /// - `copyWith()` — вернуть копию без изменений.
  /// - `copyWith(agentId: 'epoz')` — обновить только `agentId`.
  /// - `copyWith(agentId: null)` — **сбросить** `agentId` в `null`.
  /// - `copyWith(sessionId: 'abc')` — обновить только `sessionId`.
  ChatSessionState copyWith({
    Object? agentId = copyWithUnset,
    Object? sessionId = copyWithUnset,
  }) {
    return ChatSessionState(
      agentId: isCopyWithUnset(agentId) ? this.agentId : agentId as String?,
      sessionId: isCopyWithUnset(sessionId)
          ? this.sessionId
          : sessionId as String?,
    );
  }

  @override
  String toString() =>
      'ChatSessionState(agentId: $agentId, sessionId: $sessionId)';
}

/// Провайдер для управления текущей сессией чата.
///
/// **SSOT** — см. комментарий к [ChatSessionState].
final sessionProvider =
    StateNotifierProvider<SessionNotifier, ChatSessionState>((ref) {
      return SessionNotifier();
    });

class SessionNotifier extends StateNotifier<ChatSessionState> {
  SessionNotifier() : super(const ChatSessionState());

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Установить новую сессию (и агента, и чат).
  ///
  /// Используется при:
  /// - создании нового чата (`POST /platform/conversations`);
  /// - получении `agent_id` и `conversation_id` из ответа генерации;
  /// - загрузке чата из истории (`loadChat`).
  void setSession(String agentId, String sessionId) {
    if (state.agentId == agentId && state.sessionId == sessionId) {
      AppLogger.debug('Сессия уже установлена: агент=$agentId, чат=$sessionId');
      return;
    }

    state = state.copyWith(agentId: agentId, sessionId: sessionId);
    AppLogger.info('Сессия установлена: агент=$agentId, чат=$sessionId');
  }

  /// Очистить сессию (начать новый диалог).
  ///
  /// Сбрасывает **оба** поля в `null`. Используется при `createNewChat`
  /// и при выходе пользователя из чата (если понадобится).
  void clearSession() {
    if (state.agentId == null && state.sessionId == null) {
      AppLogger.debug('Сессия уже пуста');
      return;
    }

    state = const ChatSessionState();
    AppLogger.info('Сессия очищена');
  }

  /// Обновить только ID агента.
  ///
  /// [agentId] может быть `null` — тогда агент **сбрасывается**,
  /// а `sessionId` остаётся прежним.
  ///
  /// Пример использования: пользователь прикрепил файл — переключаемся
  /// на `document_chat`, но если чат ещё не создан — `sessionId` станет
  /// `null` отдельно, через `setSession`.
  void updateAgent(String? agentId) {
    if (state.agentId == agentId) return;

    state = state.copyWith(agentId: agentId);
    AppLogger.debug('Агент обновлён: ${agentId ?? "(сброшен)"}');
  }

  /// Обновить только ID сессии.
  ///
  /// [sessionId] может быть `null` — тогда сессия **сбрасывается**,
  /// а `agentId` остаётся прежним.
  void updateSession(String? sessionId) {
    if (state.sessionId == sessionId) return;

    state = state.copyWith(sessionId: sessionId);
    AppLogger.debug('Сессия обновлена: ${sessionId ?? "(сброшена)"}');
  }

  /// Проверить, совпадает ли переданная пара с текущей сессией.
  bool isCurrentSession(String agentId, String sessionId) {
    return state.agentId == agentId && state.sessionId == sessionId;
  }
}

// ============================================================
// ВСПОМОГАТЕЛЬНЫЕ ПРОВАЙДЕРЫ
// ============================================================

/// Быстрый доступ к ID агента из UI.
///
/// Пример: `ref.watch(currentAgentIdProvider)` — вернёт `agentId` или `null`.
final currentAgentIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).agentId;
});

/// Быстрый доступ к ID сессии из UI.
final currentSessionIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).sessionId;
});

/// Быстрый доступ к флагу «есть активная сессия».
final hasSessionProvider = Provider<bool>((ref) {
  return ref.watch(sessionProvider).hasSession;
});
