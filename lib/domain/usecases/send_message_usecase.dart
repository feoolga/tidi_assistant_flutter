// lib/domain/usecases/send_message_usecase.dart

import '../../services/master_chat_service.dart';
import '../../services/chat_history_service.dart';
import '../../models/chat_session.dart';
import '../../models/message.dart';  // 👈 ДОБАВЛЯЕМ

/// Параметры для отправки сообщения
class SendMessageParams {
  final String text;
  final List<Message> history;  // 👈 ДОБАВЛЯЕМ — ВСЯ ИСТОРИЯ
  final String? agentId;
  final String? sessionId;

  const SendMessageParams({
    required this.text,
    required this.history,  // 👈 ДОБАВЛЯЕМ
    this.agentId,
    this.sessionId,
  });

  /// Есть ли активная сессия
  bool get hasSession => agentId != null && sessionId != null;
}

/// Результат отправки сообщения
class SendMessageResult {
  final String text;
  final String? messageId;
  final String? agentId;
  final String? sessionId;
  final bool chatCreated;

  const SendMessageResult({
    required this.text,
    this.messageId,
    this.agentId,
    this.sessionId,
    this.chatCreated = false,
  });
}

/// UseCase для отправки сообщения
class SendMessageUseCase {
  final MasterChatService _chatService;
  final ChatHistoryService _chatHistoryService;

  SendMessageUseCase({
    required MasterChatService chatService,
    required ChatHistoryService chatHistoryService,
  }) : _chatService = chatService,
       _chatHistoryService = chatHistoryService;

  Future<SendMessageResult> execute(SendMessageParams params) async {
    print('📤 UseCase: отправка сообщения "${params.text}"');
    print('📤 История: ${params.history.length} сообщений');

    String? agentId = params.agentId;
    String? sessionId = params.sessionId;
    bool chatCreated = false;

    // ---- 1. Если нет сессии, используем авто-роутинг ----
    if (agentId == null || sessionId == null) {
      print('🆕 UseCase: нет сессии, авто-роутинг (model: "auto")');
    }

    // ---- 2. Строим историю для отправки ----
    // Добавляем новое сообщение пользователя в конец истории
    final List<Message> fullHistory = [
      ...params.history,
      Message.fromUser(text: params.text),  // 👈 новое сообщение
    ];

    // ---- 3. Отправляем сообщение ----
    final result = await _chatService.sendMessage(
      messages: fullHistory,           // 👈 ВСЯ история
      conversationId: sessionId,       // 👈 ID чата (если есть)
      forceAgentId: agentId,           // 👈 принудительный агент (если есть)
    );

    print('✅ UseCase: сообщение отправлено');

    // ---- 4. Формируем результат ----
    final bool sessionCreated = result.agentId != null && result.sessionId != null;

    return SendMessageResult(
      text: result.text,
      messageId: result.messageId,
      agentId: result.agentId,
      sessionId: result.sessionId,
      chatCreated: sessionCreated,
    );
  }
}