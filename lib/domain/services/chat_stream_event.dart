// lib/domain/services/chat_stream_event.dart

import '../../core/errors/app_exception.dart';

/// Семантические события, которые эмитит ChatStreamHandler.
///
/// sealed — потому что набор событий фиксирован.
/// Компилятор проверит, что все случаи обработаны в switch.
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// Хендлер начал обрабатывать стрим.
/// Notifier может использовать это, чтобы показать TypingIndicator
/// или сбросить состояние ошибки.
final class ChatStreamStarted extends ChatStreamEvent {
  const ChatStreamStarted();
}

/// Пришла новая порция текста (дельта).
///
/// [fullText] — полный текст на данный момент (не дельта!).
/// Мы специально отдаём полный текст, а не дельту,
/// чтобы notifier не занимался склейкой строк.
final class ChatStreamDelta extends ChatStreamEvent {
  final String fullText;

  const ChatStreamDelta({required this.fullText});
}

/// Стрим успешно завершён.
///
/// Все метаданные уже собраны — notifier просто обновит последнее
/// сообщение и (если нужно) переключит сессию.
final class ChatStreamCompleted extends ChatStreamEvent {
  final String fullText;
  final String? messageId;
  final String? agentId;
  final String? conversationId;

  const ChatStreamCompleted({
    required this.fullText,
    this.messageId,
    this.agentId,
    this.conversationId,
  });
}

/// Стрим упал с ошибкой.
///
/// Ошибка уже преобразована в AppException.
/// Notifier просто покажет [error.userMessage] пользователю.
final class ChatStreamFailed extends ChatStreamEvent {
  final AppException error;

  const ChatStreamFailed({required this.error});
}
