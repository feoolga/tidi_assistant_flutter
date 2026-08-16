// lib/domain/usecases/send_message_usecase.dart

import '../../services/master_chat_service.dart';
import '../../services/chat_history_service.dart';
import '../../models/chat_session.dart';

/// Параметры для отправки сообщения
class SendMessageParams {
  final String text;
  final String? agentId;
  final String? sessionId;

  const SendMessageParams({
    required this.text,
    this.agentId,
    this.sessionId,
  });

  /// Есть ли активная сессия
  bool get hasSession => agentId != null && sessionId != null;
}

/// Результат отправки сообщения
class SendMessageResult {
  /// Текст ответа от AI
  final String text;

  /// ID сообщения
  final String? messageId;

  /// ID агента, который обработал запрос
  final String? agentId;

  /// ID сессии (чата) на сервере
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

  /// Есть ли информация об агенте
  bool get hasAgentInfo => agentId != null && sessionId != null;

  /// Создать копию с новыми данными сессии
  SendMessageResult copyWithSession({
    String? agentId,
    String? sessionId,
  }) {
    return SendMessageResult(
      text: text,
      messageId: messageId,
      agentId: agentId ?? this.agentId,
      sessionId: sessionId ?? this.sessionId,
      chatCreated: chatCreated,
    );
  }
}

/// UseCase для отправки сообщения
///
/// Отвечает за всю бизнес-логику отправки сообщения:
/// 1. Проверка наличия сессии
/// 2. Создание нового чата, если сессии нет
/// 3. Отправка сообщения через MasterChatService
/// 4. Возврат результата с обновленной информацией о сессии
class SendMessageUseCase {
  final MasterChatService _chatService;
  final ChatHistoryService _chatHistoryService;

  /// ID агента по умолчанию для создания нового чата
  static const String defaultAgentId = 'chat';

  SendMessageUseCase({
    required MasterChatService chatService,
    required ChatHistoryService chatHistoryService,
  }) : _chatService = chatService,
       _chatHistoryService = chatHistoryService;

  /// Выполнить отправку сообщения
  ///
  /// [params] — параметры запроса
  ///
  /// Возвращает [SendMessageResult] с ответом и обновленной сессией
  Future<SendMessageResult> execute(SendMessageParams params) async {
    print('📤 UseCase: отправка сообщения "${params.text}"');

    // ---- Шаг 1: Определяем сессию ----
    String? agentId = params.agentId;
    String? sessionId = params.sessionId;
    bool chatCreated = false;

    // Если нет сессии — создаем новый чат
    if (agentId == null || sessionId == null) {
      print('🆕 UseCase: создаем новый чат...');

      final newChat = await _chatHistoryService.createChat(defaultAgentId);
      agentId = newChat.agentId;
      sessionId = newChat.id;
      chatCreated = true;

      print('✅ UseCase: создан чат: agentId=$agentId, sessionId=$sessionId');
    }

    // ---- Шаг 2: Отправляем сообщение ----
    final result = await _chatService.sendMessage(
      text: params.text,
      agentId: agentId,
      sessionId: sessionId,
    );

    print('✅ UseCase: сообщение отправлено');

    // ---- Шаг 3: Формируем результат ----
    // Если сервер вернул новые agentId/sessionId — используем их
    final String? finalAgentId = result.agentId ?? agentId;
    final String? finalSessionId = result.sessionId ?? sessionId;

    // Проверяем, изменилась ли сессия
    final bool sessionChanged =
        (result.agentId != null && result.agentId != agentId) ||
        (result.sessionId != null && result.sessionId != sessionId);

    if (sessionChanged) {
      print('🔄 UseCase: сессия обновлена: agentId=$finalAgentId, sessionId=$finalSessionId');
    }

    return SendMessageResult(
      text: result.text,
      messageId: result.messageId,
      agentId: finalAgentId,
      sessionId: finalSessionId,
      chatCreated: chatCreated,
    );
  }
}