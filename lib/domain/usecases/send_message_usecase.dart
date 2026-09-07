// lib/domain/usecases/send_message_usecase.dart

import 'dart:async';
import '../../data/repositories/chat_repository.dart';
import '../../data/models/chat_response_dto.dart';
import '../../core/logger/app_logger.dart';
import '../../core/network/sse_parser.dart';
import '../../core/errors/error_handler.dart';

// ============================================================
// 1. ПАРАМЕТРЫ
// ============================================================

/// Параметры для отправки сообщения.
class SendMessageParams {
  final String text;
  final String? agentId;
  final String? sessionId;

  const SendMessageParams({required this.text, this.agentId, this.sessionId});

  bool get hasSession => agentId != null && sessionId != null;
}

// ============================================================
// 2. USECASE
// ============================================================

/// UseCase для отправки сообщения.
///
/// Отвечает на вопрос: "Что делает приложение, когда пользователь отправляет сообщение?"
///
/// Возвращает поток ChatResponseDto — чистых данных без UI-логики.
class SendMessageUseCase {
  final ChatRepository _repository;

  SendMessageUseCase({required ChatRepository repository})
    : _repository = repository;

  /// Выполнить сценарий: отправить сообщение.
  /// Отправить сообщение и получить поток DTO.
  Stream<ChatResponseDto> execute(SendMessageParams params) {
    AppLogger.info('Отправка сообщения: "${params.text}"');

    final controller = StreamController<ChatResponseDto>();
    _sendAndProcess(params, controller);
    return controller.stream;
  }

  void _sendAndProcess(
    SendMessageParams params,
    StreamController<ChatResponseDto> controller,
  ) async {
    try {
      // 1. Отправляем запрос и получаем StreamedResponse
      final response = await _repository.sendMessageStream(
        text: params.text,
        conversationId: params.sessionId,
        agentId: params.agentId,
      );

      // 2. Парсим SSE-поток
      final eventStream = SseParser.parse(response);

      // 3. Переменные для сборки ответа
      String fullText = '';

      // 4. Обрабатываем каждое событие
      await for (final event in eventStream) {
        final eventType = event['_event_type'] as String;

        if (eventType == 'response.output_text.delta') {
          // Получаем кусочек текста
          final delta = event['delta'] as String? ?? '';
          fullText += delta;

          // ✅ Отправляем частичный DTO (isStreaming = true)
          controller.add(
            ChatResponseDto(
              id: '',
              model: params.agentId ?? 'auto',
              conversationId: params.sessionId,
              content: fullText,
              isStreaming: true,
            ),
          );
        } else if (eventType == 'response.completed') {
          // Извлекаем метаданные из финального события
          final responseData = event['response'] as Map<String, dynamic>?;
          if (responseData != null) {
            final messageId = responseData['id'] as String?;
            final agentId = responseData['model'] as String?;
            final conversationId = responseData['conversation_id'] as String?;

            // ✅ Отправляем финальный DTO (isStreaming = false)
            controller.add(
              ChatResponseDto(
                id: messageId ?? '',
                model: agentId ?? params.agentId ?? 'auto',
                conversationId: conversationId ?? params.sessionId,
                content: fullText,
                isStreaming: false,
              ),
            );
          }

          // Закрываем поток — всё готово
          controller.close();
          return;
        }
        // Игнорируем остальные служебные события
      }

      // Если поток завершился без response.completed — просто закрываем
      AppLogger.warning('Поток завершился без финального события');
      controller.close();
    } catch (error, stackTrace) {
      // Преобразуем ошибку
      final appException = ErrorHandler.handle(error);
      AppLogger.logException('Ошибка в SSE-потоке', appException, stackTrace);

      // Отправляем ошибку в поток
      controller.addError(appException);
      controller.close();
    }
  }
}
