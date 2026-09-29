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
/// - `agentId` / `sessionId` / `ragId` — это **сессия** пользователя
///   с агентом, а не «состояние чата». Логически они отдельны от
///   списка сообщений.
/// - Сессия живёт **глобально**, а чат — только когда открыт `ChatScreen`.
/// - Дублирование в `ChatState` приводило к рассинхронизации:
///   `loadChat` обновлял `sessionProvider`, но не `ChatState`.
///
/// **Про `ragId` и `agentDisplayName` (добавлены для RAG).**
///
/// RAG-агент адресуется **тремя** идентификаторами, а не двумя:
/// - `agentId = "agentic_rag"` — для путей `/agents/agentic_rag/v1/...`;
/// - `ragId = "<uuid набора>"` — для `model: "rag/<ragId>"` в теле запроса;
/// - `sessionId = "<uuid conversation>"` — для `conversation_id`.
///
/// А `agentDisplayName` — человекочитаемое имя для UI. Для обычных
/// агентов это имя из реестра («Документы», «ЕПоЗ»), для RAG — имя
/// **набора** («Регламенты», «HR 2024»). Благодаря этому `ChatScreen`
/// может показать имя **без хардкод-словаря**.
class ChatSessionState {
  /// ID агента, с которым идёт диалог.
  ///
  /// `null` — сессия ещё не начата (новый чат, до первого сообщения
  /// или первого файла).
  ///
  /// Для RAG — всегда `"agentic_rag"` (тот же агент для **всех**
  /// наборов; конкретный набор задаётся через [ragId]).
  final String? agentId;

  /// ID чата (`conversation_id`).
  ///
  /// `null` — сессия ещё не начата. Появляется после
  /// `POST /platform/conversations` (обычный чат) или после загрузки
  /// файла (чат `document_chat`).
  final String? sessionId;

  /// ID RAG-набора — **только** для RAG-сессии.
  ///
  /// `null` для обычных агентов (`document_chat`, `epoz`, `chat`, ...).
  /// Для RAG-сессии — UUID пользовательского набора документов.
  ///
  /// Используется для:
  /// - сбора `model: "rag/<ragId>"` в `POST /v1/responses`;
  /// - передачи `rag_id` в `POST /agents/agentic_rag/v1/platform/conversations`.
  final String? ragId;

  /// Человекочитаемое имя для UI.
  ///
  /// Для обычных агентов — имя из реестра («Документы», «ЕПоЗ»).
  /// Для RAG — имя **набора** («Регламенты», «HR 2024»).
  ///
  /// `null`, если имя не установлено — UI покажет fallback
  /// («AI Ассистент»).
  final String? agentDisplayName;

  const ChatSessionState({
    this.agentId,
    this.sessionId,
    this.ragId,
    this.agentDisplayName,
  });

  /// Есть ли активная сессия (и агент, и чат известны).
  ///
  /// `ragId` **не** включается в проверку: он опционален и есть
  /// только у RAG-сессии.
  bool get hasSession => agentId != null && sessionId != null;

  /// Это RAG-сессия?
  ///
  /// `true`, если установлен [ragId]. Пригодится в `SendMessageUseCase`
  /// для решения, какой `model` собирать.
  bool get isRagSession => ragId != null;

  // ------------------------------------------------------------
  // copyWith с маркером _unset
  // ------------------------------------------------------------

  /// Создать копию с изменёнными полями.
  ///
  /// Примеры:
  /// - `copyWith()` — вернуть копию без изменений.
  /// - `copyWith(agentId: 'epoz')` — обновить только `agentId`.
  /// - `copyWith(agentId: null)` — **сбросить** `agentId` в `null`.
  /// - `copyWith(ragId: 'abc')` — обновить `ragId`.
  /// - `copyWith(ragId: null)` — **сбросить** `ragId` в `null`.
  ///
  /// Все nullable-поля используют маркер [copyWithUnset], чтобы
  /// отличать «не передали параметр» от «передали `null` явно».
  ChatSessionState copyWith({
    Object? agentId = copyWithUnset,
    Object? sessionId = copyWithUnset,
    Object? ragId = copyWithUnset,
    Object? agentDisplayName = copyWithUnset,
  }) {
    return ChatSessionState(
      agentId: isCopyWithUnset(agentId) ? this.agentId : agentId as String?,
      sessionId: isCopyWithUnset(sessionId)
          ? this.sessionId
          : sessionId as String?,
      ragId: isCopyWithUnset(ragId) ? this.ragId : ragId as String?,
      agentDisplayName: isCopyWithUnset(agentDisplayName)
          ? this.agentDisplayName
          : agentDisplayName as String?,
    );
  }

