// lib/core/errors/business_exceptions.dart

import 'app_exception.dart';

/// Ошибки бизнес-логики.
///
/// Например: сообщение не может быть пустым, агент не найден и т.д.
class BusinessException extends AppException {
  const BusinessException({
    required super.code,
    required super.userMessage,
    super.technicalDetails,
    super.originalError,
  });

  /// Агент не найден
  factory BusinessException.agentNotFound(String agentId) {
    return BusinessException(
      code: 'AGENT_NOT_FOUND',
      userMessage: 'Агент "$agentId" не найден.',
      technicalDetails: 'Agent with id "$agentId" not found',
    );
  }

  /// Чат не найден
  factory BusinessException.chatNotFound(String chatId) {
    return BusinessException(
      code: 'CHAT_NOT_FOUND',
      userMessage: 'Чат не найден.',
      technicalDetails: 'Chat with id "$chatId" not found',
    );
  }

  /// Сообщение не может быть пустым
  factory BusinessException.emptyMessage() {
    return BusinessException(
      code: 'EMPTY_MESSAGE',
      userMessage: 'Сообщение не может быть пустым.',
    );
  }

  /// Ошибка в потоке SSE
  factory BusinessException.streamError(String message) {
    return BusinessException(
      code: 'STREAM_ERROR',
      userMessage: 'Ошибка при получении ответа: $message',
      technicalDetails: message,
    );
  }

  /// Не удалось создать чат
  factory BusinessException.createChatFailed(String reason) {
    return BusinessException(
      code: 'CREATE_CHAT_FAILED',
      userMessage: 'Не удалось создать чат: $reason',
      technicalDetails: reason,
    );
  }
}
