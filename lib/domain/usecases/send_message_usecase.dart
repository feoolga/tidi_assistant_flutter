// lib/domain/usecases/send_message_usecase.dart

import '../../data/repositories/chat_repository.dart';
import '../../core/logger/app_logger.dart';

// ============================================================
// 1. ПАРАМЕТРЫ
// ============================================================

/// Параметры для отправки сообщения.
class SendMessageParams {
  /// Текст сообщения пользователя
  final String text;

  /// ID агента (если уже знаем, кого вызывать)
  final String? agentId;

  /// ID сессии/чата (если продолжаем диалог)
  final String? sessionId;

  const SendMessageParams({required this.text, this.agentId, this.sessionId});

  /// Есть ли активная сессия (агент + чат)
  bool get hasSession => agentId != null && sessionId != null;
}

// ============================================================
// 2. РЕЗУЛЬТАТ
// ============================================================

/// Результат отправки сообщения.
class SendMessageResult {
  /// Текст ответа от AI
  final String text;

  /// ID сообщения (для фидбэка и источников)
  final String? messageId;

  /// ID агента, который ответил
  final String? agentId;

  /// ID сессии/чата
  final String? sessionId;

  /// Был ли создан новый чат
  final bool chatCreated;

  const SendMessageResult({
    required this.text,
    this.messageId,
    this.agentId,
    this.sessionId,
    this.chatCreated = false,
  });
}

// ============================================================
// 3. USECASE
// ============================================================

/// UseCase для отправки сообщения.
///
/// Отвечает на вопрос: "Что делает приложение, когда пользователь отправляет сообщение?"
///
/// Шаги:
/// 1. Берёт текст сообщения
/// 2. Отправляет его в Repository
/// 3. Возвращает ответ
class SendMessageUseCase {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final ChatRepository _repository;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  SendMessageUseCase({required ChatRepository repository})
    : _repository = repository;

  // ============================================================
  // 3. МЕТОДЫ
  // ============================================================

  /// Выполнить сценарий: отправить сообщение.
  Future<SendMessageResult> execute(SendMessageParams params) async {
    AppLogger.info('Отправка сообщения: "${params.text}"');

    // ---- 1. Отправляем через Repository ----
    final response = await _repository.sendMessage(
      text: params.text,
      conversationId: params.sessionId,
      agentId: params.agentId,
    );

    // ---- 2. Формируем результат ----
    AppLogger.info(
      'Сообщение отправлено (агент=${response.model}, чат=${response.conversationId})',
    );

    return SendMessageResult(
      text: response.content,
      messageId: response.id,
      agentId: response.model,
      sessionId: response.conversationId,
      chatCreated: false,
    );
  }
}
