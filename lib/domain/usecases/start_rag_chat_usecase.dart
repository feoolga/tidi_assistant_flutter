// lib/domain/usecases/start_rag_chat_usecase.dart

import '../../core/config/app_config.dart';
import '../../core/logger/app_logger.dart';
import '../../data/repositories/chat_repository.dart';
import '../models/chat_session.dart';

/// UseCase запуска чата с RAG-набором.
///
/// **Что делает:** создаёт чат у агента `agentic_rag` с привязкой
/// к конкретному RAG-набору (`rag_id`).
///
/// **Почему отдельный UseCase, а не прямой вызов из notifier.**
/// - Единая точка создания RAG-чата. Если завтра появится
///   дополнительная логика — правка в одном месте.
/// - Тестируемость: UseCase тестируется отдельно от notifier.
/// - Соответствие паттерну проекта (все операции через UseCase).
///
/// **Что НЕ делает:**
/// - не переключает `sessionProvider` — это работа `RagCreationNotifier`
///   (D6), потому что UseCase не знает про Riverpod;
/// - не проверяет `status` набора — UI уже показал «Готово»;
///   если набор не готов, **сервер** ответит ошибкой.
///
/// **Возвращает** [ChatSession] — созданный чат.
/// **Бросает** [AppException] при любой ошибке (пробрасывается
/// из `ChatRepository.createConversation`).
class StartRagChatUseCase {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final ChatRepository _chatRepository;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  StartRagChatUseCase({required ChatRepository chatRepository})
    : _chatRepository = chatRepository;

  // ============================================================
  // 3. ВЫПОЛНЕНИЕ
  // ============================================================

  /// Создать чат с RAG-набором.
  ///
  /// [ragId] — ID RAG-набора (обязательно).
  /// [title] — название чата (опционально; если `null` — сервер
  /// поставит дефолт).
  ///
  /// **Почему `agentId` захардкожен.** Для RAG-чата `agent_id` —
  /// всегда `AppConfig.ragAgentId` (`'agentic_rag'`). Конкретный
  /// набор задаётся **отдельно** через `ragId`. Смешивать их —
  /// значит путать «агента» и «набор».
  Future<ChatSession> execute({required String ragId, String? title}) async {
    AppLogger.info('Создание RAG-чата: ragId=$ragId, title="$title"');

    final session = await _chatRepository.createConversation(
      agentId: AppConfig.ragAgentId,
      ragId: ragId,
      title: title,
    );

    AppLogger.info('RAG-чат создан: ${session.id}');
    return session;
  }
}