  @override
  String toString() =>
      'ChatSessionState(agentId: $agentId, sessionId: $sessionId, '
      'ragId: $ragId, agentDisplayName: $agentDisplayName)';
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

  /// Установить новую сессию.
  ///
  /// **Обычная сессия** — вызываем с двумя позиционными параметрами:
  /// ```dart
  /// setSession('document_chat', 'fad8f104-...');
  /// setSession('epoz', 'cid-42', agentDisplayName: 'ЕПоЗ');
  /// ```
  ///
  /// **RAG-сессия** — добавляем `ragId` и `agentDisplayName`:
  /// ```dart
  /// setSession(
  ///   'agentic_rag',
  ///   'cid-42',
  ///   ragId: '22222222-...',
  ///   agentDisplayName: 'Регламенты',
  /// );
  /// ```
  ///
  /// **Используется при:**
  /// - создании нового чата (`POST /platform/conversations`);
  /// - получении `agent_id` / `conversation_id` из ответа генерации;
  /// - загрузке чата из истории (`loadChat`);
  /// - переключении на RAG-набор.
  ///
  /// **Про `ragId` и `agentDisplayName`:**
  /// - оба **опциональны** — для обычных агентов не передаём, поля
  ///   останутся `null` или **сохранят предыдущее значение** (если оно
  ///   было установлено ранее — см. `_applyOrPreserve` ниже);
  /// - если передать `ragId: null` **явно** — поле **сбросится**
  ///   в `null`. Это нужно, чтобы переключиться с RAG-сессии
  ///   на обычную.
  void setSession(
    String agentId,
    String sessionId, {
    Object? ragId = copyWithUnset,
    Object? agentDisplayName = copyWithUnset,
  }) {
    // Проверяем, изменилось ли что-то.
    // `copyWithUnset` — маркер «не передали»; в этом случае
    // текущее значение `state` сохраняется. Значит, «изменение» —
    // это когда параметр **передан** и **отличается** от текущего.
    final newRagId = isCopyWithUnset(ragId) ? state.ragId : ragId as String?;
    final newDisplayName = isCopyWithUnset(agentDisplayName)
        ? state.agentDisplayName
        : agentDisplayName as String?;

    if (state.agentId == agentId &&
        state.sessionId == sessionId &&
        state.ragId == newRagId &&
        state.agentDisplayName == newDisplayName) {
      AppLogger.debug(
        'Сессия уже установлена: агент=$agentId, чат=$sessionId, '
        'ragId=$newRagId, displayName=$newDisplayName',
      );
      return;
    }

    state = state.copyWith(
      agentId: agentId,
      sessionId: sessionId,
      ragId: ragId,
      agentDisplayName: agentDisplayName,
    );

    AppLogger.info(
      'Сессия установлена: агент=$agentId, чат=$sessionId'
      '${newRagId != null ? ", ragId=$newRagId" : ""}'
      '${newDisplayName != null ? ", displayName=$newDisplayName" : ""}',
    );
  }

  /// Очистить сессию (начать новый диалог).
  ///
  /// Сбрасывает **все** поля в `null`, включая `ragId` и
  /// `agentDisplayName`. Используется при `createNewChat`
  /// и при выходе пользователя из чата (если понадобится).
  void clearSession() {
    if (state.agentId == null &&
        state.sessionId == null &&
        state.ragId == null &&
        state.agentDisplayName == null) {
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
  /// **ВНИМАНИЕ:** этот метод **не** трогает `ragId` и
  /// `agentDisplayName`. Если переключаешься между обычным агентом
  /// и RAG — используй `setSession`.
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
  ///
  /// **Проверяются только `agentId` и `sessionId`** — `ragId`
  /// не включается, потому что для одного набора может быть
  /// несколько чатов, и «та же сессия» — это про пару
  /// «агент + чат», а не про набор.
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

/// Быстрый доступ к ID RAG-набора из UI.
///
/// `null` для обычных сессий (не RAG).
final currentRagIdProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).ragId;
});

/// Быстрый доступ к человекочитаемому имени агента.
///
/// `ChatScreen` использует это для AppBar **вместо** хардкод-словаря.
/// `null`, если имя не установлено — UI покажет fallback.
final currentAgentDisplayNameProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).agentDisplayName;
});
