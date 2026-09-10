import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/chat_response_dto.dart';

void main() {
  // ============================================================
  // ФАБРИКА ДЛЯ ТЕСТОВЫХ ДАННЫХ
  // ============================================================

  /// Создаёт "эталонный" DTO для тестов.
  /// Если понадобится поменять поля — меняем только здесь.
  ChatResponseDto buildDto() => const ChatResponseDto(
    id: 'resp_123',
    model: 'epoz',
    conversationId: 'conv_abc',
    content: 'Привет',
    isStreaming: false,
  );

  // ============================================================
  // ГРУППА: copyWith
  // ============================================================

  group('ChatResponseDto.copyWith', () {
    test('без параметров возвращает копию с теми же полями', () {
      final dto = buildDto();
      final copy = dto.copyWith();

      expect(copy.id, 'resp_123');
      expect(copy.model, 'epoz');
      expect(copy.conversationId, 'conv_abc');
      expect(copy.content, 'Привет');
      expect(copy.isStreaming, false);
    });

    test('сбрасывает conversationId в null через sentinel', () {
      final dto = buildDto();
      final cleared = dto.copyWith(conversationId: null);

      // Главная проверка: null действительно записался, а не проигнорировался
      expect(cleared.conversationId, isNull);

      // Остальные поля не тронуты
      expect(cleared.id, 'resp_123');
      expect(cleared.model, 'epoz');
      expect(cleared.content, 'Привет');
    });

    test('изменяет content и НЕ трогает остальные поля', () {
      final dto = buildDto();
      final updated = dto.copyWith(content: 'Пока');

      expect(updated.content, 'Пока');
      expect(updated.id, 'resp_123');
      expect(updated.conversationId, 'conv_abc');
    });

    test('изменяет id и model', () {
      final dto = buildDto();
      final updated = dto.copyWith(id: 'resp_999', model: 'chat');

      expect(updated.id, 'resp_999');
      expect(updated.model, 'chat');
      expect(updated.content, 'Привет');
    });

    test('изменяет isStreaming с true на false', () {
      final dto = buildDto();
      final streaming = dto.copyWith(isStreaming: true);

      expect(streaming.isStreaming, true);
    });

    test('устанавливает conversationId при первом появлении (был null)', () {
      const dto = ChatResponseDto(
        id: 'x',
        model: 'auto',
        content: '',
      ); // conversationId = null по умолчанию

      final updated = dto.copyWith(conversationId: 'new_conv');

      expect(updated.conversationId, 'new_conv');
    });
  });

  // ============================================================
  // ГРУППА: КОНСТРУКТОРЫ
  // ============================================================

  group('ChatResponseDto', () {
    test('empty() создаёт пустой DTO с isStreaming=true', () {
      final dto = ChatResponseDto.empty();

      expect(dto.id, '');
      expect(dto.model, 'auto');
      expect(dto.conversationId, isNull);
      expect(dto.content, '');
      expect(dto.isStreaming, true);
    });

    test('конструктор по умолчанию ставит isStreaming=true', () {
      const dto = ChatResponseDto(id: 'x', model: 'auto', content: '');

      expect(dto.isStreaming, true);
    });
  });

  // ============================================================
  // ГРУППА: toString
  // ============================================================

  group('ChatResponseDto.toString', () {
    test('возвращает читаемое представление', () {
      final dto = buildDto();
      final str = dto.toString();

      expect(str, contains('resp_123'));
      expect(str, contains('epoz'));
      expect(str, contains('conv_abc'));
      expect(str, contains('contentLength: 6')); // "Привет" = 6 символов
    });
  });
}
