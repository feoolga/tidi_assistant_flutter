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

  /// Ошибка, **присланная** сервером в SSE-событии `error` (или
  /// `response.error` — см. `SendMessageUseCase._parseErrorEvent`).
  ///
  /// **Почему `userMessage` не включает [serverMessage].** Текст от
  /// сервера — **технический** (например, «LLMError: ollama вернула
  /// невалидный JSON...»). Пользователю он **не помогает** — только
  /// пугает. Показываем **общее** сообщение, а [serverMessage] уходит
  /// в [technicalDetails] — для логов и отладки.
  ///
  /// **Отличие от [streamEndedUnexpectedly].** Здесь сервер **ответил**
  /// (прислал `event: error`), но в **ответе** — ошибка. Например,
  /// модель не смогла сгенерировать валидный JSON. Код `STREAM_ERROR`
  /// говорит: «сервер **сам** сообщил об ошибке».
  ///
  /// [serverMessage] — текст из поля `error.message` ответа сервера.
  factory BusinessException.streamError(String serverMessage) {
    return BusinessException(
      code: 'STREAM_ERROR',
      userMessage: 'Сервер сообщил об ошибке. Попробуйте ещё раз.',
      technicalDetails: serverMessage,
    );
  }

  /// SSE-поток **закрылся сам**, не прислав финального события
  /// `response.completed`.
  ///
  /// **Когда бывает.** Соединение открылось (HTTP `200`), но **оборвалось**
  /// до финала: сетевой сбой, прокси разорвал соединение, сервер закрыл
  /// поток без терминатора, что-то ещё. Это **не** `event: error` — там
  /// сервер **сам** сказал, что не смог; здесь сервер **промолчал**.
  ///
  /// **Отличие от [streamError].** `streamError` — сервер **ответил**
  /// ошибкой. `streamEndedUnexpectedly` — сервер **не ответил вообще**.
  /// Разные `code` — потому что причины разные, и в аналитике их полезно
  /// **различать**.
  ///
  /// **Про watchdog.** Если поток **молчит** 60 секунд (настраивается в
  /// `AppConfig.streamInactivityTimeout`), сработает watchdog — он эмитит
  /// `NetworkException.timeout`, а **не** эту ошибку. Здесь — **другой**
  /// случай: поток **закрылся** (не молчал), просто **без** финала.
  factory BusinessException.streamEndedUnexpectedly() {
    return BusinessException(
      code: 'STREAM_ENDED_UNEXPECTEDLY',
      userMessage: 'Соединение с сервером прервалось. Попробуйте ещё раз.',
      technicalDetails: 'Stream ended without terminal event',
    );
  }

  /// Не удалось создать чат.
  ///
  /// **Пока НЕ используется** — фабрика **зарезервирована** на будущее
  /// (например, для точечной обработки «создание чата упало» в
  /// `ChatRepository`). Сейчас в проекте все ошибки создания чата
  /// проходят через общий `ErrorHandler.handle`.
  ///
  /// **Потенциальная проблема.** Если [reason] — **технический**
  /// (например, текст от сервера), он **просочится** в `userMessage`.
  /// **Перед** тем как начать использовать эту фабрику — пересмотреть:
  /// вынести технические детали в `technicalDetails`, оставить в
  /// `userMessage` — **дружелюбный** текст.
  ///
  /// TODO: решить судьбу фабрики — использовать или удалить как мёртвый код.
  factory BusinessException.createChatFailed(String reason) {
    return BusinessException(
      code: 'CREATE_CHAT_FAILED',
      userMessage: 'Не удалось создать чат: $reason',
      technicalDetails: reason,
    );
  }
}
