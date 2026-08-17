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

  // 👇 УБИРАЕМ defaultAgentId — теперь агент определяется сервером

  SendMessageUseCase({
    required MasterChatService chatService,
    required ChatHistoryService chatHistoryService,
  }) : _chatService = chatService,
       _chatHistoryService = chatHistoryService;

  Future<SendMessageResult> execute(SendMessageParams params) async {
    print('📤 UseCase: отправка сообщения "${params.text}"');

    String? agentId = params.agentId;
    String? sessionId = params.sessionId;
    bool chatCreated = false;

    // 👇 ЕСЛИ НЕТ СЕССИИ — НЕ СОЗДАЕМ ЧАТ, ИСПОЛЬЗУЕМ AUTO-РОУТИНГ
    if (agentId == null || sessionId == null) {
      print('🆕 UseCase: нет сессии, используем авто-роутинг (model: "auto")');
      // agentId и sessionId остаются null — сервер сам создаст сессию
    }

    // ---- Отправляем сообщение ----
    final result = await _chatService.sendMessage(
      text: params.text,
      agentId: agentId,    // может быть null
      sessionId: sessionId, // может быть null
    );

    print('✅ UseCase: сообщение отправлено');

    // ---- Формируем результат ----
    // Если сервер вернул agentId и sessionId — значит сессия создана
    final bool sessionCreated = result.agentId != null && result.sessionId != null;

    return SendMessageResult(
      text: result.text,
      messageId: result.messageId,
      agentId: result.agentId,
      sessionId: result.sessionId,
      chatCreated: sessionCreated,  // true, если сервер создал сессию
    );
  }
}