import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/message.dart';

void main() {
  // Готовим "эталонное" сообщение, чтобы не писать его в каждом тесте
  Message buildMessage() => Message(
    id: '1',
    text: 'Привет',
    isFromUser: false,
    timestamp: DateTime(2026, 1, 1),
    agentId: 'epoz',
    sessionId: 's1',
  );

  // --- БАЗОВЫЙ ТЕСТ: ничего не сломалось ---
  test('copyWith без параметров возвращает копию с теми же полями', () {
    final msg = buildMessage();
    final copy = msg.copyWith();

    expect(copy.text, 'Привет');
    expect(copy.agentId, 'epoz');
    expect(copy.sessionId, 's1');
  });

  // --- ГЛАВНЫЙ ТЕСТ: тот самый sentinel ---
  test('copyWith сбрасывает agentId в null', () {
    final msg = buildMessage();
    final cleared = msg.copyWith(agentId: null);

    expect(cleared.agentId, isNull);
    expect(cleared.sessionId, 's1'); // не тронули — осталось
  });

  test('copyWith сбрасывает sessionId в null', () {
    final msg = buildMessage();
    final cleared = msg.copyWith(sessionId: null);

    expect(cleared.sessionId, isNull);
    expect(cleared.agentId, 'epoz');
  });

  test('copyWith сбрасывает sources в null', () {
    final msg = Message(
      id: '2',
      text: 'hi',
      isFromUser: false,
      timestamp: DateTime(2026, 1, 1),
      sources: [
        {'url': 'x'},
      ],
    );

    final cleared = msg.copyWith(sources: null);
    expect(cleared.sources, isNull);
  });

  test('copyWith изменяет text и НЕ трогает остальные поля', () {
    final msg = buildMessage();
    final updated = msg.copyWith(text: 'Пока');

    expect(updated.text, 'Пока');
    expect(updated.id, '1');
    expect(updated.agentId, 'epoz');
    expect(updated.isFromUser, false);
  });

  // --- ГРАНИЧНЫЕ СЛУЧАИ ---
  test('copyWith с пустой строкой работает как с обычным значением', () {
    final msg = buildMessage();
    final updated = msg.copyWith(text: '');

    expect(updated.text, ''); // пустая строка ≠ null
  });
}
