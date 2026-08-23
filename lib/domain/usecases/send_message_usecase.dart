// lib/domain/usecases/send_message_usecase.dart

import '../../data/repositories/chat_repository.dart';
import '../models/message.dart';

// ============================================================
// 1. ПАРАМЕТРЫ
// ============================================================

/// Параметры для отправки сообщения.
class SendMessageParams {
  /// Текст сообщения пользователя
  final String text;

  /// Вся история диалога (сообщения пользователя и AI)
  final List<Message> history;

  /// ID агента (если уже знаем, кого вызывать)
  final String? agentId;

  /// ID сессии/чата (если продолжаем диалог)
  final String? sessionId;

  const SendMessageParams({
    required this.text,
    required this.history,
    this.agentId,
    this.sessionId,
  });

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
/// 1. Берет историю сообщений
/// 2. Добавляет новое сообщение пользователя
/// 3. Отправляет всё в Repository
/// 4. Возвращает ответ
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
    print('📤 UseCase: отправка сообщения "${params.text}"');
    print('📤 История: ${params.history.length} сообщений');

    // ---- 1. Формируем полную историю ----
    // Добавляем новое сообщение пользователя в конец
    final fullHistory = [
      ...params.history,
      Message.fromUser(text: params.text),
    ];

    // ---- 2. Отправляем через Repository ----
    // ВНИМАНИЕ! sendMessage пока возвращает ошибку,
    // потому что бэкенд еще не починен.
    // Как только починят — этот код заработает.
    final response = await _repository.sendMessage(
      messages: fullHistory,
      conversationId: params.sessionId,
      forceAgentId: params.agentId,
    );

    // ---- 3. Формируем результат ----
    print('✅ UseCase: сообщение отправлено');
    print(
      '🔵 UseCase: агент=${response.model}, чат=${response.conversationId}',
    );

    return SendMessageResult(
      text: response.content,
      messageId: response.id,
      agentId: response.model,
      sessionId: response.conversationId,
      chatCreated: false, // TODO: определить, создался ли новый чат
    );
  }
}
