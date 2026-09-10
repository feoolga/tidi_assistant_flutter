import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/chat_response_dto.dart';
import 'package:tidi_assistant_flutter/domain/services/chat_stream_event.dart';
import 'package:tidi_assistant_flutter/domain/services/chat_stream_handler.dart';

void main() {
  late ChatStreamHandler handler;

  setUp(() {
    handler = ChatStreamHandler();
  });

  // ============================================================
  // ХЕЛПЕР: создаёт DTO дельты
  // ============================================================
  ChatResponseDto delta(String content) => ChatResponseDto(
    id: '',
    model: 'auto',
    content: content,
    isStreaming: true,
  );

  // ============================================================
  // ХЕЛПЕР: создаёт финальный DTO
  // ============================================================
  ChatResponseDto completed({
    String content = 'Привет!',
    String id = 'resp_1',
    String model = 'epoz',
    String? conversationId = 'conv_1',
  }) => ChatResponseDto(
    id: id,
    model: model,
    content: content,
    conversationId: conversationId,
    isStreaming: false,
  );

  // ============================================================
  // УСПЕШНЫЙ СЦЕНАРИЙ
  // ============================================================

  group('успешный стрим', () {
    test('эмитит Started, Delta-ы и Completed в правильном порядке', () async {
      final source = Stream.fromIterable([
        delta('При'),
        delta('Привет'),
        delta('Привет!'),
        completed(content: 'Привет!'),
      ]);

      final events = await handler.handle(source).toList();

      expect(events, hasLength(5));
      expect(events[0], isA<ChatStreamStarted>());

      expect(events[1], isA<ChatStreamDelta>());
      expect((events[1] as ChatStreamDelta).fullText, 'При');

      expect(events[2], isA<ChatStreamDelta>());
      expect((events[2] as ChatStreamDelta).fullText, 'Привет');

      expect(events[3], isA<ChatStreamDelta>());
      expect((events[3] as ChatStreamDelta).fullText, 'Привет!');

      expect(events[4], isA<ChatStreamCompleted>());
    });

    test('Completed содержит все метаданные', () async {
      final source = Stream.fromIterable([
        delta('Привет!'),
        completed(
          content: 'Привет!',
          id: 'resp_42',
          model: 'epoz',
          conversationId: 'conv_abc',
        ),
      ]);

      final events = await handler.handle(source).toList();
      final done = events.last as ChatStreamCompleted;

      expect(done.fullText, 'Привет!');
      expect(done.messageId, 'resp_42');
      expect(done.agentId, 'epoz');
      expect(done.conversationId, 'conv_abc');
    });

    test('если id пустой — messageId в Completed = null', () async {
      final source = Stream.fromIterable([completed(id: '', content: 'hi')]);

      final events = await handler.handle(source).toList();
      final done = events.last as ChatStreamCompleted;

      expect(done.messageId, isNull);
    });

    test('если conversationId отсутствует — в Completed = null', () async {
      final source = Stream.fromIterable([completed(conversationId: null)]);

      final events = await handler.handle(source).toList();
      final done = events.last as ChatStreamCompleted;

      expect(done.conversationId, isNull);
    });

    test('без дельт (только финал) — только Started и Completed', () async {
      final source = Stream.fromIterable([completed()]);

      final events = await handler.handle(source).toList();

      expect(events, hasLength(2));
      expect(events[0], isA<ChatStreamStarted>());
      expect(events[1], isA<ChatStreamCompleted>());
    });
  });

  // ============================================================
  // ОШИБКА В ИСТОЧНИКЕ
  // ============================================================

  group('ошибка в source', () {
    test('эмитит ChatStreamFailed с AppException', () async {
      final source = Stream<ChatResponseDto>.error(Exception('network down'));

      final events = await handler.handle(source).toList();

      expect(events, hasLength(2));
      expect(events[0], isA<ChatStreamStarted>());
      expect(events[1], isA<ChatStreamFailed>());
    });

    test('после ошибки поток закрывается (нет зависания)', () async {
      final source = Stream<ChatResponseDto>.error(Exception('boom'));

      // Без .timeout() — если поток НЕ закроется, тест зависнет
      // и упадёт по общему таймауту flutter test (30 сек)
      final events = await handler.handle(source).toList();

      expect(events.last, isA<ChatStreamFailed>());
    });

    test('ошибка после дельт — всё равно Failed, не Completed', () async {
      // Собираем поток вручную: сначала дельта, потом ошибка
      final sourceController = StreamController<ChatResponseDto>();

      // Слушаем события в фоне, пока не закроется
      final eventsFuture = handler.handle(sourceController.stream).toList();

      // Отправляем дельту и ждём её обработки
      sourceController.add(delta('При'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Отправляем ошибку — она завершит поток
      sourceController.addError(Exception('boom'));

      // Ждём все события
      final events = await eventsFuture;

      expect(events.first, isA<ChatStreamStarted>());
      expect(events.last, isA<ChatStreamFailed>());
      expect(events.whereType<ChatStreamCompleted>(), isEmpty);
    });
  });

  // ============================================================
  // ОБРЫВ БЕЗ COMPLETED
  // ============================================================

  group('обрыв без Completed', () {
    test('source закончился без Completed → ChatStreamFailed', () async {
      final source = Stream.fromIterable([
        delta('При'),
        delta('Привет'),
        // нет completed
      ]);

      final events = await handler.handle(source).toList();

      expect(events.first, isA<ChatStreamStarted>());
      expect(events.last, isA<ChatStreamFailed>());
    });

    test('пустой source → Started + Failed', () async {
      final source = Stream<ChatResponseDto>.empty();

      final events = await handler.handle(source).toList();

      expect(events, hasLength(2));
      expect(events[0], isA<ChatStreamStarted>());
      expect(events[1], isA<ChatStreamFailed>());
    });
  });

  // ============================================================
  // ОТПИСКА КЛИЕНТА (onCancel)
  // ============================================================

  group('отписка клиента', () {
    test('отписка закрывает поток без ошибок', () async {
      // Управляемый источник — сами решаем, когда что эмитить
      final sourceController = StreamController<ChatResponseDto>();

      final stream = handler.handle(sourceController.stream);
      final subscription = stream.listen((_) {});

      // Добавили одну дельту
      sourceController.add(delta('При'));
      await Future.delayed(const Duration(milliseconds: 10));

      // Отписались до завершения
      await subscription.cancel();

      // Закрываем источник — не должно быть ошибок
      await sourceController.close();

      // Если дошли сюда без исключений — тест пройден
      expect(true, isTrue);
    });
  });
}
