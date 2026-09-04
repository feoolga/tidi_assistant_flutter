// lib/domain/usecases/send_message_usecase.dart

import 'dart:async';
import '../../data/repositories/chat_repository.dart';
import '../../core/logger/app_logger.dart';
import '../../core/network/sse_parser.dart';

/// Событие в процессе стриминга ответа.
class StreamEvent {
  /// Тип события (например, 'delta', 'completed', 'error')
  final String type;

  /// Данные события
  final Map<String, dynamic> data;

  const StreamEvent({required this.type, required this.data});
}

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
  /// Отправить сообщение и получить поток событий.
  Stream<StreamEvent> execute(SendMessageParams params) {
    AppLogger.info('Отправка сообщения: "${params.text}"');

    // Создаём контроллер, который будет выдавать события
    final controller = StreamController<StreamEvent>();

    // Запускаем асинхронную работу
    _sendAndProcess(params, controller);

    // Возвращаем поток наружу
    return controller.stream;
  }

  /// Вспомогательный метод для отправки и обработки потока.
  void _sendAndProcess(
    SendMessageParams params,
    StreamController<StreamEvent> controller,
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
      String? messageId;
      String? agentId;
      String? conversationId;

      // 4. Обрабатываем каждое событие
      await for (final event in eventStream) {
        final eventType = event['_event_type'] as String;

        // --- Обработка разных типов событий ---
        if (eventType == 'response.output_text.delta') {
          // Получаем кусочек текста
          final delta = event['delta'] as String? ?? '';
          fullText += delta;

          // Отправляем событие наружу
          controller.add(
            StreamEvent(
              type: 'delta',
              data: {
                'text':
                    fullText, // Отправляем НАКОПЛЕННЫЙ текст, а не только delta!
                'delta': delta,
              },
            ),
          );
        } else if (eventType == 'response.completed') {
          // Извлекаем метаданные из финального события
          final responseData = event['response'] as Map<String, dynamic>?;
          if (responseData != null) {
            messageId = responseData['id'] as String?;
            agentId = responseData['model'] as String?;
            conversationId = responseData['conversation_id'] as String?;

            // Получаем usage (токены)
            final usage = responseData['usage'] as Map<String, dynamic>?;

            // Отправляем финальное событие
            controller.add(
              StreamEvent(
                type: 'completed',
                data: {
                  'messageId': messageId,
                  'agentId': agentId,
                  'conversationId': conversationId,
                  'usage': usage,
                  'fullText': fullText,
                },
              ),
            );
          }

          // Закрываем поток — всё готово
          controller.close();
          return;
        } else if (eventType == 'response.output_text.done') {
          // Это промежуточное событие — игнорируем, т.к. текст уже есть
          continue;
        }
        // Игнорируем остальные служебные события
      }

      // Если поток завершился без response.completed — закрываем с ошибкой
      controller.add(
        StreamEvent(
          type: 'error',
          data: {'error': 'Поток завершился без финального события'},
        ),
      );
      controller.close();
    } catch (error) {
      // Обработка ошибок
      AppLogger.error('Ошибка в SSE-потоке', error);
      controller.add(
        StreamEvent(type: 'error', data: {'error': error.toString()}),
      );
      controller.close();
    }
  }
}
