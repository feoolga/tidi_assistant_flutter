import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/domain/models/agent.dart';

void main() {
  group('Agent.toJson', () {
    test('включает все заполненные поля', () {
      const agent = Agent(
        id: 'epoz',
        name: 'ЕПоЗ',
        description: 'Помощник',
        capabilities: ['chat', 'rag'],
        routable: true,
        transport: 'http',
      );

      final json = agent.toJson();

      expect(json['id'], 'epoz');
      expect(json['name'], 'ЕПоЗ');
      expect(json['description'], 'Помощник');
      expect(json['capabilities'], ['chat', 'rag']);
      expect(json['routable'], true);
      expect(json['transport'], 'http');
    });

    test('не включает null-поля', () {
      const agent = Agent(id: 'epoz', name: 'ЕПоЗ');

      final json = agent.toJson();

      expect(json.containsKey('description'), false);
      expect(json.containsKey('capabilities'), false);
      expect(json.containsKey('routable'), false);
      expect(json.containsKey('transport'), false);
    });
  });

  group('Agent.hasCapability', () {
    test('возвращает true, если capability есть', () {
      const agent = Agent(
        id: 'epoz',
        name: 'ЕПоЗ',
        capabilities: ['chat', 'rag'],
      );

      expect(agent.hasCapability('chat'), true);
      expect(agent.hasCapability('rag'), true);
    });

    test('возвращает false, если capability нет', () {
      const agent = Agent(id: 'epoz', name: 'ЕПоЗ', capabilities: ['chat']);

      expect(agent.hasCapability('ocr'), false);
    });

    test('возвращает false, если capabilities == null', () {
      const agent = Agent(id: 'epoz', name: 'ЕПоЗ');

      expect(agent.hasCapability('chat'), false);
    });
  });
}
