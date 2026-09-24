// test/domain/models/chat_session_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/chat_session.dart';

void main() {
  group('ChatSession.displayTitle', () {
    // ============================================================
    // Есть title — используем его
    // ============================================================

    test('возвращает title, если он есть', () {
      final session = ChatSession(
        id: '1',
        agentId: 'epoz',
        title: 'Мой чат',
        createdAt: DateTime(2026, 3, 15),
        updatedAt: DateTime(2026, 3, 15),
      );

      expect(session.displayTitle, 'Мой чат');
    });

    // ============================================================
    // Нет title, но есть createdAt — «Чат от <дата>»
    // ============================================================

    test('возвращает дату, если title пустой', () {
      final session = ChatSession(
        id: '1',
        agentId: 'epoz',
        title: null,
        createdAt: DateTime(2026, 3, 15),
        updatedAt: DateTime(2026, 3, 15),
      );

      expect(session.displayTitle, 'Чат от 15.03.2026');
    });

    test('возвращает дату, если title — пустая строка', () {
      final session = ChatSession(
        id: '1',
        agentId: 'epoz',
        title: '',
        createdAt: DateTime(2026, 1, 5),
        updatedAt: DateTime(2026, 1, 5),
      );

      expect(session.displayTitle, 'Чат от 05.01.2026');
    });

    // ============================================================
    // Нет title и нет createdAt — «Чат (дата неизвестна)»
    // ============================================================

    test('возвращает «дата неизвестна», если createdAt = null', () {
      final session = ChatSession(
        id: '1',
        agentId: 'epoz',
        title: null,
        createdAt: null,
        updatedAt: null,
      );

      expect(session.displayTitle, 'Чат (дата неизвестна)');
    });

    test('возвращает «дата неизвестна», если createdAt = null '
        'и title — пустая строка', () {
      final session = ChatSession(
        id: '1',
        agentId: 'epoz',
        title: '',
        createdAt: null,
        updatedAt: null,
      );

      expect(session.displayTitle, 'Чат (дата неизвестна)');
    });

    // ============================================================
    // title всё равно важнее даты
    // ============================================================

    test('title имеет приоритет над датой', () {
      final session = ChatSession(
        id: '1',
        agentId: 'epoz',
        title: 'Важный чат',
        createdAt: null, // даже при отсутствии даты
        updatedAt: null,
      );

      expect(session.displayTitle, 'Важный чат');
    });
  });
}
