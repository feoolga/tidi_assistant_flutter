// lib/domain/services/chat_stream_handler.dart

import 'dart:async';
import '../../core/errors/business_exceptions.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logger/app_logger.dart';
import '../../data/models/chat_response_dto.dart';
import 'chat_stream_event.dart';

/// Обработчик SSE-стрима.
///
/// Преобразует сырой поток ChatResponseDto в семантические
/// ChatStreamEvent, понятные notifier'у.
///
/// Ответственности:
/// - Склейка текста из дельт (fullText)
/// - Определение момента завершения
/// - Извлечение метаданных (messageId, agentId, conversationId)
/// - Преобразование ошибок в AppException
class ChatStreamHandler {
  /// Преобразует поток DTO в поток событий.
  ///
  /// Гарантии:
  /// - В потоке будет ровно один ChatStreamStarted (в начале)
  /// - После завершения: ровно один ChatStreamCompleted ИЛИ ChatStreamFailed
  /// - Никогда не будет ChatStreamCompleted после ChatStreamFailed
  Stream<ChatStreamEvent> handle(Stream<ChatResponseDto> source) {
    // 1. Создаём контроллер — через него будем эмитить события наружу.
    final controller = StreamController<ChatStreamEvent>();

    // 2. Переменная для подписки на source.
    //    late — потому что присвоим позже, но использовать будем сразу.
    late StreamSubscription<ChatResponseDto> subscription;

    controller.add(const ChatStreamStarted());

    // 5. Переменные состояния обработки.
    //    Живут между вызовами onData — накапливают текст и флаг завершения.
    String fullText = '';
    bool isCompleted = false;

    subscription = source.listen(
      (dto) {
        // --- ШАГ А: обновляем накопленный текст ---
        fullText = dto.content;

        // --- ШАГ Б: проверяем, это дельта или финал ---
        if (dto.isStreaming) {
          // Стрим ещё идёт — эмитим промежуточное событие
          controller.add(ChatStreamDelta(fullText: fullText));
        } else {
          // Стрим завершён — эмитим финальное событие
          controller.add(
            ChatStreamCompleted(
              fullText: fullText,
              messageId: dto.id.isEmpty ? null : dto.id,
              agentId: dto.model,
              conversationId: dto.conversationId,
            ),
          );

          isCompleted = true;
          controller.close();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Преобразуем любую ошибку в AppException
        final appException = ErrorHandler.handle(error);

        // Логируем со стектрейсом — для отладки
        AppLogger.logException('Ошибка в SSE-стриме', appException, stackTrace);

        // Эмитим событие об ошибке и закрываем контроллер
        controller.add(ChatStreamFailed(error: appException));
        controller.close();
      },
      onDone: () {
        // Если стрим закончился, а ChatStreamCompleted не пришёл —
        // это нарушение контракта сервера. Считаем ошибкой.
        if (!isCompleted) {
          AppLogger.warning('Поток завершился без ChatStreamCompleted');

          controller.add(
            ChatStreamFailed(
              error: BusinessException.streamError(
                'Поток завершился без финального события',
              ),
            ),
          );
        }

        controller.close();
      },
    );

    // 6. Если клиент отпишется от controller.stream — отписываемся от source.
    //    Без этого source продолжит присылать данные в никуда (утечка).
    controller.onCancel = () {
      AppLogger.debug('Клиент отписался — отменяем подписку на source');
      subscription.cancel();
    };

    return controller.stream;
  }
}
