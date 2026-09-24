// test/data/models/chat_session_dto_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/data/models/chat_session_dto.dart';

void main() {
  // ============================================================
  // Успешный парсинг
  // ============================================================

  group('валидный JSON', () {
    test('парсит все поля', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-123',
        'title': 'Мой чат',
        'created_at': '2026-11-05T14:35:00',
        'updated_at': '2026-11-05T15:00:00',
      });

      expect(dto.id, 'chat-123');
      expect(dto.title, 'Мой чат');
      expect(dto.createdAt, DateTime(2026, 11, 5, 14, 35));
      expect(dto.updatedAt, DateTime(2026, 11, 5, 15, 0));
    });

    test('id числом приводится к строке', () {
      final dto = ChatSessionDto.fromJson({
        'id': 42,
        'created_at': '2026-11-05T14:35:00',
        'updated_at': '2026-11-05T14:35:00',
      });

      expect(dto.id, '42');
    });

    test('title = null — допустимо', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'title': null,
        'created_at': '2026-11-05T14:35:00',
        'updated_at': '2026-11-05T14:35:00',
      });

      expect(dto.title, isNull);
    });
  });

  // ============================================================
  // Устойчивость к невалидным датам → null
  // ============================================================

  group('невалидные даты → null (не DateTime.now)', () {
    test('created_at = null → createdAt = null', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'created_at': null,
        'updated_at': '2026-11-05T14:35:00',
      });

      expect(dto.createdAt, isNull);
      // updatedAt не тронут — парсится как обычно.
      expect(dto.updatedAt, DateTime(2026, 11, 5, 14, 35));
    });

    test('created_at = пустая строка → createdAt = null', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'created_at': '',
        'updated_at': '2026-11-05T14:35:00',
      });

      expect(dto.createdAt, isNull);
    });

    test('created_at = невалидная ISO-строка → createdAt = null', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'created_at': 'это не дата',
        'updated_at': '2026-11-05T14:35:00',
      });

      expect(dto.createdAt, isNull);
    });

    test('created_at = число → createdAt = null', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'created_at': 1730000000,
        'updated_at': '2026-11-05T14:35:00',
      });

      expect(dto.createdAt, isNull);
    });

    test('updated_at = null → updatedAt = null, createdAt не тронут', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'created_at': '2026-11-05T14:35:00',
        'updated_at': null,
      });

      expect(dto.createdAt, DateTime(2026, 11, 5, 14, 35));
      expect(dto.updatedAt, isNull);
    });

    test('обе даты null → обе null', () {
      final dto = ChatSessionDto.fromJson({
        'id': 'chat-1',
        'created_at': null,
        'updated_at': null,
      });

      expect(dto.createdAt, isNull);
      expect(dto.updatedAt, isNull);
    });
  });
}
